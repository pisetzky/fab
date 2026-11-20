# ChordPilot 1.0 – kit per la vendita

ChordPilot è un plug-in per **Mac, Windows e Linux**: VST3, Audio Unit (Mac), app Standalone e
**ChordPilot MIDI** (effetto MIDI per suonare qualsiasi strumento della DAW).
I segnaposto da completare sono scritti così: **[TUO NOME / AZIENDA]**, **[EMAIL SUPPORTO]**, **[SITO WEB]**.

## 1. Cosa ricevono i clienti
La cartella **ChordPilot-1.0-Download** (o i singoli file):

| Sistema | File | Cosa fa il cliente |
|---|---|---|
| Mac (Intel + Apple Silicon, macOS 10.15+) | `ChordPilot-Mac.dmg` | apre il dmg → doppio clic su **Installa ChordPilot** → Continua → Installa |
| Windows 10/11 64 bit | `ChordPilot-Windows-Setup.exe` | doppio clic → Avanti → Installa |
| Linux x86-64 | `Linux/` + `Installa-Linux.sh` | doppio clic sullo script |

Il cliente **non deve installare nient'altro**: niente GitHub, Java, Xcode, runtime o librerie.
Tutto è incluso nei plug-in (anche la libreria Visual C++ su Windows).

## 2. Come si ottengono i file di installazione
I file `.dmg` (Mac) ed `.exe` (Windows) si creano sui sistemi Mac e Windows. È già tutto automatizzato:
1. Metti il codice (`Sorgenti` / questo repository) su GitHub.
2. La compilazione automatica (`.github/workflows/build.yml`) crea `ChordPilot-Mac.dmg`, `ChordPilot-Mac.pkg`,
   `ChordPilot-Windows-Setup.exe`, la versione Linux e le cartelle **ChordPilot-1.0-Download** e **ChordPilot-1.0-Vendita**.
3. Crea un tag `v1.0.0`: i file vengono pubblicati come *Release*, pronti da caricare sul tuo negozio.

## 3. Passaggi obbligatori prima di vendere
1. **Firma e notarizzazione Apple** (Apple Developer Program, 99 €/anno): senza, macOS mostra un avviso
   all'apertura del dmg. Inserisci nei *Secrets* del repository: `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`,
   `MACOS_SIGN_IDENTITY` (Developer ID Application), `MACOS_INSTALLER_IDENTITY` (Developer ID Installer),
   `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`: la compilazione firmerà e notarizzerà da sola.
2. **Firma Windows** (certificato di firma del codice): evita l'avviso SmartScreen.
   Secrets: `WINDOWS_CERT_PFX`, `WINDOWS_CERT_PASSWORD`.
3. **Licenza JUCE**: JUCE 8 è AGPLv3 o commerciale. Per vendere a codice chiuso serve la licenza commerciale
   (esiste un piano gratuito sotto una soglia di ricavi): verifica i termini aggiornati su juce.com.
4. **VST3**: usa il marchio/logo "VST" secondo le linee guida Steinberg e verifica la licenza dell'SDK incluso in JUCE.
5. **Identificativi**: sostituisci `com.fabaudio…` e il codice produttore `FabA` con quelli della tua azienda
   (`Desktop/CMakeLists.txt`, `Desktop/Installer/*`).
6. **Nome**: verifica che "ChordPilot" sia libero come marchio (altrimenti cambialo nei pochi file indicati).
7. Completa i segnaposto in `Legale/` e pubblica EULA e Privacy sul tuo sito.

## 4. Dove vendere
- Il tuo sito con un negozio digitale (Gumroad, Paddle, FastSpring, Lemon Squeezy…): carica il `.dmg` e l'`.exe`.
- Marketplace di plug-in. Testo pronto: `Store/Pagina-prodotto-IT-EN.md`; prezzi: `Prezzi.md`;
  immagini: `PressKit/`.

## 5. Nota sulla protezione
Non c'è un sistema di codici di attivazione: puoi usare la gestione delle chiavi del negozio digitale
o aggiungerne uno in una versione successiva.
