#!/bin/bash
# ChordPilot – installazione in un clic su Linux: plug-in VST3 + app Standalone.
set -e
cd "$(dirname "$0")"
SRC="$(pwd)/Linux"
if [ ! -f "$SRC/ChordPilot" ]; then echo "Manca Linux/ChordPilot in questa cartella."; exit 1; fi
mkdir -p "$HOME/.vst3" "$HOME/.local/bin" "$HOME/.local/share/applications"
rm -rf "$HOME/.vst3/ChordPilot.vst3"
cp -R "$SRC/ChordPilot.vst3" "$HOME/.vst3/"
if [ -d "$SRC/ChordPilot MIDI.vst3" ]; then rm -rf "$HOME/.vst3/ChordPilot MIDI.vst3"; cp -R "$SRC/ChordPilot MIDI.vst3" "$HOME/.vst3/"; fi
cp "$SRC/ChordPilot" "$HOME/.local/bin/ChordPilot" && chmod +x "$HOME/.local/bin/ChordPilot"
cat > "$HOME/.local/share/applications/chordpilot.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=ChordPilot
Comment=Piano che suggerisce accordi e melodie
Exec=$HOME/.local/bin/ChordPilot
Categories=AudioVideo;Audio;Music;
Terminal=false
DESK
echo "✅ ChordPilot installato:"
echo "   • Plug-in VST3:  $HOME/.vst3/ChordPilot.vst3"
echo "   • App:           $HOME/.local/bin/ChordPilot (anche nel menu Applicazioni)"
