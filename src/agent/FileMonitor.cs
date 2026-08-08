using System.Collections.Concurrent;

namespace PurviewProtectionOverlay.Agent;

internal sealed class FileMonitor : IDisposable
{
    private readonly AppConfig _config;
    private readonly PathPolicy _policy;
    private readonly ProtectionDetector _detector;
    private readonly ProtectionCache _cache;
    private readonly AgentLogger _log;
    private readonly ConcurrentDictionary<string, DateTimeOffset> _pending =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly List<FileSystemWatcher> _watchers = [];
    private readonly SemaphoreSlim _watcherGate = new(1, 1);
    private readonly CancellationTokenSource _shutdown = new();
    private Task? _eventTask;
    private Task? _reconciliationTask;
    private int _rebuildQueued;

    public FileMonitor(
        AppConfig config,
        PathPolicy policy,
        ProtectionDetector detector,
        ProtectionCache cache,
        AgentLogger log)
    {
        _config = config;
        _policy = policy;
        _detector = detector;
        _cache = cache;
        _log = log;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        using CancellationTokenSource linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, _shutdown.Token);

        await RebuildWatchersAsync(linked.Token).ConfigureAwait(false);
        await ReconcileAsync(linked.Token).ConfigureAwait(false);

        _eventTask = ProcessPendingEventsAsync(linked.Token);
        _reconciliationTask = ReconciliationLoopAsync(linked.Token);

        _log.Info("Agent started. Explorer reads only the local protection cache.");
        await Task.WhenAll(_eventTask, _reconciliationTask).ConfigureAwait(false);
    }

    public async Task ReconcileAsync(CancellationToken cancellationToken)
    {
        _log.Info("Starting reconciliation scan.");
        int candidates = 0;
        int protectedCount = 0;
        int errors = 0;

        _cache.RemoveMissingAndExcluded(_policy);

        foreach (string file in EnumerateCandidates())
        {
            cancellationToken.ThrowIfCancellationRequested();
            candidates++;

            ProtectionResult result = await _detector.InspectAsync(file, cancellationToken)
                .ConfigureAwait(false);
            if (result.Outcome.StartsWith("Error:", StringComparison.Ordinal))
            {
                errors++;
                continue;
            }

            if (result.IsProtected)
            {
                protectedCount++;
            }
            if (_cache.Set(file, result.IsProtected, persist: false))
            {
                ShellNotifier.ItemChanged(file);
            }
        }

        _cache.Persist();
        _log.Info($"Reconciliation completed. Candidates={candidates}, " +
                  $"Cached={_cache.Count}, Protected={protectedCount}, Errors={errors}.");
    }

    private IEnumerable<string> EnumerateCandidates()
    {
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string root in _policy.WatchRoots)
        {
            var pendingDirectories = new Stack<string>();
            pendingDirectories.Push(root);

            while (pendingDirectories.Count > 0)
            {
                string directory = pendingDirectories.Pop();
                string normalized;
                try
                {
                    normalized = PathPolicy.NormalizePath(directory);
                }
                catch
                {
                    continue;
                }

                if (!visited.Add(normalized) || _policy.IsExcluded(normalized))
                {
                    continue;
                }

                foreach (string file in SafeEnumerateFiles(normalized))
                {
                    if (_policy.IsCandidate(file))
                    {
                        yield return file;
                    }
                }

                foreach (string child in SafeEnumerateDirectories(normalized))
                {
                    if (!_policy.IsExcluded(child))
                    {
                        pendingDirectories.Push(child);
                    }
                }
            }
        }
    }

    private static IReadOnlyList<string> SafeEnumerateFiles(string directory)
    {
        try
        {
            return Directory.GetFiles(directory, "*", SearchOption.TopDirectoryOnly);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
        {
            return Array.Empty<string>();
        }
    }

    private static IReadOnlyList<string> SafeEnumerateDirectories(string directory)
    {
        try
        {
            return Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
        {
            return Array.Empty<string>();
        }
    }

    private async Task RebuildWatchersAsync(CancellationToken cancellationToken)
    {
        await _watcherGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            foreach (FileSystemWatcher watcher in _watchers)
            {
                watcher.Dispose();
            }
            _watchers.Clear();

            var registered = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string root in _policy.WatchRoots)
            {
                BuildWatcherSegments(root, registered, cancellationToken);
            }

            _log.Info($"File watchers enabled: {_watchers.Count}");
        }
        finally
        {
            _watcherGate.Release();
            Interlocked.Exchange(ref _rebuildQueued, 0);
        }
    }

    private void BuildWatcherSegments(
        string directory,
        HashSet<string> registered,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!Directory.Exists(directory) || _policy.IsExcluded(directory))
        {
            return;
        }

        string normalized = PathPolicy.NormalizePath(directory);
        if (!registered.Add(normalized))
        {
            return;
        }

        bool recursive = !_policy.ContainsExcludedDescendant(normalized);
        AddWatcher(normalized, recursive);
        if (recursive)
        {
            return;
        }

        try
        {
            foreach (string child in Directory.EnumerateDirectories(normalized))
            {
                BuildWatcherSegments(child, registered, cancellationToken);
            }
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
        {
            _log.Warn($"Cannot enumerate watcher branch: {normalized}");
        }
    }

    private void AddWatcher(string path, bool recursive)
    {
        try
        {
            var watcher = new FileSystemWatcher(path)
            {
                IncludeSubdirectories = recursive,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName |
                               NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime,
                InternalBufferSize = Math.Clamp(_config.WatcherBufferKilobytes, 4, 64) * 1024,
                EnableRaisingEvents = false
            };

            watcher.Created += OnChanged;
            watcher.Changed += OnChanged;
            watcher.Deleted += OnDeleted;
            watcher.Renamed += OnRenamed;
            watcher.Error += OnWatcherError;
            watcher.EnableRaisingEvents = true;
            _watchers.Add(watcher);
            _log.Info($"Watcher enabled: {path} (recursive={recursive})");
        }
        catch (Exception ex)
        {
            _log.Warn($"Watcher not available for '{path}': {ex.Message}");
        }
    }

    private void OnChanged(object sender, FileSystemEventArgs args)
    {
        try
        {
            if (Directory.Exists(args.FullPath))
            {
                QueueWatcherRebuild();
                return;
            }

            if (_policy.IsCandidate(args.FullPath))
            {
                _pending[PathPolicy.NormalizePath(args.FullPath)] = DateTimeOffset.UtcNow;
            }
        }
        catch (Exception ex)
        {
            _log.Warn($"Ignored invalid file event path '{args.FullPath}': {ex.Message}");
        }
    }

    private void OnDeleted(object sender, FileSystemEventArgs args)
    {
        try
        {
            if (_cache.Set(args.FullPath, false))
            {
                _log.Info($"Removed deleted file from cache: {args.FullPath}");
                ShellNotifier.ItemChanged(args.FullPath);
            }
        }
        catch (Exception ex)
        {
            _log.Warn($"Ignored invalid delete event path '{args.FullPath}': {ex.Message}");
        }
    }

    private void OnRenamed(object sender, RenamedEventArgs args)
    {
        _cache.Set(args.OldFullPath, false);
        OnChanged(sender, args);
    }

    private void OnWatcherError(object sender, ErrorEventArgs args)
    {
        string path = sender is FileSystemWatcher watcher ? watcher.Path : "unknown";
        _log.Warn($"File watcher error for '{path}': {args.GetException().Message}");
        QueueWatcherRebuild();
    }

    private void QueueWatcherRebuild()
    {
        if (Interlocked.Exchange(ref _rebuildQueued, 1) != 0)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(2), _shutdown.Token).ConfigureAwait(false);
                await RebuildWatchersAsync(_shutdown.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Shutting down.
            }
        });
    }

    private async Task ProcessPendingEventsAsync(CancellationToken cancellationToken)
    {
        TimeSpan debounce = TimeSpan.FromMilliseconds(
            Math.Clamp(_config.EventDebounceMilliseconds, 100, 10_000));

        while (!cancellationToken.IsCancellationRequested)
        {
            await Task.Delay(250, cancellationToken).ConfigureAwait(false);
            DateTimeOffset cutoff = DateTimeOffset.UtcNow - debounce;

            foreach ((string path, DateTimeOffset time) in _pending.ToArray())
            {
                if (time > cutoff || !_pending.TryRemove(path, out _))
                {
                    continue;
                }

                if (!File.Exists(path))
                {
                    _cache.Set(path, false);
                    continue;
                }

                ProtectionResult result = await _detector.InspectAsync(path, cancellationToken)
                    .ConfigureAwait(false);
                if (result.Outcome.StartsWith("Error:", StringComparison.Ordinal))
                {
                    _log.Warn($"Inspection failed: {path}; {result.Outcome}");
                    continue;
                }

                bool changed = _cache.Set(path, result.IsProtected);
                if (changed)
                {
                    _log.Info($"Protection changed to {result.IsProtected}: {path}");
                    ShellNotifier.ItemChanged(path);
                }
            }
        }
    }

    private async Task ReconciliationLoopAsync(CancellationToken cancellationToken)
    {
        TimeSpan interval = TimeSpan.FromMinutes(Math.Clamp(_config.ReconciliationMinutes, 1, 1440));
        using var timer = new PeriodicTimer(interval);
        while (await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
        {
            try
            {
                await ReconcileAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _log.Error("Reconciliation failed.", ex);
            }
        }
    }

    public void Dispose()
    {
        _shutdown.Cancel();
        foreach (FileSystemWatcher watcher in _watchers)
        {
            watcher.Dispose();
        }
        _watchers.Clear();
        _watcherGate.Dispose();
        _shutdown.Dispose();
    }
}
