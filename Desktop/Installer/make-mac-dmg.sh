#!/bin/bash
# Builds ChordPilot-Mac.dmg for customers: open it, double-click "Installa ChordPilot", done.
# Usage: make-mac-dmg.sh <ChordPilot artefacts/Release> <dir containing ChordPilot-Mac.pkg> <output dir> [<ChordPilotMIDI artefacts/Release>]
set -euo pipefail
PKGDIR="$2"; OUT="$3"
STAGE="$(mktemp -d)/ChordPilot"
mkdir -p "$STAGE" "$OUT"
cp "$PKGDIR/ChordPilot-Mac.pkg" "$STAGE/Installa ChordPilot.pkg"
cat > "$STAGE/Disinstalla ChordPilot.command" <<'UNINSTALL'
#!/bin/bash
echo "Rimuovo ChordPilot (serve la password del Mac)…"
sudo rm -rf "/Applications/ChordPilot.app" \
  "/Library/Audio/Plug-Ins/VST3/ChordPilot.vst3" "/Library/Audio/Plug-Ins/VST3/ChordPilot MIDI.vst3" \
  "/Library/Audio/Plug-Ins/Components/ChordPilot.component" "/Library/Audio/Plug-Ins/Components/ChordPilot MIDI.component"
sudo pkgutil --forget com.fabaudio.chordpilot.vst3 >/dev/null 2>&1
sudo pkgutil --forget com.fabaudio.chordpilot.au >/dev/null 2>&1
sudo pkgutil --forget com.fabaudio.chordpilot.app >/dev/null 2>&1
echo "Fatto: ChordPilot è stato rimosso."
UNINSTALL
chmod +x "$STAGE/Disinstalla ChordPilot.command"
cat > "$STAGE/LEGGIMI.txt" <<'TXT'
ChordPilot per Mac (Intel e Apple Silicon, macOS 10.15 o successivo)

1. Doppio clic su "Installa ChordPilot".
2. Premi Continua → Installa (inserisci la password del Mac quando richiesta).
3. Apri la tua DAW e cerca Fab Audio → ChordPilot (strumento) o ChordPilot MIDI (effetto MIDI).
   L'app ChordPilot è nella cartella Applicazioni.

Non serve installare nient'altro.
Per rimuoverlo: doppio clic su "Disinstalla ChordPilot".
TXT
hdiutil create -volname "ChordPilot" -srcfolder "$STAGE" -ov -format UDZO "$OUT/ChordPilot-Mac.dmg"
if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then codesign --sign "$MACOS_SIGN_IDENTITY" --timestamp "$OUT/ChordPilot-Mac.dmg"; fi
echo "Built $OUT/ChordPilot-Mac.dmg"
