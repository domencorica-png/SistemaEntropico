//+------------------------------------------------------------------+
//|                      EntropyFilter.mqh                           |
//|                  Filtro Entropy Gate Ottimizzato XAU/USD 10min   |
//|                  Sistema Multi-Indicatore con Scoring Pesato     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "2.00"
#property description "Filtro avanzato basato su Entropia, ADX, Choppiness e Volatilità"

// Costanti
#define LOG2_CONST 0.69314718055994530941723212145818

//+------------------------------------------------------------------+
//| Classe filtro entropy gate per Gold 10min                        |
//+------------------------------------------------------------------+
class CEntropyFilter
{
private:
    // Identificatori
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // ============ PARAMETRI CONFIGURABILI ============

    // Entropy settings
    int m_entropy_lookback;          // Periodo per calcolo entropia (default: 18 per 10min)
    int m_pattern_length;            // Lunghezza pattern binari (2-4)

    // ADX settings
    int m_adx_period;                // Periodo ADX (default: 12 per 10min)
    double m_adx_min_trend;          // ADX minimo per trend (default: 22)

    // Choppiness settings
    int m_chop_period;               // Periodo Choppiness (default: 14)
    double m_chop_max_threshold;     // Sopra = choppy (default: 65.0)
    double m_chop_min_threshold;     // Sotto = trend (default: 35.0)

    // ATR/Volatility settings
    int m_atr_period;                // Periodo ATR (default: 14)
    double m_atr_multiplier_high;    // Moltiplicatore volatilità alta
    double m_atr_multiplier_low;     // Moltiplicatore volatilità bassa

    // Scoring system
    double m_weight_entropy;         // Peso entropia (default: 0.40)
    double m_weight_adx;             // Peso ADX (default: 0.25)
    double m_weight_choppiness;      // Peso choppiness (default: 0.20)
    double m_weight_volatility;      // Peso volatilità (default: 0.15)

    double m_min_score_to_trade;     // Score minimo per permettere trade (0-1)

    // Session filters (UTC hours)
    bool m_use_session_filter;
    double m_session_multiplier_asian;    // 23-8 UTC
    double m_session_multiplier_london;   // 8-16 UTC
    double m_session_multiplier_ny;       // 13-21 UTC
    double m_session_multiplier_overlap;  // 13-16 UTC (migliore)

    // Conferma e hysteresis
    int m_confirmation_bars;
    double m_hysteresis_factor;

    // ============ HANDLE INDICATORI ============
    int m_adx_handle;
    int m_atr_handle;

    // ============ VALORI CORRENTI ============
    double m_entropy_current;
    double m_adx_current;
    double m_choppiness_current;
    double m_atr_current;
    double m_atr_mean;
    double m_volatility_score;
    double m_session_multiplier;
    double m_tradability_score;

    // ============ STATO GATE ============
    bool m_gate_closed;              // true = blocca trade
    int m_consecutive_blocked;
    string m_market_regime;
    string m_current_session;

    // ============ BUFFERS ============
    double m_price_buffer[];
    double m_atr_history[];

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CEntropyFilter()
    {
        // Parametri ottimizzati per XAU/USD 10min
        m_entropy_lookback = 18;         // ~3 ore
        m_pattern_length = 3;

        m_adx_period = 12;
        m_adx_min_trend = 22.0;

        m_chop_period = 14;
        m_chop_max_threshold = 65.0;
        m_chop_min_threshold = 35.0;

        m_atr_period = 14;
        m_atr_multiplier_high = 2.5;
        m_atr_multiplier_low = 0.8;

        // Pesi sistema scoring (totale = 1.0)
        m_weight_entropy = 0.40;
        m_weight_adx = 0.25;
        m_weight_choppiness = 0.20;
        m_weight_volatility = 0.15;

        m_min_score_to_trade = 0.60;     // 60% minimo

        // Session multipliers (minore = più permissivo)
        m_use_session_filter = true;
        m_session_multiplier_asian = 1.30;    // Più restrittivo (ore quiete)
        m_session_multiplier_london = 0.90;   // Permissivo
        m_session_multiplier_ny = 0.95;       // Bilanciato
        m_session_multiplier_overlap = 0.85;  // Molto permissivo (migliore)

        m_confirmation_bars = 2;
        m_hysteresis_factor = 0.05;

        // Inizializza stato
        m_gate_closed = false;
        m_consecutive_blocked = 0;
        m_market_regime = "UNKNOWN";
        m_current_session = "UNKNOWN";

        // Handle invalidi
        m_adx_handle = INVALID_HANDLE;
        m_atr_handle = INVALID_HANDLE;

        // Inizializza arrays
        ArrayResize(m_price_buffer, 200);
        ArraySetAsSeries(m_price_buffer, true);
        ArrayResize(m_atr_history, 50);
        ArraySetAsSeries(m_atr_history, true);
    }

    //+------------------------------------------------------------------+
    //| Destructor - rilascia handle                                     |
    //+------------------------------------------------------------------+
    ~CEntropyFilter()
    {
        if(m_adx_handle != INVALID_HANDLE)
            IndicatorRelease(m_adx_handle);
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }

    //+------------------------------------------------------------------+
    //| Inizializzazione del filtro                                      |
    //+------------------------------------------------------------------+
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
              int entropy_lookback = 18,
              int adx_period = 12,
              int chop_period = 14,
              int atr_period = 14,
              double min_score = 0.60,
              int confirmation_bars = 2,
              double hysteresis = 0.05,
              int pattern_length = 3)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_entropy_lookback = entropy_lookback;
        m_adx_period = adx_period;
        m_chop_period = chop_period;
        m_atr_period = atr_period;
        m_min_score_to_trade = min_score;
        m_confirmation_bars = confirmation_bars;
        m_hysteresis_factor = hysteresis;
        m_pattern_length = pattern_length;

        // Crea handle ADX
        m_adx_handle = iADX(m_symbol, m_timeframe, m_adx_period);
        if(m_adx_handle == INVALID_HANDLE)
        {
            Print("ERROR: Impossibile creare handle ADX per ", m_symbol);
            return false;
        }

        // Crea handle ATR
        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("ERROR: Impossibile creare handle ATR per ", m_symbol);
            IndicatorRelease(m_adx_handle);
            return false;
        }

        Print("✅ Gold Entropy Gate Filter inizializzato per ", m_symbol, " ", EnumToString(m_timeframe));
        Print("   Entropy Lookback: ", m_entropy_lookback);
        Print("   Min Score: ", DoubleToString(m_min_score_to_trade * 100, 0), "%");

        return true;
    }

    //+------------------------------------------------------------------+
    //| Update principale - calcola tutte le metriche                    |
    //+------------------------------------------------------------------+
    void Update()
    {
        // 1. Aggiorna buffer prezzi
        if(!UpdatePriceBuffer()) return;

        // 2. Calcola tutte le metriche
        m_entropy_current = CalculatePatternEntropy();
        m_adx_current = CalculateADX();
        m_choppiness_current = CalculateChoppiness();
        m_atr_current = CalculateATR();

        // 3. Calcola ATR storico e volatility score
        UpdateATRHistory();
        m_volatility_score = CalculateVolatilityScore();

        // 4. Determina sessione e multiplier
        UpdateSessionInfo();

        // 5. Calcola score finale
        m_tradability_score = CalculateTradabilityScore();

        // 6. Determina regime di mercato
        DetermineMarketRegime();

        // 7. Aggiorna stato del gate
        UpdateGateState();

        // 8. Log periodico (ogni 20 update)
        static int log_counter = 0;
        log_counter++;
        if(log_counter % 20 == 0)
        {
            PrintGateStatus();
        }
    }

    //+------------------------------------------------------------------+
    //| METODO PRINCIPALE: Verifica se si può aprire posizione           |
    //+------------------------------------------------------------------+
    bool IsMarketSidewaysOrChaotic()
    {
        // Ritorna TRUE se il gate è CHIUSO (blocca trade)
        // Ritorna FALSE se il gate è APERTO (permetti trade)
        return m_gate_closed;
    }

    //+------------------------------------------------------------------+
    //| Getter - Score di tradabilità (0-1)                              |
    //+------------------------------------------------------------------+
    double GetTradabilityScore() const { return m_tradability_score; }

    //+------------------------------------------------------------------+
    //| Getter - Metriche individuali                                    |
    //+------------------------------------------------------------------+
    double GetEntropy() const { return m_entropy_current; }
    double GetADX() const { return m_adx_current; }
    double GetChoppiness() const { return m_choppiness_current; }
    double GetATR() const { return m_atr_current; }
    double GetVolatilityScore() const { return m_volatility_score; }

    //+------------------------------------------------------------------+
    //| Getter - Stato mercato                                           |
    //+------------------------------------------------------------------+
    string GetMarketRegime() const { return m_market_regime; }
    string GetSession() const { return m_current_session; }
    bool IsGateClosed() const { return m_gate_closed; }

    //+------------------------------------------------------------------+
    //| Getter - Compatibilità con vecchio filtro                        |
    //+------------------------------------------------------------------+
    double GetEntropyBreve() const { return m_entropy_current; }
    double GetEntropyMedio() const { return m_entropy_current; }
    double GetEntropyLungo() const { return m_entropy_current; }
    double GetWeightedEntropy() const { return m_entropy_current; }
    double GetVolatility() const { return (m_atr_current / SymbolInfoDouble(m_symbol, SYMBOL_BID)) * 100.0; }
    bool IsSideways() const { return m_gate_closed && (m_market_regime == "CHOPPY" || m_market_regime == "TRADABLE"); }
    bool IsChaotic() const { return m_gate_closed && m_market_regime == "HIGHLY_CHAOTIC"; }

    //+------------------------------------------------------------------+
    //| Setter - Modifica parametri a runtime                            |
    //+------------------------------------------------------------------+
    void SetMinScore(double score) { m_min_score_to_trade = MathMax(0.0, MathMin(1.0, score)); }
    void SetWeights(double entropy, double adx, double chop, double vol)
    {
        double total = entropy + adx + chop + vol;
        if(total > 0)
        {
            m_weight_entropy = entropy / total;
            m_weight_adx = adx / total;
            m_weight_choppiness = chop / total;
            m_weight_volatility = vol / total;
        }
    }
    void SetSessionFilter(bool enable) { m_use_session_filter = enable; }

private:
    //+------------------------------------------------------------------+
    //| Aggiorna buffer dei prezzi                                       |
    //+------------------------------------------------------------------+
    bool UpdatePriceBuffer()
    {
        int needed = MathMax(m_entropy_lookback + 10, 100);
        if(CopyClose(m_symbol, m_timeframe, 0, needed, m_price_buffer) != needed)
        {
            Print("ERROR: Impossibile copiare prezzi per ", m_symbol);
            return false;
        }
        return true;
    }

    //+------------------------------------------------------------------+
    //| Calcola Entropia su Pattern di Movimento                         |
    //+------------------------------------------------------------------+
    double CalculatePatternEntropy()
    {
        if(ArraySize(m_price_buffer) < m_entropy_lookback + 1)
            return 0.5;

        // Calcola log returns
        double log_returns[];
        ArrayResize(log_returns, m_entropy_lookback);

        for(int i = 0; i < m_entropy_lookback; i++)
        {
            if(m_price_buffer[i+1] != 0)
                log_returns[i] = MathLog(m_price_buffer[i] / m_price_buffer[i+1]);
            else
                log_returns[i] = 0.0;
        }

        // Normalizza per volatilità locale
        double std_dev = 0.0;
        double mean = 0.0;
        for(int i = 0; i < m_entropy_lookback; i++)
            mean += log_returns[i];
        mean /= m_entropy_lookback;

        for(int i = 0; i < m_entropy_lookback; i++)
            std_dev += MathPow(log_returns[i] - mean, 2);
        std_dev = MathSqrt(std_dev / m_entropy_lookback);

        // Converti in pattern binari (up/down) con threshold adattivo
        int patterns[];
        int pattern_count = 0;
        double threshold = (std_dev > 0) ? 0.1 * std_dev : 0.0001;

        ArrayResize(patterns, m_entropy_lookback);
        for(int i = 0; i < m_entropy_lookback; i++)
        {
            if(MathAbs(log_returns[i]) > threshold)
            {
                patterns[pattern_count] = (log_returns[i] > 0) ? 1 : 0;
                pattern_count++;
            }
        }

        if(pattern_count < m_pattern_length)
            return 0.5;

        // Crea sequenze di pattern
        int max_patterns = (int)MathPow(2, m_pattern_length);
        int pattern_freq[];
        ArrayResize(pattern_freq, max_patterns);
        ArrayInitialize(pattern_freq, 0);

        int sequence_count = 0;
        for(int i = 0; i <= pattern_count - m_pattern_length; i++)
        {
            int pattern_value = 0;
            for(int j = 0; j < m_pattern_length; j++)
            {
                pattern_value = pattern_value * 2 + patterns[i + j];
            }
            if(pattern_value < max_patterns)
            {
                pattern_freq[pattern_value]++;
                sequence_count++;
            }
        }

        if(sequence_count == 0)
            return 0.5;

        // Calcola entropia di Shannon
        double entropy = 0.0;
        for(int i = 0; i < max_patterns; i++)
        {
            if(pattern_freq[i] > 0)
            {
                double prob = (double)pattern_freq[i] / (double)sequence_count;
                entropy -= prob * (MathLog(prob) / LOG2_CONST);
            }
        }

        // Normalizza (max entropy = pattern_length)
        double max_entropy = m_pattern_length;
        if(max_entropy > 0)
            entropy = entropy / max_entropy;

        return MathMax(0.0, MathMin(1.0, entropy));
    }

    //+------------------------------------------------------------------+
    //| Calcola ADX                                                       |
    //+------------------------------------------------------------------+
    double CalculateADX()
    {
        double adx_buffer[];
        if(CopyBuffer(m_adx_handle, 0, 0, 1, adx_buffer) <= 0)
            return 0.0;

        return adx_buffer[0];
    }

    //+------------------------------------------------------------------+
    //| Calcola Choppiness Index                                         |
    //+------------------------------------------------------------------+
    double CalculateChoppiness()
    {
        int period = m_chop_period;
        double high[], low[], close[];

        if(CopyHigh(m_symbol, m_timeframe, 0, period + 1, high) != period + 1 ||
           CopyLow(m_symbol, m_timeframe, 0, period + 1, low) != period + 1 ||
           CopyClose(m_symbol, m_timeframe, 0, period + 1, close) != period + 1)
            return 50.0;

        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(close, true);

        // True Range
        double tr_sum = 0.0;
        for(int i = 0; i < period; i++)
        {
            double tr = high[i] - low[i];
            tr = MathMax(tr, MathAbs(high[i] - close[i+1]));
            tr = MathMax(tr, MathAbs(low[i] - close[i+1]));
            tr_sum += tr;
        }

        // High-Low range
        double high_max = high[ArrayMaximum(high, 0, period)];
        double low_min = low[ArrayMinimum(low, 0, period)];
        double range = high_max - low_min;

        if(range < 1e-10)
            return 50.0;

        // Choppiness formula
        double chop = 100.0 * MathLog10(tr_sum / range) / MathLog10(period);

        return MathMax(0.0, MathMin(100.0, chop));
    }

    //+------------------------------------------------------------------+
    //| Calcola ATR corrente                                             |
    //+------------------------------------------------------------------+
    double CalculateATR()
    {
        double atr_buffer[];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
            return 0.0;

        return atr_buffer[0];
    }

    //+------------------------------------------------------------------+
    //| Aggiorna storico ATR                                             |
    //+------------------------------------------------------------------+
    void UpdateATRHistory()
    {
        int history_size = ArraySize(m_atr_history);
        double atr_buffer[];

        if(CopyBuffer(m_atr_handle, 0, 0, history_size, atr_buffer) == history_size)
        {
            for(int i = 0; i < history_size; i++)
                m_atr_history[i] = atr_buffer[i];

            // Calcola media ATR
            m_atr_mean = 0.0;
            for(int i = 0; i < history_size; i++)
                m_atr_mean += m_atr_history[i];
            m_atr_mean /= history_size;
        }
    }

    //+------------------------------------------------------------------+
    //| Calcola Volatility Score                                         |
    //+------------------------------------------------------------------+
    double CalculateVolatilityScore()
    {
        if(m_atr_mean == 0)
            return 0.5;

        // Z-score della volatilità
        double atr_std = 0.0;
        int count = ArraySize(m_atr_history);
        for(int i = 0; i < count; i++)
            atr_std += MathPow(m_atr_history[i] - m_atr_mean, 2);
        atr_std = MathSqrt(atr_std / count);

        if(atr_std == 0)
            return 0.5;

        double z_score = (m_atr_current - m_atr_mean) / atr_std;

        // Score ottimale: z-score tra -0.5 e 1.5
        double score;
        if(z_score >= -0.5 && z_score <= 1.5)
            score = 1.0;
        else if(z_score > 1.5)  // Troppo volatile
            score = MathMax(0.0, 1.0 - (z_score - 1.5) * 0.2);
        else  // Troppo bassa
            score = MathMax(0.0, 1.0 + (z_score + 0.5) * 0.3);

        return MathMax(0.0, MathMin(1.0, score));
    }

    //+------------------------------------------------------------------+
    //| Aggiorna info sessione                                           |
    //+------------------------------------------------------------------+
    void UpdateSessionInfo()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int hour_utc = dt.hour;

        // Determina sessione e multiplier
        if(hour_utc >= 13 && hour_utc < 16)
        {
            m_current_session = "LONDON_NY_OVERLAP";
            m_session_multiplier = m_session_multiplier_overlap;
        }
        else if(hour_utc >= 8 && hour_utc < 16)
        {
            m_current_session = "LONDON";
            m_session_multiplier = m_session_multiplier_london;
        }
        else if(hour_utc >= 13 && hour_utc < 21)
        {
            m_current_session = "NY";
            m_session_multiplier = m_session_multiplier_ny;
        }
        else
        {
            m_current_session = "ASIAN";
            m_session_multiplier = m_session_multiplier_asian;
        }

        // Disabilita se non usato
        if(!m_use_session_filter)
            m_session_multiplier = 1.0;
    }

    //+------------------------------------------------------------------+
    //| Calcola Score di Tradabilità Finale                              |
    //+------------------------------------------------------------------+
    double CalculateTradabilityScore()
    {
        // Score individuali (0-1, dove 1 = ottimo per trading)
        double entropy_score = 1.0 - m_entropy_current;  // Bassa entropia = buono
        double adx_score = MathMin(m_adx_current / 40.0, 1.0);  // Alto ADX = buono
        double chop_score = 1.0 - (m_choppiness_current / 100.0);  // Basso chop = buono

        // Score base pesato
        double base_score = (entropy_score * m_weight_entropy) +
                           (adx_score * m_weight_adx) +
                           (chop_score * m_weight_choppiness) +
                           (m_volatility_score * m_weight_volatility);

        // Applica multiplier sessione
        double final_score = base_score * m_session_multiplier;

        return MathMax(0.0, MathMin(1.0, final_score));
    }

    //+------------------------------------------------------------------+
    //| Determina Regime di Mercato                                      |
    //+------------------------------------------------------------------+
    void DetermineMarketRegime()
    {
        if(m_tradability_score >= 0.75)
            m_market_regime = "STRONG_TREND";
        else if(m_tradability_score >= 0.60)
            m_market_regime = "TRADABLE";
        else if(m_tradability_score >= 0.45)
            m_market_regime = "CHOPPY";
        else
            m_market_regime = "HIGHLY_CHAOTIC";
    }

    //+------------------------------------------------------------------+
    //| Aggiorna Stato del Gate                                          |
    //+------------------------------------------------------------------+
    void UpdateGateState()
    {
        bool should_block = (m_tradability_score < m_min_score_to_trade);

        if(should_block)
        {
            m_consecutive_blocked++;

            // Attiva blocco dopo N barre consecutive
            if(m_consecutive_blocked >= m_confirmation_bars)
            {
                if(!m_gate_closed)
                {
                    m_gate_closed = true;
                    Print("🚫 GATE CHIUSO - Score: ", DoubleToString(m_tradability_score * 100, 1),
                          "% (min: ", DoubleToString(m_min_score_to_trade * 100, 0), "%)");
                    Print("   Regime: ", m_market_regime, " | Session: ", m_current_session);
                }
            }
        }
        else
        {
            m_consecutive_blocked = 0;

            // Disattiva blocco con hysteresis
            if(m_gate_closed && m_tradability_score > (m_min_score_to_trade * (1.0 + m_hysteresis_factor)))
            {
                m_gate_closed = false;
                Print("✅ GATE APERTO - Score: ", DoubleToString(m_tradability_score * 100, 1), "%");
                Print("   Regime: ", m_market_regime, " | Session: ", m_current_session);
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Stampa Status del Gate (debug)                                   |
    //+------------------------------------------------------------------+
    void PrintGateStatus()
    {
        string status = m_gate_closed ? "🚫 CLOSED" : "✅ OPEN";

        Print("========== GOLD ENTROPY GATE ==========");
        Print("Status: ", status, " | Score: ", DoubleToString(m_tradability_score * 100, 1),
              "% (min: ", DoubleToString(m_min_score_to_trade * 100, 0), "%)");
        Print("Regime: ", m_market_regime, " | Session: ", m_current_session,
              " (x", DoubleToString(m_session_multiplier, 2), ")");
        Print("--- Metrics ---");
        Print("Entropy: ", DoubleToString(m_entropy_current, 3),
              " (score: ", DoubleToString((1.0 - m_entropy_current) * 100, 1), "%)");
        Print("ADX: ", DoubleToString(m_adx_current, 1),
              " (score: ", DoubleToString(MathMin(m_adx_current / 40.0, 1.0) * 100, 1), "%)");
        Print("Choppiness: ", DoubleToString(m_choppiness_current, 1),
              " (score: ", DoubleToString((1.0 - m_choppiness_current/100.0) * 100, 1), "%)");
        Print("ATR: $", DoubleToString(m_atr_current, 2),
              " | Vol.Score: ", DoubleToString(m_volatility_score * 100, 1), "%");
        Print("Consecutive Blocked: ", m_consecutive_blocked, "/", m_confirmation_bars);
        Print("=======================================");
    }
};
