#!/bin/bash
# Builds ChordPilot-Mac.pkg with selectable components (VST3 / AU / Standalone).
# Usage: make-mac-pkg.sh <artefacts/Release dir> <output dir>
set -euo pipefail
SRC="$1"; OUT="$2"; MIDI="${3:-}"; WORK="$(mktemp -d)"
mkdir -p "$OUT" "$WORK/vst3/Library/Audio/Plug-Ins/VST3" "$WORK/au/Library/Audio/Plug-Ins/Components" "$WORK/app/Applications"
cp -R "$SRC/VST3/ChordPilot.vst3" "$WORK/vst3/Library/Audio/Plug-Ins/VST3/"
cp -R "$SRC/AU/ChordPilot.component" "$WORK/au/Library/Audio/Plug-Ins/Components/"
if [ -n "$MIDI" ]; then   # ChordPilot MIDI: MIDI-effect version that drives any instrument
  cp -R "$MIDI/VST3/ChordPilot MIDI.vst3" "$WORK/vst3/Library/Audio/Plug-Ins/VST3/"
  cp -R "$MIDI/AU/ChordPilot MIDI.component" "$WORK/au/Library/Audio/Plug-Ins/Components/"
fi
cp -R "$SRC/Standalone/ChordPilot.app" "$WORK/app/Applications/"
pkgbuild --root "$WORK/vst3" --identifier com.fabaudio.chordpilot.vst3 --version 1.0.0 --install-location / "$WORK/vst3.pkg"
pkgbuild --root "$WORK/au" --identifier com.fabaudio.chordpilot.au --version 1.0.0 --install-location / "$WORK/au.pkg"
pkgbuild --root "$WORK/app" --identifier com.fabaudio.chordpilot.app --version 1.0.0 --install-location / "$WORK/app.pkg"
cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>ChordPilot</title>
  <options customize="always" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <choices-outline>
    <line choice="vst3"/><line choice="au"/><line choice="app"/>
  </choices-outline>
  <choice id="vst3" title="Plug-in VST3 (ChordPilot + ChordPilot MIDI)" description="Ableton Live, Cubase, Reaper, Studio One, Bitwig, FL Studio…"><pkg-ref id="com.fabaudio.chordpilot.vst3"/></choice>
  <choice id="au" title="Plug-in Audio Unit (ChordPilot + ChordPilot MIDI)" description="Logic Pro (anche come MIDI FX),, GarageBand, MainStage, Ableton Live…"><pkg-ref id="com.fabaudio.chordpilot.au"/></choice>
  <choice id="app" title="App Standalone" description="Si collega da sola alla scheda audio e alle tastiere MIDI."><pkg-ref id="com.fabaudio.chordpilot.app"/></choice>
  <pkg-ref id="com.fabaudio.chordpilot.vst3">vst3.pkg</pkg-ref>
  <pkg-ref id="com.fabaudio.chordpilot.au">au.pkg</pkg-ref>
  <pkg-ref id="com.fabaudio.chordpilot.app">app.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" "$OUT/ChordPilot-Mac.pkg"
echo "Built $OUT/ChordPilot-Mac.pkg"
