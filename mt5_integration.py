"""
Integrazione MT5 per HMM Trend Filter
Script che legge dati da MT5, calcola regime HMM e scrive output
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
from pathlib import Path
import sys

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    print("WARNING: MetaTrader5 package non installato")
    print("Installa con: pip install MetaTrader5")

from hmm_filter import HMMTrendFilter


class MT5HMMBridge:
    """
    Bridge tra MetaTrader 5 e HMM Trend Filter
    """

    def __init__(self, symbol: str = "XAUUSD", timeframe=None,
                 output_file: str = "./output/hmm_regime.txt"):
        """
        Args:
            symbol: Simbolo da tradare (default: XAUUSD = GOLD)
            timeframe: Timeframe MT5 (default: MT5.TIMEFRAME_M10)
            output_file: Path file output per MT5
        """
        self.symbol = symbol
        self.timeframe = timeframe or (mt5.TIMEFRAME_M10 if MT5_AVAILABLE else None)
        self.output_file = output_file

        # HMM Filter
        self.filter = HMMTrendFilter()
        self.is_initialized = False

        # Stats
        self.last_update = None
        self.update_count = 0

    def connect_mt5(self, login: int = None, password: str = None, server: str = None) -> bool:
        """
        Connessione a MT5

        Args:
            login: Login MT5 (opzionale)
            password: Password (opzionale)
            server: Server (opzionale)

        Returns:
            True se connesso
        """
        if not MT5_AVAILABLE:
            print("ERROR: MetaTrader5 non disponibile")
            return False

        # Inizializza MT5
        if not mt5.initialize():
            print(f"initialize() failed, error code = {mt5.last_error()}")
            return False

        # Login (se credenziali fornite)
        if login and password and server:
            if not mt5.login(login, password, server):
                print(f"Login failed, error code = {mt5.last_error()}")
                mt5.shutdown()
                return False

        print(f"MT5 connesso: {mt5.account_info()}")
        print(f"Simbolo: {self.symbol}")
        print(f"Timeframe: {self.timeframe}")

        return True

    def disconnect_mt5(self):
        """Disconnetti da MT5"""
        if MT5_AVAILABLE:
            mt5.shutdown()
            print("MT5 disconnesso")

    def fetch_historical_data(self, n_bars: int = 1500) -> pd.DataFrame:
        """
        Scarica dati storici da MT5

        Args:
            n_bars: Numero di barre da scaricare

        Returns:
            DataFrame con OHLCV
        """
        if not MT5_AVAILABLE:
            raise RuntimeError("MT5 non disponibile")

        # Ottieni rates
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, n_bars)

        if rates is None or len(rates) == 0:
            raise RuntimeError(f"Impossibile ottenere dati per {self.symbol}")

        # Converti in DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)

        # Rinomina colonne
        df = df.rename(columns={'tick_volume': 'volume'})

        # Seleziona colonne necessarie
        df = df[['open', 'high', 'low', 'close', 'volume']]

        print(f"Scaricati {len(df)} bars da MT5")
        print(f"Range: {df.index[0]} - {df.index[-1]}")

        return df

    def initialize_filter(self, training_bars: int = 1000):
        """
        Inizializza filtro HMM con dati storici

        Args:
            training_bars: Numero bars per training iniziale
        """
        print(f"\nInizializzazione HMM Filter...")

        # Scarica dati storici
        historical_data = self.fetch_historical_data(n_bars=training_bars + 100)

        # Training
        self.filter.fit_initial(historical_data.iloc[:training_bars])

        self.is_initialized = True
        print("HMM Filter inizializzato con successo")

        # Statistiche
        stats = self.filter.get_statistics()
        print(f"\nStatistiche training:")
        print(f"  Regimi identificati: {stats['hmm']}")

    def get_current_regime(self, window_size: int = 100) -> dict:
        """
        Ottiene regime corrente

        Args:
            window_size: Dimensione finestra per analisi

        Returns:
            Dict con regime e dettagli
        """
        if not self.is_initialized:
            raise RuntimeError("Filtro non inizializzato. Chiamare initialize_filter() prima.")

        # Scarica ultimi dati
        current_data = self.fetch_historical_data(n_bars=window_size)

        # Predizione
        result = self.filter.predict(current_data, return_details=True)

        # Update stats
        self.last_update = datetime.now()
        self.update_count += 1

        return result

    def write_regime_to_file(self, regime_data: dict):
        """
        Scrive regime in file per MT5

        Args:
            regime_data: Dict con dati regime
        """
        # Crea directory se non esiste
        Path(self.output_file).parent.mkdir(parents=True, exist_ok=True)

        # Contenuto file
        content = (
            f"{regime_data['regime']}\n"
            f"{regime_data['regime_name']}\n"
            f"{regime_data['confidence']:.4f}\n"
            f"{self.last_update.strftime('%Y.%m.%d %H:%M:%S')}\n"
        )

        # Scrivi file
        with open(self.output_file, 'w') as f:
            f.write(content)

    def run_continuous(self, update_interval: int = 60):
        """
        Esecuzione continua (daemon mode)
        Aggiorna regime ogni N secondi

        Args:
            update_interval: Secondi tra updates
        """
        print(f"\n{'='*70}")
        print(f"DAEMON MODE ATTIVO")
        print(f"Update interval: {update_interval}s")
        print(f"Output file: {self.output_file}")
        print(f"{'='*70}\n")

        try:
            while True:
                try:
                    # Ottieni regime corrente
                    regime_data = self.get_current_regime()

                    # Scrivi in file
                    self.write_regime_to_file(regime_data)

                    # Log
                    print(
                        f"[{self.last_update.strftime('%H:%M:%S')}] "
                        f"Regime: {regime_data['regime']} ({regime_data['regime_name']}) | "
                        f"Confidence: {regime_data['confidence']:.2%} | "
                        f"Updates: {self.update_count}"
                    )

                    # Export anche via metodo filter
                    self.filter.export_signal_to_file(self.output_file)

                except Exception as e:
                    print(f"ERROR durante update: {e}")

                # Attendi
                time.sleep(update_interval)

        except KeyboardInterrupt:
            print("\n\nDaemon interrotto dall'utente")
            self.disconnect_mt5()

    def run_on_new_bar(self):
        """
        Esecuzione ad ogni nuova barra (più efficiente)
        Monitora MT5 e aggiorna solo quando c'è nuova barra
        """
        print(f"\n{'='*70}")
        print(f"NEW BAR MODE ATTIVO")
        print(f"Output file: {self.output_file}")
        print(f"{'='*70}\n")

        last_bar_time = None

        try:
            while True:
                # Ottieni ultima barra
                rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, 1)

                if rates is None or len(rates) == 0:
                    print("ERROR: Impossibile ottenere ultima barra")
                    time.sleep(10)
                    continue

                current_bar_time = pd.to_datetime(rates[0]['time'], unit='s')

                # Check se è nuova barra
                if last_bar_time is None or current_bar_time > last_bar_time:
                    print(f"\n[NUOVA BARRA] {current_bar_time}")

                    # Update regime
                    try:
                        regime_data = self.get_current_regime()
                        self.write_regime_to_file(regime_data)

                        print(
                            f"  Regime: {regime_data['regime']} ({regime_data['regime_name']}) | "
                            f"Confidence: {regime_data['confidence']:.2%}"
                        )

                    except Exception as e:
                        print(f"  ERROR: {e}")

                    last_bar_time = current_bar_time

                # Check ogni 5 secondi
                time.sleep(5)

        except KeyboardInterrupt:
            print("\n\nMonitoring interrotto")
            self.disconnect_mt5()


# ============================================================================
# SCRIPT PRINCIPALE
# ============================================================================

def main():
    """Funzione principale"""

    print("\n")
    print("╔" + "═" * 68 + "╗")
    print("║" + " " * 15 + "MT5 - HMM TREND FILTER BRIDGE" + " " * 23 + "║")
    print("║" + " " * 25 + "GOLD 10min" + " " * 33 + "║")
    print("╚" + "═" * 68 + "╝")
    print()

    # Configurazione
    SYMBOL = "XAUUSD"  # Gold
    OUTPUT_FILE = "./output/hmm_regime.txt"

    # Crea bridge
    bridge = MT5HMMBridge(
        symbol=SYMBOL,
        output_file=OUTPUT_FILE
    )

    # Connetti MT5
    print("Connessione a MetaTrader 5...")
    if not bridge.connect_mt5():
        print("ERRORE: Impossibile connettersi a MT5")
        return

    # Inizializza filtro
    bridge.initialize_filter(training_bars=1000)

    # Menu
    print("\n" + "=" * 70)
    print("Seleziona modalità:")
    print("  1. Single prediction (una volta)")
    print("  2. Continuous mode (daemon, update ogni 60s)")
    print("  3. New bar mode (update ad ogni nuova barra)")
    print("=" * 70)

    choice = input("\nScelta [1-3]: ").strip()

    if choice == '1':
        # Single prediction
        print("\nOttenimento regime corrente...")
        result = bridge.get_current_regime()

        print("\n" + "=" * 70)
        print("RISULTATO:")
        print(f"  Regime: {result['regime']} - {result['regime_name']}")
        print(f"  Confidence: {result['confidence']:.2%}")
        print(f"  Probabilities: Bull={result['probabilities'][0]:.2%}, "
              f"Bear={result['probabilities'][1]:.2%}, "
              f"Lateral={result['probabilities'][2]:.2%}")
        print("=" * 70)

        # Scrivi in file
        bridge.write_regime_to_file(result)
        print(f"\nOutput scritto in: {OUTPUT_FILE}")

    elif choice == '2':
        # Continuous mode
        bridge.run_continuous(update_interval=60)

    elif choice == '3':
        # New bar mode
        bridge.run_on_new_bar()

    else:
        print("Scelta non valida")

    # Disconnect
    bridge.disconnect_mt5()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"\nERRORE FATALE: {e}")
        import traceback
        traceback.print_exc()
