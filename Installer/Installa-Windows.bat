@echo off
chcp 65001 >nul
title ChordPilot - Installazione
:menu
cls
echo.
echo   ChordPilot - Installazione
echo   ==========================
echo.
echo   1) iPad - installa l'app con Sideloadly (file .ipa)
echo   2) Windows VST3 / standalone - informazioni (in arrivo)
echo   3) Esci
echo.
set /p CHOICE=  Scelta [1-3]: 
if "%CHOICE%"=="1" (
  start "" "https://sideloadly.io"
  start "" "%~dp0iPad"
  echo.
  echo   Trascina ChordPilot-iPad-unsigned.ipa in Sideloadly, collega l'iPad e premi Start.
  pause
  goto menu
)
if "%CHOICE%"=="2" (
  start "" "%~dp0Windows\LEGGIMI.md"
  goto menu
)
exit /b 0
