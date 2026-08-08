#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <algorithm>
#include <atomic>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <mutex>
#include <new>
#include <string>
#include <unordered_set>
#include <vector>

namespace {

// {3AF57D64-BC9A-4F16-AB7A-34C56498B0B1}
constexpr CLSID CLSID_ProtectedFileOverlay = {
    0x3af57d64, 0xbc9a, 0x4f16,
    {0xab, 0x7a, 0x34, 0xc5, 0x64, 0x98, 0xb0, 0xb1}
};

std::atomic<long> g_objectCount{0};
std::atomic<long> g_lockCount{0};
HMODULE g_module = nullptr;

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(),
        [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
    return value;
}

std::wstring NormalizePath(const wchar_t* input) {
    if (input == nullptr || *input == L'\0') {
        return {};
    }

    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetFullPathNameW(input, static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
    std::wstring result = (length > 0 && length < buffer.size())
        ? std::wstring(buffer.data(), length)
        : std::wstring(input);

    if (result.rfind(L"\\\\?\\", 0) == 0) {
        result.erase(0, 4);
    }

    while (result.size() > 3 && (result.back() == L'\\' || result.back() == L'/')) {
        result.pop_back();
    }

    return ToLower(std::move(result));
}

bool IsSupportedExtension(const std::wstring& path) {
    static const std::unordered_set<std::wstring> extensions = {
        L".doc", L".docx", L".xls", L".xlsx", L".ppt", L".pptx",
        L".pdf", L".pfile"
    };

    const wchar_t* extension = PathFindExtensionW(path.c_str());
    return extension != nullptr && extensions.contains(ToLower(extension));
}

std::wstring GetCachePath() {
    PWSTR localAppData = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &localAppData))) {
        return {};
    }

    std::filesystem::path path(localAppData);
    CoTaskMemFree(localAppData);
    path /= L"PurviewProtectionOverlay";
    path /= L"protected-files.txt";
    return path.wstring();
}

std::wstring Utf8ToWide(const std::string& input) {
    if (input.empty()) {
        return {};
    }

    const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        input.data(), static_cast<int>(input.size()), nullptr, 0);
    if (required <= 0) {
        return {};
    }

    std::wstring output(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
        static_cast<int>(input.size()), output.data(), required);
    return output;
}

class ProtectionCache final {
public:
    bool Contains(const std::wstring& normalizedPath) {
        RefreshIfChanged();
        std::scoped_lock lock(mutex_);
        return protectedFiles_.contains(normalizedPath);
    }

private:
    void RefreshIfChanged() {
        const std::wstring cachePath = GetCachePath();
        if (cachePath.empty()) {
            return;
        }

        WIN32_FILE_ATTRIBUTE_DATA attributes{};
        if (!GetFileAttributesExW(cachePath.c_str(), GetFileExInfoStandard, &attributes)) {
            std::scoped_lock lock(mutex_);
            if (loaded_) {
                protectedFiles_.clear();
                loaded_ = false;
                lastWrite_ = {};
            }
            return;
        }

        {
            std::scoped_lock lock(mutex_);
            if (loaded_ && CompareFileTime(&attributes.ftLastWriteTime, &lastWrite_) == 0) {
                return;
            }
        }

        std::ifstream stream(std::filesystem::path(cachePath), std::ios::binary);
        if (!stream) {
            return;
        }

        std::string bytes((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
        if (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF &&
            static_cast<unsigned char>(bytes[1]) == 0xBB &&
            static_cast<unsigned char>(bytes[2]) == 0xBF) {
            bytes.erase(0, 3);
        }

        std::unordered_set<std::wstring> replacement;
        size_t offset = 0;
        while (offset <= bytes.size()) {
            const size_t end = bytes.find('\n', offset);
            std::string line = bytes.substr(offset,
                end == std::string::npos ? std::string::npos : end - offset);
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            const std::wstring normalized = NormalizePath(Utf8ToWide(line).c_str());
            if (!normalized.empty()) {
                replacement.insert(normalized);
            }
            if (end == std::string::npos) {
                break;
            }
            offset = end + 1;
        }

        std::scoped_lock lock(mutex_);
        protectedFiles_ = std::move(replacement);
        lastWrite_ = attributes.ftLastWriteTime;
        loaded_ = true;
    }

    std::mutex mutex_;
    std::unordered_set<std::wstring> protectedFiles_;
    FILETIME lastWrite_{};
    bool loaded_ = false;
};

ProtectionCache g_cache;

class ProtectedFileOverlay final : public IShellIconOverlayIdentifier {
public:
    ProtectedFileOverlay() { ++g_objectCount; }
    ~ProtectedFileOverlay() { --g_objectCount; }

    IFACEMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (object == nullptr) {
            return E_POINTER;
        }
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_IShellIconOverlayIdentifier) {
            *object = static_cast<IShellIconOverlayIdentifier*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    IFACEMETHODIMP_(ULONG) AddRef() override { return ++references_; }

    IFACEMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (remaining == 0) {
            delete this;
        }
        return remaining;
    }

    IFACEMETHODIMP IsMemberOf(PCWSTR path, DWORD attributes) override {
        if (path == nullptr || (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            return S_FALSE;
        }

        const std::wstring normalized = NormalizePath(path);
        if (normalized.empty() || !IsSupportedExtension(normalized)) {
            return S_FALSE;
        }

        return g_cache.Contains(normalized) ? S_OK : S_FALSE;
    }

    IFACEMETHODIMP GetOverlayInfo(PWSTR iconFile, int iconFileSize,
        int* iconIndex, DWORD* flags) override {
        if (iconFile == nullptr || iconFileSize <= 0 || iconIndex == nullptr || flags == nullptr) {
            return E_INVALIDARG;
        }

        wchar_t modulePath[MAX_PATH]{};
        const DWORD length = GetModuleFileNameW(g_module, modulePath, ARRAYSIZE(modulePath));
        if (length == 0 || length >= ARRAYSIZE(modulePath)) {
            return HRESULT_FROM_WIN32(GetLastError());
        }

        PathRemoveFileSpecW(modulePath);
        if (!PathAppendW(modulePath, L"Protected.ico")) {
            return E_FAIL;
        }

        if (wcslen(modulePath) + 1 > static_cast<size_t>(iconFileSize)) {
            return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
        }

        wcscpy_s(iconFile, static_cast<size_t>(iconFileSize), modulePath);
        *iconIndex = 0;
        *flags = ISIOI_ICONFILE | ISIOI_ICONINDEX;
        return S_OK;
    }

    IFACEMETHODIMP GetPriority(int* priority) override {
        if (priority == nullptr) {
            return E_POINTER;
        }
        *priority = 0;
        return S_OK;
    }

private:
    std::atomic<ULONG> references_{1};
};

class ClassFactory final : public IClassFactory {
public:
    ClassFactory() { ++g_objectCount; }
    ~ClassFactory() { --g_objectCount; }

    IFACEMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (object == nullptr) {
            return E_POINTER;
        }
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_IClassFactory) {
            *object = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    IFACEMETHODIMP_(ULONG) AddRef() override { return ++references_; }

    IFACEMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (remaining == 0) {
            delete this;
        }
        return remaining;
    }

    IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** object) override {
        if (outer != nullptr) {
            return CLASS_E_NOAGGREGATION;
        }
        auto* overlay = new (std::nothrow) ProtectedFileOverlay();
        if (overlay == nullptr) {
            return E_OUTOFMEMORY;
        }
        const HRESULT result = overlay->QueryInterface(iid, object);
        overlay->Release();
        return result;
    }

    IFACEMETHODIMP LockServer(BOOL lock) override {
        if (lock) {
            ++g_lockCount;
        } else {
            --g_lockCount;
        }
        return S_OK;
    }

private:
    std::atomic<ULONG> references_{1};
};

} // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** object) {
    if (clsid != CLSID_ProtectedFileOverlay) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    auto* factory = new (std::nothrow) ClassFactory();
    if (factory == nullptr) {
        return E_OUTOFMEMORY;
    }
    const HRESULT result = factory->QueryInterface(iid, object);
    factory->Release();
    return result;
}

extern "C" HRESULT __stdcall DllCanUnloadNow() {
    return (g_objectCount.load() == 0 && g_lockCount.load() == 0) ? S_OK : S_FALSE;
}
