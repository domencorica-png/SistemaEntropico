//+------------------------------------------------------------------+
//|                      EntropyFilter.mqh                           |
//|                        Filtro Entropico Corretto                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property version   "1.00"

// Costante ottimizzazione: logaritmo in base 2 pre-calcolato
#define LOG2_CONST 0.69314718055994530941723212145818

class CEntropyFilter
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // Parametri configurabili
    int m_period_breve;      // Periodo breve (default: 14)
    int m_period_medio;      // Periodo medio (default: 42)
    int m_period_lungo;      // Periodo lungo (default: 100)

    int m_bins;              // Numero di bins per la discretizzazione
    double m_sideways_threshold;    // Soglia per mercato laterale
    double m_chaotic_threshold;     // Soglia per mercato caotico
    
    // Volatilità per conferma
    double m_volatility_threshold_min;
    double m_volatility_threshold_max;
    
    // Buffer per i calcoli
    double m_returns_breve[];
    double m_returns_medio[];
    double m_returns_lungo[];
    
    double m_entropy_breve;
    double m_entropy_medio; 
    double m_entropy_lungo;
    
    double m_volatility_current;
    
    // Stato del filtro
    bool m_is_sideways;
    bool m_is_chaotic;
    int m_consecutive_sideways;
    int m_consecutive_chaotic;
    
    // Parametri di smoothing
    int m_confirmation_bars;
    double m_hysteresis_factor;

    // FIX CRITICO: Handle dedicato per ATR volatilità
    int m_atr_volatility_handle;
    
public:
    // Costruttore
    CEntropyFilter()
    {
        m_period_breve = 14;
        m_period_medio = 42;
        m_period_lungo = 100;
        m_bins = 10;
        m_sideways_threshold = 0.85;
        m_chaotic_threshold = 0.95;
        m_volatility_threshold_min = 0.5;
        m_volatility_threshold_max = 3.0;
        m_confirmation_bars = 2;
        m_hysteresis_factor = 0.05;

        m_is_sideways = false;
        m_is_chaotic = false;
        m_consecutive_sideways = 0;
        m_consecutive_chaotic = 0;
        m_atr_volatility_handle = INVALID_HANDLE;  // Inizializza handle ATR

        // Inizializza i buffer
        InitializeBuffers();
    }
    
    // Inizializzazione
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe, 
              int period_breve = 14, int period_medio = 42, int period_lungo = 100,
              int bins = 10, double sideways_threshold = 0.85, double chaotic_threshold = 0.95,
              double volatility_min = 0.5, double volatility_max = 3.0,
              int confirmation_bars = 2, double hysteresis = 0.05)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_period_breve = period_breve;
        m_period_medio = period_medio;
        m_period_lungo = period_lungo;
        m_bins = bins;
        m_sideways_threshold = sideways_threshold;
        m_chaotic_threshold = chaotic_threshold;
        m_volatility_threshold_min = volatility_min;
        m_volatility_threshold_max = volatility_max;
        m_confirmation_bars = confirmation_bars;
        m_hysteresis_factor = hysteresis;
        
        // Ri-inizializza i buffer con i nuovi parametri
        InitializeBuffers();
        
        return true;
    }
    
    // Inizializza i buffer
    void InitializeBuffers()
    {
        ArrayResize(m_returns_breve, MathMax(m_period_breve + 5, 20));
        ArrayInitialize(m_returns_breve, 0.0);
        ArrayResize(m_returns_medio, MathMax(m_period_medio + 5, 20));
        ArrayInitialize(m_returns_medio, 0.0);
        ArrayResize(m_returns_lungo, MathMax(m_period_lungo + 5, 20)); 
        ArrayInitialize(m_returns_lungo, 0.0);
        
        ArraySetAsSeries(m_returns_breve, true);
        ArraySetAsSeries(m_returns_medio, true);
        ArraySetAsSeries(m_returns_lungo, true);
    }
    
    // Aggiorna i dati e calcola l'entropia
    void Update()
    {
        if(!UpdateReturns()) return;

        // Calcola l'entropia per ogni timeframe - CORREZIONE FONDAMENTALE: usa MathLog2
        m_entropy_breve = CalculateEntropy(m_returns_breve, m_period_breve);
        m_entropy_medio = CalculateEntropy(m_returns_medio, m_period_medio);
        m_entropy_lungo = CalculateEntropy(m_returns_lungo, m_period_lungo);

        // Calcola volatilità corrente (ATR normalizzato)
        m_volatility_current = CalculateNormalizedVolatility();

        // DEBUG LOGGING: Stampa valori ad ogni update per identificare problemi
        static int log_counter = 0;
        log_counter++;
        if(log_counter % 20 == 0)  // Logga ogni 20 barre per non sovraccaricare
        {
            Print("=== ENTROPY FILTER DEBUG ===");
            Print("Entropia Breve: ", DoubleToString(m_entropy_breve, 4));
            Print("Entropia Medio: ", DoubleToString(m_entropy_medio, 4));
            Print("Entropia Lungo: ", DoubleToString(m_entropy_lungo, 4));
            Print("Entropia Ponderata: ", DoubleToString((m_entropy_breve * 0.5) + (m_entropy_medio * 0.3) + (m_entropy_lungo * 0.2), 4),
                  " (Soglia Sideways: ", DoubleToString(m_sideways_threshold, 2),
                  ", Soglia Chaotic: ", DoubleToString(m_chaotic_threshold, 2), ")");
            Print("Volatilità %: ", DoubleToString(m_volatility_current, 4));
            Print("Consecutive Sideways: ", m_consecutive_sideways,
                  " / ", m_confirmation_bars);
            Print("Consecutive Chaotic: ", m_consecutive_chaotic,
                  " / ", m_confirmation_bars);
            Print("Stato: ", (m_is_sideways ? "LATERALE" : (m_is_chaotic ? "CAOTICO" : "NORMALE")));
            Print("============================");
        }

        // Determina lo stato del mercato con conferma
        UpdateMarketState();
    }
    
    // Verifica se il mercato è laterale/caotico
    bool IsMarketSidewaysOrChaotic()
    {
        return m_is_sideways || m_is_chaotic;
    }
    
    // Ottieni i valori correnti
    double GetEntropyBreve() const { return m_entropy_breve; }
    double GetEntropyMedio() const { return m_entropy_medio; }
    double GetEntropyLungo() const { return m_entropy_lungo; }
    double GetWeightedEntropy() const
    {
        return (m_entropy_breve * 0.5) + (m_entropy_medio * 0.3) + (m_entropy_lungo * 0.2);
    }
    double GetVolatility() const { return m_volatility_current; }
    bool IsSideways() const { return m_is_sideways; }
    bool IsChaotic() const { return m_is_chaotic; }
    
private:
    // Aggiorna i returns dei prezzi
    bool UpdateReturns()
    {
        int total_bars = MathMax(m_period_lungo + 5, 200);
        double close_prices[];
        
        if(CopyClose(m_symbol, m_timeframe, 0, total_bars, close_prices) != total_bars)
            return false;
            
        ArraySetAsSeries(close_prices, true);

        // OTTIMIZZAZIONE: Calcola returns logaritmici con un singolo ciclo unificato
        // Questo migliora la località della cache e riduce le iterazioni
        for(int i = 0; i < m_period_lungo; i++)
        {
            if(i + 1 < total_bars && close_prices[i+1] != 0)
            {
                double log_return = MathLog(close_prices[i] / close_prices[i+1]);

                if(i < m_period_breve)
                    m_returns_breve[i] = log_return;

                if(i < m_period_medio)
                    m_returns_medio[i] = log_return;

                m_returns_lungo[i] = log_return;
            }
            else
            {
                // Imposta a 0 se non ci sono abbastanza dati
                if(i < m_period_breve)
                    m_returns_breve[i] = 0.0;
                if(i < m_period_medio)
                    m_returns_medio[i] = 0.0;
                m_returns_lungo[i] = 0.0;
            }
        }
        
        return true;
    }
    
    // Calcola l'entropia di Shannon CORRETTAMENTE (base 2)
    double CalculateEntropy(const double &returns[], int period)
    {
        if(period <= 0 || ArraySize(returns) < period) return 0.0;
        
        // Trova minimo e massimo dei returns
        double min_val = returns[0];
        double max_val = returns[0];
        
        for(int i = 0; i < period; i++)
        {
            if(returns[i] < min_val) min_val = returns[i];
            if(returns[i] > max_val) max_val = returns[i];
        }
        
        // Evita divisione per zero
        if(max_val == min_val) return 0.0;
        
        // Calcola la larghezza di ogni bin
        double bin_width = (max_val - min_val) / m_bins;
        if(bin_width == 0) return 0.0;
        
        // Conta le occorrenze in ogni bin
        int bin_counts[];
        ArrayResize(bin_counts, m_bins + 1);
        ArrayInitialize(bin_counts, 0);
        
        for(int i = 0; i < period; i++)
        {
            double r = returns[i];
            int bin_index;
            
            if(r <= min_val) bin_index = 0;
            else if(r >= max_val) bin_index = m_bins;
            else bin_index = (int)((r - min_val) / bin_width);
            
            if(bin_index >= 0 && bin_index <= m_bins)
                bin_counts[bin_index]++;
        }
        
        // Calcola le probabilità e l'entropia - CORREZIONE FONDAMENTALE
        double entropy = 0.0;
        for(int i = 0; i <= m_bins; i++)
        {
            double probability = (double)bin_counts[i] / (double)period;
            if(probability > 0)
            {
                // Usa logaritmo in base 2: log2(x) = log(x) / log(2)
                entropy -= probability * (MathLog(probability) / LOG2_CONST);
            }
        }
        
        // Normalizza l'entropia tra 0 e 1
        double max_entropy = (MathLog((double)(m_bins + 1)) / LOG2_CONST);
        if(max_entropy > 0)
            entropy = entropy / max_entropy;
            
        return MathMax(0.0, MathMin(1.0, entropy));
    }
    
    // Calcola volatilità normalizzata (ATR relativo)
    // FIX CRITICO: Usa handle separato per ATR invece di crearne uno nuovo ogni volta!
    double CalculateNormalizedVolatility()
    {
        int atr_period = 14;
        double atr[];

        // Crea handle se non esiste
        if(m_atr_volatility_handle == INVALID_HANDLE)
        {
            m_atr_volatility_handle = iATR(m_symbol, m_timeframe, atr_period);
            if(m_atr_volatility_handle == INVALID_HANDLE)
            {
                Print("ERRORE EntropyFilter: Impossibile creare handle ATR per volatilità");
                return 1.0;
            }
        }

        if(CopyBuffer(m_atr_volatility_handle, 0, 0, atr_period + 1, atr) <= 0)
            return 1.0;

        ArraySetAsSeries(atr, true);

        double current_price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(current_price == 0) return 1.0;

        // ATR normalizzato come percentuale del prezzo
        return (atr[0] / current_price) * 100.0;
    }
    
    // Determina lo stato del mercato con meccanismo di conferma - LOGICA CORRETTA
    void UpdateMarketState()
    {
        // FIX CRITICO #2: Usa TUTTE E 3 le entropie con media ponderata
        // Peso maggiore al breve (più reattivo), ma considera anche medio e lungo
        double weighted_entropy = (m_entropy_breve * 0.5) + (m_entropy_medio * 0.3) + (m_entropy_lungo * 0.2);

        // Determina lo stato corrente usando l'entropia ponderata
        // Alta entropia = mercato laterale/caotico (movimento random)
        bool current_sideways = (weighted_entropy > m_sideways_threshold);
        bool current_chaotic = (weighted_entropy > m_chaotic_threshold);

        // FIX CRITICO: Conta le barre CONSECUTIVE in cui lo stato È attivo
        // Non i cambi di stato!

        // Gestione SIDEWAYS
        if(current_sideways)
        {
            m_consecutive_sideways++;
        }
        else
        {
            m_consecutive_sideways = 0;
        }

        // Gestione CHAOTIC
        if(current_chaotic)
        {
            m_consecutive_chaotic++;
        }
        else
        {
            m_consecutive_chaotic = 0;
        }

        // Attiva lo stato solo dopo N barre consecutive di conferma
        if(m_consecutive_sideways >= m_confirmation_bars)
        {
            if(!m_is_sideways)
            {
                m_is_sideways = true;
                Print("ENTROPY FILTER: Mercato LATERALE attivato (Entropia Ponderata=",
                      DoubleToString(weighted_entropy, 4), ", Soglia=",
                      DoubleToString(m_sideways_threshold, 4), ")");
            }
        }
        else
        {
            if(m_is_sideways && weighted_entropy < (m_sideways_threshold * (1.0 - m_hysteresis_factor)))
            {
                m_is_sideways = false;
                Print("ENTROPY FILTER: Mercato LATERALE disattivato");
            }
        }

        // Attiva lo stato CHAOTIC solo dopo N barre consecutive di conferma
        if(m_consecutive_chaotic >= m_confirmation_bars)
        {
            if(!m_is_chaotic)
            {
                m_is_chaotic = true;
                Print("ENTROPY FILTER: Mercato CAOTICO attivato (Entropia Ponderata=",
                      DoubleToString(weighted_entropy, 4), ", Soglia=",
                      DoubleToString(m_chaotic_threshold, 4), ")");
            }
        }
        else
        {
            if(m_is_chaotic && weighted_entropy < (m_chaotic_threshold * (1.0 - m_hysteresis_factor)))
            {
                m_is_chaotic = false;
                Print("ENTROPY FILTER: Mercato CAOTICO disattivato");
            }
        }
    }

    // Distruttore - rilascia handle ATR
    ~CEntropyFilter()
    {
        if(m_atr_volatility_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_volatility_handle);
    }
};