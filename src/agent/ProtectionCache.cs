using System.Text;

namespace PurviewProtectionOverlay.Agent;

internal sealed class ProtectionCache
{
    private readonly object _gate = new();
    private readonly string _cachePath;
    private readonly HashSet<string> _protectedFiles = new(StringComparer.OrdinalIgnoreCase);

    public ProtectionCache(string dataRoot)
    {
        Directory.CreateDirectory(dataRoot);
        _cachePath = Path.Combine(dataRoot, "protected-files.txt");
        Load();
    }

    public string CachePath => _cachePath;
    public int Count { get { lock (_gate) return _protectedFiles.Count; } }

    public bool Contains(string path)
    {
        lock (_gate)
        {
            return _protectedFiles.Contains(PathPolicy.NormalizePath(path));
        }
    }

    public bool Set(string path, bool isProtected, bool persist = true)
    {
        string normalized = PathPolicy.NormalizePath(path);
        bool changed;
        lock (_gate)
        {
            changed = isProtected ? _protectedFiles.Add(normalized) : _protectedFiles.Remove(normalized);
            if (changed && persist)
            {
                PersistUnsafe();
            }
        }
        return changed;
    }

    public void RemoveMissingAndExcluded(PathPolicy policy)
    {
        lock (_gate)
        {
            int removed = _protectedFiles.RemoveWhere(path => !File.Exists(path) || policy.IsExcluded(path));
            if (removed > 0)
            {
                PersistUnsafe();
            }
        }
    }

    public void Persist()
    {
        lock (_gate)
        {
            PersistUnsafe();
        }
    }

    private void Load()
    {
        if (!File.Exists(_cachePath))
        {
            return;
        }

        foreach (string line in File.ReadLines(_cachePath))
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                _protectedFiles.Add(PathPolicy.NormalizePath(line));
            }
        }
    }

    private void PersistUnsafe()
    {
        string temporary = _cachePath + ".tmp";
        string content = string.Join(Environment.NewLine,
            _protectedFiles.OrderBy(value => value, StringComparer.OrdinalIgnoreCase));
        if (content.Length > 0)
        {
            content += Environment.NewLine;
        }

        File.WriteAllText(temporary, content, new UTF8Encoding(false));
        File.Move(temporary, _cachePath, true);
    }
}

