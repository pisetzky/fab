# ChordPilot su Windows – VST3 + app Standalone

1. Fai doppio clic su **ChordPilot-Windows-Setup.exe**.
   (Se Windows mostra "PC protetto": *Ulteriori informazioni → Esegui comunque*. L'installer non è ancora firmato.)
2. Scegli cosa installare:
   - **Tutto** – plug-in VST3 + app Standalone
   - **Solo plug-in VST3** – per Ableton Live, FL Studio, Cubase, Reaper, Studio One, Bitwig…
   - **Solo app Standalone**
3. Il VST3 va in `C:\Program Files\Common Files\VST3` (la cartella che tutte le DAW leggono già).
   Nella DAW: riscansiona i plug-in e cerca **Fab Audio → ChordPilot**.

**App Standalone**: si apre con la scheda audio predefinita e attiva da sola ogni tastiera MIDI collegata,
anche quelle che colleghi dopo. Da *Options → Audio/MIDI Settings* puoi scegliere un driver ASIO o WASAPI.

> Se `ChordPilot-Windows-Setup.exe` manca da questa cartella, viene creato dalla compilazione automatica
> su GitHub (`.github/workflows/ipad-build.yml`); il codice è in `iPad/ChordPilot-source.zip`, cartella `Desktop`.
