; Aurora Signal - installer per Windows (Windows 7, 8, 10 e 11, 32 e 64 bit)
; Non richiede permessi di amministratore: installa nella cartella dell'utente.
Unicode true
!include "MUI2.nsh"
!include "WordFunc.nsh"

!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!define APPNAME "Aurora Signal"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AuroraSignal"

Name "${APPNAME}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\AuroraSignal"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APPNAME} ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "Installazione di ${APPNAME}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "(c) 2026 ${APPNAME}"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Benvenuto in ${APPNAME}"
!define MUI_WELCOMEPAGE_TEXT "Questa procedura installa ${APPNAME} sul computer.$\r$\n$\r$\nL'app mostra ogni giorno per ogni criptovaluta il segnale COMPRA o VENDI, con obiettivo di vendita e data stimata, controllando mercati e notizie mondiali.$\r$\n$\r$\nNon servono permessi di amministratore. Premi Avanti per continuare."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Apri ${APPNAME} adesso"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchApp

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE}"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Italian"

Var Browser
Var AppUrl

; Cerca un browser che supporta la finestra dedicata (--app): Edge, Chrome, Brave
Function FindBrowser
  StrCpy $Browser ""
  IfFileExists "$PROGRAMFILES64\Microsoft\Edge\Application\msedge.exe" 0 +3
    StrCpy $Browser "$PROGRAMFILES64\Microsoft\Edge\Application\msedge.exe"
    Return
  IfFileExists "$PROGRAMFILES32\Microsoft\Edge\Application\msedge.exe" 0 +3
    StrCpy $Browser "$PROGRAMFILES32\Microsoft\Edge\Application\msedge.exe"
    Return
  IfFileExists "$PROGRAMFILES64\Google\Chrome\Application\chrome.exe" 0 +3
    StrCpy $Browser "$PROGRAMFILES64\Google\Chrome\Application\chrome.exe"
    Return
  IfFileExists "$PROGRAMFILES32\Google\Chrome\Application\chrome.exe" 0 +3
    StrCpy $Browser "$PROGRAMFILES32\Google\Chrome\Application\chrome.exe"
    Return
  IfFileExists "$LOCALAPPDATA\Google\Chrome\Application\chrome.exe" 0 +3
    StrCpy $Browser "$LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    Return
  IfFileExists "$LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe" 0 +2
    StrCpy $Browser "$LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
FunctionEnd

Function MakeShortcut ; $0 = percorso del collegamento
  StrCmp $Browser "" 0 +3
    CreateShortCut "$0" "$INSTDIR\app.html" "" "$INSTDIR\icon.ico" 0
    Return
  CreateShortCut "$0" "$Browser" '--app="$AppUrl"' "$INSTDIR\icon.ico" 0
FunctionEnd

Function LaunchApp
  StrCmp $Browser "" 0 +3
    ExecShell "open" "$INSTDIR\app.html"
    Return
  Exec '"$Browser" --app="$AppUrl"'
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  File "/oname=app.html" "${APPHTML}"
  File "/oname=icon.ico" "${ICON}"
  File "/oname=LEGGIMI.txt" "${README}"
  WriteUninstaller "$INSTDIR\Disinstalla.exe"

  Call FindBrowser
  ${WordReplace} "$INSTDIR\app.html" "\" "/" "+" $AppUrl
  StrCpy $AppUrl "file:///$AppUrl"

  StrCpy $0 "$DESKTOP\${APPNAME}.lnk"
  Call MakeShortcut
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  StrCpy $0 "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Call MakeShortcut
  CreateShortCut "$SMPROGRAMS\${APPNAME}\Disinstalla ${APPNAME}.lnk" "$INSTDIR\Disinstalla.exe"

  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "Publisher" "${APPNAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\icon.ico"
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Disinstalla.exe"'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APPNAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APPNAME}"
  Delete "$INSTDIR\app.html"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\LEGGIMI.txt"
  Delete "$INSTDIR\Disinstalla.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${UNINSTKEY}"
SectionEnd
