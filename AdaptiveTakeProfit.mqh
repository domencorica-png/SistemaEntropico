//+------------------------------------------------------------------+
//|                      AdaptiveTakeProfit.mqh                      |
//|                        Copyright 2025, Your Name                 |
//|                        Modulo Take Profit Adattativo Percentuale |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property version   "1.00"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Struttura per la configurazione del modulo                       |
//+------------------------------------------------------------------+
struct AdaptiveTPConfig
{
    bool active;                    // Attiva/disattiva il modulo
    double long_a;                  // Coefficiente 'a' per long
    double long_b;                  // Coefficiente 'b' per long  
    double short_a;                 // Coefficiente 'a' per short
    double short_b;                 // Coefficiente 'b' per short
    double fixed_cap_percent;       // CAP massimo in percentuale
    double min_threshold_percent;   // Soglia minima in percentuale
    double fallback_percent;        // Valore fallback in percentuale
    
    // Costruttore con valori di default ottimizzati per XAUUSD 10min
    AdaptiveTPConfig()
    {
        active = false;             // Disattivato di default
        long_a = 1.2;               // Moltiplicatore base per long
        long_b = 0.8;               // Offset base per long
        short_a = 1.3;              // Moltiplicatore base per short (più aggressivo)
        short_b = 0.7;              // Offset base per short
        fixed_cap_percent = 0.65;   // 0.65% CAP (circa 26 punti a 4000)
        min_threshold_percent = 0.2; // 0.2% minimo
        fallback_percent = 0.4;     // 0.4% fallback (valore attuale del tuo bot)
    }
};

//+------------------------------------------------------------------+
//| Classe per il calcolo del Take Profit Adattativo                |
//+------------------------------------------------------------------+
class CAdaptiveTakeProfit
{
private:
    AdaptiveTPConfig m_config;          // Configurazione del modulo
    int m_atr_handle;                   // Handle per l'indicatore ATR
    double m_atr_buffer[];              // Buffer per i valori ATR
    
public:
    // Costruttore
    CAdaptiveTakeProfit()
    {
        m_atr_handle = INVALID_HANDLE;
        ArraySetAsSeries(m_atr_buffer, true);
    }
    
    // Inizializzazione
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe, const AdaptiveTPConfig &config)
    {
        m_config = config;
        
        if(m_config.active)
        {
            // Crea handle per ATR(14)
            m_atr_handle = iATR(symbol, timeframe, 14);
            if(m_atr_handle == INVALID_HANDLE)
            {
                Print("ERRORE AdaptiveTP: Impossibile creare handle ATR(14)");
                return false;
            }
            
            // Prepara buffer
            if(ArrayResize(m_atr_buffer, 3) <= 0)
            {
                Print("ERRORE AdaptiveTP: Impossibile allocare buffer ATR");
                return false;
            }
        }
        
        return true;
    }
    
    // Configura i parametri
    void Configure(const AdaptiveTPConfig &config)
    {
        m_config = config;
    }
    
    // Aggiorna i dati dell'indicatore
    bool UpdateData()
    {
        if(!m_config.active || m_atr_handle == INVALID_HANDLE)
            return true;
        
        if(CopyBuffer(m_atr_handle, 0, 0, 3, m_atr_buffer) <= 0)
        {
            Print("ERRORE AdaptiveTP: Errore copia buffer ATR");
            return false;
        }
        
        return true;
    }
    
    // Calcola la soglia di attivazione trailing in PERCENTUALE
    double CalculateTrailingThreshold(bool is_long, double current_price, 
                                      double ema20, double ema50, 
                                      double atr_value = 0.0)
    {
        // Se il modulo è disattivato, usa il fallback
        if(!m_config.active)
            return m_config.fallback_percent;
        
        double atr;
        if(atr_value > 0.0)
        {
            atr = atr_value;
        }
        else
        {
            if(ArraySize(m_atr_buffer) > 0)
            {
                atr = m_atr_buffer[0];
            }
            else
            {
                atr = 10.0; // Valore di sicurezza
            }
        }
        
        if(atr <= 0.0) 
            atr = 10.0; // Valore di sicurezza
        
        // Converte ATR da punti a percentuale
        double atr_percent = (atr / current_price) * 100.0;
        
        // Calcola il moltiplicatore adattativo basato sul trend
        double multiplier = 0.0;
        
        if(is_long)
        {
            // Solo per long: EMA20/EMA50 (deve essere >1 per aprire long)
            double ema_ratio;
            if(ema50 != 0.0)
            {
                ema_ratio = ema20 / ema50;
            }
            else
            {
                ema_ratio = 1.0;
            }
            multiplier = (m_config.long_a * ema_ratio) + m_config.long_b;
        }
        else
        {
            // Solo per short: EMA50/EMA20 (deve essere >1 per aprire short)  
            double ema_ratio;
            if(ema20 != 0.0)
            {
                ema_ratio = ema50 / ema20;
            }
            else
            {
                ema_ratio = 1.0;
            }
            multiplier = (m_config.short_a * ema_ratio) + m_config.short_b;
        }
        
        // Calcolo base in percentuale
        double base_threshold = atr_percent * multiplier;
        
        // Applica CAP per proteggere da inversioni improvvise
        double capped_threshold;
        if(base_threshold < m_config.fixed_cap_percent)
        {
            capped_threshold = base_threshold;
        }
        else
        {
            capped_threshold = m_config.fixed_cap_percent;
        }
        
        // Applica vincoli di sicurezza
        double final_threshold;
        double max_allowed = m_config.fixed_cap_percent * 1.5;
        
        if(capped_threshold < m_config.min_threshold_percent)
        {
            final_threshold = m_config.min_threshold_percent;
        }
        else if(capped_threshold > max_allowed)
        {
            final_threshold = max_allowed;
        }
        else
        {
            final_threshold = capped_threshold;
        }
        
        return final_threshold;
    }
    
    // Ottieni lo stato del modulo
    bool IsActive() const { return m_config.active; }
    
    // Ottieni l'ATR corrente
    double GetCurrentATR() const 
    {
        if(ArraySize(m_atr_buffer) > 0)
        {
            return m_atr_buffer[0];
        }
        else
        {
            return 0.0;
        }
    }
    
    // Distruttore
    ~CAdaptiveTakeProfit()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }
};
//+------------------------------------------------------------------+