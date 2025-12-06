# Changelog - Riscrittura Modulo Adaptive Take Profit

## Data: 2025-11-14

### Modifiche Principali

#### 1. AdaptiveTakeProfit.mqh - Completamente riscritto
- **Nuova formula esponenziale**: `TP = (ATR*100)/Prezzo * [a*(EMA_ratio)^b + c]`
- **Per LONG** (EMA20 > EMA50): `ratio = EMA20/EMA50`
- **Per SHORT** (EMA20 < EMA50): `ratio = EMA50/EMA20`
- **ATR(100)** invece di ATR(14)
- **Parametri unificati** (stessi per long e short):
  - `a` = 3.2 (moltiplicatore)
  - `b` = 0.75 (esponente)
  - `c` = 0.03 (offset)
- **Limiti**:
  - `CAP` = 0.6% (massimo)
  - `FLOOR` = 0.2% (minimo)
  - `FALLBACK` = 0.4% (valore in caso di errore)
- **Metodo principale**: `CalculateTrailingStartPercent(price, ema20, ema50, atr)`

#### 2. TradingWrapper.mqh - Integrazione completa
- **Struttura TrailingData** estesa con campo `adaptive_trailing_start_percent`
- **All'apertura di ogni trade** (linee 828-843):
  - Calcola il valore adaptivo usando EMA20, EMA50, prezzo e ATR del momento
  - Memorizza il valore per quel trade specifico
  - Log dettagliato del calcolo
- **Nella logica di trailing** (linee 886, 889, 933):
  - Usa il valore adaptivo memorizzato invece del parametro fisso
  - Ogni trade ha il suo TrailingStartPercent personalizzato
- **Configurazione default** aggiornata (linee 80-85)

#### 3. SistemaCompleto.mq5 - Parametri aggiornati
- **Modulo ATTIVATO di default**: `EnableAdaptiveTP = true`
- **Nuovi parametri input**:
  - `AdaptiveTP_A` = 3.2
  - `AdaptiveTP_B` = 0.75
  - `AdaptiveTP_C` = 0.03
  - `AdaptiveTP_Cap` = 0.6
  - `AdaptiveTP_Floor` = 0.2
  - `AdaptiveTP_Fallback` = 0.4
- **Log migliorato** con informazioni sulla formula all'avvio

#### 4. BotOriginale.mqh - Struttura dati estesa
- Aggiunto campo `adaptive_trailing_start_percent` a `TrailingData`

### Come Funziona

1. **All'apertura di un trade**:
   - Il sistema legge ATR(100), EMA20, EMA50 e il prezzo corrente
   - Calcola il ratio EMA appropriato (long o short)
   - Applica la formula: `TP = (ATR*100)/Prezzo * [a*(ratio)^b + c]`
   - Applica CAP e FLOOR
   - Memorizza il valore calcolato per quel trade

2. **Durante il trailing**:
   - Ogni trade usa il suo valore personalizzato di TrailingStartPercent
   - Il trailing si attiva quando il profitto raggiunge quella percentuale
   - Comportamento completamente dinamico e adattivo al mercato

### Benefici

- **Adattamento al mercato**: Ogni trade ha un TP ottimizzato per le condizioni di apertura
- **Volatilità**: ATR(100) cattura la volatilità di lungo periodo
- **Trend**: Il ratio EMA cattura la forza del trend
- **Sicurezza**: CAP e FLOOR prevengono valori estremi
- **Fallback**: In caso di errore, usa un valore sicuro

### Testing

Il modulo è pronto per il testing. Verificare:
- Compilazione corretta in MetaTrader
- Corretta inizializzazione all'avvio
- Log dei valori calcolati
- Comportamento del trailing con valori diversi
