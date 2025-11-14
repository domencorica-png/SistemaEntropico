//+------------------------------------------------------------------+
//|                      SistemaCompleto.mq5                         |
//|                        Copyright 2025, Your Name                 |
//|                        Sistema Completo con Filtro Entropico    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Sistema di trading completo con filtro entropico per mercati laterali"
#property strict

// Include i file necessari
#include "TradingWrapper.mqh"
#include "AdaptiveTakeProfit.mqh"  // Include per il modulo Adaptive Take Profit

// Parametri del bot originale (visibili nella finestra di input)
input group "=== CONFIGURAZIONE GLOBALE ==="
input bool     UseDynamicLotManagement = true;
input int      MagicNumber          = 123456;
input int      BacktestEndBufferDays = 30;
input bool     Stoch_Filter_Post = false;
input group "=== CONFIGURAZIONE SIMBOLO ==="
input string   Symbol_Name         = "EURUSD";
input bool     Symbol_Active       = true;
input ENUM_TIMEFRAMES Symbol_TimeFrame = PERIOD_M10;
input group "=== SIMBOLO - INDICATORI ==="
input int      Symbol_EMA20_Period = 15;
input int      Symbol_EMA50_Period = 40;
input int      Symbol_Stoch_K      = 12;
input int      Symbol_Stoch_D      = 2;
input int      Symbol_Stoch_Slowing = 2;
input int      Symbol_MACD_Fast    = 10;
input int      Symbol_MACD_Slow    = 22;
input int      Symbol_MACD_Signal  = 7;
input int      Symbol_ADX_Period   = 14;
input double   Symbol_ADX_Threshold = 20.0;
input group "=== SIMBOLO - FILTRO EMA50 SLOPE (LATERALITÀ) ==="
input bool     Symbol_UseEMASlopeFilter = false;
input double   Symbol_EMASlopeThreshold = 5.0;
input int      Symbol_EMASlopePeriod = 2;
input group "=== SIMBOLO - FILTRO TREND TIMEFRAME SUPERIORE ==="
input bool     Symbol_UseTrendFilter = false;
input ENUM_TIMEFRAMES Symbol_TrendTimeframe = PERIOD_M30;
input group "=== SIMBOLO - TRADING ==="
input int      Symbol_MaxPositions = 1;
input int      Symbol_MACD_LookbackPeriods = 0;
input int      Symbol_EMA_LookbackPeriods = 0;
input int      Symbol_MACD_LookaheadPeriods = 0;
input int      Symbol_EMA_LookaheadPeriods = 0;
input bool     Symbol_IgnoreMACDCondition = false;
input bool     Symbol_IgnoreEMACondition = false;
input group "=== SIMBOLO - FILTRI STOCASTICO ==="
input bool     Symbol_FilterStochOverBought = false;
input double   Symbol_StochOverBoughtLevel = 80.0;
input bool     Symbol_FilterStochOverSold = false;
input double   Symbol_StochOverSoldLevel = 20.0;
input group "=== SIMBOLO - FILTRO RSI ==="
input bool     Symbol_UseRSIFilter = false;
input int      Symbol_RSI_Period = 14;
input double   Symbol_RSI_OverboughtLevel = 70.0;
input double   Symbol_RSI_OversoldLevel = 30.0;
input group "=== SIMBOLO - FILTRO OBV ==="
input bool     Symbol_UseOBVFilter = false;
input int      Symbol_OBV_EMA_Fast = 20;
input int      Symbol_OBV_EMA_Slow = 50;
input group "=== SIMBOLO - STOP LOSS ==="
input bool     Symbol_UseAdvancedSL = false;
input double   Symbol_AdvancedSL_Exponent = 1.0;
input bool     Symbol_UseAdvancedSL_Threshold = false;
input double   Symbol_AdvancedSL_ThresholdValue = 0.5;
input bool     Symbol_UseFixedSL   = false;
input double   Symbol_FixedSL_Percent = 1.0;
input double   Symbol_SL_OffsetPercent = 0.0;
input bool     Symbol_UseSL_Cap    = false;
input double   Symbol_SL_CapPercent = 2.0;
input bool     Symbol_UseEMASpreadOverride = false;
input double   Symbol_EMASpreadThreshold = 0.50;
input int      Symbol_EMA_Override_Period = 20;
input group "=== SIMBOLO - TAKE PROFIT ==="
input bool     Symbol_UseFixedTP   = true;
input double   Symbol_FixedTP_Percent = 2.0;
input double   Symbol_TrailingStartPercent = 1.0;
input double   Symbol_TrailingStartDistance = 0.01;
input double   Symbol_TrailingMaxPercent = 0.01;
input group "=== SIMBOLO - BREAKEVEN STOP LOSS ==="
input bool     Symbol_UseBreakevenLogic = false;
input double   Symbol_BreakevenTriggerPercent = 50.0;
input double   Symbol_BreakevenSLPercent = 30.0;
input bool     Symbol_UseBreakevenStep2 = false;
input group "=== SIMBOLO - GESTIONE RISCHIO ==="
input double   Symbol_LotSize      = 0.01;
input group "=== SIMBOLO - GESTIONE ORARI ==="
input bool     Symbol_UseTimeManagement = true;
input int      Symbol_BlockMinutesBefore = 20;
input string   Symbol_MondayOpen    = "00:00";
input string   Symbol_MondayClose   = "24:00";
input string   Symbol_TuesdayOpen   = "00:00";
input string   Symbol_TuesdayClose  = "24:00";
input string   Symbol_WednesdayOpen = "00:00";
input string   Symbol_WednesdayClose = "24:00";
input string   Symbol_ThursdayOpen  = "00:00";
input string   Symbol_ThursdayClose = "24:00";
input string   Symbol_FridayOpen    = "00:00";
input string   Symbol_FridayClose   = "18:50";
input string   Symbol_SaturdayOpen  = "00:00";
input string   Symbol_SaturdayClose = "00:00";
input string   Symbol_SundayOpen    = "00:00";
input string   Symbol_SundayClose   = "00:00";

// Parametri del filtro entropico
input group "=== FILTRO ENTROPICO ==="
input bool     EnableEntropyFilter = true;           // Attiva Filtro Entropico
input int      Entropy_Period_Breve = 14;            // Periodo Entropia Breve
input int      Entropy_Period_Medio = 42;            // Periodo Entropia Medio  
input int      Entropy_Period_Lungo = 100;           // Periodo Entropia Lungo
input int      Entropy_Bins = 10;                    // Numero Bins Discretizzazione
input double   Entropy_Sideways_Threshold = 0.85;    // Soglia Mercato Laterale
input double   Entropy_Chaotic_Threshold = 0.95;     // Soglia Mercato Caotico
input double   Entropy_Volatility_Min = 0.5;         // Soglia Volatilità Minima
input double   Entropy_Volatility_Max = 3.0;         // Soglia Volatilità Massima

//+------------------------------------------------------------------+
//| Parametri Adaptive Take Profit                                   |
//| Formula: TP = (ATR*100)/Prezzo * [a*(EMA_ratio)^b + c]          |
//+------------------------------------------------------------------+
input group "=== ADAPTIVE TAKE PROFIT ==="
input bool     EnableAdaptiveTP = false;            // Attiva Adaptive Take Profit (DISATTIVATO per performance)
input double   AdaptiveTP_A = 3.2;                  // Coefficiente A (moltiplicatore)
input double   AdaptiveTP_B = 0.75;                 // Coefficiente B (esponente)
input double   AdaptiveTP_C = 0.03;                 // Coefficiente C (offset)
input double   AdaptiveTP_Cap = 0.6;                // CAP massimo (%)
input double   AdaptiveTP_Floor = 0.2;              // FLOOR minimo (%)
input double   AdaptiveTP_Fallback = 0.4;           // Valore fallback (%)

// Variabile globale per il wrapper
CTradingWrapper tradingWrapper;

//+------------------------------------------------------------------+
//| Funzione di inizializzazione                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Inizializza il wrapper - aggiungi il parametro EnableAdaptiveTP
    if(!tradingWrapper.Init(Symbol_Name, Symbol_TimeFrame, MagicNumber, 
                           EnableEntropyFilter,
                           UseDynamicLotManagement,
                           BacktestEndBufferDays,
                           Stoch_Filter_Post,
                           EnableAdaptiveTP))  // <-- Parametro aggiunto
    {
        Print("ERRORE: Impossibile inizializzare il wrapper");
        return(INIT_FAILED);
    }
    
    // Crea la struttura di configurazione
    SymbolConfig config;
    
    // Configura i parametri del simbolo
    config.symbol = Symbol_Name;
    config.active = Symbol_Active;
    config.timeframe = Symbol_TimeFrame;
    config.ema20_period = Symbol_EMA20_Period;
    config.ema50_period = Symbol_EMA50_Period;
    config.stoch_k = Symbol_Stoch_K;
    config.stoch_d = Symbol_Stoch_D;
    config.stoch_slowing = Symbol_Stoch_Slowing;
    config.macd_fast = Symbol_MACD_Fast;
    config.macd_slow = Symbol_MACD_Slow;
    config.macd_signal_period = Symbol_MACD_Signal;
    config.adx_period = Symbol_ADX_Period;
    config.adx_threshold = Symbol_ADX_Threshold;
    config.max_positions = Symbol_MaxPositions;
    config.macd_lookback = Symbol_MACD_LookbackPeriods;
    config.ema_lookback = Symbol_EMA_LookbackPeriods;
    config.macd_lookahead = Symbol_MACD_LookaheadPeriods;
    config.ema_lookahead = Symbol_EMA_LookaheadPeriods;
    config.ignore_macd = Symbol_IgnoreMACDCondition;
    config.ignore_ema = Symbol_IgnoreEMACondition;
    config.filter_stoch_overbought = Symbol_FilterStochOverBought;
    config.stoch_overbought_level = Symbol_StochOverBoughtLevel;
    config.filter_stoch_oversold = Symbol_FilterStochOverSold;
    config.stoch_oversold_level = Symbol_StochOverSoldLevel;
    config.use_rsi_filter = Symbol_UseRSIFilter;
    config.rsi_period = Symbol_RSI_Period;
    config.rsi_overbought_level = Symbol_RSI_OverboughtLevel;
    config.rsi_oversold_level = Symbol_RSI_OversoldLevel;
    config.use_obv_filter = Symbol_UseOBVFilter;
    config.obv_ema_fast = Symbol_OBV_EMA_Fast;
    config.obv_ema_slow = Symbol_OBV_EMA_Slow;
    config.use_advanced_sl = Symbol_UseAdvancedSL;
    config.advanced_sl_exponent = Symbol_AdvancedSL_Exponent;
    config.use_advanced_sl_threshold = Symbol_UseAdvancedSL_Threshold;
    config.advanced_sl_threshold_value = Symbol_AdvancedSL_ThresholdValue;
    config.use_fixed_sl = Symbol_UseFixedSL;
    config.fixed_sl_percent = Symbol_FixedSL_Percent;
    config.sl_offset_percent = Symbol_SL_OffsetPercent;
    config.use_sl_cap = Symbol_UseSL_Cap;
    config.sl_cap_percent = Symbol_SL_CapPercent;
    config.use_ema_spread_override = Symbol_UseEMASpreadOverride;
    config.ema_spread_threshold = Symbol_EMASpreadThreshold;
    config.ema_override_period = Symbol_EMA_Override_Period;
    config.use_fixed_tp = Symbol_UseFixedTP;
    config.fixed_tp_percent = Symbol_FixedTP_Percent;
    config.trailing_start_percent = Symbol_TrailingStartPercent;
    config.trailing_start_distance = Symbol_TrailingStartDistance;
    config.trailing_max_percent = Symbol_TrailingMaxPercent;
    config.use_breakeven_logic = Symbol_UseBreakevenLogic;
    config.breakeven_trigger_percent = Symbol_BreakevenTriggerPercent;
    config.breakeven_sl_percent = Symbol_BreakevenSLPercent;
    config.use_breakeven_step2 = Symbol_UseBreakevenStep2;
    config.lot_size = Symbol_LotSize;
    config.use_time_mgmt = Symbol_UseTimeManagement;
    config.block_minutes_before = Symbol_BlockMinutesBefore;
    config.monday_open = Symbol_MondayOpen;
    config.monday_close = Symbol_MondayClose;
    config.tuesday_open = Symbol_TuesdayOpen;
    config.tuesday_close = Symbol_TuesdayClose;
    config.wednesday_open = Symbol_WednesdayOpen;
    config.wednesday_close = Symbol_WednesdayClose;
    config.thursday_open = Symbol_ThursdayOpen;
    config.thursday_close = Symbol_ThursdayClose;
    config.friday_open = Symbol_FridayOpen;
    config.friday_close = Symbol_FridayClose;
    config.saturday_open = Symbol_SaturdayOpen;
    config.saturday_close = Symbol_SaturdayClose;
    config.sunday_open = Symbol_SundayOpen;
    config.sunday_close = Symbol_SundayClose;
    config.use_ema_slope_filter = Symbol_UseEMASlopeFilter;
    config.ema_slope_threshold = Symbol_EMASlopeThreshold;
    config.ema_slope_period = Symbol_EMASlopePeriod;
    config.use_trend_filter = Symbol_UseTrendFilter;
    config.trend_timeframe = Symbol_TrendTimeframe;
    config.magic_number = MagicNumber;
    
    // Configura il simbolo nel wrapper
    tradingWrapper.ConfigureSymbol(config);
    
    // Configura il filtro entropico
    tradingWrapper.ConfigureEntropyFilter(
        Entropy_Period_Breve, Entropy_Period_Medio, Entropy_Period_Lungo,
        Entropy_Bins, Entropy_Sideways_Threshold, Entropy_Chaotic_Threshold,
        Entropy_Volatility_Min, Entropy_Volatility_Max
    );
    
    // Configura l'Adaptive Take Profit se attivato
    if(EnableAdaptiveTP)
    {
        AdaptiveTPConfig tpConfig;
        tpConfig.active = true;
        tpConfig.a = AdaptiveTP_A;
        tpConfig.b = AdaptiveTP_B;
        tpConfig.c = AdaptiveTP_C;
        tpConfig.cap = AdaptiveTP_Cap;
        tpConfig.floor = AdaptiveTP_Floor;
        tpConfig.fallback = AdaptiveTP_Fallback;

        tradingWrapper.ConfigureAdaptiveTP(tpConfig);
        Print("Adaptive Take Profit ATTIVATO con formula esponenziale");
        Print("  Formula: TP = (ATR*100)/Prezzo * [a*(EMA_ratio)^b + c]");
        Print("  Parametri: a=", AdaptiveTP_A, " b=", AdaptiveTP_B, " c=", AdaptiveTP_C);
        Print("  Limiti: CAP=", AdaptiveTP_Cap, "% FLOOR=", AdaptiveTP_Floor, "% FALLBACK=", AdaptiveTP_Fallback, "%");
    }
    
    // Chiama l'OnInit del wrapper
    return tradingWrapper.OnInit();
}

//+------------------------------------------------------------------+
//| Funzione Tick                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
    // Il wrapper gestirà tutto il processo
    tradingWrapper.OnTick();
}

//+------------------------------------------------------------------+
//| Funzione Deinit                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Chiama l'OnDeinit del wrapper
    tradingWrapper.OnDeinit(reason);
}