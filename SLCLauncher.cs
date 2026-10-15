// SLCLauncher.exe -- the SLCLauncher settings app.
//
// This is what you open. It is not the watcher: that is SLCWatcher.ps1,
// which the scheduled task keeps running in the background with no window and
// no tray icon. This program only shows the settings window, and exits when
// the window is closed.
//
// The window itself is SLCLauncherSettings.ps1, run inside this process
// rather than handed to powershell.exe. That keeps it a real application --
// its own name in Task Manager, its own icon on the taskbar, no console window
// -- while the settings logic stays in the same language as the watcher that
// reads them.
//
// Run as "SLCLauncher.exe --update-available <version>" -- which only the
// watcher does, once per new version -- it instead shows a Windows notification
// that the version is out, and opens the settings window if it is clicked.
//
// Install.ps1 compiles this with the C# compiler that ships with the .NET
// Framework in every copy of Windows 10 and 11, so no prebuilt binary is kept
// in the repository.

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("SLCLauncher")]
[assembly: AssemblyProduct("SLCLauncher")]
[assembly: AssemblyDescription("Choose what starts with World of Warcraft")]

static class Program
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);

    const int SW_RESTORE = 9;

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "--update-available")
            return ShowUpdateNotice(args[1]);

        // One settings window at a time. Opening it again brings the one
        // already open to the front rather than a second copy that could
        // save over the first.
        bool first;
        using (var mutex = new Mutex(true, @"Local\SLCLauncherSettings", out first))
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
        string script = Path.Combine(dir, "SLCLauncherSettings.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("SLCLauncherSettings.ps1 is missing from " + dir + ".\n\n" +
                            "Run Install.cmd again to repair it.",
                            "SLCLauncher", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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

    // A tray icon's balloon, which Windows 10 and 11 show as an ordinary
    // notification in the bottom right, under this program's name and icon.
    // The icon is there only as long as the notification is: this process
    // ends when it is clicked, dismissed or times out.
    static int ShowUpdateNotice(string version)
    {
        bool open = false;
        using (var icon = new NotifyIcon())
        using (var giveUp = new System.Windows.Forms.Timer())
        {
            try { icon.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { icon.Icon = SystemIcons.Application; }
            icon.Text    = "SLCLauncher";
            icon.Visible = true;

            EventHandler openSettings = delegate { open = true; Application.ExitThread(); };
            icon.BalloonTipClicked += openSettings;
            icon.Click             += openSettings;
            icon.BalloonTipClosed  += delegate { Application.ExitThread(); };

            // In case Windows never reports the notification closed.
            giveUp.Interval = 60000;
            giveUp.Tick += delegate { Application.ExitThread(); };
            giveUp.Start();

            icon.ShowBalloonTip(10000, "SLCLauncher " + version + " is available",
                                "Open SLCLauncher to download and install it. Your settings are kept.",
                                ToolTipIcon.None);
            Application.Run();
            icon.Visible = false;
        }

        if (open)
        {
            // A fresh copy, so the settings window gets its usual single-copy check.
            try { Process.Start(Application.ExecutablePath); } catch { }
        }
        return 0;
    }

    static void ShowFailure(string detail)
    {
        MessageBox.Show("The settings window could not be opened.\n\n" + detail,
                        "SLCLauncher", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
