// ArchonLauncher.exe -- the Archon Launcher settings app.
//
// This is what you open. It is not the watcher: that is ArchonWatcher.ps1,
// which the scheduled task keeps running in the background with no window and
// no tray icon. This program only shows the settings window, and exits when
// the window is closed.
//
// The window itself is ArchonLauncherOptions.ps1, run inside this process
// rather than handed to powershell.exe. That keeps it a real application --
// its own name in Task Manager, its own icon on the taskbar, no console window
// -- while the settings logic stays in the same language as the watcher that
// reads them.
//
// Install.ps1 compiles this with the C# compiler that ships with the .NET
// Framework in every copy of Windows 10 and 11, so no prebuilt binary is kept
// in the repository.

using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Archon Launcher")]
[assembly: AssemblyProduct("Archon Launcher")]
[assembly: AssemblyDescription("Choose what starts with World of Warcraft")]

static class Program
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);

    const int SW_RESTORE = 9;

    [STAThread]
    static int Main()
    {
        // One settings window at a time. Opening it again brings the one
        // already open to the front rather than a second copy that could
        // save over the first.
        bool first;
        using (var mutex = new Mutex(true, @"Local\ArchonLauncherSettings", out first))
        {
            if (!first)
            {
                FocusExistingWindow();
                return 0;
            }
            return RunSettingsWindow();
        }
    }

    static void FocusExistingWindow()
    {
        var me = Process.GetCurrentProcess();
        foreach (var p in Process.GetProcessesByName(me.ProcessName))
        {
            if (p.Id == me.Id || p.MainWindowHandle == IntPtr.Zero) continue;
            if (IsIconic(p.MainWindowHandle)) ShowWindow(p.MainWindowHandle, SW_RESTORE);
            SetForegroundWindow(p.MainWindowHandle);
            return;
        }
    }

    static int RunSettingsWindow()
    {
        string dir    = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "ArchonLauncherOptions.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("ArchonLauncherOptions.ps1 is missing from " + dir + ".\n\n" +
                            "Run Install.cmd again to repair it.",
                            "Archon Launcher", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }

        // The window has to live on this thread, which is STA as WinForms
        // requires. The script is the installer's own copy, so there is no
        // reason for the machine's execution policy to refuse it.
        var state = InitialSessionState.CreateDefault();
        state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        state.ApartmentState  = ApartmentState.STA;
        state.ThreadOptions   = PSThreadOptions.UseCurrentThread;

        using (var runspace = RunspaceFactory.CreateRunspace(state))
        {
            runspace.Open();
            using (var ps = PowerShell.Create())
            {
                ps.Runspace = runspace;
                ps.AddCommand(script);
                try
                {
                    ps.Invoke();
                }
                catch (Exception e)
                {
                    ShowFailure(e.Message);
                    return 1;
                }
                if (ps.Streams.Error.Count > 0)
                {
                    ShowFailure(ps.Streams.Error[0].ToString());
                    return 1;
                }
            }
        }
        return 0;
    }

    static void ShowFailure(string detail)
    {
        MessageBox.Show("The settings window could not be opened.\n\n" + detail,
                        "Archon Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
