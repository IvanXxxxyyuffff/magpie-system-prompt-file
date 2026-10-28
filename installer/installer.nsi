; magpie-system-prompt-file installer
;
;   1. copy the plugin into %USERPROFILE%\.config\magpie\plugins\
;   2. create %USERPROFILE%\.config\magpie\prompts\system.md if it is
;      not there yet
;   3. register the plugin with magpie and set its options
;
; The prompt file is the user's own: an existing one is never overwritten.

!include "MUI2.nsh"
!include "LogicLib.nsh"

!define PLUGIN_NAME "magpie-system-prompt-file"
!define PLUGIN_VERSION "0.4.0"
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

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_FINISHPAGE_RUN
!insertmacro MUI_FINISHPAGE_RUN_TEXT "打开提示词文件 / Open the prompt file"
!insertmacro MUI_FINISHPAGE_RUN_FUNCTION OpenPromptFile

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "Install" SecInstall
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${HELPER}"
  File "payload\README.md"
  File "payload\LICENSE"
  SetOutPath "$INSTDIR\payload"
  File "payload\package.json"
  File "payload\system-prompt.hooks.mjs"

  ; magpie keeps its files in %USERPROFILE%\.config\magpie on Windows too
  CreateDirectory "$PLUGIN_DIR"
  CreateDirectory "$PROMPTS_DIR"

  ; the prompt file: created only when the user has none yet
  IfFileExists "$PROMPTS_DIR\system.md" 0 0
    ClearErrors
    FileOpen $0 "$PROMPTS_DIR\system.md" w
    IfErrors 0 0
      FileWrite $0 "---$\r$\n"
      FileWrite $0 "title: system$\r$\n"
      FileWrite $0 "---$\r$\n$\r$\n"
      FileWrite $0 "<!-- Put your own system prompt (persona) here.$\r$\n"
      FileWrite $0 "     This file is read on every request, so editing it takes effect at once,$\r$\n"
      FileWrite $0 "     with no reload and no restart. Markdown and plain text both work. -->$\r$\n"
      FileClose $0

  WriteRegStr HKCU "Software\${PLUGIN_NAME}" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; register with magpie now, so the plugin works without a second step
  DetailPrint "Registering the plugin with magpie..."
  ExecWait '"$INSTDIR\${HELPER}" --quiet' $0
  ${If} $0 == 2
    DetailPrint "magpie was not found. Install magpie, then run the shortcut on your desktop to register the plugin."
  ${ElseIf} $0 != 0
    DetailPrint "Could not run magpie's CLI (exit $0). Use the shortcut on your desktop to finish."
  ${Else}
    DetailPrint "Registered."
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
  RMDir "$INSTDIR\payload"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${PLUGIN_NAME}.lnk"
  Delete "$SMPROGRAMS\${PLUGIN_NAME}.lnk"
  Delete "$SMPROGRAMS\Uninstall ${PLUGIN_NAME}.lnk"

  DeleteRegKey HKCU "Software\${PLUGIN_NAME}"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
!insertmacro MUI_DESCRIPTION_TEXT ${PLUGIN_NAME} "Installs the Magpie gateway hook that reads a system prompt (persona) from a local .md / .txt file and injects it into every agent request.$n$nThe plugin is registered with magpie automatically. The prompt file lives at:$n$n$PROMPTS_DIR\system.md$n$nEdit it whenever you like: the file is read on every request, so a change takes effect at once, with no reload and no restart.$n$nMarkdown and plain text both work."
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
