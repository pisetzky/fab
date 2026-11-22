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

## Registrare nella DAW tutto quello che esce da ChordPilot (premi REC)
Viene registrato **tutto**: le note che suoni, gli accordi della Modalità Genio, il **Genre Player** e
**Nuova canzone**, con il tempo della DAW.

**Metodo universale su Mac e Linux (vale per tutte le DAW, anche Logic)**
1. In ChordPilot apri **Pro** e attiva **Porta MIDI virtuale "ChordPilot"** (nell'app Standalone è sempre attiva).
2. Nella DAW crea una nuova traccia MIDI/strumento e come **ingresso MIDI** scegli **ChordPilot**.
3. Premi **REC** nella DAW e suona (o premi *Genre Player* / *Nuova canzone*): la traccia registra tutto.
4. Nella traccia dove si trova ChordPilot, imposta l'ingresso sulla tua tastiera e non su "Tutti gli ingressi",
   così le note non tornano indietro a ChordPilot.

Su **Windows** non esistono porte MIDI virtuali di sistema: usa l'uscita MIDI del plug-in (tabella qui sotto)
oppure, per l'app Standalone, il programma gratuito *loopMIDI* come porta verso la DAW.

**Via uscita MIDI del plug-in (senza porta virtuale)**
| DAW | Come registrare |
|---|---|
| **Ableton Live** | Nuova traccia MIDI → *MIDI From*: traccia di ChordPilot → "ChordPilot" → arma la traccia e premi REC |
| **Cubase / Nuendo** | Traccia MIDI con *Input* = "ChordPilot – MIDI Out" → arma e premi REC |
| **FL Studio** | *MIDI output port* di ChordPilot = 1, nuovo canale con *input port* = 1 → REC (registra le note nel pattern) |
| **Reaper** | Traccia nuova: *Record: output (MIDI)* sulla traccia di ChordPilot, oppure invio MIDI a una traccia armata |
| **Bitwig / Studio One** | Traccia nuova con ingresso = uscita MIDI di ChordPilot → REC |
| **Logic Pro** | Usa la **Porta MIDI virtuale** (metodo universale) |

**Il tasto "Esporta esecuzione"**: ChordPilot registra anche da sé tutto quello che esce dal plug-in. Quando
premi REC nella DAW la registrazione riparte allineata alla battuta: trascina il tasto sulla traccia, a
battuta 1, e le note finiscono esattamente dove le hai suonate. Il file contiene tracce separate: *Suonato da te*,
*Genre Player – accordi e arpeggio*, *Genre Player – melodia*, *Accordi del Genio*. Cliccando il tasto
puoi salvare il file .mid oppure azzerare e ricominciare.
