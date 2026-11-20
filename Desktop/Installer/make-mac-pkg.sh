#!/bin/bash
# Builds ChordPilot-Mac.pkg: one installer, everything selected by default (VST3, AU, ChordPilot MIDI, app),
# with welcome screen and licence. The customer only clicks Continue → Install.
# Usage: make-mac-pkg.sh <ChordPilot artefacts/Release> <output dir> [<ChordPilotMIDI artefacts/Release>]
set -euo pipefail
SRC="$1"; OUT="$2"; MIDI="${3:-}"; WORK="$(mktemp -d)"
RES="$(cd "$(dirname "$0")" && pwd)/mac-resources"
mkdir -p "$OUT" "$WORK/vst3/Library/Audio/Plug-Ins/VST3" "$WORK/au/Library/Audio/Plug-Ins/Components" "$WORK/app/Applications"
cp -R "$SRC/VST3/ChordPilot.vst3" "$WORK/vst3/Library/Audio/Plug-Ins/VST3/"
cp -R "$SRC/AU/ChordPilot.component" "$WORK/au/Library/Audio/Plug-Ins/Components/"
if [ -n "$MIDI" ]; then
  cp -R "$MIDI/VST3/ChordPilot MIDI.vst3" "$WORK/vst3/Library/Audio/Plug-Ins/VST3/"
  cp -R "$MIDI/AU/ChordPilot MIDI.component" "$WORK/au/Library/Audio/Plug-Ins/Components/"
fi
cp -R "$SRC/Standalone/ChordPilot.app" "$WORK/app/Applications/"
# Bundles must never be "relocated": app, VST3 and AU share a bundle id, and a relocatable
# package would install one on top of another (or into an old copy elsewhere on the disk).
for part in vst3 au app; do
  pkgbuild --analyze --root "$WORK/$part" "$WORK/$part.plist"
  i=0
  while /usr/libexec/PlistBuddy -c "Print :$i" "$WORK/$part.plist" >/dev/null 2>&1; do
    /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$WORK/$part.plist"
    /usr/libexec/PlistBuddy -c "Set :$i:BundleIsVersionChecked false" "$WORK/$part.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :$i:BundleOverwriteAction upgrade" "$WORK/$part.plist" 2>/dev/null || true
    i=$((i+1))
  done
  pkgbuild --root "$WORK/$part" --component-plist "$WORK/$part.plist" --identifier "com.fabaudio.chordpilot.$part" \
           --version 1.0.0 --install-location / "$WORK/$part.pkg"
done
cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>ChordPilot</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <license file="license.txt" mime-type="text/plain"/>
  <options customize="allow" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <domains enable_localSystem="true"/>
  <choices-outline>
    <line choice="vst3"/><line choice="au"/><line choice="app"/>
  </choices-outline>
  <choice id="vst3" title="Plug-in VST3 (ChordPilot + ChordPilot MIDI)" start_selected="true"><pkg-ref id="com.fabaudio.chordpilot.vst3"/></choice>
  <choice id="au" title="Plug-in Audio Unit (ChordPilot + ChordPilot MIDI)" start_selected="true"><pkg-ref id="com.fabaudio.chordpilot.au"/></choice>
  <choice id="app" title="App ChordPilot" start_selected="true"><pkg-ref id="com.fabaudio.chordpilot.app"/></choice>
  <pkg-ref id="com.fabaudio.chordpilot.vst3">vst3.pkg</pkg-ref>
  <pkg-ref id="com.fabaudio.chordpilot.au">au.pkg</pkg-ref>
  <pkg-ref id="com.fabaudio.chordpilot.app">app.pkg</pkg-ref>
</installer-gui-script>
XML
SIGN_ARGS=()
if [ -n "${MACOS_INSTALLER_IDENTITY:-}" ]; then SIGN_ARGS=(--sign "$MACOS_INSTALLER_IDENTITY"); fi
productbuild --distribution "$WORK/distribution.xml" --resources "$RES" --package-path "$WORK" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$OUT/ChordPilot-Mac.pkg"
echo "Built $OUT/ChordPilot-Mac.pkg"
