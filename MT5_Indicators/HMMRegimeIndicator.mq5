//+------------------------------------------------------------------+
//|                                        HMMRegimeIndicator.mq5   |
//|                           Visualizza regimi HMM sul grafico     |
//|                        Legge dati da file processato Python     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   1

//--- Plot Regime
#property indicator_label1  "HMM Regime"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrLime,clrRed,clrGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Input parameters
input string   RegimeDataFile = "hmm_data\\gold_10min_historical_regimes.csv";  // File dati regimi
input string   DataFolder = "";              // Cartella dati (vuoto = auto)
input bool     ShowRegimeLabels = true;      // Mostra etichette regime
input bool     ShowConfidence = true;        // Mostra confidence
input int      RefreshInterval = 300;        // Intervallo refresh (secondi)

//--- Indicator buffers
double RegimeBuffer[];          // Buffer principale regime
double ColorBuffer[];           // Buffer colori
double ConfidenceBuffer[];      // Buffer confidence
double DummyBuffer[];           // Buffer dummy

//--- Global variables
datetime last_file_check = 0;
datetime last_file_modtime = 0;
string regime_names[] = {"UNKNOWN", "BULLISH", "BEARISH", "LATERAL"};
int total_bars_loaded = 0;

//--- Regime data storage
struct RegimeData
{
    datetime time;
    int regime;
    double confidence;
};

RegimeData regime_data[];
int regime_data_count = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Indicator buffers mapping
    SetIndexBuffer(0, RegimeBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
    SetIndexBuffer(2, ConfidenceBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, DummyBuffer, INDICATOR_DATA);

    //--- Set indicator digits
    IndicatorSetInteger(INDICATOR_DIGITS, 0);

    //--- Set indicator levels
    IndicatorSetInteger(INDICATOR_LEVELS, 3);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 1.0);  // BULLISH
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, 2.0);  // BEARISH
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, 3.0);  // LATERAL

    IndicatorSetString(INDICATOR_LEVELTEXT, 0, "BULLISH");
    IndicatorSetString(INDICATOR_LEVELTEXT, 1, "BEARISH");
    IndicatorSetString(INDICATOR_LEVELTEXT, 2, "LATERAL");

    //--- Set level colors
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrLime);
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrRed);
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 2, clrGray);

    //--- Set level styles
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 2, STYLE_DOT);

    //--- Indicator short name
    IndicatorSetString(INDICATOR_SHORTNAME, "HMM Regime");

    //--- Load regime data
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║  HMM REGIME INDICATOR INITIALIZING                            ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");

    if(!LoadRegimeData())
    {
        Print("WARNING: Impossibile caricare dati regime");
        Print("         L'indicator mostrerà LATERAL finché i dati non sono disponibili");
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    //--- Check if need to reload data
    datetime current_time = TimeCurrent();
    if(current_time - last_file_check > RefreshInterval)
    {
        LoadRegimeData();
        last_file_check = current_time;
    }

    //--- Set array as series
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(RegimeBuffer, true);
    ArraySetAsSeries(ColorBuffer, true);
    ArraySetAsSeries(ConfidenceBuffer, true);

    //--- Calculate regimes for each bar
    int limit = rates_total - prev_calculated;
    if(prev_calculated == 0)
        limit = rates_total;

    for(int i = 0; i < limit; i++)
    {
        datetime bar_time = time[i];

        // Find regime for this bar time
        int regime = FindRegimeForTime(bar_time);

        RegimeBuffer[i] = (double)regime;

        // Set color based on regime
        if(regime == 1)
            ColorBuffer[i] = 0;  // Green (BULLISH)
        else if(regime == 2)
            ColorBuffer[i] = 1;  // Red (BEARISH)
        else
            ColorBuffer[i] = 2;  // Gray (LATERAL)

        // Set confidence
        ConfidenceBuffer[i] = GetConfidenceForTime(bar_time);
    }

    //--- return value of prev_calculated for next call
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Load regime data from file                                       |
//+------------------------------------------------------------------+
bool LoadRegimeData()
{
    string file_path = RegimeDataFile;

    Print("Caricamento dati regime da: ", file_path);

    int file_handle = FileOpen(file_path, FILE_READ|FILE_CSV|FILE_ANSI, ',');

    if(file_handle == INVALID_HANDLE)
    {
        Print("ERRORE: Impossibile aprire file regime: ", file_path);
        Print("        Error code: ", GetLastError());
        Print("        Path completo: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", file_path);
        return false;
    }

    //--- Clear existing data
    ArrayFree(regime_data);
    regime_data_count = 0;

    //--- Read header
    string header = FileReadString(file_handle);

    //--- Read data lines
    int lines_read = 0;
    while(!FileIsEnding(file_handle))
    {
        // Read line: time,regime,regime_name,confidence,close
        string time_str = FileReadString(file_handle);       // time
        int regime = (int)FileReadNumber(file_handle);       // regime
        string regime_name = FileReadString(file_handle);    // regime_name
        double confidence = FileReadNumber(file_handle);     // confidence
        double close_price = FileReadNumber(file_handle);    // close

        if(time_str == "" || regime < 1 || regime > 3)
            continue;

        // Parse time
        datetime dt = StringToTime(time_str);

        if(dt == 0)
            continue;

        // Store regime data
        ArrayResize(regime_data, regime_data_count + 1);
        regime_data[regime_data_count].time = dt;
        regime_data[regime_data_count].regime = regime;
        regime_data[regime_data_count].confidence = confidence;

        regime_data_count++;
        lines_read++;
    }

    FileClose(file_handle);

    total_bars_loaded = lines_read;

    Print("✓ Caricati ", lines_read, " regime records");

    if(lines_read > 0)
    {
        Print("  Periodo: ", TimeToString(regime_data[0].time), " -> ",
              TimeToString(regime_data[regime_data_count-1].time));

        // Statistics
        int bull_count = 0, bear_count = 0, lat_count = 0;
        for(int i = 0; i < regime_data_count; i++)
        {
            if(regime_data[i].regime == 1) bull_count++;
            else if(regime_data[i].regime == 2) bear_count++;
            else if(regime_data[i].regime == 3) lat_count++;
        }

        Print("  Regimi: BULL=", bull_count, " BEAR=", bear_count, " LAT=", lat_count);
    }

    return (lines_read > 0);
}

//+------------------------------------------------------------------+
//| Find regime for specific time                                    |
//+------------------------------------------------------------------+
int FindRegimeForTime(datetime search_time)
{
    if(regime_data_count == 0)
        return 3;  // Default: LATERAL

    // Binary search (data is sorted by time)
    int left = 0;
    int right = regime_data_count - 1;

    // If before first data point
    if(search_time < regime_data[0].time)
        return regime_data[0].regime;

    // If after last data point
    if(search_time >= regime_data[right].time)
        return regime_data[right].regime;

    // Binary search
    while(left <= right)
    {
        int mid = (left + right) / 2;

        if(regime_data[mid].time == search_time)
            return regime_data[mid].regime;

        if(regime_data[mid].time < search_time)
            left = mid + 1;
        else
            right = mid - 1;
    }

    // Return closest (previous bar)
    if(right >= 0 && right < regime_data_count)
        return regime_data[right].regime;

    return 3;  // Default: LATERAL
}

//+------------------------------------------------------------------+
//| Get confidence for specific time                                 |
//+------------------------------------------------------------------+
double GetConfidenceForTime(datetime search_time)
{
    if(regime_data_count == 0)
        return 0.0;

    // Linear search (could optimize with binary search)
    for(int i = 0; i < regime_data_count; i++)
    {
        if(regime_data[i].time == search_time)
            return regime_data[i].confidence;
    }

    return 0.0;
}

//+------------------------------------------------------------------+
//| Get regime value for EA access                                   |
//+------------------------------------------------------------------+
int GetRegimeValue(int bar_index = 0)
{
    if(bar_index < 0 || bar_index >= ArraySize(RegimeBuffer))
        return 3;  // Default: LATERAL

    return (int)RegimeBuffer[bar_index];
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // Handle chart events if needed
}

//+------------------------------------------------------------------+
//| Deinitialization function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("HMM Regime Indicator deinitialized. Bars loaded: ", total_bars_loaded);

    ArrayFree(regime_data);
}
