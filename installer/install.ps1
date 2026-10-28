# Install magpie-system-prompt-file on Windows.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# It writes the plugin into %USERPROFILE%\.config\magpie\plugins\ and puts
# it into magpie's plugins.json, so magpie shows it in Plugins without its
# CLI having to be found. The Windows build of magpie is a single exe the
# user leaves where they downloaded it (Downloads is the usual place),
# which is neither on PATH nor under %LOCALAPPDATA%\Programs, so the
# plugin list is written directly rather than left to the CLI.
#
# It creates the prompt file if it is missing and never overwrites one
# that is already there.
#
# Everything is written as UTF-8 without a byte order mark, which is what
# magpie's JSON reader expects. This file is UTF-8 with a byte order mark,
# so Windows PowerShell 5.1 reads it as UTF-8 and not as the system's
# code page.

param(
    [string]$Log = ""
)

$ErrorActionPreference = "Stop"

# Everything is written to the log as well as to the console, so the
# installer can leave a record of what happened without having to
# redirect anything (NSIS's ExecWait cannot redirect).
if ($Log) {
    try {
        Remove-Item $Log -ErrorAction SilentlyContinue
        Start-Transcript -Path $Log -Force | Out-Null
    } catch { }
}

# A plain file log beside the transcript: Start-Transcript can refuse to
# start, and the installer wants a record either way.
$script:LogLines = New-Object System.Collections.ArrayList
function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    [void]$script:LogLines.Add($line)
    Write-Host $m
    if ($Log) {
        try { Add-Content -Path $Log -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    }
}

function Find-Magpie {
    $c = Get-Command magpie.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\magpie\magpie.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Magpie\magpie.exe"),
        (Join-Path $env:APPDATA "Programs\magpie\magpie.exe"),
        (Join-Path $env:LOCALAPPDATA "magpie\magpie.exe"),
        (Join-Path $env:USERPROFILE "Downloads\magpie.exe"),
        (Join-Path $env:USERPROFILE "Desktop\magpie.exe"),
        (Join-Path $env:USERPROFILE "magpie.exe")
    )
    foreach ($c2 in $candidates) { if (Test-Path $c2) { return $c2 } }

    $proc = Get-Process magpie -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { try { return $proc.Path } catch { } }
    return $null
}

$PluginName  = "magpie-system-prompt-file"
$Source      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload     = Join-Path $Source "payload"
if (-not (Test-Path (Join-Path $Payload "system-prompt.hooks.mjs"))) { $Payload = $Source }

$Home_     = Join-Path $env:USERPROFILE ".config\magpie"
$Plugins   = Join-Path $Home_ "plugins"
$PromptDir = Join-Path $Home_ "prompts"
$Package   = Join-Path $Plugins $PluginName
$Prompt    = Join-Path $PromptDir "system.md"
$ListFile  = Join-Path $Home_ "plugins.json"

New-Item -ItemType Directory -Force -Path $Package   | Out-Null
New-Item -ItemType Directory -Force -Path $PromptDir | Out-Null

Copy-Item (Join-Path $Payload "package.json")           -Destination $Package -Force
Copy-Item (Join-Path $Payload "system-prompt.hooks.mjs") -Destination $Package -Force

if (-not (Test-Path $Prompt)) {
    $template = @"
---
title: system
---

<!-- Put your own system prompt (persona) here.
     This file is read on every request, so editing it takes effect at once,
     with no reload and no restart. Markdown and plain text both work. -->
"@
    [IO.File]::WriteAllText($Prompt, $template, (New-Object Text.UTF8Encoding $false))
    Write-Log "created $Prompt"
}

$options = @{
    prompt_file       = "~/.config/magpie/prompts/system.md"
    override          = $true
    position          = "append"
    strip_frontmatter = $true
    gatewayTimeoutMs  = 3000
}

# magpie's plugins.json, with the plugins that are already in it kept
$list = @{ plugins = @() }
if (Test-Path $ListFile) {
    $raw = [IO.File]::ReadAllText($ListFile)
    if ($raw.Trim()) {
        try { $list = $raw | ConvertFrom-Json } catch { $list = @{ plugins = @() } }
    }
}
$kept  = @($list.plugins | Where-Object { $_.spec -notlike "*$PluginName" })
$entry = [ordered]@{ spec = $Package; options = $options }
$list.plugins = @($kept) + @([pscustomobject]$entry)
$json = $list | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($ListFile, $json + "`n", (New-Object Text.UTF8Encoding $false))
Write-Log "updated $ListFile"

# magpie's CLI, when it is somewhere we can find it, does the same thing
# and makes magpie reload its list at once
$magpie = Find-Magpie
if ($magpie) {
    & $magpie plugin add $Package | Out-Null
    # the options are one argument, and their quotes have to be escaped:
    # magpie reads them the way Windows hands a program its command line
    $optsJson = ($options | ConvertTo-Json -Compress) -replace '"', '\"'
    & $magpie plugin options $Package $optsJson | Out-Null
    Write-Log "registered with $magpie"
} else {
    Write-Log "magpie's CLI was not found; the plugin list was written directly."
}

Write-Host ""
Write-Log "installed. edit $Prompt and it takes effect on the next request."

# a marker, so a test can see this script really ran and not the fallback
[IO.File]::WriteAllText((Join-Path $env:TEMP "magpie-system-prompt-file.ps1-ran"), "yes", (New-Object Text.UTF8Encoding $false))

if ($Log) { try { Stop-Transcript | Out-Null } catch { } }
