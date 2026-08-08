using System.Text;

namespace PurviewProtectionOverlay.Agent;

internal sealed class AgentLogger
{
    private readonly object _gate = new();
    private readonly string _logPath;

    public AgentLogger(string dataRoot)
    {
        string logDirectory = Path.Combine(dataRoot, "Logs");
        Directory.CreateDirectory(logDirectory);
        _logPath = Path.Combine(logDirectory, "Agent.log");
    }

    public string LogPath => _logPath;

    public void Info(string message) => Write("INFO", message);
    public void Warn(string message) => Write("WARN", message);
    public void Error(string message, Exception? exception = null) =>
        Write("ERROR", exception is null ? message : $"{message} {exception.GetType().Name}: {exception.Message}");

    private void Write(string level, string message)
    {
        string line = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz} [{level}] {message}";
        lock (_gate)
        {
            RotateIfNeeded();
            File.AppendAllText(_logPath, line + Environment.NewLine, new UTF8Encoding(false));
        }

        if (Environment.UserInteractive)
        {
            Console.WriteLine(line);
        }
    }

    private void RotateIfNeeded()
    {
        try
        {
            var file = new FileInfo(_logPath);
            if (!file.Exists || file.Length < 5 * 1024 * 1024)
            {
                return;
            }

            string archive = Path.Combine(file.DirectoryName!, $"Agent-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            File.Move(_logPath, archive, true);
            foreach (FileInfo old in new DirectoryInfo(file.DirectoryName!)
                         .GetFiles("Agent-*.log")
                         .OrderByDescending(item => item.LastWriteTimeUtc)
                         .Skip(5))
            {
                old.Delete();
            }
        }
        catch
        {
            // Logging must never terminate the agent.
        }
    }
}

