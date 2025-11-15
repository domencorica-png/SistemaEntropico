# 🧪 GUIDA COMPLETA AL BACKTESTING HMM FILTER

Sistema completo per testare il filtro HMM su dati storici in MetaTrader 5.

## 📋 INDICE

1. [Panoramica Sistema](#panoramica-sistema)
2. [Prerequisiti](#prerequisiti)
3. [Workflow Completo](#workflow-completo)
4. [Dettagli Tecnici](#dettagli-tecnici)
5. [Troubleshooting](#troubleshooting)
6. [FAQ](#faq)

---

## 🎯 PANORAMICA SISTEMA

Il sistema di backtesting permette di:

✅ Testare il filtro HMM su **TUTTI i dati storici**
✅ Visualizzare i regimi **direttamente sul grafico MT5**
✅ Eseguire **backtest dell'EA** con filtro HMM attivo
✅ Analizzare **performance** per ogni regime

### Workflow Generale

```
┌─────────────────┐
│   MT5: Export   │  Script ExportHistoricalData.mq5
│  Dati Storici   │  → CSV file
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Python: Processa│  hmm_backtest_processor.py
│  Tutti i Dati   │  → Calcola regimi per ogni barra
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  MT5: Visualizza│  Custom Indicator HMMRegimeIndicator.mq5
│  sul Grafico    │  → Mostra regimi storici
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   MT5: Backtest │  EA legge regimi dall'indicator
│   con Filtro    │  → Testa strategia con filtro attivo
└─────────────────┘
```

---

## 🔧 PREREQUISITI

### Software Richiesto

- **MetaTrader 5** (build 3650+)
- **Python 3.8+** con packages:
  ```bash
  pip install -r requirements.txt
  ```

### File Necessari

#### MT5 Scripts/Indicators:
- `MT5_Scripts/ExportHistoricalData.mq5` - Export dati
- `MT5_Indicators/HMMRegimeIndicator.mq5` - Visualizzazione regimi
- `HMMFilter.mqh` - Filtro HMM per EA

#### Python:
- `hmm_backtest_processor.py` - Batch processor
- `hmm_filter/` - Modulo HMM completo
- `hmm_config.json` - Configurazione

---

## 📝 WORKFLOW COMPLETO

### STEP 1: EXPORT DATI STORICI DA MT5

#### 1.1 Compila lo Script

```
1. Apri MT5
2. MetaEditor → File → Open → ExportHistoricalData.mq5
3. Compila (F7)
4. Chiudi MetaEditor
```

#### 1.2 Configura Parametri

Nello script, modifica se necessario:

```mql5
input int      BarsToExport = 5000;            // Numero bars (min 1000)
input string   ExportFileName = "gold_10min_historical.csv";
input string   ExportFolder = "hmm_data";
input ENUM_TIMEFRAMES Timeframe = PERIOD_M10;  // 10 minuti
```

#### 1.3 Esegui Export

```
1. MT5 → Navigator → Scripts → ExportHistoricalData
2. Trascina su grafico GOLD 10min
3. Click OK
4. Attendi completamento (barra progress nel log)
```

**Output:**
- File: `MQL5/Files/hmm_data/gold_10min_historical.csv`
- Formato: `time,open,high,low,close,volume`

#### 1.4 Verifica Export

```
Expert log dovrebbe mostrare:
╔═══════════════════════════════════════╗
║  EXPORT COMPLETATO CON SUCCESSO       ║
║  Bars esportate: 5000                 ║
╚═══════════════════════════════════════╝
```

---

### STEP 2: PROCESSA DATI CON PYTHON

#### 2.1 Copia File CSV

```bash
# Windows
copy "%APPDATA%\MetaQuotes\Terminal\<ID>\MQL5\Files\hmm_data\gold_10min_historical.csv" data/

# Oppure usa path diretto
```

#### 2.2 Configura HMM (Opzionale)

Modifica `hmm_config.json` se vuoi personalizzare:

```json
{
  "training": {
    "training_window": 1000,
    "retrain_frequency": 100
  },
  "validation": {
    "confidence_threshold": 0.65,
    "adx_validation": {
      "threshold": 25
    }
  }
}
```

#### 2.3 Esegui Batch Processor

```bash
# Basic
python hmm_backtest_processor.py data/gold_10min_historical.csv

# Con opzioni
python hmm_backtest_processor.py \
    data/gold_10min_historical.csv \
    --config hmm_config.json \
    --output gold_10min_regimes.csv \
    --indicator-file
```

**Parametri:**
- `--config, -c`: File configurazione JSON
- `--output, -o`: Nome file output (default: input_regimes.csv)
- `--indicator-file, -i`: Crea anche file per indicator MT5

#### 2.4 Verifica Output

Il processor mostra:

```
1. Caricamento dati da: data/gold_10min_historical.csv
   ✓ Caricate 5000 bars

2. Configurazione Walk-Forward:
   Training window: 1000 bars
   Retrain frequency: 100 bars

3. Training iniziale (primi 1000 bars)...
   ✓ Training completato

4. Walk-forward predictions...
   Progress: 0% (0/5000)
   Progress: 5% (250/5000)
   ...
   Progress: 100% (5000/5000)
   ✓ Predictions completate

5. Statistiche Regimi:
   BULLISH (1):  1623 bars ( 32.5%)
   BEARISH (2):  1489 bars ( 29.8%)
   LATERAL (3):  1888 bars ( 37.7%)

   Average Confidence: 72.34%
   Regime Changes: 234

6. Output salvato:
   File: output/gold_10min_regimes.csv
   Size: 245.67 KB
```

**File Output:**
- `output/gold_10min_regimes.csv` - Regimi completi
- `output/hmm_indicator_data.csv` - Dati per indicator (se -i)

---

### STEP 3: IMPORTA IN MT5 CON INDICATOR

#### 3.1 Copia File Dati

```bash
# Copia file regimi in MT5
copy output\gold_10min_regimes.csv "%APPDATA%\MetaQuotes\Terminal\<ID>\MQL5\Files\hmm_data\"
```

**Importante:** Il file DEVE essere in `MQL5/Files/hmm_data/` per essere accessibile dall'indicator.

#### 3.2 Compila Indicator

```
1. MetaEditor → Open → HMMRegimeIndicator.mq5
2. Compila (F7)
3. Verifica compilazione OK
```

#### 3.3 Applica Indicator al Grafico

```
1. Apri grafico GOLD 10min
2. Navigator → Indicators → Custom → HMMRegimeIndicator
3. Trascina sul grafico
4. Configura parametri:

   RegimeDataFile = "hmm_data\\gold_10min_regimes.csv"
   ShowRegimeLabels = true
   ShowConfidence = true
   RefreshInterval = 300  (secondi)

5. Click OK
```

#### 3.4 Verifica Visualizzazione

Dovresti vedere:

- **Finestra separata** sotto il grafico principale
- **Istogramma colorato:**
  - 🟢 Verde = BULLISH (valore 1)
  - 🔴 Rosso = BEARISH (valore 2)
  - ⚪ Grigio = LATERAL (valore 3)
- **Linee orizzontali** a 1, 2, 3

**Expert log:**
```
╔═══════════════════════════════════════╗
║  HMM REGIME INDICATOR INITIALIZING    ║
╚═══════════════════════════════════════╝
✓ Caricati 5000 regime records
  Periodo: 2024.01.01 -> 2024.12.31
  Regimi: BULL=1623 BEAR=1489 LAT=1888
```

---

### STEP 4: BACKTEST EA CON FILTRO HMM

#### 4.1 Integra Filtro nell'EA

Nel tuo EA `SistemaCompleto.mq5`, il filtro HMM è già integrato tramite `HMMFilter.mqh`.

Verifica che usi il filtro:

```mql5
#include "HMMFilter.mqh"

CHMMFilter hmmFilter;

int OnInit()
{
    // Inizializza filtro
    hmmFilter.Init(_Symbol, PERIOD_M10, "output\\hmm_regime.txt");
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    // Controlla regime
    if(hmmFilter.ShouldBlockTrade())
    {
        Print("HMM: Trade bloccato - mercato LATERAL");
        return;  // Blocca trades
    }

    // Tua logica trading qui...
}
```

#### 4.2 Configura Strategy Tester

```
1. MT5 → View → Strategy Tester (Ctrl+R)

2. Configura:
   Symbol: XAUUSD
   Period: M10
   Date: Stesso periodo dei dati esportati
   Model: Every tick (più accurato)

3. Expert Properties → Inputs:
   EnableHMMFilter = true
   [Altri tuoi parametri...]

4. Click START
```

#### 4.3 Modalità Backtest

**Per backtest storici**, l'EA leggerà i regimi da:
- **Indicator buffer** (se indicator è applicato)
- **File regime.txt** (per real-time)

L'indicator permette di avere regimi "storici corretti" per ogni barra del backtest.

#### 4.4 Analizza Risultati

Dopo il backtest:

```
1. Strategy Tester → Results
2. Controlla:
   - Total Trades (dovrebbe essere inferiore senza filtro)
   - Profit Factor (dovrebbe migliorare)
   - Drawdown (dovrebbe ridursi)

3. Graph → Visualizza equity curve

4. Expert Log → Cerca messaggi HMM:
   "HMM: Trade bloccato - mercato LATERAL"
```

**Confronto con/senza filtro:**

| Metrica | Senza HMM | Con HMM | Miglioramento |
|---------|-----------|---------|---------------|
| Trades | 450 | 280 | -38% (meno noise) |
| Win Rate | 52% | 61% | +17% |
| Profit Factor | 1.2 | 1.8 | +50% |
| Max DD | -15% | -9% | -40% |

*(Esempio - i tuoi risultati varieranno)*

---

## 🔍 DETTAGLI TECNICI

### File CSV Formato

**Input (da MT5):**
```csv
time,open,high,low,close,volume
2024.01.01 00:00:00,1950.25,1951.80,1949.50,1950.75,1250
...
```

**Output (da Python):**
```csv
time,regime,regime_name,confidence,close
2024.01.01 00:00:00,1,BULLISH,0.7823,1950.75
2024.01.01 00:10:00,1,BULLISH,0.8134,1951.20
2024.01.01 00:20:00,3,LATERAL,0.6521,1950.50
...
```

### Walk-Forward Training

Il processor usa **walk-forward** automatico:

```
Training #1: Bars 0-1000    → Model A
  ↓ Predict bars 1000-1100

Training #2: Bars 100-1100  → Model B
  ↓ Predict bars 1100-1200

Training #3: Bars 200-1200  → Model C
  ↓ Predict bars 1200-1300

...e così via
```

Questo simula **esattamente** come l'HMM si comporterebbe in real-time.

### Indicator Performance

L'indicator usa **binary search** per lookup rapido:
- 5000 bars: ~13 confronti max
- 10000 bars: ~14 confronti max
- Trascurabile overhead

---

## 🐛 TROUBLESHOOTING

### Problema: "File regime non trovato"

**Causa:** Percorso file errato

**Soluzione:**
```mql5
// Verifica path completo
Print("Path completo: ", TerminalInfoString(TERMINAL_DATA_PATH),
      "\\MQL5\\Files\\hmm_data\\gold_10min_regimes.csv");

// Il file DEVE essere in questa posizione esatta
```

### Problema: "Indicator mostra solo grigio (LATERAL)"

**Cause possibili:**

1. **File dati non caricato:**
   - Check Expert log per errori caricamento
   - Verifica path file

2. **Time mismatch:**
   - Dati CSV hanno timestamp diversi dal grafico
   - Soluzione: Esporta dati dallo stesso grafico che usi per backtest

3. **Formato CSV errato:**
   - Verifica separatore virgola
   - Verifica formato time

### Problema: "Python error durante processing"

**Errori comuni:**

```python
# ModuleNotFoundError: No module named 'hmmlearn'
→ Soluzione: pip install hmmlearn

# ValueError: DataFrame mancante di colonne
→ Verifica formato CSV da MT5

# MemoryError
→ Riduci BarsToExport o usa dataset più piccolo
```

### Problema: "Backtest ignora filtro HMM"

**Check list:**
1. `EnableHMMFilter = true` nei parametri EA
2. Indicator applicato al grafico
3. File regime presente e accessibile
4. Verifica log Expert per messaggi HMM

---

## ❓ FAQ

### Q: Quanti dati storici servono?
**A:** Minimo 1000 bars per training iniziale. Ideale 3000-5000 bars per risultati affidabili.

### Q: Posso usare su altri timeframe?
**A:** Sì, ma devi:
- Modificare configurazione (`hmm_config.json`)
- Ricalib rare parametri (ATR period, training window, ecc.)

### Q: Il filtro funziona in forward testing?
**A:** Sì! Usa `mt5_integration.py` in modalità "New Bar" per aggiornare regime in real-time.

### Q: Posso modificare i parametri HMM?
**A:** Sì, edita `hmm_config.json`:
- `confidence_threshold`: Aumenta per meno segnali ma più qualità
- `adx_validation.threshold`: Riduci per identificare più laterali
- `retrain_frequency`: Aumenta per più stabilità

### Q: Quanto tempo richiede il processing?
**A:**
- 1000 bars: ~10 secondi
- 5000 bars: ~45 secondi
- 10000 bars: ~2 minuti

(Dipende da CPU e configurazione)

### Q: Posso usare più simboli?
**A:** Sì, ripeti il workflow per ogni simbolo:
1. Export dati simbolo A
2. Process con Python → regimes_A.csv
3. Indicator con file A
4. Export dati simbolo B
5. Process con Python → regimes_B.csv
6. Indicator con file B
...

### Q: Come aggiorno i dati?
**A:**
1. Re-esegui export da MT5 (con nuovi dati)
2. Re-processa con Python
3. Indicator si aggiorna automaticamente (per RefreshInterval)

---

## 📚 RIFERIMENTI

- **Codice sorgente:** `hmm_filter/`, `MT5_Scripts/`, `MT5_Indicators/`
- **Configurazione:** `hmm_config.json`
- **Documentazione HMM:** `README_HMM.md`
- **Paper scientifici:** Vedi README_HMM.md sezione References

---

## 🎓 BEST PRACTICES

1. **Sempre esporta dati sufficienti** (>1000 bars)
2. **Usa stesso timeframe** per export e backtest
3. **Verifica statistiche regimi** (distribuzione bilanciata è ok)
4. **Confronta con/senza filtro** per validare efficacia
5. **Monitora confidence** (media > 70% è ottimale)
6. **Retrain periodicamente** con nuovi dati

---

**Versione:** 2.0
**Ultima modifica:** 2025-11-15
**Compatibilità:** MT5 build 3650+, Python 3.8+
