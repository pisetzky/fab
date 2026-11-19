#!/bin/bash
# ChordPilot – installer con menu. Doppio clic su questo file dal Finder (Mac).
cd "$(dirname "$0")"
HERE="$(pwd)"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        ChordPilot – Installazione    ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
echo "  Cosa vuoi installare?"
echo ""
echo "   1) iPad  – app + plug-in AUv3 (con Xcode, sull'iPad collegato)"
echo "   2) Mac Apple Silicon – app + plug-in AUv3 per Logic/GarageBand (con Xcode)"
echo "   3) iPad  – installa il file .ipa con Sideloadly"
echo "   4) Mac Intel / Windows (VST3) – informazioni"
echo "   5) Esci"
echo ""
read -r -p "  Scelta [1-5]: " CHOICE

prepare_project() {
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "  Serve Xcode: lo apro nell'App Store."; open "macappstore://apps.apple.com/app/xcode/id497799835"; exit 1
  fi
  SRC="$HERE/iPad/ChordPilot-source"
  if [ ! -d "$SRC" ]; then
    echo "  Estraggo il codice sorgente…"
    unzip -q -o "$HERE/iPad/ChordPilot-source.zip" -d "$HERE/iPad"
  fi
  cd "$SRC/ChordPilot" || exit 1
  if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      echo "  Installo XcodeGen…"; brew install xcodegen
    else
      echo "  Serve Homebrew (https://brew.sh) per installare XcodeGen. Installalo e riprova."; exit 1
    fi
  fi
  xcodegen generate && open ChordPilot.xcodeproj
}

case "$CHOICE" in
  1)
    prepare_project
    echo ""
    echo "  In Xcode: scegli il tuo Team in 'Signing & Capabilities' (target ChordPilot e ChordPilotAU),"
    echo "  seleziona il tuo iPad in alto e premi ▶︎."
    ;;
  2)
    prepare_project
    echo ""
    echo "  In Xcode: scegli il tuo Team, poi come destinazione 'My Mac (Designed for iPad)' e premi ▶︎."
    echo "  Dopo il primo avvio il plug-in compare in Logic Pro / GarageBand (Audio Units → Fab Audio)."
    ;;
  3)
    open "https://sideloadly.io"
    open "$HERE/iPad"
    echo "  Trascina ChordPilot-iPad-unsigned.ipa in Sideloadly e premi Start."
    ;;
  4)
    open "$HERE/Windows/LEGGIMI.md"
    ;;
  *)
    echo "  Ciao!";;
esac
echo ""
read -r -p "  Premi Invio per chiudere…" _
