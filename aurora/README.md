# Aurora Signal

App web (un solo file, `index.html`) che dà per ogni criptovaluta un segnale **COMPRA** o **VENDI** del giorno, con obiettivo di vendita (% di guadagno), stop di sicurezza e data stimata.

## Come usarla
Apri `aurora/index.html` nel browser (o pubblicala con GitHub Pages). Non serve installare niente.

## Fonti controllate in automatico
- Prezzi crypto (top 100/250), capitalizzazione totale, dominanza BTC: CoinGecko, ogni 5 minuti
- Leva sui future (funding rate): Binance
- Nasdaq, S&P 500, VIX, dollaro (EUR/USD), bond USA a 20 anni, petrolio, gas, oro, argento, rame: versioni tokenizzate quotate su CoinGecko (nel weekend, a borse chiuse, il loro peso si dimezza)
- Gli asset tokenizzati (fondi, titoli di Stato, prestiti, azioni, oro) sono esclusi dalla lista: non sono criptovalute
- Tono delle notizie mondiali su 32 temi, ogni 30 minuti (GDELT): crypto, regolamentazione, hack, ETF, tassi e banche centrali, inflazione, dollaro, lavoro e recessione, banche e debito, tech e chip, borse, rendimenti, petrolio, gas, oro, metalli, cibo, elettricità, guerre, armi e nucleare, terrorismo, dazi e sanzioni, elezioni, Cina e Taiwan, cyberattacchi, scioperi, aerei, navi e trasporti, meteo, terremoti, epidemie, acqua
- Ciclo dell'halving di Bitcoin (tendenza storica)
- Meteo estremo nelle aree chiave (Midwest USA, Ucraina, Brasile, Golfo del Messico, Suez, Nord Europa): Open-Meteo
- Crypto Fear & Greed: alternative.me
- Analisi AI con ricerca web (Claude, chiave API Anthropic personale): parte da sola ogni 3 ore, e subito all'apertura se sono passate più di 3 ore

## Come calcola il segnale
Se è inserita la chiave AI, il voto COMPRA/VENDI dell'AI (prime 25 monete + preferite, ogni 3 ore, con ricerca web) entra nel segnale con un peso scelto dall'utente (default 40%) che cala con l'età dell'analisi.

Punteggio tecnico (trend vs EMA50, MACD, momentum 24h, RSI, posizione nel range 7 giorni), fattori della singola moneta (trend 30 giorni, liquidità, token ancora da sbloccare, distanza dal massimo storico, funding dei future, andamento di Bitcoin e dominanza BTC per le altcoin), combinati con l'indice di rischio mondiale. L'affidabilità scende con poca liquidità, molti sblocchi, nel weekend e quando mancano fonti. Obiettivo e data derivano dalla volatilità della moneta.

**Non è consulenza finanziaria.** Le previsioni sono stime statistiche, non certezze.

## Cartella di vendita
La cartella `vendita/` contiene installer pronti per Mac (DMG), Windows (Setup.exe e portatile), Linux e la versione web. Si ricostruisce con `bash packaging/build.sh <versione>` (vedi `packaging/README.md`).
