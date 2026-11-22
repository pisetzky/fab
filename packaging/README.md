# Packaging di Aurora Signal (note per il venditore)

Questa cartella contiene tutto quello che serve per **ricostruire** la cartella `vendita/`. L'acquirente riceve solo `vendita/`.

## Ricostruire la cartella di vendita

Su Linux (Ubuntu/Debian):

```bash
sudo apt-get install -y xorriso nsis python3-pil nodejs npm
bash packaging/build.sh 1.0.1        # numero di versione
```

Lo script:
1. compila `aurora/index.html` per i browser più vecchi (Chrome 58+, Firefox 57+, Safari 11+);
2. genera l'icona (`make_icons.py`) in formato Mac (.icns) e Windows (.ico);
3. crea l'app per Mac `Aurora Signal.app` e il disco `Aurora-Signal-<versione>.dmg`;
4. crea l'installer Windows `Aurora-Signal-Setup-<versione>.exe` (NSIS) e la versione portatile;
5. crea il pacchetto Linux e la versione web;
6. scrive `SHA256SUMS.txt` con le impronte dei file.

| File | Cosa fa |
|---|---|
| `mac/AuroraSignal` | Avvio su Mac. Dal DMG si copia da solo in Applicazioni, poi apre l'app in una finestra dedicata (Chrome/Edge/Brave) o nel browser predefinito |
| `mac/Info.plist` | Dati dell'app Mac (nome, versione, icona, macOS minimo 10.11) |
| `windows/installer.nsi` | Installer Windows: niente permessi di amministratore, icona su desktop e menu Start, disinstallazione |
| `docs/LEGGIMI.txt`, `docs/LICENZA.txt` | Istruzioni per l'acquirente e licenza d'uso |

## Da fare prima di vendere

**1. Firma digitale (consigliata).** Gli installer non sono firmati, quindi alla prima apertura:
- su Mac compare l'avviso "sviluppatore non identificato" (le istruzioni per superarlo sono nel LEGGIMI);
- su Windows compare SmartScreen ("Windows ha protetto il PC").

Per eliminare gli avvisi servono:
- **Mac:** un account Apple Developer (99 $/anno) e un Mac. Firma e notarizza l'app con `codesign` e `xcrun notarytool`, poi ricrea il DMG con `hdiutil create -format UDZO`. Il DMG creato da Linux è un'immagine ibrida HFS+/ISO non compressa: macOS la apre normalmente, ma non può essere firmata.
- **Windows:** un certificato di firma del codice (OV o EV) e `signtool` (o `osslsigncode` su Linux) sul file `Setup.exe`.

**2. Prova su macchine vere.** Gli installer sono stati costruiti e controllati su Linux. Non sono stati provati su un Mac o un PC Windows reale.

**3. Aspetti legali.**
- Vendere segnali di compravendita può rientrare nella consulenza o raccomandazione di investimento, che in Italia/UE è regolata (CONSOB, MiFID II, MiCA per le cripto-attività). L'app e la licenza dicono chiaramente che non è consulenza finanziaria, ma conviene far verificare a un legale come presentarla e venderla.
- Alcune fonti dati gratuite hanno limiti per l'uso commerciale (per esempio l'API gratuita di CoinGecko). Controlla i termini d'uso di CoinGecko, GDELT, Binance e alternative.me, e valuta un piano a pagamento dove serve.
- Completa la licenza (`docs/LICENZA.txt`) con il nome del titolare e i dati legali.

**4. Fattura e partita IVA.** Per vendere software servono gli adempimenti fiscali previsti (partita IVA, IVA sui servizi digitali per clienti UE).
