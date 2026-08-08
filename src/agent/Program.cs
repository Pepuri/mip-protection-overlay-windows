using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;

namespace PurviewProtectionOverlay.Agent;

internal static class Program
{
    private const string Version = "1.0.0";

    public static async Task<int> Main(string[] args)
    {
        string dataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PurviewProtectionOverlay");
        Directory.CreateDirectory(dataRoot);
        var log = new AgentLogger(dataRoot);

        try
        {
            Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.BelowNormal;
            log.Info("Process priority set to BelowNormal.");
        }
        catch (Exception ex)
        {
            log.Warn($"Could not lower process priority: {ex.Message}");
        }

        string? configPath = GetOption(args, "--config");
        AppConfig config = AppConfig.Load(configPath, log);
        var policy = new PathPolicy(config);

        log.Info($"Version={Version}");
        log.Info($"Watch roots: {string.Join("; ", policy.WatchRoots)}");
        log.Info($"Excluded paths: {string.Join("; ", policy.ExcludedPaths)}");

        using var detector = new ProtectionDetector(dataRoot, config.MaxConcurrentInspections);

        string? probePath = GetOption(args, "--probe");
        if (!string.IsNullOrWhiteSpace(probePath))
        {
            ProtectionResult result = await detector.InspectAsync(
                PathPolicy.NormalizePath(probePath), CancellationToken.None);
            string json = JsonSerializer.Serialize(new
            {
                path = result.Path,
                isProtected = result.IsProtected,
                isLabeled = result.IsLabeled,
                containsProtectedObjects = result.ContainsProtectedObjects,
                outcome = result.Outcome
            }, new JsonSerializerOptions { WriteIndented = true });

            string? outputPath = GetOption(args, "--output");
            if (!string.IsNullOrWhiteSpace(outputPath))
            {
                File.WriteAllText(outputPath, json);
            }
            else
            {
                Console.WriteLine(json);
            }
            return result.Outcome.StartsWith("Error:", StringComparison.Ordinal) ? 2 : 0;
        }

        using Mutex mutex = CreateUserMutex(out bool isFirstInstance);
        if (!isFirstInstance)
        {
            log.Warn("Another agent instance is already running for this user.");
            return 0;
        }

        var cache = new ProtectionCache(dataRoot);
        log.Info($"Loaded {cache.Count} cached protected file states.");

        using var monitor = new FileMonitor(config, policy, detector, cache, log);
        using var shutdown = new CancellationTokenSource();
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            shutdown.Cancel();
        };

        try
        {
            if (args.Contains("--once", StringComparer.OrdinalIgnoreCase))
            {
                await monitor.ReconcileAsync(shutdown.Token);
                return 0;
            }

            await monitor.RunAsync(shutdown.Token);
            return 0;
        }
        catch (OperationCanceledException)
        {
            log.Info("Agent stopped.");
            return 0;
        }
        catch (Exception ex)
        {
            log.Error("Agent terminated unexpectedly.", ex);
            return 1;
        }
    }

    private static Mutex CreateUserMutex(out bool isFirstInstance)
    {
        string sid;
        try
        {
            sid = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        }
        catch
        {
            sid = Environment.UserName;
        }

        string safeSid = string.Concat(sid.Select(character => char.IsLetterOrDigit(character) ? character : '_'));
        return new Mutex(true, $"Local\\PurviewProtectionOverlayAgent_{safeSid}", out isFirstInstance);
    }

    private static string? GetOption(string[] args, string option)
    {
        for (int index = 0; index < args.Length - 1; index++)
        {
            if (args[index].Equals(option, StringComparison.OrdinalIgnoreCase))
            {
                return args[index + 1];
            }
        }
        return null;
    }
}
