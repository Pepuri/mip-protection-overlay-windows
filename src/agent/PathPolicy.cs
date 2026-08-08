namespace PurviewProtectionOverlay.Agent;

internal sealed class PathPolicy
{
    private readonly HashSet<string> _extensions;
    private readonly List<string> _excludedPaths;
    private readonly List<string> _watchRoots;

    public PathPolicy(AppConfig config)
    {
        _extensions = config.Extensions
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.StartsWith('.') ? value : "." + value)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        _excludedPaths = config.ExcludedPaths
            .Select(ExpandPath)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(NormalizePath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        AddProfileDataExclusions(_excludedPaths);

        if (config.ExcludeOneDrive)
        {
            string[] variables = ["OneDrive", "OneDriveCommercial", "OneDriveConsumer"];
            foreach (string variable in variables)
            {
                string? value = Environment.GetEnvironmentVariable(variable);
                if (!string.IsNullOrWhiteSpace(value))
                {
                    _excludedPaths.Add(NormalizePath(value));
                }
            }
        }

        _excludedPaths = _excludedPaths
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value.Length)
            .ToList();

        _watchRoots = ExpandWatchRoots(config.WatchRoots)
            .Where(Directory.Exists)
            .Select(NormalizePath)
            .Where(value => !IsExcluded(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public IReadOnlyList<string> WatchRoots => _watchRoots;
    public IReadOnlyList<string> ExcludedPaths => _excludedPaths;

    public bool IsCandidate(string path)
    {
        try
        {
            string normalized = NormalizePath(path);
            return !IsExcluded(normalized) && _extensions.Contains(Path.GetExtension(normalized));
        }
        catch
        {
            return false;
        }
    }

    public bool IsExcluded(string path)
    {
        string normalized = NormalizePath(path);
        return _excludedPaths.Any(excluded =>
            normalized.Equals(excluded, StringComparison.OrdinalIgnoreCase) ||
            normalized.StartsWith(EnsureTrailingSeparator(excluded), StringComparison.OrdinalIgnoreCase));
    }

    public bool ContainsExcludedDescendant(string directory)
    {
        string normalized = EnsureTrailingSeparator(NormalizePath(directory));
        return _excludedPaths.Any(excluded =>
            excluded.StartsWith(normalized, StringComparison.OrdinalIgnoreCase));
    }

    public static string NormalizePath(string path)
    {
        string expanded = ExpandPath(path);
        string full = Path.GetFullPath(expanded);
        if (full.StartsWith("\\\\?\\", StringComparison.Ordinal))
        {
            full = full[4..];
        }
        return Path.TrimEndingDirectorySeparator(full);
    }

    private static string ExpandPath(string value)
    {
        string expanded = Environment.ExpandEnvironmentVariables(value.Trim().Trim('"'));
        return expanded.Replace('/', Path.DirectorySeparatorChar);
    }

    private static string EnsureTrailingSeparator(string path) =>
        path.EndsWith(Path.DirectorySeparatorChar) ? path : path + Path.DirectorySeparatorChar;

    private static IEnumerable<string> ExpandWatchRoots(IEnumerable<string> values)
    {
        foreach (string value in values)
        {
            if (value.Equals("%FIXED_DRIVES%", StringComparison.OrdinalIgnoreCase))
            {
                foreach (DriveInfo drive in DriveInfo.GetDrives().Where(drive =>
                             drive.IsReady && drive.DriveType == DriveType.Fixed &&
                             drive.DriveFormat.Equals("NTFS", StringComparison.OrdinalIgnoreCase)))
                {
                    yield return drive.RootDirectory.FullName;
                }
            }
            else
            {
                yield return ExpandPath(value);
            }
        }
    }

    private static void AddProfileDataExclusions(ICollection<string> excludedPaths)
    {
        string systemDrive = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
        string usersRoot = Path.Combine(systemDrive + Path.DirectorySeparatorChar, "Users");
        try
        {
            foreach (string profile in Directory.EnumerateDirectories(usersRoot))
            {
                excludedPaths.Add(NormalizePath(Path.Combine(profile, "AppData")));
            }
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
        {
            // The current user's configured AppData exclusion still applies.
        }
    }
}
