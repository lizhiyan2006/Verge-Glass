using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using Microsoft.Win32;

class Setup
{
    const string AppId = "io.github.clash-verge-rev.clash-verge-rev";
    static readonly string DataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VergeGlass");
    static readonly string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    static int Main(string[] args)
    {
        bool uninstall = args.Length > 0 && args[0].ToLowerInvariant().Contains("uninstall");
        bool quiet = Array.Exists(args, a => a.Equals("/quiet", StringComparison.OrdinalIgnoreCase));

        Console.WriteLine();
        Console.WriteLine("  Verge Glass " + (uninstall ? "uninstaller" : "installer"));
        Console.WriteLine();

        try
        {
            if (uninstall)
            {
                Uninstall();
                Console.WriteLine("  [ok] uninstalled");
            }
            else
            {
                Install();
                Console.WriteLine("  [ok] installed");
                Console.WriteLine("      - Settings card: Clash Verge -> Settings -> bottom of page");
                Console.WriteLine("      - Next time launch from Start Menu \"Clash Verge (Verge Glass)\"");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("  [x] " + ex.GetType().Name + ": " + ex.Message);
            if (!quiet && !Console.IsInputRedirected) { Console.WriteLine(); Console.WriteLine("  Press any key ..."); Console.ReadKey(true); }
            return 1;
        }

        if (!quiet && !Console.IsInputRedirected)
        {
            Console.WriteLine();
            Console.WriteLine("  Press any key to exit ...");
            Console.ReadKey(true);
        }
        return 0;
    }

    static string ExeDir { get { return Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location); } }

    static void Install()
    {
        Directory.CreateDirectory(Path.Combine(DataDir, "src"));

        // 1) 释放内置文件（exe 自己写，不依赖子进程）
        string css = ReadResource("verge-glass.css");
        string js = ReadResource("verge-glass.js");
        string manifest = ReadResource("plugin.json");
        string engine = ReadResource("VergeGlass.ps1");
        File.WriteAllText(Path.Combine(DataDir, "src", "verge-glass.css"), css);
        File.WriteAllText(Path.Combine(DataDir, "src", "verge-glass.js"), js);
        File.WriteAllText(Path.Combine(DataDir, "plugin.json"), manifest);
        File.WriteAllText(Path.Combine(DataDir, "VergeGlass.ps1"), engine);
        try
        {
            Assembly asmIco = Assembly.GetExecutingAssembly();
            foreach (string name in asmIco.GetManifestResourceNames())
            {
                if (!name.EndsWith("clash-verge.ico")) continue;
                using (Stream s = asmIco.GetManifestResourceStream(name))
                using (FileStream f = File.Create(Path.Combine(DataDir, "clash-verge.ico")))
                {
                    s.CopyTo(f);
                }
            }
        }
        catch { }
        Console.WriteLine("  files -> " + DataDir);

        // 2) 隐藏启动器
        string vbs = Path.Combine(DataDir, "VergeGlass.vbs");
        string vbsBody = "Set sh = CreateObject(\"WScript.Shell\")\r\n" +
                         "sh.Run \"powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"\"" + Path.Combine(DataDir, "VergeGlass.ps1") + "\"\" start -RestartApp\", 0, False\r\n";
        File.WriteAllText(vbs, vbsBody, System.Text.Encoding.ASCII);

        // 3) 登录自启
        using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, true))
        {
            k.SetValue("VergeGlass", "wscript.exe //B \"" + vbs + "\"");
        }
        Console.WriteLine("  logon entry registered");

        // 4) 开始菜单快捷方式（WScript.Shell，失败不影响主流程）
        try
        {
            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            string lnkPath = Path.Combine(programs, "Clash Verge (Verge Glass).lnk");
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(shellType);
            object lnk = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
            Type lnkType = lnk.GetType();
            lnkType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { "wscript.exe" });
            lnkType.InvokeMember("Arguments", BindingFlags.SetProperty, null, lnk, new object[] { "//B \"" + vbs + "\"" });
            lnkType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { DataDir });
            lnkType.InvokeMember("Description", BindingFlags.SetProperty, null, lnk, new object[] { "Launch Clash Verge with Verge Glass theme" });
            string iconFile = Path.Combine(DataDir, "clash-verge.ico");
            if (File.Exists(iconFile)) lnkType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { iconFile + ",0" });
            lnkType.InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
            Console.WriteLine("  start menu shortcut created");
        }
        catch (Exception ex)
        {
            Console.WriteLine("  (shortcut skipped: " + ex.Message + ")");
        }

        // 5) 带调试端口启动 Clash Verge
        string appExe = FindAppExe();
        if (appExe != null)
        {
            bool running = Process.GetProcessesByName("clash-verge").Length > 0;
            if (running)
            {
                Console.WriteLine("  Clash Verge is running; restart it once to enable CDP (or it will be handled at next launch)");
            }
            else
            {
                Environment.SetEnvironmentVariable("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9333");
                var app = new ProcessStartInfo(appExe);
                app.WorkingDirectory = Path.GetDirectoryName(appExe);
                app.UseShellExecute = false;
                Process.Start(app);
                Console.WriteLine("  launched Clash Verge (CDP port 9333)");
            }
        }

        // 6) 启动守护进程（隐藏）
        var watcher = new ProcessStartInfo("wscript.exe", "//B \"" + vbs + "\"");
        watcher.UseShellExecute = false;
        Process.Start(watcher);
        Console.WriteLine("  watcher started");
    }

    static void Uninstall()
    {
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, true))
            {
                if (k != null) k.DeleteValue("VergeGlass", false);
            }
        }
        catch { }

        try
        {
            string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Clash Verge (Verge Glass).lnk");
            if (File.Exists(lnk)) File.Delete(lnk);
        }
        catch { }

        try
        {
            if (Directory.Exists(DataDir)) Directory.Delete(DataDir, true);
        }
        catch { }
    }

    static string ReadResource(string suffix)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        foreach (string name in asm.GetManifestResourceNames())
        {
            if (!name.EndsWith(suffix)) continue;
            using (Stream s = asm.GetManifestResourceStream(name))
            using (StreamReader r = new StreamReader(s))
            {
                return r.ReadToEnd();
            }
        }
        throw new InvalidOperationException("missing embedded resource: " + suffix);
    }

    static string FindAppExe()
    {
        string[] candidates = new string[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Clash Verge", "clash-verge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "clash-verge", "clash-verge.exe")
        };
        foreach (string c in candidates)
        {
            if (File.Exists(c)) return c;
        }
        return null;
    }
}
