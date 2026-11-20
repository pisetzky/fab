# Usare ChordPilot con qualsiasi strumento della DAW

ChordPilot genera MIDI: accordi, melodie, Modalità Genio/Pianista, Due mani, Genre Player, Ispirazione.
Oltre al suo pianoforte può quindi suonare **qualsiasi strumento** della DAW: synth, archi, pad, piani
virtuali, plug-in di terze parti o hardware MIDI.

**Impostazioni consigliate**: in *Pro* metti **Uscita MIDI → "Tutto sul canale 1"** (lo strumento riceve
tutto insieme) e spegni **Pianoforte interno** se vuoi sentire solo lo strumento scelto.

Nel pacchetto ci sono due versioni del plug-in:
- **ChordPilot**: strumento con il suo pianoforte + uscita MIDI.
- **ChordPilot MIDI**: effetto MIDI senza audio, da mettere *prima* dello strumento.

## Le DAW principali
| DAW | Come fare |
|---|---|
| **Logic Pro / MainStage** | Canale dello strumento → slot *MIDI FX* → Audio Units → Fab Audio → **ChordPilot MIDI** |
| **Ableton Live** | Traccia MIDI con **ChordPilot** (o ChordPilot MIDI); nella traccia dello strumento: *MIDI From* → traccia di ChordPilot → "ChordPilot", Monitor *In* |
| **FL Studio** | ChordPilot nel Channel Rack → impostazioni plug-in → *MIDI output port* = 1; nello strumento *MIDI input port* = 1 |
| **Cubase / Nuendo** | Traccia strumento con ChordPilot; crea una traccia MIDI con *Input* = "ChordPilot – MIDI Out" e *Output* = lo strumento, monitor attivo |
| **Reaper** | Metti **ChordPilot MIDI** nella catena FX dello strumento, prima dello strumento |
| **Bitwig Studio** | Metti **ChordPilot MIDI** prima dello strumento nella catena del dispositivo (Note FX) |
| **Studio One** | Traccia di ChordPilot; nella traccia dello strumento come *Input* scegli l'uscita MIDI di ChordPilot |
| **App Standalone** | Opzioni → Audio/MIDI Settings → *MIDI Output* = la porta del synth (o una porta virtuale verso la DAW) |

Suggerimento: con **Uscita MIDI → "Canali separati"** puoi mandare accompagnamento (canale 1), melodia
(canale 2) e accordi Genio (canale 3) a **tre strumenti diversi**.
