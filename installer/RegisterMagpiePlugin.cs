// Registers magpie-system-prompt-file with magpie, and takes it out again.
//
//   RegisterMagpiePlugin.exe             register, and print what happened
//   RegisterMagpiePlugin.exe --quiet     register, no output
//   RegisterMagpiePlugin.exe --uninstall take it out of magpie's list
//
// It writes magpie's own plugins.json, so it does not need magpie's CLI
// to be found: the Windows build of magpie is a single exe the user
// leaves where they downloaded it (Downloads is the usual place), which is
// neither on PATH nor under %LOCALAPPDATA%\Programs. When the CLI is
// found, it is used too, so magpie reloads the list at once.
//
// Everything it writes lives under the user's profile, so it needs no
// administrator rights.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

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
            var listPath = Path.Combine(config, "plugins.json");

            if (uninstall)
            {
                var magpie = FindMagpie();
                if (magpie != null) Run(magpie, quiet, "plugin", "rm", target);
                RemoveFromList(listPath, target);
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

            var options = "{\"prompt_file\":\"~/" + PromptRel +
                        "\",\"override\":true,\"position\":\"append\"," +
                        "\"strip_frontmatter\":true,\"gatewayTimeoutMs\":3000}";
            var written = WriteToList(listPath, target, options);

            // the CLI, when it is found, does the same thing and makes
            // magpie reload its list at once
            var cli = FindMagpie();
            if (cli != null)
            {
                Run(cli, quiet, "plugin", "add", target);
                Run(cli, quiet, "plugin", "options", target, options);
            }

            if (!quiet)
            {
                Console.WriteLine("magpie-system-prompt-file is installed.");
                Console.WriteLine("plugin : " + target);
                Console.WriteLine("prompt : " + prompt);
                if (written) Console.WriteLine("magpie's plugin list was updated.");
                if (cli != null) Console.WriteLine("magpie's CLI was found and used: " + cli);
                else Console.WriteLine("magpie's CLI was not found on PATH; the plugin list was written directly.");
                Console.WriteLine("Restart magpie (or it reloads on its own) and the plugin is in Plugins.");
                Console.WriteLine("Edit the prompt file and the next request uses it.");
            }
            return 0;
        }
        catch (Exception e)
        {
            if (!quiet) Console.Error.WriteLine("failed: " + e.Message);
            return 1;
        }
    }

    // WriteToList puts the plugin into magpie's plugins.json, keeping the
    // plugins that are already there. It is magpie's own format: a list of
    // {spec, off, options}. A file that cannot be read is left alone and
    // reported, so a broken list is never overwritten.
    static bool WriteToList(string listPath, string spec, string optionsJson)
    {
        var list = new Dictionary<string, object>();
        var ser = new JavaScriptSerializer();

        object existing = null;
        if (File.Exists(listPath))
        {
            var raw = File.ReadAllText(listPath, Encoding.UTF8);
            if (!string.IsNullOrEmpty(raw.Trim()))
            {
                try { existing = ser.DeserializeObject(raw); }
                catch { return false; }
            }
        }

        var plugins = new List<object>();
        var old = existing as Dictionary<string, object>;
        if (old != null && old.ContainsKey("plugins"))
        {
            var arr = old["plugins"] as object[];
            if (arr != null) foreach (var e in arr) if (e != null) plugins.Add(e);
        }

        // take the old entry of this plugin out, then add it again
        for (int i = plugins.Count - 1; i >= 0; i--)
        {
            var e = plugins[i] as Dictionary<string, object>;
            if (e != null && e.ContainsKey("spec"))
            {
                var s = e["spec"] as string;
                if (s != null && (string.Equals(s, spec, StringComparison.OrdinalIgnoreCase) ||
                                   s.EndsWith(PluginDirName, StringComparison.OrdinalIgnoreCase)))
                {
                    plugins.RemoveAt(i);
                }
            }
        }

        var entry = new Dictionary<string, object>();
        entry["spec"] = spec;
        entry["options"] = ser.DeserializeObject(optionsJson);
        plugins.Add(entry);

        var outList = new Dictionary<string, object>();
        outList["plugins"] = plugins.ToArray();
        if (old != null)
        {
            foreach (var kv in old)
            {
                if (kv.Key == "plugins") continue;
                outList[kv.Key] = kv.Value;
            }
        }

        var dir = Path.GetDirectoryName(listPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(listPath, ser.Serialize(outList) + "\n", new UTF8Encoding(false));
        return true;
    }

    // RemoveFromList takes the plugin out of magpie's plugins.json.
    static void RemoveFromList(string listPath, string spec)
    {
        if (!File.Exists(listPath)) return;
        var ser = new JavaScriptSerializer();
        var raw = File.ReadAllText(listPath, Encoding.UTF8);
        if (string.IsNullOrEmpty(raw.Trim())) return;
        object existing;
        try { existing = ser.DeserializeObject(raw); } catch { return; }
        var old = existing as Dictionary<string, object>;
        if (old == null || !old.ContainsKey("plugins")) return;
        var arr = old["plugins"] as object[];
        if (arr == null) return;
        var keep = new List<object>();
        foreach (var e in arr)
        {
            var d = e as Dictionary<string, object>;
            if (d != null && d.ContainsKey("spec"))
            {
                var s = d["spec"] as string;
                if (s != null && (string.Equals(s, spec, StringComparison.OrdinalIgnoreCase) ||
                                   s.EndsWith(PluginDirName, StringComparison.OrdinalIgnoreCase)))
                    continue;
            }
            keep.Add(e);
        }
        var outList = new Dictionary<string, object>();
        foreach (var kv in old) outList[kv.Key == "plugins" ? "plugins" : kv.Key] = kv.Key == "plugins" ? keep.ToArray() : kv.Value;
        File.WriteAllText(listPath, ser.Serialize(outList) + "\n", new UTF8Encoding(false));
    }

    // FindMagpie looks for magpie's CLI: the one on PATH first, then the
    // places the Windows build is left in. The Windows build is a single
    // exe the user downloads and runs where they like, so the folders it
    // is most often left in are all asked.
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
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var known = new List<string> {
            Path.Combine(local, "Programs", "magpie", "magpie.exe"),
            Path.Combine(local, "Programs", "Magpie", "magpie.exe"),
            Path.Combine(local, "Programs", "Magpie", "magpie.exe"),
            Path.Combine(roaming, "Programs", "magpie", "magpie.exe"),
            Path.Combine(local, "magpie", "magpie.exe"),
            Path.Combine(profile, "Downloads", "magpie.exe"),
            Path.Combine(profile, "Desktop", "magpie.exe"),
            Path.Combine(profile, "magpie.exe"),
            Path.Combine(local, "Microsoft", "WindowsApps", "magpie.exe"),
        };
        foreach (var c in known) if (File.Exists(c)) return c;

        // the folder the running magpie (if any) was started from
        return RunningExe();
    }

    // RunningExe is the magpie that is running now, when there is one.
    static string RunningExe()
    {
        try
        {
            foreach (var p in Process.GetProcesses())
            {
                try
                {
                    var name = p.ProcessName;
                    if (!string.Equals(name, "magpie", StringComparison.OrdinalIgnoreCase)) continue;
                    var exe = p.MainModule.FileName;
                    if (!string.IsNullOrEmpty(exe) && File.Exists(exe)) return exe;
                }
                catch { }
                finally { p.Dispose(); }
            }
        }
        catch { }
        return null;
    }

    // Run runs magpie's CLI and waits for it.
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
