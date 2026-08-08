using Microsoft.InformationProtection;
using Microsoft.InformationProtection.File;

namespace PurviewProtectionOverlay.Agent;

internal sealed class ProtectionDetector : IDisposable
{
    // This identifies the open-source application, not a tenant. GetFileStatus is offline-only.
    private const string ApplicationId = "7f62a1cc-1d79-4ce5-9db4-e41235de4368";
    private readonly MipContext _mipContext;
    private readonly SemaphoreSlim _inspectionGate;

    public ProtectionDetector(string dataRoot, int maxConcurrency)
    {
        string mipData = Path.Combine(dataRoot, "MipSdk");
        Directory.CreateDirectory(mipData);

        MIP.Initialize(MipComponent.File);
        var appInfo = new ApplicationInfo
        {
            ApplicationId = ApplicationId,
            ApplicationName = "Purview Protection Overlay",
            ApplicationVersion = typeof(ProtectionDetector).Assembly.GetName().Version?.ToString() ?? "1.0.0"
        };

        var configuration = new MipConfiguration(
            appInfo,
            mipData,
            LogLevel.Error,
            true,
            CacheStorageType.InMemory);

        _mipContext = MIP.CreateMipContext(configuration);
        _inspectionGate = new SemaphoreSlim(Math.Clamp(maxConcurrency, 1, 8));
    }

    public async Task<ProtectionResult> InspectAsync(string path, CancellationToken cancellationToken)
    {
        await _inspectionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!File.Exists(path))
            {
                return new ProtectionResult(path, false, false, false, "Missing");
            }

            var status = FileHandler.GetFileStatus(path, _mipContext);
            return new ProtectionResult(
                path,
                status.IsProtected(),
                status.IsLabeled(),
                status.ContainsProtectedObjects(),
                "Inspected");
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new ProtectionResult(path, false, false, false,
                $"Error:{ex.GetType().Name}:{ex.Message}");
        }
        finally
        {
            _inspectionGate.Release();
        }
    }

    public void Dispose()
    {
        _inspectionGate.Dispose();
        _mipContext.Dispose();
    }
}

internal sealed record ProtectionResult(
    string Path,
    bool IsProtected,
    bool IsLabeled,
    bool ContainsProtectedObjects,
    string Outcome);
