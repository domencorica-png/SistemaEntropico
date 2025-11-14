//+------------------------------------------------------------------+
//|                      BotOriginale.mqh                            |
//|                        Copyright 2025, Your Name                 |
//|                        Logiche di trading riutilizzabili         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property version   "1.00"
#include <Trade\Trade.mqh>

//--- Strutture
struct SymbolConfig
{
   string symbol;
   bool active;
   ENUM_TIMEFRAMES timeframe;
   int ema20_handle, ema50_handle, stoch_handle, macd_handle, adx_handle;
   int rsi_handle, obv_handle, ema_override_handle;
   double ema20_buffer[], ema50_buffer[], stoch_main[], stoch_signal[];
   double macd_main[], macd_signal[], adx_buffer[];
   double rsi_buffer[], obv_buffer[], ema_override_buffer[];
   int ema20_period, ema50_period, stoch_k, stoch_d, stoch_slowing;
   int macd_fast, macd_slow, macd_signal_period, adx_period;
   double adx_threshold;
   int max_positions, macd_lookback, ema_lookback, macd_lookahead, ema_lookahead;
   bool ignore_macd, ignore_ema, filter_stoch_overbought, filter_stoch_oversold;
   double stoch_overbought_level, stoch_oversold_level;
   bool use_rsi_filter;
   int rsi_period;
   double rsi_overbought_level, rsi_oversold_level;
   bool use_obv_filter;
   int obv_ema_fast, obv_ema_slow;
   bool use_advanced_sl;
   double advanced_sl_exponent;
   bool use_advanced_sl_threshold;
   double advanced_sl_threshold_value;
   bool use_fixed_sl;
   double fixed_sl_percent, sl_offset_percent;
   bool use_sl_cap;
   double sl_cap_percent, fixed_tp_percent;
   bool use_fixed_tp;
   double trailing_start_percent, trailing_start_distance, trailing_max_percent;
   bool use_breakeven_logic;
   double breakeven_trigger_percent, breakeven_sl_percent;
   bool use_breakeven_step2;
   double lot_size;
   bool use_ema_spread_override;
   double ema_spread_threshold;
   int ema_override_period;
   bool use_time_mgmt;
   int block_minutes_before;
   string monday_open, monday_close, tuesday_open, tuesday_close;
   string wednesday_open, wednesday_close, thursday_open, thursday_close;
   string friday_open, friday_close, saturday_open, saturday_close, sunday_open, sunday_close;
   datetime last_bar_time;
   bool use_ema_slope_filter;
   double ema_slope_threshold;
   int ema_slope_period;
   bool use_trend_filter;
   ENUM_TIMEFRAMES trend_timeframe;
   int trend_ema20_handle, trend_ema50_handle;
   double trend_ema20_buffer[], trend_ema50_buffer[];
   int magic_number;
};

struct TrailingData
{
   ulong ticket;
   string symbol;
   double open_price, highest_profit;
   bool trailing_active;
   bool breakeven_triggered;
   bool breakeven_first_activation_done;
   bool breakeven_price_went_below_trigger;
   bool phase_one_completed;
   double adaptive_trailing_start_percent;  // Valore adaptivo calcolato all'apertura del trade
};

struct PendingSignal
{
   string symbol;
   datetime signal_time;
   datetime cross_bar_time;
   bool is_long, ema_condition_met, macd_condition_met;
   double signal_price;
   int bars_waiting;
};

struct SimpleCrossTracker
{
   string symbol;
   datetime bar_time;
   bool is_long;
   bool position_opened;
   ulong ticket;
};

//--- Funzioni di utilità
void BotCore_Log(string msg, int magic_number)
{
   Print("[BotCore-" + IntegerToString(magic_number) + "] " + msg);
}

double CalculateEMASlopeAbs(const double &ema50_buffer[], int ema_slope_period)
{
   int N = MathMax(1, ema_slope_period);
   int required_bars = N + 1;
   if(ArraySize(ema50_buffer) < required_bars) 
   {
      BotCore_Log("ERRORE: Buffer EMA50 insufficiente per calcolo pendenza", 0);
      return 0.0;
   }
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
   if(count == 0) 
   {
      BotCore_Log("AVVISO: Nessun valore valido per calcolo pendenza EMA", 0);
      return 0.0;
   }
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
          DoubleToString(threshold, 2) + " bp ? nessun trade", config.magic_number);
      return false;
   }
   return true;
}

bool CheckTrendFilter(const SymbolConfig &config, bool is_long)
{
   if(!config.use_trend_filter) return true;
   
   // Verifica che i buffer siano validi
   if(ArraySize(config.trend_ema20_buffer) == 0 || ArraySize(config.trend_ema50_buffer) == 0)
   {
      BotCore_Log(config.symbol + " - AVVISO: Buffer trend non inizializzati, skip trend filter", config.magic_number);
      return true;
   }
   
   double ema20_htf = config.trend_ema20_buffer[0];
   double ema50_htf = config.trend_ema50_buffer[0];
   if(ema20_htf == 0 || ema50_htf == 0) 
   {
      BotCore_Log(config.symbol + " - AVVISO: Valori EMA trend nulli, skip trend filter", config.magic_number);
      return true;
   }
   
   if(is_long)
   {
      if(ema50_htf > ema20_htf)
      {
         BotCore_Log(config.symbol + " - ? TREND FILTER: LONG bloccato (EMA50 > EMA20 su HTF)", config.magic_number);
         return false;
      }
   }
   else
   {
      if(ema20_htf > ema50_htf)
      {
         BotCore_Log(config.symbol + " - ? TREND FILTER: SHORT bloccato (EMA20 > EMA50 su HTF)", config.magic_number);
         return false;
      }
   }
   return true;
}

bool CheckStochFilter(const SymbolConfig &config, bool is_long, bool stoch_filter_post)
{
   if(!stoch_filter_post) return true;
   
   // Verifica che i buffer siano validi
   if(ArraySize(config.stoch_main) < 3)
   {
      BotCore_Log(config.symbol + " - AVVISO: Buffer stocastico insufficiente, skip stoch filter", config.magic_number);
      return true;
   }
   
   double main_2 = config.stoch_main[2];
   double main_1 = config.stoch_main[1];
   if(is_long)
   {
      if(config.filter_stoch_overbought && 
         (main_2 > config.stoch_overbought_level || main_1 > config.stoch_overbought_level))
      {
         BotCore_Log(config.symbol + " - ? STOCH POST: BUY rifiutato (Overbought)", config.magic_number);
         return false;
      }
   }
   else
   {
      if(config.filter_stoch_oversold && 
         (main_2 < config.stoch_oversold_level || main_1 < config.stoch_oversold_level))
      {
         BotCore_Log(config.symbol + " - ? STOCH POST: SELL rifiutato (Oversold)", config.magic_number);
         return false;
      }
   }
   return true;
}

double CalculateEMA_OnOBV(const double &obv_buffer[], int period, int shift)
{
   if(period <= 0 || shift < 0) 
   {
      BotCore_Log("ERRORE: Parametri EMA OBV non validi", 0);
      return 0;
   }
   
   int required_bars = period + shift + 10;
   if(ArraySize(obv_buffer) < required_bars) 
   {
      BotCore_Log("AVVISO: Buffer OBV insufficiente per calcolo EMA", 0);
      return 0;
   }
   
   double alpha = 2.0 / (period + 1.0);
   double ema = 0;
   int start_index = shift + period - 1;
   if(start_index >= ArraySize(obv_buffer)) 
   {
      BotCore_Log("ERRORE: Indice di partenza EMA OBV fuori range", 0);
      return 0;
   }
   
   double sum = 0;
   for(int i = 0; i < period; i++)
   {
      int idx = shift + period - 1 - i;
      if(idx >= ArraySize(obv_buffer)) 
      {
         BotCore_Log("ERRORE: Indice EMA OBV fuori range durante calcolo media iniziale", 0);
         return 0;
      }
      sum += obv_buffer[idx];
   }
   
   if(period == 0) 
   {
      BotCore_Log("ERRORE: Periodo EMA OBV zero", 0);
      return 0;
   }
   
   ema = sum / period;
   
   for(int i = start_index - 1; i >= shift; i--)
   {
      if(i < 0 || i >= ArraySize(obv_buffer)) 
      {
         BotCore_Log("ERRORE: Indice EMA OBV fuori range durante calcolo ricorsivo", 0);
         return 0;
      }
      ema = (obv_buffer[i] - ema) * alpha + ema;
   }
   
   return ema;
}

bool CheckRSIFilter(const SymbolConfig &config, bool is_long)
{
   if(!config.use_rsi_filter) return true;
   
   // Verifica che il buffer RSI sia valido
   if(ArraySize(config.rsi_buffer) == 0)
   {
      BotCore_Log(config.symbol + " - AVVISO: Buffer RSI non disponibile, skip RSI filter", config.magic_number);
      return true;
   }
   
   double rsi_current = config.rsi_buffer[0];
   if(is_long)
   {
      if(rsi_current > config.rsi_overbought_level)
      {
         BotCore_Log(config.symbol + " - ? BLOCCO RSI: BUY rifiutato (RSI=" +
               DoubleToString(rsi_current, 2) + " > " + DoubleToString(config.rsi_overbought_level, 2) + ")", config.magic_number);
         return false;
      }
   }
   else
   {
      if(rsi_current < config.rsi_oversold_level)
      {
         BotCore_Log(config.symbol + " - ? BLOCCO RSI: SELL rifiutato (RSI=" +
               DoubleToString(rsi_current, 2) + " < " + DoubleToString(config.rsi_oversold_level, 2) + ")", config.magic_number);
         return false;
      }
   }
   return true;
}

bool CheckOBVFilter(const SymbolConfig &config, bool is_long)
{
   if(!config.use_obv_filter) return true;
   
   // Verifica che il buffer OBV sia valido
   if(ArraySize(config.obv_buffer) < MathMax(config.obv_ema_fast, config.obv_ema_slow) + 10)
   {
      BotCore_Log(config.symbol + " - AVVISO: Buffer OBV insufficiente, skip OBV filter", config.magic_number);
      return true;
   }
   
   double ema_fast = CalculateEMA_OnOBV(config.obv_buffer, config.obv_ema_fast, 0);
   double ema_slow = CalculateEMA_OnOBV(config.obv_buffer, config.obv_ema_slow, 0);
   
   if(ema_fast == 0 || ema_slow == 0)
   {
      BotCore_Log(config.symbol + " - ERRORE OBV: EMA non calcolabili", config.magic_number);
      return true; // Non bloccare il trade in caso di errore
   }
   
   if(is_long)
   {
      if(ema_fast < ema_slow)
      {
         BotCore_Log(config.symbol + " - ? BLOCCO OBV: BUY rifiutato (EMA_Fast < EMA_Slow)", config.magic_number);
         return false;
      }
   }
   else
   {
      if(ema_fast > ema_slow)
      {
         BotCore_Log(config.symbol + " - ? BLOCCO OBV: SELL rifiutato (EMA_Fast > EMA_Slow)", config.magic_number);
         return false;
      }
   }
   return true;
}

bool CheckEMACondition(const SymbolConfig &config, bool fl, double p, int bi)
{
   // Verifica che i buffer siano validi
   if(ArraySize(config.ema20_buffer) <= bi || ArraySize(config.ema50_buffer) <= bi)
   {
      BotCore_Log("ERRORE: Buffer EMA insufficienti per CheckEMACondition", config.magic_number);
      return false;
   }
   
   double hp = (bi == 0) ? p : iClose(config.symbol, config.timeframe, bi);
   if(fl) 
   {
      return (hp > config.ema20_buffer[bi] && config.ema20_buffer[bi] > config.ema50_buffer[bi]);
   }
   return (hp < config.ema20_buffer[bi] && config.ema20_buffer[bi] < config.ema50_buffer[bi]);
}

bool CheckEMAConditionLookback(const SymbolConfig &config, bool fl, double cp)
{
   for(int i = 1; i <= config.ema_lookback; i++)
   {
      if(CheckEMACondition(config, fl, cp, i)) 
         return true;
   }
   return false;
}

bool CheckMACDCondition(const SymbolConfig &config, bool fl, int bi)
{
   // Verifica che i buffer siano validi
   if(ArraySize(config.macd_main) <= bi || ArraySize(config.macd_signal) <= bi)
   {
      BotCore_Log("ERRORE: Buffer MACD insufficienti per CheckMACDCondition", config.magic_number);
      return false;
   }
   
   if(fl) 
      return (config.macd_main[bi] > config.macd_signal[bi]);
   return (config.macd_main[bi] < config.macd_signal[bi]);
}

bool CheckMACDConditionLookback(const SymbolConfig &config, bool fl)
{
   for(int i = 1; i <= config.macd_lookback; i++)
   {
      if(CheckMACDCondition(config, fl, i)) 
         return true;
   }
   return false;
}

double CalculateLotSize(double equity, const SymbolConfig &config, bool use_dynamic_lot_management)
{
   double te = equity;
   double se = te;
   double tl = config.lot_size;
   int mp = config.max_positions;
   string sym = config.symbol;
   double mpl = 0;
   
   // Verifica che il simbolo sia valido
   if(StringLen(sym) == 0)
   {
      BotCore_Log("ERRORE: Simbolo non specificato per calcolo lot size", config.magic_number);
      return 0;
   }
   
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, tl, SymbolInfoDouble(sym, SYMBOL_ASK), mpl)) 
   {
      BotCore_Log("ERRORE: Calcolo margin fallito per " + sym + " - " + IntegerToString(GetLastError()), config.magic_number);
      return 0;
   }
   
   double tmn = mpl * mp;
   if(!use_dynamic_lot_management)
   {
      if(se >= tmn) 
         return tl;
      
      int ap = (int)(se / mpl);
      return (ap >= 1) ? tl : 0;
   }
   else
   {
      if(se >= tmn) 
         return tl;
      
      double al = (se / mp) / (mpl / tl);
      double ls = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double ml = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double xl = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      
      if(ls > 0) 
         al = MathFloor(al / ls) * ls;
      
      al = MathMax(al, ml);
      al = MathMin(al, xl);
      
      // Verifica che il lot size sia valido
      if(al < ml || al > xl || MathAbs(al) < 0.0001)
      {
         BotCore_Log("AVVISO: Lot size calcolato non valido (" + DoubleToString(al, 2) + "), uso minimo", config.magic_number);
         return ml;
      }
      
      return al;
   }
}

double CalculateAdvancedStopLoss(ENUM_ORDER_TYPE ot, double open_price, const SymbolConfig &config)
{
   // Verifica che i buffer siano validi
   if(ArraySize(config.ema50_buffer) == 0 || ArraySize(config.ema20_buffer) == 0)
   {
      BotCore_Log("ERRORE: Buffer EMA non disponibili per calcolo SL avanzato", config.magic_number);
      return open_price * (1.0 - config.fixed_sl_percent / 100.0);
   }
   
   double EMA50 = config.ema50_buffer[0];
   double EMA20 = config.ema20_buffer[0];
   
   // Verifica valori EMA validi
   if(EMA50 == 0 || EMA20 == 0)
   {
      BotCore_Log("AVVISO: Valori EMA nulli, uso SL fisso", config.magic_number);
      return open_price * (1.0 - config.fixed_sl_percent / 100.0);
   }
   
   double OFST = config.sl_offset_percent / 100.0;
   double CAP = config.sl_cap_percent / 100.0;
   double y = config.advanced_sl_exponent;
   double SL, SLcap, SLp;
   bool is_long = (ot == ORDER_TYPE_BUY);
   
   if(is_long)
   {
      SL = 1.0 - (EMA50 * (1.0 - OFST)) / open_price;
      SLcap = (SL < CAP) ? SL : CAP;
      
      if(config.use_advanced_sl_threshold && SL > 0)
      {
         double ratio = SLcap / SL;
         if(ratio < config.advanced_sl_threshold_value)
         {
            SLp = EMA20;
            return SLp;
         }
      }
      
      if(SL < CAP)
      {
         if(SL != 0)
            SLp = open_price * (1.0 - (SLcap * SLcap) / SL);
         else
            SLp = open_price * (1.0 - SLcap);
      }
      else
      {
         double SL_powered = MathPow(SL, y);
         if(EMA20 > open_price * (1.0 - CAP))
         {
            double temp_sl = open_price * (1.0 - (SLcap * SLcap) / SL_powered);
            if(temp_sl >= EMA20)
               SLp = EMA20;
            else
               SLp = temp_sl;
         }
         else
         {
            SLp = open_price * (1.0 - (SLcap * SLcap) / SL_powered);
         }
      }
   }
   else
   {
      SL = (EMA50 * (1.0 + OFST)) / open_price - 1.0;
      SLcap = (SL < CAP) ? SL : CAP;
      
      if(config.use_advanced_sl_threshold && SL > 0)
      {
         double ratio = SLcap / SL;
         if(ratio < config.advanced_sl_threshold_value)
         {
            SLp = EMA20;
            return SLp;
         }
      }
      
      if(SL < CAP)
      {
         if(SL != 0)
            SLp = open_price * (1.0 + (SLcap * SLcap) / SL);
         else
            SLp = open_price * (1.0 + SLcap);
      }
      else
      {
         double SL_powered = MathPow(SL, y);
         if(EMA20 < open_price * (1.0 + CAP))
         {
            double temp_sl = open_price * (1.0 + (SLcap * SLcap) / SL_powered);
            if(temp_sl <= EMA20)
               SLp = EMA20;
            else
               SLp = temp_sl;
         }
         else
         {
            SLp = open_price * (1.0 + (SLcap * SLcap) / SL_powered);
         }
      }
   }
   
   return SLp;
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
   if(!ArrayResize(trackers, sz + 1))
   {
      BotCore_Log("ERRORE: Impossibile ridimensionare array trackers", magic_number);
      return;
   }
   
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
   if(!ArrayResize(trackers, sz + 1))
   {
      BotCore_Log("ERRORE: Impossibile ridimensionare array trackers per cross bruciato", magic_number);
      return;
   }
   
   trackers[sz].symbol = sym;
   trackers[sz].bar_time = bt;
   trackers[sz].is_long = il;
   trackers[sz].position_opened = false;
   trackers[sz].ticket = 0;
   BotCore_Log("?? Cross BRUCIATO: " + sym + " " + (il ? "LONG" : "SHORT"), magic_number);
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
         
         if(!ArrayResize(trackers, sz - 1))
         {
            BotCore_Log("ERRORE: Impossibile ridimensionare array durante pulizia trackers", 0);
            return;
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
   if(StringLen(ts) == 0)
   {
      h = m = 0;
      return false;
   }
   
   string p[];
   if(StringSplit(ts, ':', p) != 2) 
   {
      BotCore_Log("ERRORE: Formato orario non valido: " + ts, 0);
      return false;
   }
   
   h = (int)StringToInteger(p[0]);
   m = (int)StringToInteger(p[1]);
   
   if(h == 24 && m == 0) 
   { 
      h = 23; 
      m = 59; 
   }
   
   return (h >= 0 && h <= 23 && m >= 0 && m <= 59);
}

bool IsTradingAllowed(const SymbolConfig &config)
{
   if(!config.use_time_mgmt) return true;
   
   MqlDateTime ct;
   TimeToStruct(TimeCurrent(), ct);
   string dop, dcl;
   GetDaySchedule(ct.day_of_week, dop, dcl, config);
   
   if(IsMarketClosed(dop, dcl)) 
      return false;
   
   if(IsContinuousTrading(dop, dcl)) 
      return true;
   
   int oh, om, ch, cm;
   if(!ParseTime(dop, oh, om) || !ParseTime(dcl, ch, cm)) 
      return true;
   
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

int CountPositions(string sym, int magic_number)
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == magic_number && 
         PositionGetString(POSITION_SYMBOL) == sym)
      {
         c++;
      }
   }
   return c;
}

void CloseAllPositions(string sym, CTrade &trade, int magic_number, TrailingData &trailing_positions[], PendingSignal &pending_signals[])
{
   int cc = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == magic_number &&
         PositionGetString(POSITION_SYMBOL) == sym)
      {
         ulong t = PositionGetInteger(POSITION_TICKET);
         if(trade.PositionClose(t))
         {
            cc++;
            for(int j = ArraySize(trailing_positions) - 1; j >= 0; j--)
            {
               if(trailing_positions[j].ticket == t) 
               {
                  // Rimuovi trailing position
                  int sz = ArraySize(trailing_positions);
                  for(int k = j; k < sz - 1; k++)
                     trailing_positions[k] = trailing_positions[k + 1];
                  
                  if(!ArrayResize(trailing_positions, sz - 1))
                  {
                     BotCore_Log("ERRORE: Impossibile ridimensionare array trailing_positions", magic_number);
                  }
                  break;
               }
            }
         }
         else
         {
            BotCore_Log("ERRORE chiusura posizione " + IntegerToString(t) + ": " + IntegerToString(GetLastError()), magic_number);
         }
      }
   }
   
   if(cc > 0) 
      BotCore_Log(sym + " - Chiuse " + IntegerToString(cc) + " posizioni", magic_number);
   
   // Pulisci pending signals per questo simbolo
   for(int i = ArraySize(pending_signals) - 1; i >= 0; i--) 
   {
      if(pending_signals[i].symbol == sym) 
      {
         int sz = ArraySize(pending_signals);
         for(int j = i; j < sz - 1; j++)
            pending_signals[j] = pending_signals[j + 1];
         
         if(!ArrayResize(pending_signals, sz - 1))
         {
            BotCore_Log("ERRORE: Impossibile ridimensionare array pending_signals", magic_number);
         }
      }
   }
}