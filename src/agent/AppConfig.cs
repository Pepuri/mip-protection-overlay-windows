using System.Text.Json;

namespace PurviewProtectionOverlay.Agent;

internal sealed class AppConfig
{
    public string[] WatchRoots { get; init; } = ["%FIXED_DRIVES%"];

    public string[] Extensions { get; init; } =
    [
        ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".pdf", ".pfile"
    ];

    public string[] ExcludedPaths { get; init; } =
    [
        "%SystemDrive%\\$Recycle.Bin",
        "%SystemDrive%\\$WINDOWS.~BT",
        "%SystemDrive%\\$WINDOWS.~WS",
        "%SystemDrive%\\$WinREAgent",
        "%SystemDrive%\\Config.Msi",
        "%SystemDrive%\\Documents and Settings",
        "%SystemDrive%\\PerfLogs",
        "%ProgramFiles%",
        "%ProgramFiles(x86)%",
        "%ProgramData%",
        "%SystemDrive%\\Recovery",
        "%SystemDrive%\\System Volume Information",
        "%SystemRoot%",
        "%USERPROFILE%\\AppData"
    ];

    public bool ExcludeOneDrive { get; init; } = true;
    public int ReconciliationMinutes { get; init; } = 15;
    public int EventDebounceMilliseconds { get; init; } = 750;
    public int MaxConcurrentInspections { get; init; } = 2;
    public int WatcherBufferKilobytes { get; init; } = 64;

    public static AppConfig Load(string? explicitPath, AgentLogger log)
    {
        string path = explicitPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "PurviewProtectionOverlay",
            "config.json");

        if (!File.Exists(path))
        {
            log.Info($"Configuration not found. Using defaults: {path}");
            return new AppConfig();
        }

        try
        {
            string json = File.ReadAllText(path);
            AppConfig? config = JsonSerializer.Deserialize<AppConfig>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                ReadCommentHandling = JsonCommentHandling.Skip,
                AllowTrailingCommas = true
            });
            return config ?? new AppConfig();
        }
        catch (Exception ex)
        {
            log.Error($"Invalid configuration '{path}'. Defaults will be used.", ex);
            return new AppConfig();
        }
    }
}

