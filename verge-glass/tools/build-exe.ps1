$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$out = Join-Path $root "VergeGlass-Setup.exe"
$src = Join-Path $env:TEMP "VergeGlassSetup.cs"

$cs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

class Setup
{
    static int Main(string[] args)
    {
        bool uninstall = args.Length > 0 && args[0].ToLowerInvariant().Contains("uninstall");
        bool quiet = Array.Exists(args, a => a.Equals("/quiet", StringComparison.OrdinalIgnoreCase));

        Console.WriteLine();
        Console.WriteLine("  Verge Glass " + (uninstall ? "uninstaller" : "installer"));
        Console.WriteLine();

        string work = Path.Combine(Path.GetTempPath(), "VergeGlassSetup");
        string srcDir = Path.Combine(work, "src");
        Directory.CreateDirectory(srcDir);

        Assembly asm = Assembly.GetExecutingAssembly();
        foreach (string name in asm.GetManifestResourceNames())
        {
            string rel = null;
            if (name.EndsWith("verge-glass.css")) rel = Path.Combine("src", "verge-glass.css");
            else if (name.EndsWith("verge-glass.js")) rel = Path.Combine("src", "verge-glass.js");
            else if (name.EndsWith("plugin.json")) rel = "plugin.json";
            else if (name.EndsWith("VergeGlass.ps1")) rel = "VergeGlass.ps1";
            if (rel == null) continue;
            using (Stream s = asm.GetManifestResourceStream(name))
            using (FileStream f = File.Create(Path.Combine(work, rel)))
            {
                s.CopyTo(f);
            }
        }

        string script = Path.Combine(work, "VergeGlass.ps1");
        string action = uninstall ? "uninstall" : "install";
        string argline = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" " + action;

        var psi = new ProcessStartInfo("powershell.exe", argline);
        psi.UseShellExecute = false;
        Process proc = Process.Start(psi);
        proc.WaitForExit();

        Console.WriteLine();
        if (proc.ExitCode == 0) Console.WriteLine(uninstall ? "  [ok] uninstalled" : "  [ok] installed");
        else Console.WriteLine("  [x] failed with exit code " + proc.ExitCode);

        if (!quiet && !Console.IsInputRedirected)
        {
            Console.WriteLine();
            Console.WriteLine("  Press any key to exit ...");
            Console.ReadKey(true);
        }
        return proc.ExitCode;
    }
}
'@
[IO.File]::WriteAllText($src, $cs, (New-Object Text.UTF8Encoding $false))

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "csc.exe not found" }

$res = @(
    "/resource:$root\src\verge-glass.css,verge-glass.css",
    "/resource:$root\src\verge-glass.js,verge-glass.js",
    "/resource:$root\plugin.json,plugin.json",
    "/resource:$root\VergeGlass.ps1,VergeGlass.ps1"
)
& $csc /nologo /target:exe /out:$out $res $src
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }
"built: $out (" + [math]::Round((Get-Item $out).Length / 1KB, 1) + " KB)"
