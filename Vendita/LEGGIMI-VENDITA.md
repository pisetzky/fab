# ChordPilot – pacchetto per la vendita

Questa cartella contiene tutto ciò che serve per **pubblicare e vendere** ChordPilot.
I segnaposto da completare sono scritti così: **[TUO NOME / AZIENDA]**, **[EMAIL SUPPORTO]**, **[SITO WEB]**.

## 1. Cosa è pronto

| Versione | Formato | Stato |
|---|---|---|
| iPad / iPhone (web) | `ChordPilot.html` – si aggiunge alla Home | ✅ pronto (pubblicabile su qualsiasi hosting) |
| Linux | VST3 + Standalone | ✅ compilato |
| iPad (app nativa) | App + plug-in AUv3 (strumento e MIDI FX) | 🛠 codice completo, da compilare con Xcode e firmare |
| Mac (Intel + Apple Silicon) | VST3 + AU + Standalone: immagine disco `.dmg` (app da trascinare + installer `.pkg` con scelta componenti) | 🛠 compilazione automatica (GitHub Actions) |
| Windows | VST3 + Standalone, installer `.exe` con scelta componenti | 🛠 compilazione automatica (GitHub Actions) |

Funzioni incluse in tutte le versioni: 23 generi, 10 pianoforti, suggerimento accordi e note,
Genre Player con 30 arpeggi × 30 melodie per genere, Nuova canzone, Modalità Genio, Ispirazione
(10 melodie che seguono la traccia), opzioni Pro (accordi con un dito, blocca scala, strum, humanize,
swing, voicing, trasposizione), batteria del genere, export MIDI. La versione web ha in più
costruttore di brani, cerchio delle quinte con cambi di tonalità e "Le mie canzoni".

## 2. Passaggi obbligatori prima di vendere

1. **Licenza JUCE** (versione desktop). JUCE 8 è distribuito con doppia licenza (AGPLv3 o commerciale).
   Per vendere un plug-in a codice chiuso serve una licenza commerciale JUCE (esiste un piano gratuito
   per ricavi sotto una certa soglia): verifica i termini aggiornati su juce.com prima della vendita.
2. **VST3**: usa il logo "VST" e il marchio Steinberg solo secondo le linee guida Steinberg
   e verifica la licenza dell'SDK VST3 in uso (nelle versioni recenti è open source).
3. **Apple** (iPad e Mac): iscrizione all'Apple Developer Program (99 €/anno),
   firma del codice, notarizzazione del `.pkg` Mac, revisione App Store per l'app iPad.
4. **Windows**: certificato di firma del codice (evita l'avviso "PC protetto" di SmartScreen).
5. **Identificativi**: sostituisci `com.fabaudio…` (bundle ID) e il codice produttore `FabA`
   con quelli della tua azienda (in `ChordPilot/project.yml`, `AUExtension/Info.plist`,
   `Desktop/CMakeLists.txt`).
6. **Nome commerciale**: verifica che "ChordPilot" sia libero come marchio nel tuo mercato
   (in alternativa scegli un altro nome: va cambiato in pochi file).
7. Completa i segnaposto in `Legale/` (titolare, email, sede) e pubblica EULA e Privacy sul tuo sito.

## 3. Dove vendere

- **App Store (iPad + Mac Apple Silicon)**: testi pronti in `Store/AppStore-IT.md` e `Store/AppStore-EN.md`,
  screenshot 2732×2048 in `PressKit/screenshots/`, icona 1024×1024 in `PressKit/icona-1024.png`.
- **Plug-in desktop (VST3/AU)**: il tuo sito con un negozio digitale (es. Gumroad, Paddle, FastSpring,
  Lemon Squeezy) oppure marketplace di plug-in. Testo pronto in `Store/Pagina-prodotto-IT-EN.md`.
- **Versione web**: pubblica `ChordPilot.html` su un hosting (anche gratuito) e vendi l'accesso
  o usala come demo gratuita che porta all'acquisto della versione completa.

Prezzi consigliati: vedi `Prezzi.md`.

## 4. Nota sulla protezione

La versione attuale non ha un sistema di licenze/codici di attivazione: sugli store (App Store)
non serve; per la vendita diretta dei plug-in desktop puoi usare la gestione chiavi del negozio
digitale scelto o aggiungere un sistema di attivazione in una versione successiva.
