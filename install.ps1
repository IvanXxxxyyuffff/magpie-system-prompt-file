# Install magpie-system-prompt-file on Windows.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# It copies the package into %USERPROFILE%\.config\magpie\plugins\
# magpie-system-prompt-file, creates the prompt file if it is missing, and
# prints the two commands that register the plugin and set its options.

$ErrorActionPreference = "Stop"

$Magpie = Join-Path $env:LOCALAPPDATA "Programs\magpie\magpie.exe"
if (-not (Test-Path $Magpie)) {
  $Magpie = Get-Command magpie -ErrorAction SilentlyContinue
  if (-not $Magpie) {
    Write-Error "magpie not found. Install it first, or run this script from a shell where 'magpie' is on PATH."
    exit 1
  }
  $Magpie = $Magpie.Source
}

$Source = Split-Path -Parent $MyInvocation.MyCommand.Path
$Home_ = Join-Path $env:USERPROFILE ".config\magpie"
$Plugins = Join-Path $Home_ "plugins"
$PromptDir = Join-Path $Home_ "prompts"
$Package = Join-Path $Plugins "magpie-system-prompt-file"
$PromptFile = Join-Path $PromptDir "system.md"

New-Item -ItemType Directory -Force -Path $Plugins | Out-Null
New-Item -ItemType Directory -Force -Path $PromptDir | Out-Null

# The package: this script's own directory, minus the git and install files.
Copy-Item -Path (Join-Path $Source "package.json") -Destination $Package -Force
Copy-Item -Path (Join-Path $Source "system-prompt.hooks.mjs") -Destination $Package -Force
if (Test-Path (Join-Path $Source "README.md")) {
  Copy-Item -Path (Join-Path $Source "README.md") -Destination $Package -Force
}

# The prompt file is created only when the user has none yet, so an existing
# one is never overwritten. It ships empty: the persona is the user's own.
if (-not (Test-Path $PromptFile)) {
  @"
---
title: system
---

<!-- Put your own system prompt (persona) here.
     This file is read on every request, so editing it takes effect at once,
     with no reload and no restart. Markdown and plain text both work. -->
"@ | Set-Content -Path $PromptFile -Encoding UTF8
  Write-Host "created $PromptFile"
}

$Options = '{
  "prompt_file": "~/.config/magpie/prompts/system.md",
  "override": true,
  "position": "append",
  "strip_frontmatter": true,
  "gatewayTimeoutMs": 3000
}'

& $Magpie plugin add $Package
& $Magpie plugin options $Package $Options

Write-Host ""
Write-Host "installed. edit $PromptFile and it takes effect on the next request."
