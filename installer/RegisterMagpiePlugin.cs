// Registers magpie-system-prompt-file with magpie, and takes it out again.
//
//   RegisterMagpiePlugin.exe             register, and print what happened
//   RegisterMagpiePlugin.exe --quiet     register, no output
//   RegisterMagpiePlugin.exe --uninstall take it out of magpie's list
//
// It finds magpie's CLI, copies the plugin into magpie's own plugins
// folder and sets the plugin's options. Everything it writes lives under
// the user's profile, so it needs no administrator rights.

using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class Program
{
    const string PluginDirName = "magpie-system-prompt-file";
    const string SourceDirName = "payload";
    const string PromptRel = ".config/magpie/prompts/system.md";

    static int Main(string[] args)
    {
        bool quiet = false, uninstall = false;
        foreach (var a in args)
        {
            var t = a.TrimStart('-', '/').ToLowerInvariant();
            if (t == "quiet") quiet = true;
            else if (t == "uninstall") uninstall = true;
        }

        try
        {
            var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var config = Path.Combine(profile, ".config", "magpie");
            var pluginsDir = Path.Combine(config, "plugins");
            var promptsDir = Path.Combine(config, "prompts");
            var target = Path.Combine(pluginsDir, PluginDirName);
            var prompt = Path.Combine(promptsDir, "system.md");
            var magpie = FindMagpie();

            if (uninstall)
            {
                if (magpie != null) Run(magpie, quiet, "plugin", "rm", target);
                TryDelete(target);
                if (!quiet)
                {
                    Console.WriteLine(PluginDirName + " was removed from magpie.");
                    Console.WriteLine("Your prompt file was left where it was.");
                }
                return 0;
            }

            // the plugin's own copy inside magpie's plugins folder
            var source = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, SourceDirName);
            if (!Directory.Exists(source)) source = AppDomain.CurrentDomain.BaseDirectory;
            Directory.CreateDirectory(target);
            foreach (var name in new[] { "package.json", "system-prompt.hooks.mjs" })
            {
                var from = Path.Combine(source, name);
                if (File.Exists(from)) File.Copy(from, Path.Combine(target, name), true);
            }

            // the prompt file: the user's own, never overwritten
            Directory.CreateDirectory(promptsDir);
            if (!File.Exists(prompt))
            {
                File.WriteAllText(prompt,
                    "---\r\ntitle: system\r\n---\r\n\r\n" +
                    "<!-- Put your own system prompt (persona) here.\r\n" +
                    "     This file is read on every request, so editing it takes effect at once,\r\n" +
                    "     with no reload and no restart. Markdown and plain text both work. -->\r\n",
                    new UTF8Encoding(false));
            }

            if (magpie == null)
            {
                if (!quiet)
                {
                    Console.WriteLine("magpie was not found on this machine.");
                    Console.WriteLine("The plugin's files are in " + target + " and the prompt file is " + prompt + ".");
                    Console.WriteLine("Install magpie and run this again (or use the desktop shortcut) to register it.");
                }
                return 2;
            }

            Run(magpie, quiet, "plugin", "add", target);
            var options = "{\"prompt_file\":\"~/" + PromptRel +
                        "\",\"override\":true,\"position\":\"append\"," +
                        "\"strip_frontmatter\":true,\"gatewayTimeoutMs\":3000}";
            Run(magpie, quiet, "plugin", "options", target, options);

            if (!quiet)
            {
                Console.WriteLine("magpie-system-prompt-file is installed.");
                Console.WriteLine("prompt file: " + prompt);
                Console.WriteLine("Edit it and the next request uses it.");
            }
            return 0;
        }
        catch (Exception e)
        {
            if (!quiet) Console.Error.WriteLine("failed: " + e.Message);
            return 1;
        }
    }

    // FindMagpie looks for magpie's CLI: the one on PATH first, then the
    // places it is installed.
    static string FindMagpie()
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(';'))
        {
            if (dir.Trim().Length == 0) continue;
            var exe = Path.Combine(dir.Trim(), "magpie.exe");
            if (File.Exists(exe)) return exe;
        }
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var candidates = new[] {
            Path.Combine(local, "Programs", "magpie", "magpie.exe"),
            Path.Combine(roaming, "Programs", "magpie", "magpie.exe"),
            Path.Combine(local, "magpie", "magpie.exe"),
            Path.Combine(local, "Programs", "Magpie", "magpie.exe"),
        };
        foreach (var c in candidates) if (File.Exists(c)) return c;
        return null;
    }

    // Run runs magpie's CLI and waits for it. Its output goes to magpie's
    // own console unless it is quiet.
    static int Run(string exe, bool quiet, params string[] args)
    {
        try
        {
            var psi = new ProcessStartInfo(exe, Quote(args));
            psi.UseShellExecute = false;
            psi.CreateNoWindow = quiet;
            psi.RedirectStandardOutput = quiet;
            psi.RedirectStandardError = quiet;
            psi.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            using (var p = Process.Start(psi))
            {
                if (quiet)
                {
                    p.StandardOutput.ReadToEnd();
                    p.StandardError.ReadToEnd();
                }
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception e)
        {
            if (!quiet) Console.Error.WriteLine("could not run " + exe + ": " + e.Message);
            return 1;
        }
    }

    static string Quote(string[] args)
    {
        var sb = new StringBuilder();
        foreach (var a in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            sb.Append('"').Append(a.Replace("\"", "\\\"")).Append('"');
        }
        return sb.ToString();
    }

    static void TryDelete(string dir)
    {
        try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch { }
    }
}
