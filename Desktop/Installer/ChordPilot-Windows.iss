; Inno Setup script – Windows installer with component choice (VST3 / Standalone).
; Built by CI:  iscc /DSrcDir=<artefacts\Release> ChordPilot-Windows.iss
#ifndef SrcDir
  #define SrcDir "..\build\ChordPilot_artefacts\Release"
#endif

[Setup]
AppName=ChordPilot
AppVersion=1.0.0
AppPublisher=Fab Audio
DefaultDirName={autopf}\Fab Audio\ChordPilot
DefaultGroupName=ChordPilot
OutputBaseFilename=ChordPilot-Windows-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Types]
Name: "full"; Description: "Tutto (VST3 + app Standalone)"
Name: "vst3"; Description: "Solo plug-in VST3"
Name: "standalone"; Description: "Solo app Standalone"
Name: "custom"; Description: "Personalizzata"; Flags: iscustom

[Components]
Name: "vst3"; Description: "Plug-in VST3 (Ableton, FL Studio, Cubase, Reaper, Studio One, Bitwig…)"; Types: full vst3 custom
Name: "standalone"; Description: "App Standalone (si collega da sola a scheda audio e tastiere MIDI)"; Types: full standalone custom

[Files]
Source: "{#SrcDir}\VST3\ChordPilot.vst3\*"; DestDir: "{commoncf64}\VST3\ChordPilot.vst3"; Components: vst3; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#SrcDir}\Standalone\ChordPilot.exe"; DestDir: "{app}"; Components: standalone; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\ChordPilot"; Filename: "{app}\ChordPilot.exe"; Components: standalone
Name: "{autodesktop}\ChordPilot"; Filename: "{app}\ChordPilot.exe"; Components: standalone; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crea un'icona sul desktop"; Components: standalone

[Run]
Filename: "{app}\ChordPilot.exe"; Description: "Avvia ChordPilot"; Components: standalone; Flags: nowait postinstall skipifsilent
