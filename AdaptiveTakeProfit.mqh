//+------------------------------------------------------------------+
//|                                      AdaptiveTakeProfit.mqh      |
//|                                  Copyright 2025, Your Name       |
//|              Modulo Take Profit Adattativo con Formula Esponenziale |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property version   "2.00"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Struttura per la configurazione del modulo                       |
//+------------------------------------------------------------------+
struct AdaptiveTPConfig
{
    bool active;                          // Attiva/disattiva il modulo
    double a;                             // Coefficiente 'a' (moltiplicatore)
    double b;                             // Coefficiente 'b' (esponente)
    double c;                             // Coefficiente 'c' (offset)
    double cap;                           // CAP massimo in percentuale
    double floor;                         // FLOOR minimo in percentuale
    double fallback;                      // Valore fallback in percentuale

    // Costruttore con valori di default
    AdaptiveTPConfig()
    {
        active = true;                    // Attivo di default
        a = 3.2;                          // Moltiplicatore base
        b = 0.75;                         // Esponente
        c = 0.03;                         // Offset
        cap = 0.6;                        // 0.6% CAP massimo
        floor = 0.2;                      // 0.2% minimo
        fallback = 0.4;                   // 0.4% fallback
    }
};

//+------------------------------------------------------------------+
//| Classe per il calcolo del Take Profit Adattativo                 |
//+------------------------------------------------------------------+
class CAdaptiveTakeProfit
{
private:
    AdaptiveTPConfig m_config;            // Configurazione del modulo
    int m_atr_handle;                     // Handle per l'indicatore ATR
    double m_atr_buffer[];                // Buffer per i valori ATR
    string m_symbol;                      // Simbolo corrente

public:
    // Costruttore
    CAdaptiveTakeProfit()
    {
        m_atr_handle = INVALID_HANDLE;
        ArraySetAsSeries(m_atr_buffer, true);
        m_symbol = "";
    }

    // Inizializzazione
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe, const AdaptiveTPConfig &config)
    {
        m_config = config;
        m_symbol = symbol;

        if(m_config.active)
        {
            // Crea handle per ATR(100)
            m_atr_handle = iATR(symbol, timeframe, 100);
            if(m_atr_handle == INVALID_HANDLE)
            {
                Print("ERRORE AdaptiveTP: Impossibile creare handle ATR(100) per ", symbol);
                return false;
            }

            // Prepara buffer
            if(ArrayResize(m_atr_buffer, 3) <= 0)
            {
                Print("ERRORE AdaptiveTP: Impossibile allocare buffer ATR");
                return false;
            }

            Print("AdaptiveTP: Inizializzato per ", symbol,
                  " | a=", m_config.a, " b=", m_config.b, " c=", m_config.c,
                  " | CAP=", m_config.cap, "% FLOOR=", m_config.floor, "% FALLBACK=", m_config.fallback, "%");
        }
        else
        {
            Print("AdaptiveTP: Modulo DISATTIVATO - Usa fallback ", m_config.fallback, "%");
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

    //+------------------------------------------------------------------+
    //| Calcola la percentuale di TrailingStartPercent                   |
    //| Formula: TP = (ATR*100)/Prezzo * [a*(EMA_ratio)^b + c]          |
    //| - Per LONG (EMA20 > EMA50): ratio = EMA20/EMA50                 |
    //| - Per SHORT (EMA20 < EMA50): ratio = EMA50/EMA20                |
    //+------------------------------------------------------------------+
    double CalculateTrailingStartPercent(double current_price,
                                         double ema20,
                                         double ema50,
                                         double atr_value = 0.0)
    {
        // Se il modulo è disattivato, usa il fallback
        if(!m_config.active)
        {
            return m_config.fallback;
        }

        // Validazione input
        if(current_price <= 0.0 || ema20 <= 0.0 || ema50 <= 0.0)
        {
            Print("ERRORE AdaptiveTP: Dati invalidi - Prezzo=", current_price,
                  " EMA20=", ema20, " EMA50=", ema50);
            return m_config.fallback;
        }

        // Ottieni valore ATR
        double atr;
        if(atr_value > 0.0)
        {
            atr = atr_value;
        }
        else
        {
            if(ArraySize(m_atr_buffer) > 0 && m_atr_buffer[0] > 0.0)
            {
                atr = m_atr_buffer[0];
            }
            else
            {
                Print("ERRORE AdaptiveTP: ATR non disponibile");
                return m_config.fallback;
            }
        }

        // Calcola ATR in percentuale: (ATR * 100) / Prezzo
        double atr_percent = (atr * 100.0) / current_price;

        // Determina se è LONG o SHORT
        bool is_long = (ema20 > ema50);

        // Calcola il ratio EMA
        double ema_ratio;
        if(is_long)
        {
            // LONG: EMA20 / EMA50
            ema_ratio = ema20 / ema50;
        }
        else
        {
            // SHORT: EMA50 / EMA20
            ema_ratio = ema50 / ema20;
        }

        // Calcola il moltiplicatore: a * (ratio)^b + c
        double multiplier = m_config.a * MathPow(ema_ratio, m_config.b) + m_config.c;

        // Calcola il TP finale: atr_percent * multiplier
        double tp_percent = atr_percent * multiplier;

        // Applica CAP (massimo)
        if(tp_percent > m_config.cap)
        {
            tp_percent = m_config.cap;
        }

        // Applica FLOOR (minimo)
        if(tp_percent < m_config.floor)
        {
            tp_percent = m_config.floor;
        }

        // OTTIMIZZATO: Log dettagliato solo se NON in backtesting
        if(!MQLInfoInteger(MQL_TESTER))
        {
            string direction = is_long ? "LONG" : "SHORT";
            Print("AdaptiveTP [", direction, "]: Prezzo=", DoubleToString(current_price, 2),
                  " ATR=", DoubleToString(atr, 2), " (", DoubleToString(atr_percent, 4), "%)",
                  " | EMA20=", DoubleToString(ema20, 2), " EMA50=", DoubleToString(ema50, 2),
                  " | Ratio=", DoubleToString(ema_ratio, 4),
                  " | Mult=", DoubleToString(multiplier, 4),
                  " | TP=", DoubleToString(tp_percent, 4), "%");
        }

        return tp_percent;
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

    // Ottieni configurazione
    AdaptiveTPConfig GetConfig() const { return m_config; }

    // Distruttore
    ~CAdaptiveTakeProfit()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }
};
//+------------------------------------------------------------------+
