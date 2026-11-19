# ChordPilot per iPad – come installarlo

ChordPilot è **un'app + un plug-in AUv3** in un solo pacchetto. Installando l'app,
il plug-in compare automaticamente in tutte le DAW per iPad che supportano AUv3:
GarageBand, Logic Pro per iPad, Cubasis, AUM, Loopy Pro, BeatMaker, NanoStudio,
Drambo, FL Studio Mobile (AUv3), Koala e altre.

Nel plug-in trovi due versioni:
- **Fab Audio: ChordPilot** → strumento (suona il suo pianoforte + manda MIDI).
- **Fab Audio: ChordPilot MIDI** → effetto MIDI (per pilotare altri strumenti / Logic "MIDI FX").

Requisiti: iPadOS 16 o successivo (tutti gli iPad usciti dal 2017 in poi).

---

## Subito, senza computer – versione web (ChordPilot.html)

Funziona già adesso su questo iPad, senza Xcode e senza Apple ID sviluppatore:

1. Apri il link di ChordPilot (o il file `ChordPilot.html` pubblicato su un sito) in **Safari**.
2. Tocca **Condividi** → **Aggiungi alla schermata Home** → **Aggiungi**.
3. Apri ChordPilot dalla Home: si apre a schermo intero come un'app.

Ha i 20 generi, i 10 pianoforti, i suggerimenti luminosi e il Genre Player.
Non ha il plug-in AUv3 per le DAW e il MIDI esterno (Safari su iPad non supporta il Web MIDI):
per quelli serve l'app nativa qui sotto.

> Aprire `ChordPilot.html` direttamente dall'app File dell'iPad mostra solo un'anteprima:
> usa il link in Safari.

## Opzione A – App nativa con Xcode (consigliata, gratis)

Serve un Mac con Xcode 15 o 16 e un Apple ID (anche gratuito).

1. Estrai `ChordPilot-source.zip`.
2. Apri il Terminale nella cartella `ChordPilot-source/ChordPilot` e lancia:
   ```
   brew install xcodegen
   xcodegen generate
   open ChordPilot.xcodeproj
   ```
   (oppure fai doppio clic su `Installa-Mac.command` nella cartella principale e scegli l'opzione 1)
3. In Xcode: seleziona il target **ChordPilot** → *Signing & Capabilities* → scegli il tuo *Team*
   (fallo anche per il target **ChordPilotAU**). Se Xcode lo chiede, cambia il Bundle Identifier
   (es. `com.tuonome.chordpilot` e `com.tuonome.chordpilot.auv3`).
4. Collega l'iPad via cavo, selezionalo in alto e premi ▶︎ (Run).
5. Sull'iPad: *Impostazioni → Generali → VPN e gestione dispositivi* → autorizza il tuo profilo sviluppatore.

> Con un Apple ID gratuito l'app va reinstallata ogni 7 giorni. Con l'Apple Developer Program
> (99 €/anno) dura 1 anno e si può distribuire con TestFlight / App Store.

## Opzione B – File .ipa (Sideloadly / AltStore)

`ChordPilot-iPad-unsigned.ipa` è il pacchetto compilato **non firmato**.
Apple non permette di installare app non firmate: usa uno strumento che le firma con il tuo Apple ID,
ad esempio **Sideloadly** (Mac/Windows) o **AltStore**:

1. Apri Sideloadly, collega l'iPad, trascina dentro il file `.ipa`.
2. Inserisci il tuo Apple ID e premi *Start*.
3. Autorizza il profilo sull'iPad come al punto 5 sopra.

## Opzione C – App Store / TestFlight

Quando l'app sarà pubblicata riceverai un link TestFlight o App Store: è il modo più semplice.

---

## Primo avvio

- **Audio**: usa automaticamente l'uscita attiva dell'iPad – altoparlante, cuffie, AirPlay,
  Bluetooth, schede audio USB/Lightning/USB-C (class compliant). Se colleghi o scolleghi qualcosa
  mentre suoni, ChordPilot si riaggancia da solo.
- **MIDI**: ogni tastiera MIDI (USB, Bluetooth, Wi-Fi/rete, app virtuali) viene collegata da sola.
  Per le tastiere Bluetooth: tocca l'icona del cavo in alto a destra → *Abbina tastiera MIDI Bluetooth*.
- ChordPilot crea anche le porte virtuali **ChordPilot In** e **ChordPilot Out**, visibili in tutte
  le app musicali, per registrare in una DAW ciò che suoni o che suona il Genre Player.

## Uso in una DAW

Aggiungi una traccia strumento → *Audio Units* / *AUv3* → **Fab Audio → ChordPilot**.
Il Genre Player si sincronizza al tempo e al Play della DAW (opzione *Sincronizza con la DAW*).
Ogni genere è anche un **preset di fabbrica**, quindi puoi cambiarlo dal menu preset della DAW.
