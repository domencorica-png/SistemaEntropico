//+------------------------------------------------------------------+
//|                      TradingWrapper.mqh                          |
//|                        Wrapper per Integrazione Filtro           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property version   "1.00"
#include <Trade\Trade.mqh>
// Include i file necessari
#include "EntropyFilter.mqh"
#include "BotOriginale.mqh"
#include "AdaptiveTakeProfit.mqh"  // Inclusione modulo Adaptive Take Profit

class CTradingWrapper
{
private:
    CTrade m_trade;                    // Oggetto di trading
    CEntropyFilter m_entropyFilter;    // Filtro entropico CORRETTO
    CAdaptiveTakeProfit m_adaptiveTP;  // Modulo Take Profit Adattativo
    
    bool m_enableEntropyFilter;        // Flag per attivare/disattivare il filtro
    bool m_enableAdaptiveTP;           // Flag per attivare/disattivare il TP adattativo
    int m_magicNumber;                  // Magic number per identificare le posizioni
    
    string m_symbol;                    // Simbolo di trading
    ENUM_TIMEFRAMES m_timeframe;        // Timeframe
    
    SymbolConfig m_symbolConfig;
    TrailingData m_trailingPositions[];
    PendingSignal m_pendingSignals[];
    SimpleCrossTracker m_crossTrackers[];

    datetime m_lastFilterUpdate;        // Ultimo aggiornamento del filtro
    datetime m_lastAdaptiveTPUpdate;   // Ultimo aggiornamento del modulo AdaptiveTP
    datetime m_lastManagePositions;    // Ultimo aggiornamento ManagePositions
    int m_filterUpdateInterval;         // Intervallo di aggiornamento filtro in secondi
    int m_adaptiveTPUpdateInterval;    // Intervallo di aggiornamento AdaptiveTP in secondi
    int m_managePositionsInterval;     // Intervallo di aggiornamento ManagePositions in secondi

    bool m_useDynamicLotManagement;
    int m_backtestEndBufferDays;
    bool m_stochFilterPost;

    // OTTIMIZZAZIONE: Cache per valori SymbolInfo statici
    double m_cached_point;
    int m_cached_digits;
    double m_cached_min_stop_distance;
    bool m_symbol_info_cached;

public:
    // Costruttore
    CTradingWrapper()
    {
        m_enableEntropyFilter = true;
        m_enableAdaptiveTP = false;    // Disattivato di default
        m_magicNumber = 123456;

        // OTTIMIZZAZIONE: Intervalli più lunghi in backtesting per massima velocità
        if(MQLInfoInteger(MQL_TESTER))
        {
            m_filterUpdateInterval = 300;      // Backtesting: 5 minuti (il filtro non cambia rapidamente)
            m_adaptiveTPUpdateInterval = 120;  // Backtesting: 2 minuti
            m_managePositionsInterval = 2;     // Backtesting: 2 secondi (trailing meno frequente)
        }
        else
        {
            m_filterUpdateInterval = 60;       // Live: 1 minuto
            m_adaptiveTPUpdateInterval = 60;   // Live: 1 minuto
            m_managePositionsInterval = 1;     // Live: 1 secondo (più reattivo)
        }

        m_lastFilterUpdate = 0;
        m_lastAdaptiveTPUpdate = 0;
        m_lastManagePositions = 0;
        m_useDynamicLotManagement = true;
        m_backtestEndBufferDays = 30;
        m_stochFilterPost = false;
        m_symbol_info_cached = false;
    }
    
    // Inizializzazione
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe, int magicNumber, 
             bool enableEntropyFilter = true,
             bool useDynamicLotManagement = true,
             int backtestEndBufferDays = 30,
             bool stochFilterPost = false,
             bool enableAdaptiveTP = false)  // Parametro aggiuntivo per TP adattativo
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_magicNumber = magicNumber;
        m_enableEntropyFilter = enableEntropyFilter;
        m_enableAdaptiveTP = enableAdaptiveTP;  // Imposta lo stato del TP adattativo
        m_useDynamicLotManagement = useDynamicLotManagement;
        m_backtestEndBufferDays = backtestEndBufferDays;
        m_stochFilterPost = stochFilterPost;
        
        // Inizializza il modulo AdaptiveTP se attivato
        if(m_enableAdaptiveTP)
        {
            AdaptiveTPConfig tpConfig;
            tpConfig.active = true;
            // Valori di default con formula esponenziale
            tpConfig.a = 3.2;        // Moltiplicatore
            tpConfig.b = 0.75;       // Esponente
            tpConfig.c = 0.03;       // Offset
            tpConfig.cap = 0.6;      // 0.6% CAP massimo
            tpConfig.floor = 0.2;    // 0.2% minimo
            tpConfig.fallback = 0.4; // 0.4% fallback
            
            if(!m_adaptiveTP.Init(m_symbol, m_timeframe, tpConfig))
            {
                Print("WARNING: Impossibile inizializzare AdaptiveTP - disattivato");
                m_enableAdaptiveTP = false;
            }
        }
        
        // Configura l'oggetto di trading
        m_trade.SetExpertMagicNumber(m_magicNumber);
        m_trade.SetDeviationInPoints(10);
        
        // Inizializza la configurazione del simbolo
        InitializeSymbolConfig();
            
        return true;
    }
    
    // Configura i parametri del simbolo usando una struttura
    void ConfigureSymbol(const SymbolConfig &config)
    {
        m_symbolConfig = config;
        
        // Inizializza gli handle degli indicatori
        if(!InitializeSymbolIndicators())
        {
            BotCore_Log("ERRORE: Impossibile inizializzare gli indicatori del simbolo", m_magicNumber);
        }
    }
    
    // Configura il filtro entropico - CORRETTO CON PARAMETRI AGGIUNTIVI
    void ConfigureEntropyFilter(int period_breve = 14, int period_medio = 42, int period_lungo = 100,
                               int bins = 10, double sideways_threshold = 0.85, 
                               double chaotic_threshold = 0.95, double volatility_min = 0.5,
                               double volatility_max = 3.0, int confirmation_bars = 2,
                               double hysteresis = 0.05)  // Parametri aggiuntivi per la conferma
    {
        m_entropyFilter.Init(m_symbol, m_timeframe, period_breve, period_medio, period_lungo,
                           bins, sideways_threshold, chaotic_threshold, volatility_min, volatility_max,
                           confirmation_bars, hysteresis);  // Passa i nuovi parametri
    }
    
    // Configura il modulo AdaptiveTP
    void ConfigureAdaptiveTP(const AdaptiveTPConfig &config)
    {
        m_adaptiveTP.Configure(config);
        m_enableAdaptiveTP = config.active;
    }
    
    // Funzione Tick wrapper
    void OnTick()
    {
        // Aggiorna il filtro entropico se necessario
        UpdateEntropyFilter();
        
        // Aggiorna il modulo AdaptiveTP se necessario
        UpdateAdaptiveTP();
        
        // Chiama la funzione Tick del bot originale
        BotOriginale_OnTick();
    }
    
    // Funzione OnInit wrapper  
    int OnInit()
    {
        return BotOriginale_OnInit();
    }
    
    // Funzione OnDeinit wrapper
    void OnDeinit(const int reason)
    {
        BotOriginale_OnDeinit(reason);
    }
    
    // Override delle funzioni di trading per applicare il filtro
    bool Buy(double lots, string symbol, double price, double sl, double tp, string comment)
    {
        if(m_enableEntropyFilter && ShouldBlockTrade())
        {
            // OTTIMIZZATO: Log solo se NON in backtesting (rallenta molto)
            if(!MQLInfoInteger(MQL_TESTER))
            {
                Print("ENTROPY FILTER: TRADE BLOCCATO - Mercato Laterale/Caotico");
                Print("  Entropia Breve: ", DoubleToString(m_entropyFilter.GetEntropyBreve(), 4));
                Print("  Volatilità: ", DoubleToString(m_entropyFilter.GetVolatility(), 4), "%");
                Print("  Stato: ", m_entropyFilter.IsSideways() ? "LATERALE" : "CAOTICO");
            }
            return false;
        }

        return m_trade.Buy(lots, symbol, price, sl, tp, comment);
    }

    bool Sell(double lots, string symbol, double price, double sl, double tp, string comment)
    {
        if(m_enableEntropyFilter && ShouldBlockTrade())
        {
            // OTTIMIZZATO: Log solo se NON in backtesting (rallenta molto)
            if(!MQLInfoInteger(MQL_TESTER))
            {
                Print("ENTROPY FILTER: TRADE BLOCCATO - Mercato Laterale/Caotico");
                Print("  Entropia Breve: ", DoubleToString(m_entropyFilter.GetEntropyBreve(), 4));
                Print("  Volatilità: ", DoubleToString(m_entropyFilter.GetVolatility(), 4), "%");
                Print("  Stato: ", m_entropyFilter.IsSideways() ? "LATERALE" : "CAOTICO");
            }
            return false;
        }

        return m_trade.Sell(lots, symbol, price, sl, tp, comment);
    }
    
    bool PositionClose(ulong ticket)
    {
        // Non filtriamo le chiusure, solo le aperture
        return m_trade.PositionClose(ticket);
    }
    
    bool PositionModify(ulong ticket, double sl, double tp)
    {
        // Non filtriamo le modifiche, solo le aperture
        return m_trade.PositionModify(ticket, sl, tp);
    }
    
    // Ottieni risultati delle operazioni
    ulong ResultOrder() const { return m_trade.ResultOrder(); }
    uint ResultRetcode() const { return m_trade.ResultRetcode(); }
    
private:
    void InitializeSymbolConfig()
    {
        // Inizializza i valori di default
        m_symbolConfig.magic_number = m_magicNumber;
    }
    
    bool InitializeSymbolIndicators()
    {
        if(!m_symbolConfig.active) return true;
        
        m_symbolConfig.ema20_handle = iMA(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.ema20_period, 0, MODE_EMA, PRICE_CLOSE);
        m_symbolConfig.ema50_handle = iMA(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.ema50_period, 0, MODE_EMA, PRICE_CLOSE);
        m_symbolConfig.stoch_handle = iStochastic(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.stoch_k, m_symbolConfig.stoch_d, m_symbolConfig.stoch_slowing, MODE_SMA, STO_LOWHIGH);
        m_symbolConfig.macd_handle = iMACD(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.macd_fast, m_symbolConfig.macd_slow, m_symbolConfig.macd_signal_period, PRICE_CLOSE);
        m_symbolConfig.adx_handle = iADX(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.adx_period);
        m_symbolConfig.rsi_handle = iRSI(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.rsi_period, PRICE_CLOSE);
        m_symbolConfig.obv_handle = iOBV(m_symbolConfig.symbol, m_symbolConfig.timeframe, VOLUME_TICK);
        m_symbolConfig.ema_override_handle = iMA(m_symbolConfig.symbol, m_symbolConfig.timeframe, m_symbolConfig.ema_override_period, 0, MODE_EMA, PRICE_CLOSE);
        m_symbolConfig.trend_ema20_handle = iMA(m_symbolConfig.symbol, m_symbolConfig.trend_timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
        m_symbolConfig.trend_ema50_handle = iMA(m_symbolConfig.symbol, m_symbolConfig.trend_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        
        if(m_symbolConfig.ema20_handle == INVALID_HANDLE || m_symbolConfig.ema50_handle == INVALID_HANDLE ||
           m_symbolConfig.stoch_handle == INVALID_HANDLE || m_symbolConfig.macd_handle == INVALID_HANDLE ||
           m_symbolConfig.adx_handle == INVALID_HANDLE || m_symbolConfig.rsi_handle == INVALID_HANDLE || 
           m_symbolConfig.obv_handle == INVALID_HANDLE || m_symbolConfig.ema_override_handle == INVALID_HANDLE ||
           m_symbolConfig.trend_ema20_handle == INVALID_HANDLE || m_symbolConfig.trend_ema50_handle == INVALID_HANDLE)
        {
            BotCore_Log("ERRORE: Handle indicatori non validi", m_magicNumber);
            return false;
        }
        
        ArraySetAsSeries(m_symbolConfig.ema20_buffer, true);
        ArraySetAsSeries(m_symbolConfig.ema50_buffer, true);
        ArraySetAsSeries(m_symbolConfig.stoch_main, true);
        ArraySetAsSeries(m_symbolConfig.stoch_signal, true);
        ArraySetAsSeries(m_symbolConfig.macd_main, true);
        ArraySetAsSeries(m_symbolConfig.macd_signal, true);
        ArraySetAsSeries(m_symbolConfig.adx_buffer, true);
        ArraySetAsSeries(m_symbolConfig.rsi_buffer, true);
        ArraySetAsSeries(m_symbolConfig.obv_buffer, true);
        ArraySetAsSeries(m_symbolConfig.ema_override_buffer, true);
        ArraySetAsSeries(m_symbolConfig.trend_ema20_buffer, true);
        ArraySetAsSeries(m_symbolConfig.trend_ema50_buffer, true);
        
        return true;
    }
    
    // Aggiorna il filtro entropico - FORZATO AD OGNI TICK IN BACKTESTING
    void UpdateEntropyFilter()
    {
        datetime current_time = TimeCurrent();
        
        // Forza l'aggiornamento ad ogni tick in backtesting per risultati consistenti
        #ifdef __MQL5__
        if(MQLInfoInteger(MQL_TESTER))
        {
            m_entropyFilter.Update();
            m_lastFilterUpdate = current_time;
            return;
        }
        #endif
        
        if(m_enableEntropyFilter && 
           (current_time - m_lastFilterUpdate >= m_filterUpdateInterval || m_lastFilterUpdate == 0))
        {
            m_entropyFilter.Update();
            m_lastFilterUpdate = current_time;
        }
    }
    
    // Aggiorna il modulo AdaptiveTP
    void UpdateAdaptiveTP()
    {
        if(!m_enableAdaptiveTP) return;
        
        datetime current_time = TimeCurrent();
        if(current_time - m_lastAdaptiveTPUpdate >= m_adaptiveTPUpdateInterval || m_lastAdaptiveTPUpdate == 0)
        {
            if(!m_adaptiveTP.UpdateData())
            {
                Print("ERRORE AdaptiveTP: Aggiornamento fallito - disattivazione");
                m_enableAdaptiveTP = false;
            }
            m_lastAdaptiveTPUpdate = current_time;
        }
    }
    
    // Determina se bloccare i trades
    bool ShouldBlockTrade()
    {
        if(!m_enableEntropyFilter) return false;

        // USA I DATI GIÀ IN CACHE - NON FORZARE L'AGGIORNAMENTO!
        // L'aggiornamento viene fatto ogni 60 secondi in UpdateEntropyFilter()
        return m_entropyFilter.IsMarketSidewaysOrChaotic();
    }
    
    // Funzioni del bot originale adattate
    int BotOriginale_OnInit()
    {
        BotCore_Log("========================================", m_magicNumber);
        BotCore_Log("EA v3.19 - SINGLE SYMBOL VERSION - WRAPPED", m_magicNumber);
        BotCore_Log("========================================", m_magicNumber);
        
        return INIT_SUCCEEDED;
    }
    
    void BotOriginale_OnDeinit(const int reason)
    {
        if(m_symbolConfig.ema20_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.ema20_handle);
        if(m_symbolConfig.ema50_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.ema50_handle);
        if(m_symbolConfig.stoch_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.stoch_handle);
        if(m_symbolConfig.macd_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.macd_handle);
        if(m_symbolConfig.adx_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.adx_handle);
        if(m_symbolConfig.rsi_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.rsi_handle);
        if(m_symbolConfig.obv_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.obv_handle);
        if(m_symbolConfig.ema_override_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.ema_override_handle);
        if(m_symbolConfig.trend_ema20_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.trend_ema20_handle);
        if(m_symbolConfig.trend_ema50_handle != INVALID_HANDLE) IndicatorRelease(m_symbolConfig.trend_ema50_handle);
    }
    
    void BotOriginale_OnTick()
    {
        static datetime last_cleanup = 0;
        static datetime last_orphan_check = 0;
        datetime current = TimeCurrent();
        
        #ifdef __MQL5__
        if(MQLInfoInteger(MQL_TESTER))
        {
            if(current - last_orphan_check > 300)
            {
                last_orphan_check = current;
                CheckOrphanPositions();
            }
        }
        #endif
        
        #ifdef __MQL5__
        if(MQLInfoInteger(MQL_TESTER) && m_backtestEndBufferDays > 0)
        {
            static datetime last_check = 0;
            if(current - last_check > 3600)
            {
                last_check = current;
                if(m_symbolConfig.active)
                {
                    for(int i = PositionsTotal() - 1; i >= 0; i--)
                    {
                        if(PositionGetTicket(i) > 0 &&
                           PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
                           PositionGetString(POSITION_SYMBOL) == m_symbolConfig.symbol)
                        {
                            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
                            int days_open = (int)((current - open_time) / 86400);
                            if(days_open >= m_backtestEndBufferDays)
                            {
                                PositionClose(PositionGetInteger(POSITION_TICKET));
                            }
                        }
                    }
                }
            }
        }
        #endif
        
        if(current - last_cleanup > 3600)
        {
            CleanOldCrossTrackers(m_crossTrackers);
            last_cleanup = current;
        }
        
        if(!m_symbolConfig.active) return;

        if(m_symbolConfig.use_time_mgmt) CheckTimeManagement();

        // OTTIMIZZAZIONE CRITICA: ManagePositions throttling per evitare chiamate ad ogni tick
        // Chiamalo solo ogni m_managePositionsInterval secondi (default 1 secondo)
        if(current - m_lastManagePositions >= m_managePositionsInterval || m_lastManagePositions == 0)
        {
            ManagePositions();
            m_lastManagePositions = current;
        }

        datetime ct = iTime(m_symbolConfig.symbol, m_symbolConfig.timeframe, 0);
        if(ct == m_symbolConfig.last_bar_time) return;
        m_symbolConfig.last_bar_time = ct;
        
        if(!UpdateIndicatorData()) return;
        
        int cp = CountPositions(m_symbolConfig.symbol, m_magicNumber);
        if(cp < m_symbolConfig.max_positions && IsTradingAllowed(m_symbolConfig))
        {
            CheckPendingSignals();
            CheckSignals();
        }
    }
    
    bool UpdateIndicatorData()
    {
        int eb = MathMax(10, m_symbolConfig.ema_lookback + 3);
        if(CopyBuffer(m_symbolConfig.ema20_handle, 0, 0, eb, m_symbolConfig.ema20_buffer) <= 0 ||
           CopyBuffer(m_symbolConfig.ema50_handle, 0, 0, eb, m_symbolConfig.ema50_buffer) <= 0) return false;
           
        if(CopyBuffer(m_symbolConfig.stoch_handle, 0, 0, 3, m_symbolConfig.stoch_main) <= 0 ||
           CopyBuffer(m_symbolConfig.stoch_handle, 1, 0, 3, m_symbolConfig.stoch_signal) <= 0) return false;
           
        int mb = MathMax(10, m_symbolConfig.macd_lookback + 3);
        if(CopyBuffer(m_symbolConfig.macd_handle, 0, 0, mb, m_symbolConfig.macd_main) <= 0 ||
           CopyBuffer(m_symbolConfig.macd_handle, 1, 0, mb, m_symbolConfig.macd_signal) <= 0) return false;
           
        if(CopyBuffer(m_symbolConfig.adx_handle, 0, 0, 3, m_symbolConfig.adx_buffer) <= 0) return false;
        
        if(CopyBuffer(m_symbolConfig.rsi_handle, 0, 0, 3, m_symbolConfig.rsi_buffer) <= 0) return false;
        
        int obv_bars = MathMax(m_symbolConfig.obv_ema_slow + 10, 30);
        if(CopyBuffer(m_symbolConfig.obv_handle, 0, 0, obv_bars, m_symbolConfig.obv_buffer) <= 0) return false;
        
        if(CopyBuffer(m_symbolConfig.ema_override_handle, 0, 0, 3, m_symbolConfig.ema_override_buffer) <= 0) return false;
        
        if(CopyBuffer(m_symbolConfig.trend_ema20_handle, 0, 0, 3, m_symbolConfig.trend_ema20_buffer) <= 0 ||
           CopyBuffer(m_symbolConfig.trend_ema50_handle, 0, 0, 3, m_symbolConfig.trend_ema50_buffer) <= 0) return false;
           
        return true;
    }
    
    void CheckOrphanPositions()
    {
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetTicket(i) > 0 &&
               PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                string s = PositionGetString(POSITION_SYMBOL);
                if(s != m_symbolConfig.symbol) continue;
                bool found_in_tracking = false;
                for(int j = 0; j < ArraySize(m_trailingPositions); j++)
                {
                    if(m_trailingPositions[j].ticket == ticket)
                    {
                        found_in_tracking = true;
                        break;
                    }
                }
                if(!found_in_tracking && !m_symbolConfig.use_fixed_tp)
                {
                    int sz = ArraySize(m_trailingPositions);
                    ArrayResize(m_trailingPositions, sz + 1);
                    m_trailingPositions[sz].ticket = ticket;
                    m_trailingPositions[sz].symbol = s;
                    m_trailingPositions[sz].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                    m_trailingPositions[sz].highest_profit = 0;
                    m_trailingPositions[sz].trailing_active = false;
                    m_trailingPositions[sz].breakeven_triggered = false;
                    m_trailingPositions[sz].breakeven_first_activation_done = false;
                    m_trailingPositions[sz].breakeven_price_went_below_trigger = false;
                    m_trailingPositions[sz].phase_one_completed = false;
                    BotCore_Log("POSIZIONE ORFANA RECUPERATA: Ticket: " + IntegerToString(ticket), m_magicNumber);
                }
            }
        }
    }
    
    void CheckTimeManagement()
    {
        MqlDateTime ct;
        TimeToStruct(TimeCurrent(), ct);
        string dop, dcl;
        GetDaySchedule(ct.day_of_week, dop, dcl, m_symbolConfig);
        
        if(IsMarketClosed(dop, dcl))
        {
            static bool wcd = false;
            static int lwcd = -1;
            if(!wcd || ct.day != lwcd)
            {
                int op = CountPositions(m_symbolConfig.symbol, m_magicNumber);
                if(op > 0) CloseAllPositions(m_symbolConfig.symbol, m_trade, m_magicNumber, m_trailingPositions, m_pendingSignals);
                wcd = true;
                lwcd = ct.day;
            }
            return;
        }
        
        if(IsContinuousTrading(dop, dcl)) return;
        
        int oh, om, ch, cm;
        if(!ParseTime(dop, oh, om) || !ParseTime(dcl, ch, cm)) return;
        
        if(ct.hour == ch && ct.min == cm)
        {
            static int lcd = -1;
            if(ct.day != lcd)
            {
                CloseAllPositions(m_symbolConfig.symbol, m_trade, m_magicNumber, m_trailingPositions, m_pendingSignals);
                lcd = ct.day;
            }
        }
    }
    
    void CheckSignals()
    {
        datetime closed_bar_time = iTime(m_symbolConfig.symbol, m_symbolConfig.timeframe, 1);
        double cp = SymbolInfoDouble(m_symbolConfig.symbol, SYMBOL_ASK);
        bool lc = (m_symbolConfig.stoch_main[2] < m_symbolConfig.stoch_signal[2] &&
                  m_symbolConfig.stoch_main[1] > m_symbolConfig.stoch_signal[1]);
        bool sc = (m_symbolConfig.stoch_main[2] > m_symbolConfig.stoch_signal[2] &&
                  m_symbolConfig.stoch_main[1] < m_symbolConfig.stoch_signal[1]);
        
        if(lc)
        {
            if(IsPositionOpenedForCross(m_crossTrackers, m_symbolConfig.symbol, closed_bar_time, true))
            {
                BotCore_Log(m_symbolConfig.symbol + " - Cross LONG già processato", m_magicNumber);
                return;
            }
            if(!m_stochFilterPost)
            {
                bool ok = true;
                if(m_symbolConfig.filter_stoch_overbought &&
                   (m_symbolConfig.stoch_main[2] > m_symbolConfig.stoch_overbought_level ||
                    m_symbolConfig.stoch_main[1] > m_symbolConfig.stoch_overbought_level))
                {
                    BotCore_Log(m_symbolConfig.symbol + " - ? STOCH OVERBOUGHT: Cross LONG BRUCIATO", m_magicNumber);
                    ok = false;
                }
                if(!ok)
                {
                    MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, closed_bar_time, true, m_magicNumber);
                    return;
                }
            }
            BotCore_Log(m_symbolConfig.symbol + " - ? Cross LONG valido, processo segnale", m_magicNumber);
            ProcessStochSignal(true, cp, closed_bar_time);
        }
        
        if(sc)
        {
            if(IsPositionOpenedForCross(m_crossTrackers, m_symbolConfig.symbol, closed_bar_time, false))
            {
                BotCore_Log(m_symbolConfig.symbol + " - Cross SHORT già processato", m_magicNumber);
                return;
            }
            if(!m_stochFilterPost)
            {
                bool ok = true;
                if(m_symbolConfig.filter_stoch_oversold &&
                   (m_symbolConfig.stoch_main[2] < m_symbolConfig.stoch_oversold_level ||
                    m_symbolConfig.stoch_main[1] < m_symbolConfig.stoch_oversold_level))
                {
                    BotCore_Log(m_symbolConfig.symbol + " - ? STOCH OVERSOLD: Cross SHORT BRUCIATO", m_magicNumber);
                    ok = false;
                }
                if(!ok)
                {
                    MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, closed_bar_time, false, m_magicNumber);
                    return;
                }
            }
            BotCore_Log(m_symbolConfig.symbol + " - ? Cross SHORT valido, processo segnale", m_magicNumber);
            ProcessStochSignal(false, cp, closed_bar_time);
        }
    }
    
    void ProcessStochSignal(bool il, double cp, datetime cross_time)
    {
        bool em = m_symbolConfig.ignore_ema || CheckEMACondition(m_symbolConfig, il, cp, 0);
        bool mm = m_symbolConfig.ignore_macd || CheckMACDCondition(m_symbolConfig, il, 0);
        
        if(em && mm)
        {
            OpenPosition(il ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, cp, cross_time);
            return;
        }
        
        if(!em && !m_symbolConfig.ignore_ema && m_symbolConfig.ema_lookback > 0)
            em = CheckEMAConditionLookback(m_symbolConfig, il, cp);
            
        if(!mm && !m_symbolConfig.ignore_macd && m_symbolConfig.macd_lookback > 0)
            mm = CheckMACDConditionLookback(m_symbolConfig, il);
            
        if(em && mm)
        {
            OpenPosition(il ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, cp, cross_time);
            return;
        }
        
        bool needs_lookahead = false;
        if(!em && !m_symbolConfig.ignore_ema && m_symbolConfig.ema_lookahead > 0)
            needs_lookahead = true;
        else if(!em && !m_symbolConfig.ignore_ema)
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? EMA non soddisfatto e no lookahead ? BRUCIO", m_magicNumber);
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, il, m_magicNumber);
            return;
        }
        
        if(!mm && !m_symbolConfig.ignore_macd && m_symbolConfig.macd_lookahead > 0)
            needs_lookahead = true;
        else if(!mm && !m_symbolConfig.ignore_macd)
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? MACD non soddisfatto e no lookahead ? BRUCIO", m_magicNumber);
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, il, m_magicNumber);
            return;
        }
        
        if(needs_lookahead)
            AddPendingSignal(il, cp, em, mm, cross_time);
    }
    
    void AddPendingSignal(bool il, double sp, bool em, bool mm, datetime cross_time)
    {
        int sz = ArraySize(m_pendingSignals);
        ArrayResize(m_pendingSignals, sz + 1);
        m_pendingSignals[sz].symbol = m_symbolConfig.symbol;
        m_pendingSignals[sz].signal_time = TimeCurrent();
        m_pendingSignals[sz].cross_bar_time = cross_time;
        m_pendingSignals[sz].is_long = il;
        m_pendingSignals[sz].signal_price = sp;
        m_pendingSignals[sz].ema_condition_met = em;
        m_pendingSignals[sz].macd_condition_met = mm;
        m_pendingSignals[sz].bars_waiting = 0;
        BotCore_Log(m_symbolConfig.symbol + " - ? Segnale in attesa (lookahead)", m_magicNumber);
    }
    
    void CheckPendingSignals()
    {
        double cp = SymbolInfoDouble(m_symbolConfig.symbol, SYMBOL_ASK);
        for(int i = ArraySize(m_pendingSignals) - 1; i >= 0; i--)
        {
            if(m_pendingSignals[i].symbol != m_symbolConfig.symbol) continue;
            
            m_pendingSignals[i].bars_waiting++;
            
            bool eo = m_pendingSignals[i].ema_condition_met;
            bool mo = m_pendingSignals[i].macd_condition_met;
            
            if(!eo && !m_symbolConfig.ignore_ema && m_symbolConfig.ema_lookahead > 0 &&
               m_pendingSignals[i].bars_waiting <= m_symbolConfig.ema_lookahead)
            {
                eo = CheckEMACondition(m_symbolConfig, m_pendingSignals[i].is_long, cp, 0);
                if(eo) m_pendingSignals[i].ema_condition_met = true;
            }
            
            if(!mo && !m_symbolConfig.ignore_macd && m_symbolConfig.macd_lookahead > 0 &&
               m_pendingSignals[i].bars_waiting <= m_symbolConfig.macd_lookahead)
            {
                mo = CheckMACDCondition(m_symbolConfig, m_pendingSignals[i].is_long, 0);
                if(mo) m_pendingSignals[i].macd_condition_met = true;
            }
            
            if(eo && mo)
            {
                OpenPosition(m_pendingSignals[i].is_long ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                            cp, m_pendingSignals[i].cross_bar_time);
                RemovePendingSignal(i);
                continue;
            }
            
            bool ema_expired = (!eo && !m_symbolConfig.ignore_ema && m_symbolConfig.ema_lookahead > 0 &&
                               m_pendingSignals[i].bars_waiting > m_symbolConfig.ema_lookahead);
            bool macd_expired = (!mo && !m_symbolConfig.ignore_macd && m_symbolConfig.macd_lookahead > 0 &&
                                m_pendingSignals[i].bars_waiting > m_symbolConfig.macd_lookahead);
                                
            if(ema_expired || macd_expired)
            {
                BotCore_Log(m_symbolConfig.symbol + " - ? Lookahead scaduto ? BRUCIO cross", m_magicNumber);
                MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, m_pendingSignals[i].cross_bar_time, m_pendingSignals[i].is_long, m_magicNumber);
                RemovePendingSignal(i);
            }
        }
    }
    
    void RemovePendingSignal(int idx)
    {
        int sz = ArraySize(m_pendingSignals);
        if(idx < 0 || idx >= sz) return;
        for(int i = idx; i < sz - 1; i++) 
            m_pendingSignals[i] = m_pendingSignals[i + 1];
        ArrayResize(m_pendingSignals, sz - 1);
    }
    
    void OpenPosition(ENUM_ORDER_TYPE ot, double p, datetime cross_time)
    {
        datetime current_bar = iTime(m_symbolConfig.symbol, m_symbolConfig.timeframe, 0);
        bool is_long = (ot == ORDER_TYPE_BUY);
        
        static datetime last_trade_bar_time = 0;
        if(last_trade_bar_time == current_bar)
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? Già aperto un trade in questa candela", m_magicNumber);
            return;
        }
        
        if(IsPositionOpenedForCross(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long))
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? Cross già aperto o bruciato", m_magicNumber);
            return;
        }
        
        int current_positions = CountPositions(m_symbolConfig.symbol, m_magicNumber);
        if(current_positions >= m_symbolConfig.max_positions)
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? Max positions raggiunto", m_magicNumber);
            return;
        }
        
        if(!CheckStochFilter(m_symbolConfig, is_long, m_stochFilterPost))
        {
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, m_magicNumber);
            return;
        }
        
        if(m_symbolConfig.adx_buffer[0] <= m_symbolConfig.adx_threshold)
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? ADX troppo basso (" + DoubleToString(m_symbolConfig.adx_buffer[0], 2) + ")", m_magicNumber);
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, m_magicNumber);
            return;
        }
        
        if(!CheckRSIFilter(m_symbolConfig, is_long))
        {
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, m_magicNumber);
            return;
        }
        
        if(!CheckOBVFilter(m_symbolConfig, is_long))
        {
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, m_magicNumber);
            return;
        }
        
        if(!CheckEMASlopeFilter(m_symbolConfig))
        {
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, m_magicNumber);
            return;
        }
        
        if(!CheckTrendFilter(m_symbolConfig, is_long))
        {
            MarkCrossAsBurned(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, m_magicNumber);
            return;
        }
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double tl = CalculateLotSize(equity, m_symbolConfig, m_useDynamicLotManagement);
        if(tl <= 0)
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? Lot size nullo", m_magicNumber);
            return;
        }
        
        double sl = 0, tp = 0;
        double sop = m_symbolConfig.sl_offset_percent;
        double scp = m_symbolConfig.sl_cap_percent;
        
        if(m_symbolConfig.use_fixed_sl)
        {
            if(ot == ORDER_TYPE_BUY) sl = p - (p * m_symbolConfig.fixed_sl_percent / 100.0);
            else sl = p + (p * m_symbolConfig.fixed_sl_percent / 100.0);
        }
        else if(m_symbolConfig.use_advanced_sl)
        {
            sl = CalculateAdvancedStopLoss(ot, p, m_symbolConfig);
        }
        else
        {
            double e50 = m_symbolConfig.ema50_buffer[0];
            double so = e50 * (sop / 100.0);
            if(ot == ORDER_TYPE_BUY) { sl = e50 - so; if(m_symbolConfig.use_sl_cap) { double cap = p - (p * scp / 100.0); if(sl < cap) sl = cap; } }
            else { sl = e50 + so; if(m_symbolConfig.use_sl_cap) { double cap = p + (p * scp / 100.0); if(sl > cap) sl = cap; } }
        }
        
        if(m_symbolConfig.use_ema_spread_override)
        {
            double ema20 = m_symbolConfig.ema20_buffer[0];
            double ema50 = m_symbolConfig.ema50_buffer[0];
            double spread_percent = (ema50 != 0) ? (MathAbs(ema20 - ema50) / ema50) * 100.0 : 0;
            if(spread_percent > m_symbolConfig.ema_spread_threshold)
            {
                sl = m_symbolConfig.ema_override_buffer[0];
                BotCore_Log(m_symbolConfig.symbol + " - ? EMA SPREAD OVERRIDE attivato (" +
                    DoubleToString(spread_percent, 2) + "%). SL = EMA(" +
                    IntegerToString(m_symbolConfig.ema_override_period) + ") = " +
                    DoubleToString(sl, 5), m_magicNumber);
            }
        }
        
        if(m_symbolConfig.use_fixed_tp)
        {
            if(ot == ORDER_TYPE_BUY) tp = p + (p * m_symbolConfig.fixed_tp_percent / 100.0);
            else tp = p - (p * m_symbolConfig.fixed_tp_percent / 100.0);
        }
        
        sl = NormalizeDouble(sl, (int)SymbolInfoInteger(m_symbolConfig.symbol, SYMBOL_DIGITS));
        if(tp > 0) tp = NormalizeDouble(tp, (int)SymbolInfoInteger(m_symbolConfig.symbol, SYMBOL_DIGITS));
        
        bool r = (ot == ORDER_TYPE_BUY) ?
                Buy(tl, m_symbolConfig.symbol, 0, sl, tp, "EA v3.19 TRAILING") :
                Sell(tl, m_symbolConfig.symbol, 0, sl, tp, "EA v3.19 TRAILING");
                
        if(r)
        {
            ulong t = ResultOrder();
            if(t > 0)
            {
                last_trade_bar_time = current_bar;
                MarkCrossAsOpened(m_crossTrackers, m_symbolConfig.symbol, cross_time, is_long, t, m_magicNumber);
                BotCore_Log(m_symbolConfig.symbol + " - ? POSIZIONE APERTA: " + (is_long ? "LONG" : "SHORT") +
                    " Lotti=" + DoubleToString(tl, 2) + " SL=" + DoubleToString(sl, 5) + " TP=" + DoubleToString(tp, 5), m_magicNumber);
                
                if(t > 0 && !m_symbolConfig.use_fixed_tp)
                {
                    int sz = ArraySize(m_trailingPositions);
                    ArrayResize(m_trailingPositions, sz + 1);
                    m_trailingPositions[sz].ticket = t;
                    m_trailingPositions[sz].symbol = m_symbolConfig.symbol;
                    m_trailingPositions[sz].open_price = p;
                    m_trailingPositions[sz].highest_profit = 0;
                    m_trailingPositions[sz].trailing_active = false;
                    m_trailingPositions[sz].breakeven_triggered = false;
                    m_trailingPositions[sz].breakeven_first_activation_done = false;
                    m_trailingPositions[sz].breakeven_price_went_below_trigger = false;
                    m_trailingPositions[sz].phase_one_completed = false;

                    // Calcola il valore adaptivo del TrailingStartPercent per questo trade
                    if(m_enableAdaptiveTP)
                    {
                        double ema20_val = m_symbolConfig.ema20_buffer[0];
                        double ema50_val = m_symbolConfig.ema50_buffer[0];
                        double adaptive_percent = m_adaptiveTP.CalculateTrailingStartPercent(p, ema20_val, ema50_val);
                        m_trailingPositions[sz].adaptive_trailing_start_percent = adaptive_percent;

                        BotCore_Log(m_symbolConfig.symbol + " - AdaptiveTP: Calcolato trailing start = " +
                                DoubleToString(adaptive_percent, 4) + "%", m_magicNumber);
                    }
                    else
                    {
                        // Usa il valore fisso se il modulo è disattivato
                        m_trailingPositions[sz].adaptive_trailing_start_percent = m_symbolConfig.trailing_start_percent;
                    }
                }
            }
        }
        else
        {
            BotCore_Log(m_symbolConfig.symbol + " - ? Errore apertura posizione: " + IntegerToString(GetLastError()), m_magicNumber);
        }
    }
    
    void ManagePositions()
    {
        // OTTIMIZZAZIONE: Usa cache per valori SymbolInfo statici
        if(!m_symbol_info_cached)
        {
            m_cached_point = SymbolInfoDouble(m_symbolConfig.symbol, SYMBOL_POINT);
            m_cached_digits = (int)SymbolInfoInteger(m_symbolConfig.symbol, SYMBOL_DIGITS);
            m_cached_min_stop_distance = SymbolInfoInteger(m_symbolConfig.symbol, SYMBOL_TRADE_STOPS_LEVEL) * m_cached_point;
            m_symbol_info_cached = true;
        }

        double point = m_cached_point;
        int digits = m_cached_digits;
        double min_stop_distance = m_cached_min_stop_distance;

        for(int i = ArraySize(m_trailingPositions) - 1; i >= 0; i--)
        {
            if(m_trailingPositions[i].symbol != m_symbolConfig.symbol) continue;
            
            if(!PositionSelectByTicket(m_trailingPositions[i].ticket)) 
            {
                // Rimuovi trailing position
                int sz = ArraySize(m_trailingPositions);
                for(int j = i; j < sz - 1; j++)
                    m_trailingPositions[j] = m_trailingPositions[j + 1];
                ArrayResize(m_trailingPositions, sz - 1);
                continue;
            }
            
            double op = m_trailingPositions[i].open_price;
            double cp = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                        SymbolInfoDouble(m_symbolConfig.symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_symbolConfig.symbol, SYMBOL_ASK);
                        
            double pp = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                        ((cp - op) / op) * 100.0 : ((op - cp) / op) * 100.0;
                        
            if(pp > m_trailingPositions[i].highest_profit)
            {
                m_trailingPositions[i].highest_profit = pp;
            }
            
            if(!m_trailingPositions[i].phase_one_completed && pp >= m_trailingPositions[i].adaptive_trailing_start_percent)
            {
                bool is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                double target_sl_percent = m_trailingPositions[i].adaptive_trailing_start_percent - m_symbolConfig.trailing_start_distance;
                double new_sl_price;
                
                if(is_buy)
                {
                    new_sl_price = op * (1.0 + target_sl_percent / 100.0);
                    double min_valid_sl = cp - (min_stop_distance * 1.1);
                    if(new_sl_price > min_valid_sl)
                    {
                        new_sl_price = min_valid_sl;
                    }
                }
                else
                {
                    new_sl_price = op * (1.0 - target_sl_percent / 100.0);
                    double max_valid_sl = cp + (min_stop_distance * 1.1);
                    if(new_sl_price < max_valid_sl)
                    {
                        new_sl_price = max_valid_sl;
                    }
                }
                
                new_sl_price = NormalizeDouble(new_sl_price, digits);
                double current_sl = PositionGetDouble(POSITION_SL);
                double current_sl_norm = NormalizeDouble(current_sl, digits);
                double tolerance = point * 5.0;
                bool sl_is_different = MathAbs(new_sl_price - current_sl_norm) > tolerance;
                
                if(sl_is_different)
                {
                    if(PositionModify(m_trailingPositions[i].ticket, new_sl_price, PositionGetDouble(POSITION_TP)))
                    {
                        m_trailingPositions[i].breakeven_first_activation_done = true;
                        m_trailingPositions[i].phase_one_completed = true;
                    }
                }
                else
                {
                    m_trailingPositions[i].breakeven_first_activation_done = true;
                    m_trailingPositions[i].phase_one_completed = true;
                }
            }
            
            else if(m_trailingPositions[i].phase_one_completed && !m_trailingPositions[i].trailing_active &&
                    pp >= (m_trailingPositions[i].adaptive_trailing_start_percent + m_symbolConfig.trailing_max_percent))
            {
                m_trailingPositions[i].trailing_active = true;
            }
            
            if(m_trailingPositions[i].trailing_active)
            {
                double dd = m_trailingPositions[i].highest_profit - pp;
                double tolerance = 0.01;
                if(dd >= (m_symbolConfig.trailing_max_percent - tolerance))
                {
                    if(PositionClose(m_trailingPositions[i].ticket)) 
                    {
                        // Rimuovi trailing position
                        int sz = ArraySize(m_trailingPositions);
                        for(int j = i; j < sz - 1; j++)
                            m_trailingPositions[j] = m_trailingPositions[j + 1];
                        ArrayResize(m_trailingPositions, sz - 1);
                    }
                }
            }
        }
    }
    
    void GetDaySchedule(int dow, string &ot, string &ct, const SymbolConfig &config)
    {
        switch(dow)
        {
            case 1: ot = config.monday_open; ct = config.monday_close; break;
            case 2: ot = config.tuesday_open; ct = config.tuesday_close; break;
            case 3: ot = config.wednesday_open; ct = config.wednesday_close; break;
            case 4: ot = config.thursday_open; ct = config.thursday_close; break;
            case 5: ot = config.friday_open; ct = config.friday_close; break;
            case 6: ot = config.saturday_open; ct = config.saturday_close; break;
            case 0: ot = config.sunday_open; ct = config.sunday_close; break;
            default: ot = "00:00"; ct = "24:00"; break;
        }
    }
    
    bool IsMarketClosed(string ot, string ct) 
    { 
        return (ot == "00:00" && ct == "00:00"); 
    }
    
    bool IsContinuousTrading(string ot, string ct) 
    { 
        return (ot == "00:00" && ct == "24:00"); 
    }
    
    bool ParseTime(string ts, int &h, int &m)
    {
        string p[];
        if(StringSplit(ts, ':', p) != 2) return false;
        h = (int)StringToInteger(p[0]);
        m = (int)StringToInteger(p[1]);
        if(h == 24 && m == 0) { h = 23; m = 59; }
        return (h >= 0 && h <= 23 && m >= 0 && m <= 59);
    }
    
    bool IsTradingAllowed(const SymbolConfig &config)
    {
        if(!config.use_time_mgmt) return true;
        
        MqlDateTime ct;
        TimeToStruct(TimeCurrent(), ct);
        string dop, dcl;
        GetDaySchedule(ct.day_of_week, dop, dcl, config);
        
        if(IsMarketClosed(dop, dcl)) return false;
        
        if(IsContinuousTrading(dop, dcl)) return true;
        
        int oh, om, ch, cm;
        if(!ParseTime(dop, oh, om) || !ParseTime(dcl, ch, cm)) return true;
        
        int cm_total = ct.hour * 60 + ct.min;
        int om_total = oh * 60 + om;
        int clm_total = ch * 60 + cm;
        
        if(om_total < clm_total)
        {
            int bs = clm_total - config.block_minutes_before;
            if(bs < om_total) bs = om_total;
            if(cm_total >= bs && cm_total < clm_total) return false;
            return (cm_total >= om_total && cm_total < clm_total);
        }
        else if(clm_total < om_total)
        {
            int bs = clm_total - config.block_minutes_before;
            if(bs < 0) bs = 0;
            if(cm_total >= bs && cm_total < clm_total) return false;
            if(cm_total < clm_total) return true;
            if(cm_total >= om_total) return true;
            return false;
        }
        return false;
    }
    
    void CleanOldCrossTrackers(SimpleCrossTracker &trackers[])
    {
        datetime current = TimeCurrent();
        for(int i = ArraySize(trackers) - 1; i >= 0; i--)
        {
            if(current - trackers[i].bar_time > 86400)
            {
                int sz = ArraySize(trackers);
                for(int j = i; j < sz - 1; j++)
                    trackers[j] = trackers[j + 1];
                ArrayResize(trackers, sz - 1);
            }
        }
    }
    
    bool IsPositionOpenedForCross(const SimpleCrossTracker &trackers[], string sym, datetime bt, bool il)
    {
        for(int i = 0; i < ArraySize(trackers); i++)
        {
            if(trackers[i].symbol == sym &&
               trackers[i].bar_time == bt &&
               trackers[i].is_long == il)
               return true;
        }
        return false;
    }
    
    void MarkCrossAsOpened(SimpleCrossTracker &trackers[], string sym, datetime bt, bool il, ulong ticket, int magic_number)
    {
        for(int i = 0; i < ArraySize(trackers); i++)
        {
            if(trackers[i].symbol == sym &&
               trackers[i].bar_time == bt &&
               trackers[i].is_long == il)
            {
                trackers[i].position_opened = true;
                trackers[i].ticket = ticket;
                BotCore_Log("? Cross APERTO: " + sym + " " + (il ? "LONG" : "SHORT") + " ticket=" + IntegerToString(ticket), magic_number);
                return;
            }
        }
        int sz = ArraySize(trackers);
        ArrayResize(trackers, sz + 1);
        trackers[sz].symbol = sym;
        trackers[sz].bar_time = bt;
        trackers[sz].is_long = il;
        trackers[sz].position_opened = true;
        trackers[sz].ticket = ticket;
        BotCore_Log("? Nuovo tracker creato per cross APERTO: " + sym + " " + (il ? "LONG" : "SHORT") + " ticket=" + IntegerToString(ticket), magic_number);
    }
    
    void MarkCrossAsBurned(SimpleCrossTracker &trackers[], string sym, datetime bt, bool il, int magic_number)
    {
        int sz = ArraySize(trackers);
        ArrayResize(trackers, sz + 1);
        trackers[sz].symbol = sym;
        trackers[sz].bar_time = bt;
        trackers[sz].is_long = il;
        trackers[sz].position_opened = false;
        trackers[sz].ticket = 0;
        BotCore_Log("?? Cross BRUCIATO: " + sym + " " + (il ? "LONG" : "SHORT"), magic_number);
    }
    
    int CountPositions(string sym, int magic_number)
    {
        int c = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
            if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == magic_number && PositionGetString(POSITION_SYMBOL) == sym) c++;
        return c;
    }
    
    void CloseAllPositions(string sym, CTrade &trade, int magic_number, TrailingData &trailing_positions[], PendingSignal &pending_signals[])
    {
        int cc = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == magic_number &&
               PositionGetString(POSITION_SYMBOL) == sym)
            {
                ulong t = PositionGetInteger(POSITION_TICKET);
                if(trade.PositionClose(t))
                {
                    cc++;
                    for(int j = ArraySize(trailing_positions) - 1; j >= 0; j--)
                       if(trailing_positions[j].ticket == t) 
                       {
                           // Rimuovi trailing position
                           int sz = ArraySize(trailing_positions);
                           for(int k = j; k < sz - 1; k++)
                              trailing_positions[k] = trailing_positions[k + 1];
                           ArrayResize(trailing_positions, sz - 1);
                           break;
                       }
                }
            }
        }
        
        if(cc > 0) BotCore_Log(sym + " - Chiuse " + IntegerToString(cc) + " posizioni", magic_number);
        
        for(int i = ArraySize(pending_signals) - 1; i >= 0; i--) {
            if(pending_signals[i].symbol == sym) {
                int sz = ArraySize(pending_signals);
                for(int j = i; j < sz - 1; j++)
                    pending_signals[j] = pending_signals[j + 1];
                ArrayResize(pending_signals, sz - 1);
            }
        }
    }
    
    void BotCore_Log(string msg, int magic_number)
    {
        // OTTIMIZZATO: Disabilita log in backtesting per migliorare performance
        if(!MQLInfoInteger(MQL_TESTER))
        {
            Print("[BotCore-" + IntegerToString(magic_number) + "] " + msg);
        }
    }
    
    double CalculateEMASlopeAbs(const double &ema50_buffer[], int ema_slope_period)
    {
        int N = MathMax(1, ema_slope_period);
        int required_bars = N + 1;
        if(ArraySize(ema50_buffer) < required_bars) return 0.0;
        double sum_deriv = 0.0;
        int count = 0;
        for(int i = 0; i < N; i++)
        {
            double ema_t   = ema50_buffer[i];
            double ema_t1  = ema50_buffer[i + 1];
            if(ema_t1 == 0.0) continue;
            double deriv = (ema_t - ema_t1) / ema_t1;
            sum_deriv += deriv;
            count++;
        }
        if(count == 0) return 0.0;
        double avg_deriv = sum_deriv / count;
        return MathAbs(avg_deriv * 10000.0);
    }
    
    bool CheckEMASlopeFilter(const SymbolConfig &config)
    {
        if(!config.use_ema_slope_filter) return true;
        double abs_slope_bp = CalculateEMASlopeAbs(config.ema50_buffer, config.ema_slope_period);
        double threshold = config.ema_slope_threshold;
        if(abs_slope_bp < threshold)
        {
            BotCore_Log(config.symbol + " - ? EMA50 TROPPO PIATTA: pendenza=" + 
                DoubleToString(abs_slope_bp, 2) + " bp < soglia=" + 
                DoubleToString(threshold, 2) + " bp ? nessun trade", m_magicNumber);
            return false;
        }
        return true;
    }
    
    bool CheckTrendFilter(const SymbolConfig &config, bool is_long)
    {
        if(!config.use_trend_filter) return true;
        double ema20_htf = config.trend_ema20_buffer[0];
        double ema50_htf = config.trend_ema50_buffer[0];
        if(ema20_htf == 0 || ema50_htf == 0) return true;
        if(is_long)
        {
            if(ema50_htf > ema20_htf)
            {
                BotCore_Log(config.symbol + " - ? TREND FILTER: LONG bloccato (EMA50 > EMA20 su HTF)", m_magicNumber);
                return false;
            }
        }
        else
        {
            if(ema20_htf > ema50_htf)
            {
                BotCore_Log(config.symbol + " - ? TREND FILTER: SHORT bloccato (EMA20 > EMA50 su HTF)", m_magicNumber);
                return false;
            }
        }
        return true;
    }
    
    bool CheckStochFilter(const SymbolConfig &config, bool is_long, bool stoch_filter_post)
    {
        if(!stoch_filter_post) return true;
        double main_2 = config.stoch_main[2];
        double main_1 = config.stoch_main[1];
        if(is_long)
        {
            if(config.filter_stoch_overbought && 
               (main_2 > config.stoch_overbought_level || main_1 > config.stoch_overbought_level))
            {
                BotCore_Log(config.symbol + " - ? STOCH POST: BUY rifiutato (Overbought)", m_magicNumber);
                return false;
            }
        }
        else
        {
            if(config.filter_stoch_oversold && 
               (main_2 < config.stoch_oversold_level || main_1 < config.stoch_oversold_level))
            {
                BotCore_Log(config.symbol + " - ? STOCH POST: SELL rifiutato (Oversold)", m_magicNumber);
                return false;
            }
        }
        return true;
    }
};