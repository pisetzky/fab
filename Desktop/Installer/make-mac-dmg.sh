#!/bin/bash
# Builds ChordPilot-Mac.dmg: drag-to-install app, one-click installer (.pkg) and the plug-ins.
# Usage: make-mac-dmg.sh <artefacts/Release dir> <dir containing ChordPilot-Mac.pkg> <output dir>
set -euo pipefail
SRC="$1"; PKGDIR="$2"; OUT="$3"; MIDI="${4:-}"
STAGE="$(mktemp -d)/ChordPilot"
mkdir -p "$STAGE/Plug-in" "$OUT"
cp -R "$SRC/Standalone/ChordPilot.app" "$STAGE/"
ln -s /Applications "$STAGE/Applicazioni"
cp "$PKGDIR/ChordPilot-Mac.pkg" "$STAGE/Installa ChordPilot (tutto).pkg"
cp -R "$SRC/VST3/ChordPilot.vst3" "$STAGE/Plug-in/"
cp -R "$SRC/AU/ChordPilot.component" "$STAGE/Plug-in/"
if [ -n "$MIDI" ]; then cp -R "$MIDI/VST3/ChordPilot MIDI.vst3" "$MIDI/AU/ChordPilot MIDI.component" "$STAGE/Plug-in/"; fi
cat > "$STAGE/LEGGIMI.txt" <<TXT
ChordPilot per Mac (Intel e Apple Silicon)

INSTALLA TUTTO IN UN CLIC
  Doppio clic su "Installa ChordPilot (tutto).pkg" e scegli VST3, Audio Unit e/o app.

OPPURE A MANO
  • App:       trascina ChordPilot.app nella cartella Applicazioni.
  • VST3:      copia Plug-in/ChordPilot.vst3 in /Library/Audio/Plug-Ins/VST3
  • AU:        copia Plug-in/ChordPilot.component in /Library/Audio/Plug-Ins/Components

Poi apri la DAW e cerca Fab Audio → ChordPilot.
TXT
hdiutil create -volname "ChordPilot" -srcfolder "$STAGE" -ov -format UDZO "$OUT/ChordPilot-Mac.dmg"
echo "Built $OUT/ChordPilot-Mac.dmg"
