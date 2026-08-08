using System.Runtime.InteropServices;

namespace PurviewProtectionOverlay.Agent;

internal static class ShellNotifier
{
    private const uint ShcneUpdateItem = 0x00002000;
    private const uint ShcnfPathW = 0x0005;
    private const uint ShcnfFlushNowait = 0x2000;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern void SHChangeNotify(
        uint eventId,
        uint flags,
        string item1,
        IntPtr item2);

    public static void ItemChanged(string path)
    {
        try
        {
            SHChangeNotify(ShcneUpdateItem, ShcnfPathW | ShcnfFlushNowait, path, IntPtr.Zero);
        }
        catch
        {
            // A notification failure must not stop detection or cache updates.
        }
    }
}

