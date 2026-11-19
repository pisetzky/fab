@echo off
chcp 65001 >nul
title ChordPilot - Installazione
:menu
cls
echo.
echo   ChordPilot - Installazione
echo   ==========================
echo.
echo   0) TUTTO - VST3 + app Standalone in un clic  (Invio)
echo   1) Windows - plug-in VST3 e/o app Standalone (scegli nell'installer)
echo   2) iPad - installa l'app con Sideloadly (file .ipa)
echo   3) Esci
echo.
set CHOICE=0
set /p CHOICE=  Scelta [0-3, Invio = 0]: 
if "%CHOICE%"=="0" (
  if exist "%~dp0Windows\ChordPilot-Windows-Setup.exe" (
    echo   Installo VST3 + app Standalone...
    "%~dp0Windows\ChordPilot-Windows-Setup.exe" /SILENT /COMPONENTS="vst3,standalone"
    echo   Fatto. iPad: apri INSTALLA.html sull'iPad.
  ) else (
    echo   Il setup non e' in questa cartella: lo crea la compilazione su GitHub.
  )
  start "" "%~dp0INSTALLA.html"
  pause
  goto menu
)
if "%CHOICE%"=="1" (
  if exist "%~dp0Windows\ChordPilot-Windows-Setup.exe" (
    start "" "%~dp0Windows\ChordPilot-Windows-Setup.exe"
  ) else (
    echo   Il setup non e' in questa cartella: lo crea la compilazione su GitHub.
    start "" "%~dp0Windows\LEGGIMI.md"
    pause
  )
  goto menu
)
if "%CHOICE%"=="2" (
  start "" "https://sideloadly.io"
  start "" "%~dp0iPad"
  echo.
  echo   Trascina ChordPilot-iPad-unsigned.ipa in Sideloadly, collega l'iPad e premi Start.
  pause
  goto menu
)
exit /b 0
