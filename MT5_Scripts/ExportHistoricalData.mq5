//+------------------------------------------------------------------+
//|                                        ExportHistoricalData.mq5 |
//|                              Esporta dati storici OHLCV in CSV  |
//|                                   Per HMM Trend Filter Training |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"
#property script_show_inputs

//--- Input parameters
input int      BarsToExport = 5000;            // Numero bars da esportare
input string   ExportFileName = "gold_10min_historical.csv";  // Nome file output
input string   ExportFolder = "hmm_data";      // Cartella output (in Files/)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M10;  // Timeframe da esportare
input bool     IncludeTickVolume = true;       // Includi tick volume
input bool     OverwriteExisting = true;       // Sovrascrivi se esiste

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    PrintHeader();

    string symbol = _Symbol;
    ENUM_TIMEFRAMES tf = Timeframe;

    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║  EXPORT DATI STORICI PER HMM TREND FILTER                     ║");
    Print("╠═══════════════════════════════════════════════════════════════╣");
    PrintFormat("║  Simbolo: %-50s ║", symbol);
    PrintFormat("║  Timeframe: %-48s ║", EnumToString(tf));
    PrintFormat("║  Bars da esportare: %-40d ║", BarsToExport);
    PrintFormat("║  File output: %-46s ║", ExportFileName);
    Print("╚═══════════════════════════════════════════════════════════════╝");

    //--- Verifica dati disponibili
    int bars_available = Bars(symbol, tf);
    if(bars_available == 0)
    {
        Print("ERRORE: Nessuna barra disponibile per ", symbol, " ", EnumToString(tf));
        return;
    }

    int bars_to_export = MathMin(BarsToExport, bars_available);
    Print("Bars disponibili: ", bars_available);
    Print("Bars da esportare: ", bars_to_export);

    //--- Copia dati
    Print("\nCaricamento dati...");
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    int copied = CopyRates(symbol, tf, 0, bars_to_export, rates);

    if(copied <= 0)
    {
        Print("ERRORE: Impossibile copiare rates. Error: ", GetLastError());
        return;
    }

    Print("✓ Caricati ", copied, " bars");

    //--- Crea cartella se non esiste
    string folder_path = ExportFolder;
    if(!CreateFolder(folder_path))
    {
        Print("ERRORE: Impossibile creare cartella ", folder_path);
        return;
    }

    //--- Crea file CSV
    string file_path = folder_path + "\\" + ExportFileName;

    // Check se file esiste
    if(FileIsExist(file_path) && !OverwriteExisting)
    {
        Print("ERRORE: File già esiste e OverwriteExisting = false");
        Print("  File: ", file_path);
        return;
    }

    Print("\nCreazione file CSV...");

    int file_handle = FileOpen(file_path, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');

    if(file_handle == INVALID_HANDLE)
    {
        Print("ERRORE: Impossibile creare file. Error: ", GetLastError());
        Print("  Path: ", file_path);
        return;
    }

    //--- Scrivi header
    if(IncludeTickVolume)
        FileWrite(file_handle, "time", "open", "high", "low", "close", "tick_volume", "volume", "spread");
    else
        FileWrite(file_handle, "time", "open", "high", "low", "close", "volume");

    //--- Scrivi dati
    Print("Scrittura dati...");

    int progress_step = (int)MathMax(1, copied / 20);  // Progress ogni 5%

    for(int i = copied - 1; i >= 0; i--)  // Scrivi dal più vecchio al più recente
    {
        string time_str = TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES|TIME_SECONDS);

        if(IncludeTickVolume)
        {
            FileWrite(file_handle,
                      time_str,
                      DoubleToString(rates[i].open, _Digits),
                      DoubleToString(rates[i].high, _Digits),
                      DoubleToString(rates[i].low, _Digits),
                      DoubleToString(rates[i].close, _Digits),
                      IntegerToString(rates[i].tick_volume),
                      DoubleToString(rates[i].real_volume, 0),
                      IntegerToString(rates[i].spread)
                     );
        }
        else
        {
            FileWrite(file_handle,
                      time_str,
                      DoubleToString(rates[i].open, _Digits),
                      DoubleToString(rates[i].high, _Digits),
                      DoubleToString(rates[i].low, _Digits),
                      DoubleToString(rates[i].close, _Digits),
                      DoubleToString(rates[i].real_volume, 0)
                     );
        }

        // Progress indicator
        if((copied - i) % progress_step == 0)
        {
            double progress = ((double)(copied - i) / copied) * 100.0;
            PrintFormat("  Progress: %.0f%% (%d/%d)", progress, copied - i, copied);
        }
    }

    FileClose(file_handle);

    //--- Summary
    Print("\n╔═══════════════════════════════════════════════════════════════╗");
    Print("║  EXPORT COMPLETATO CON SUCCESSO                               ║");
    Print("╠═══════════════════════════════════════════════════════════════╣");
    PrintFormat("║  File: %-54s ║", file_path);
    PrintFormat("║  Bars esportate: %-45d ║", copied);
    PrintFormat("║  Periodo: %s  -  %s   ║",
                TimeToString(rates[copied-1].time, TIME_DATE),
                TimeToString(rates[0].time, TIME_DATE));
    PrintFormat("║  Dimensione file: ~%-38.2f KB ║", (double)FileSize(file_handle) / 1024.0);
    Print("╠═══════════════════════════════════════════════════════════════╣");
    Print("║  PROSSIMI PASSI:                                              ║");
    Print("║  1. Copia file da: MQL5/Files/" + folder_path + "              ║");
    Print("║  2. Esegui Python batch processor:                            ║");
    Print("║     python hmm_backtest_processor.py                          ║");
    Print("║  3. Importa risultati in MT5 con custom indicator             ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");

    // Apri cartella Explorer
    string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
    string full_path = terminal_path + "\\MQL5\\Files\\" + folder_path;

    Print("\nCartella output: ", full_path);
    Print("Premi OK per aprire la cartella");

    #ifdef __MQL5__
    if(MessageBox("Export completato!\nVuoi aprire la cartella?",
                  "Export Dati Storici", MB_YESNO|MB_ICONINFORMATION) == IDYES)
    {
        ShellExecuteW(0, "open", full_path, "", "", 1);
    }
    #endif
}

//+------------------------------------------------------------------+
//| Crea cartella se non esiste                                      |
//+------------------------------------------------------------------+
bool CreateFolder(string folder_name)
{
    if(FolderCreate(folder_name, FILE_COMMON))
    {
        Print("✓ Cartella creata: ", folder_name);
        return true;
    }

    // Check se esiste già
    if(GetLastError() == 5019)  // Already exists
    {
        Print("✓ Cartella esistente: ", folder_name);
        ResetLastError();
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Print header                                                      |
//+------------------------------------------------------------------+
void PrintHeader()
{
    Print("\n");
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║                                                                ║");
    Print("║     EXPORT HISTORICAL DATA FOR HMM TREND FILTER               ║");
    Print("║                    Version 1.0                                ║");
    Print("║                                                                ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    Print("\n");
}
