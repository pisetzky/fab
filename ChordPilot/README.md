# ChordPilot – piano che suggerisce gli accordi

Versioni: **iPad** (app Standalone + plug-in AUv3, in questa cartella), **desktop** VST3 / AU / Standalone
per Mac, Windows e Linux (`../Desktop`, JUCE), **web** installabile su iPad dalla Home (`../WebApp`).

Suona una nota o un accordo: i tasti degli accordi e delle note **successive** si illuminano,
nello stile del genere scelto dal menu a tendina (20 generi).

| Colore sui tasti | Significato |
|---|---|
| Colore del genere (pieno) | accordo successivo consigliato (+ basso) |
| Azzurro | accordi alternativi |
| Ambra | note di melodia consigliate |
| Puntino / rombo | note della scala / note "tipiche" del genere |
| Barra verde | note suonate dal Genre Player |

## Funzioni
- **Riconoscimento accordi** in tempo reale (triadi, settime, none, sus, power chord, rivolti).
- **Tonalità automatica** (algoritmo Krumhansl-Schmuckler) oppure fissa.
- **20 generi**: Pop, Rock, Hip-Hop, Trap, R&B, Jazz, Blues, EDM, House, Reggaeton, Latin/Bossa,
  Country, Funk, Gospel/Soul, Metal, Reggae, Classica, Lo-Fi, Afrobeats, Cinematic – ognuno con scale,
  progressioni tipiche, note caratteristiche e un ritmo proprio.
- **Genre Player**: suona in loop una progressione tipica del genere (accordi + basso), sincronizzato alla DAW,
  e la manda in uscita MIDI per registrarla.
- **Schede accordo**: tocca un suggerimento per ascoltarlo (e inviarlo in MIDI).
- Complessità: *Semplici* (triadi), *Del genere*, *Ricchi* (settime/none).
- **10 pianoforti** (menu a tendina): Gran Coda, Brillante, Verticale, Elettrico a lamelle, Elettrico ad ance,
  Elettrico FM, Honky-Tonk, Clavicembalo, Toy Piano, Felt Piano – sintesi additiva/FM, stessi parametri su tutte le versioni.
- Tema grafico **aurora boreale**.
- **Plug-in AUv3** in due versioni: strumento (`aumu`) e MIDI FX (`aumi`); ogni genere è un preset di fabbrica;
  tutti i parametri sono automatizzabili e salvati nel progetto della DAW.
- **App standalone**: audio su qualsiasi uscita (anche schede USB), MIDI con collegamento automatico
  (USB, Bluetooth, rete, porte virtuali `ChordPilot In/Out`).

## Struttura
```
ChordPilot/
  Packages/ChordPilotCore   motore musicale (Swift puro, testato con `swift test`)
  Shared/DSP                sintetizzatore + sequencer real-time, code lock-free in C
  Shared/AudioUnit          ChordPilotAudioUnit (AUAudioUnit)
  Shared/UI                 interfaccia SwiftUI + tastiera multitouch
  AUExtension               estensione AUv3 (Info.plist con i due componenti)
  App                       app standalone, MIDI automatico, audio host
  project.yml               progetto XcodeGen
```

## Compilare
```
brew install xcodegen
cd ChordPilot && xcodegen generate && open ChordPilot.xcodeproj
```
Scegli il tuo Team per i target `ChordPilot` e `ChordPilotAU`, collega l'iPad e premi Run.
La GitHub Action `.github/workflows/ipad-build.yml` compila tutto su macOS, esegue i test
e produce la cartella scaricabile **ChordPilot-Installer.zip**.

ChordPilot è un progetto originale: il codice, il nome, la grafica e i dati musicali sono propri.
Le progressioni di accordi sono convenzioni armoniche di pubblico dominio.
