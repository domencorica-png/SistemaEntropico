//+------------------------------------------------------------------+
//|                                                    HMMFilter.mqh |
//|                                  HMM Trend Filter for MT5        |
//|                   Legge regime da Python HMM system              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Classe HMM Filter                                                 |
//| Legge output dal sistema Python HMM                              |
//| Regime: 1=BULLISH, 2=BEARISH, 3=LATERAL                         |
//+------------------------------------------------------------------+
class CHMMFilter
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // Configurazione
    string m_regimeFilePath;          // Path del file regime da Python
    int m_updateIntervalSeconds;      // Intervallo aggiornamento (secondi)
    bool m_enabled;                   // Abilitato/disabilitato

    // Stato corrente
    int m_currentRegime;              // 1=BULL, 2=BEAR, 3=LATERAL
    string m_currentRegimeName;       // Nome regime
    double m_confidence;              // Confidence score (0-1)
    datetime m_lastUpdate;            // Ultimo aggiornamento
    datetime m_lastFileModTime;       // Ultima modifica file

    // Statistiche
    int m_readCount;                  // Numero letture effettuate
    int m_errorCount;                 // Numero errori lettura
    datetime m_regimeChangeTime;      // Ultimo cambio regime
    int m_previousRegime;             // Regime precedente

    // Cache per performance
    bool m_useCache;
    int m_cachedRegime;
    datetime m_cacheTime;
    int m_cacheValiditySeconds;

public:
    //+------------------------------------------------------------------+
    //| Costruttore                                                       |
    //+------------------------------------------------------------------+
    CHMMFilter()
    {
        m_currentRegime = 3;           // Default: LATERAL (blocca tutto)
        m_currentRegimeName = "LATERAL";
        m_confidence = 0.0;
        m_lastUpdate = 0;
        m_lastFileModTime = 0;
        m_readCount = 0;
        m_errorCount = 0;
        m_previousRegime = 3;
        m_regimeChangeTime = 0;
        m_updateIntervalSeconds = 60;  // Default 60 secondi
        m_enabled = true;

        // Cache
        m_useCache = true;
        m_cachedRegime = 3;
        m_cacheTime = 0;
        m_cacheValiditySeconds = 30;   // Cache valida 30 secondi

        // Path default
        m_regimeFilePath = "output\\hmm_regime.txt";
    }

    //+------------------------------------------------------------------+
    //| Inizializzazione                                                 |
    //+------------------------------------------------------------------+
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
              string regimeFilePath = "output\\hmm_regime.txt",
              int updateIntervalSeconds = 60,
              bool enabled = true)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_regimeFilePath = regimeFilePath;
        m_updateIntervalSeconds = updateIntervalSeconds;
        m_enabled = enabled;

        // Verifica che il file esista (o crealo con default)
        if(!FileIsExist(m_regimeFilePath, FILE_COMMON))
        {
            Print("WARNING: File regime HMM non trovato: ", m_regimeFilePath);
            Print("         Creazione file default con regime LATERAL...");
            CreateDefaultRegimeFile();
        }

        // Prima lettura
        Update();

        Print("HMM Filter inizializzato:");
        Print("  File: ", m_regimeFilePath);
        Print("  Update interval: ", m_updateIntervalSeconds, "s");
        Print("  Regime corrente: ", m_currentRegime, " (", m_currentRegimeName, ")");

        return true;
    }

    //+------------------------------------------------------------------+
    //| Aggiorna regime leggendo dal file                               |
    //+------------------------------------------------------------------+
    void Update()
    {
        if(!m_enabled)
            return;

        datetime currentTime = TimeCurrent();

        // Check cache validity
        if(m_useCache && (currentTime - m_cacheTime) < m_cacheValiditySeconds)
        {
            // Cache ancora valida, usa valore cached
            m_currentRegime = m_cachedRegime;
            return;
        }

        // Check intervallo aggiornamento
        if((currentTime - m_lastUpdate) < m_updateIntervalSeconds)
            return;

        // Leggi regime da file
        int newRegime = ReadRegimeFromFile();

        if(newRegime >= 1 && newRegime <= 3)
        {
            // Regime valido
            if(newRegime != m_currentRegime)
            {
                // Cambio regime!
                m_previousRegime = m_currentRegime;
                m_regimeChangeTime = currentTime;

                Print("╔═════════════════════════════════════════════╗");
                Print("║  HMM REGIME CHANGE                          ║");
                Print("╠═════════════════════════════════════════════╣");
                Print("║  From: ", GetRegimeName(m_previousRegime), "                           ║");
                Print("║  To:   ", GetRegimeName(newRegime), "                           ║");
                Print("║  Confidence: ", DoubleToString(m_confidence, 2), "%                        ║");
                Print("╚═════════════════════════════════════════════╝");
            }

            m_currentRegime = newRegime;
            m_currentRegimeName = GetRegimeName(newRegime);
            m_lastUpdate = currentTime;
            m_readCount++;

            // Aggiorna cache
            m_cachedRegime = newRegime;
            m_cacheTime = currentTime;
        }
        else
        {
            // Errore lettura - mantieni regime precedente
            m_errorCount++;
            Print("ERROR: Regime non valido letto dal file: ", newRegime);
            Print("       Mantenimento regime precedente: ", m_currentRegime);
        }
    }

    //+------------------------------------------------------------------+
    //| Legge regime da file                                            |
    //+------------------------------------------------------------------+
    int ReadRegimeFromFile()
    {
        int fileHandle = FileOpen(m_regimeFilePath, FILE_READ|FILE_TXT|FILE_COMMON);

        if(fileHandle == INVALID_HANDLE)
        {
            Print("ERROR: Impossibile aprire file regime: ", m_regimeFilePath);
            Print("       Error code: ", GetLastError());
            return -1;  // Errore
        }

        // Leggi prima linea (regime code: 1, 2, or 3)
        string line = FileReadString(fileHandle);
        StringTrimLeft(line);   // Rimuovi spazi a sinistra
        StringTrimRight(line);  // Rimuovi spazi a destra

        int regime = (int)StringToInteger(line);

        // Leggi seconda linea (regime name) se disponibile
        if(!FileIsEnding(fileHandle))
        {
            string regimeName = FileReadString(fileHandle);
            // Leggi terza linea (confidence) se disponibile
            if(!FileIsEnding(fileHandle))
            {
                string confStr = FileReadString(fileHandle);
                m_confidence = StringToDouble(confStr) * 100.0;  // Converti in %
            }
        }

        FileClose(fileHandle);

        return regime;
    }

    //+------------------------------------------------------------------+
    //| Crea file default se non esiste                                 |
    //+------------------------------------------------------------------+
    void CreateDefaultRegimeFile()
    {
        int fileHandle = FileOpen(m_regimeFilePath, FILE_WRITE|FILE_TXT|FILE_COMMON);

        if(fileHandle != INVALID_HANDLE)
        {
            // Scrivi regime default: LATERAL (blocca trades)
            FileWriteString(fileHandle, "3\n");
            FileWriteString(fileHandle, "LATERAL\n");
            FileWriteString(fileHandle, "1.0000\n");
            FileWriteString(fileHandle, TimeToString(TimeCurrent()) + "\n");

            FileClose(fileHandle);
            Print("File regime default creato con successo");
        }
        else
        {
            Print("ERROR: Impossibile creare file regime default");
        }
    }

    //+------------------------------------------------------------------+
    //| Verifica se il trade deve essere bloccato                       |
    //+------------------------------------------------------------------+
    bool ShouldBlockTrade()
    {
        if(!m_enabled)
            return false;  // Filtro disabilitato = non bloccare

        // Aggiorna regime
        Update();

        // Blocca se LATERAL (3)
        return (m_currentRegime == 3);
    }

    //+------------------------------------------------------------------+
    //| Verifica se il trade LONG è permesso                            |
    //+------------------------------------------------------------------+
    bool IsLongAllowed()
    {
        if(!m_enabled)
            return true;

        Update();

        // Long permesso solo in regime BULLISH (1)
        return (m_currentRegime == 1);
    }

    //+------------------------------------------------------------------+
    //| Verifica se il trade SHORT è permesso                           |
    //+------------------------------------------------------------------+
    bool IsShortAllowed()
    {
        if(!m_enabled)
            return true;

        Update();

        // Short permesso solo in regime BEARISH (2)
        return (m_currentRegime == 2);
    }

    //+------------------------------------------------------------------+
    //| Ottieni regime corrente                                         |
    //+------------------------------------------------------------------+
    int GetCurrentRegime()
    {
        Update();
        return m_currentRegime;
    }

    //+------------------------------------------------------------------+
    //| Ottieni nome regime corrente                                    |
    //+------------------------------------------------------------------+
    string GetCurrentRegimeName()
    {
        Update();
        return m_currentRegimeName;
    }

    //+------------------------------------------------------------------+
    //| Ottieni confidence corrente                                     |
    //+------------------------------------------------------------------+
    double GetConfidence()
    {
        return m_confidence;
    }

    //+------------------------------------------------------------------+
    //| Get regime name da code                                         |
    //+------------------------------------------------------------------+
    string GetRegimeName(int regime)
    {
        switch(regime)
        {
            case 1: return "BULLISH";
            case 2: return "BEARISH";
            case 3: return "LATERAL";
            default: return "UNKNOWN";
        }
    }

    //+------------------------------------------------------------------+
    //| Verifica se regime è cambiato                                   |
    //+------------------------------------------------------------------+
    bool HasRegimeChanged()
    {
        return (m_currentRegime != m_previousRegime);
    }

    //+------------------------------------------------------------------+
    //| Ottieni statistiche                                             |
    //+------------------------------------------------------------------+
    string GetStatistics()
    {
        string stats = "";
        stats += "╔═════════════════════════════════════════════╗\n";
        stats += "║  HMM FILTER STATISTICS                      ║\n";
        stats += "╠═════════════════════════════════════════════╣\n";
        stats += StringFormat("║  Current Regime: %-10s              ║\n", m_currentRegimeName);
        stats += StringFormat("║  Confidence: %.2f%%                        ║\n", m_confidence);
        stats += StringFormat("║  Read Count: %d                            ║\n", m_readCount);
        stats += StringFormat("║  Error Count: %d                           ║\n", m_errorCount);
        stats += StringFormat("║  Last Update: %s               ║\n", TimeToString(m_lastUpdate, TIME_DATE|TIME_MINUTES));
        if(m_regimeChangeTime > 0)
            stats += StringFormat("║  Last Change: %s               ║\n", TimeToString(m_regimeChangeTime, TIME_DATE|TIME_MINUTES));
        stats += "╚═════════════════════════════════════════════╝";

        return stats;
    }

    //+------------------------------------------------------------------+
    //| Abilita/disabilita filtro                                       |
    //+------------------------------------------------------------------+
    void SetEnabled(bool enabled)
    {
        m_enabled = enabled;
        Print("HMM Filter ", (enabled ? "ABILITATO" : "DISABILITATO"));
    }

    //+------------------------------------------------------------------+
    //| Verifica se filtro è abilitato                                  |
    //+------------------------------------------------------------------+
    bool IsEnabled()
    {
        return m_enabled;
    }

    //+------------------------------------------------------------------+
    //| Forza aggiornamento (ignora intervallo)                         |
    //+------------------------------------------------------------------+
    void ForceUpdate()
    {
        m_lastUpdate = 0;  // Reset last update time
        m_cacheTime = 0;   // Invalida cache
        Update();
    }

    //+------------------------------------------------------------------+
    //| Set intervallo aggiornamento                                    |
    //+------------------------------------------------------------------+
    void SetUpdateInterval(int seconds)
    {
        m_updateIntervalSeconds = MathMax(1, seconds);
        Print("HMM Filter update interval impostato a ", m_updateIntervalSeconds, " secondi");
    }
};
