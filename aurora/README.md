# Aurora Signal

App web (un solo file, `index.html`) che dà per ogni criptovaluta un segnale **COMPRA** o **VENDI** del giorno, con obiettivo di vendita (% di guadagno), stop di sicurezza e data stimata.

## Come usarla
Apri `aurora/index.html` nel browser (o pubblicala con GitHub Pages). Non serve installare niente.

## Fonti controllate in automatico
- Prezzi crypto (top 100/250): CoinGecko, ogni 5 minuti
- Nasdaq, petrolio, gas, oro, grano: Stooq
- Tono delle notizie mondiali su guerre, scioperi, aerei, armi, medicina, acqua, petrolio, gas, cibo, meteo, Nasdaq, crypto: GDELT, ogni 30 minuti
- Meteo estremo nelle aree chiave (Midwest USA, Ucraina, Brasile, Golfo del Messico, Suez, Nord Europa): Open-Meteo
- Crypto Fear & Greed: alternative.me
- Facoltativo: analisi AI con ricerca web (Claude, chiave API Anthropic personale)

## Come calcola il segnale
Punteggio tecnico (trend vs EMA50, MACD, momentum 24h, RSI, posizione nel range 7 giorni) combinato con l'indice di rischio mondiale. Obiettivo e data derivano dalla volatilità della moneta.

**Non è consulenza finanziaria.** Le previsioni sono stime statistiche, non certezze.
