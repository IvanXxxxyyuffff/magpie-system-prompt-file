; magpie-system-prompt-file installer
;
;   1. copy the plugin into %USERPROFILE%\.config\magpie\plugins\
;   2. write the persona to %USERPROFILE%\.config\magpie\prompts\system.md
;      when the user has no prompt file yet (an existing one is kept)
;   3. put the plugin into magpie's plugins.json and register it with
;      magpie's CLI when it can be found
;
; Nothing here needs administrator rights: everything is written under the
; user's own profile.

!include "MUI2.nsh"
!include "LogicLib.nsh"

!define PLUGIN_NAME "magpie-system-prompt-file"
!define PLUGIN_VERSION "0.5.0"
!define PUBLISHER "IvanXxxxyyuffff"
!define HELPER "RegisterMagpiePlugin.exe"

Name "${PLUGIN_NAME} ${PLUGIN_VERSION}"
OutFile "magpie-system-prompt-file-setup.exe"
Unicode true
InstallDir "$LOCALAPPDATA\Programs\${PLUGIN_NAME}"
InstallDirRegKey HKCU "Software\${PLUGIN_NAME}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${PLUGIN_VERSION}.0"
VIAddVersionKey "ProductName" "${PLUGIN_NAME}"
VIAddVersionKey "FileDescription" "Magpie plugin: a system prompt (persona) from a local .md / .txt file"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileVersion" "${PLUGIN_VERSION}.0"
VIAddVersionKey "ProductVersion" "${PLUGIN_VERSION}.0"
VIAddVersionKey "LegalCopyright" "MIT"

!define MUI_ABORTWARNING
!define MUI_ICON "magpie.ico"
!define MUI_UNICON "magpie.ico"

!define MUI_FINISHPAGE_RUN "notepad.exe"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenPromptFile
!define MUI_FINISHPAGE_RUN_TEXT "打开人格文件 / Open the persona file"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

Var PLUGIN_DIR
Var PROMPTS_DIR
Var PKG_DIR
Var LOG_FILE

Section "Install" SecInstall
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${HELPER}"
  File "payload\README.md"
  File "payload\LICENSE"
  SetOutPath "$INSTDIR\payload"
  File "payload\install.ps1"
  File "payload\package.json"
  File "payload\system-prompt.hooks.mjs"
  File "payload\system.md"

  ; magpie keeps its files in %USERPROFILE%\.config\magpie on Windows too
  StrCpy $PLUGIN_DIR "$PROFILE\.config\magpie\plugins"
  StrCpy $PROMPTS_DIR "$PROFILE\.config\magpie\prompts"
  StrCpy $PKG_DIR "$PLUGIN_DIR\${PLUGIN_NAME}"
  CreateDirectory "$PKG_DIR"
  CreateDirectory "$PROMPTS_DIR"

  ; the plugin's own copy inside magpie's plugins folder
  CopyFiles "$INSTDIR\payload\package.json" "$PKG_DIR\package.json"
  CopyFiles "$INSTDIR\payload\system-prompt.hooks.mjs" "$PKG_DIR\system-prompt.hooks.mjs"

  ; the persona: written only when the user has no prompt file yet
  IfFileExists "$PROMPTS_DIR\system.md" 0 0
    CopyFiles "$INSTDIR\payload\system.md" "$PROMPTS_DIR\system.md"
    DetailPrint "Writing the persona to $PROMPTS_DIR\system.md"

  WriteRegStr HKCU "Software\${PLUGIN_NAME}" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; register with magpie now, so the plugin works without a second step
  DetailPrint "Registering the plugin with magpie..."
  StrCpy $LOG_FILE "$TEMP\${PLUGIN_NAME}-install.log"
  DetailPrint "  (a log is left at $LOG_FILE)"
  ; the script writes its own log: NSIS's ExecWait cannot redirect
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\payload\install.ps1" -Log "$LOG_FILE"' $0
  ${If} $0 == 0
    DetailPrint "Done."
  ${ElseIf} $0 == 9009
    DetailPrint "PowerShell was not found. Use the shortcut on your desktop to finish."
  ${Else}
    DetailPrint "The script reported a problem (exit $0). See $LOG_FILE"
  ${EndIf}

  ; the helper is the fallback: it writes the plugin list by itself
  ${If} $0 != 0
    DetailPrint "Falling back to the bundled helper..."
    ExecWait '"$INSTDIR\${HELPER}" --quiet' $1
    ${If} $1 == 0
      DetailPrint "Done."
    ${Else}
      DetailPrint "Could not finish (exit $1). Run the desktop shortcut once magpie is installed."
    ${EndIf}
  ${EndIf}

  CreateShortCut "$DESKTOP\${PLUGIN_NAME}.lnk" "$INSTDIR\${HELPER}"
  CreateShortCut "$SMPROGRAMS\${PLUGIN_NAME}.lnk" "$INSTDIR\${HELPER}"
  CreateShortCut "$SMPROGRAMS\Uninstall ${PLUGIN_NAME}.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  ; take the plugin out of magpie first: it needs the helper to still be there
  ExecWait '"$INSTDIR\${HELPER}" --uninstall --quiet' $0

  Delete "$INSTDIR\${HELPER}"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\payload\package.json"
  Delete "$INSTDIR\payload\system-prompt.hooks.mjs"
  Delete "$INSTDIR\payload\system.md"
  Delete "$INSTDIR\payload\install.ps1"
  Delete "$INSTDIR\install.ps1"
  RMDir "$INSTDIR\payload"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${PLUGIN_NAME}.lnk"
  Delete "$SMPROGRAMS\${PLUGIN_NAME}.lnk"
  Delete "$SMPROGRAMS\Uninstall ${PLUGIN_NAME}.lnk"

  DeleteRegKey HKCU "Software\${PLUGIN_NAME}"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
!insertmacro MUI_DESCRIPTION_TEXT ${PLUGIN_NAME} "Installs the Magpie gateway hook that reads a system prompt (persona) from a local .md / .txt file and injects it into every agent request.$\\n$\\nThe plugin is registered with magpie automatically, and the persona that ships with it is written to %USERPROFILE%\\.config\\magpie\\prompts\\system.md (an existing file there is kept as it is).$\\n$\\nThe file is read on every request, so editing it takes effect at once, with no reload and no restart. Markdown and plain text both work."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function OpenPromptFile
  ExecShell "" "notepad.exe" '"$PROMPTS_DIR\system.md"'
FunctionEnd

Function .onInit
  StrCpy $PLUGIN_DIR "$PROFILE\.config\magpie\plugins"
  StrCpy $PROMPTS_DIR "$PROFILE\.config\magpie\prompts"
FunctionEnd

Function un.onInit
  StrCpy $PLUGIN_DIR "$PROFILE\.config\magpie\plugins"
  StrCpy $PROMPTS_DIR "$PROFILE\.config\magpie\prompts"
FunctionEnd
