"""
Script di esempio per utilizzo HMM Trend Filter
GOLD 10min
"""

import pandas as pd
import numpy as np
from pathlib import Path

# Import del nostro filtro
from hmm_filter import HMMTrendFilter


def example_with_synthetic_data():
    """
    Esempio con dati sintetici
    Utile per testare il sistema
    """
    print("=" * 70)
    print("ESEMPIO 1: Dati Sintetici")
    print("=" * 70)

    # Genera dati GOLD sintetici (10min bars)
    n_bars = 1500
    dates = pd.date_range('2024-01-01', periods=n_bars, freq='10min')

    # Simulazione GOLD con trend e fasi laterali
    np.random.seed(42)

    # Trend bullish: bars 0-500
    bull_trend = 1950 + np.cumsum(np.random.randn(500) * 0.5 + 0.2)

    # Laterale: bars 500-1000
    lateral = 1970 + np.random.randn(500) * 2

    # Trend bearish: bars 1000-1500
    bear_trend = 1970 + np.cumsum(np.random.randn(500) * 0.5 - 0.2)

    close_prices = np.concatenate([bull_trend, lateral, bear_trend])

    # Crea OHLCV
    data = pd.DataFrame({
        'time': dates,
        'open': close_prices + np.random.randn(n_bars) * 0.5,
        'high': close_prices + np.abs(np.random.randn(n_bars)) * 1.0,
        'low': close_prices - np.abs(np.random.randn(n_bars)) * 1.0,
        'close': close_prices,
        'volume': np.random.randint(100, 1000, n_bars)
    })

    data.set_index('time', inplace=True)

    # Fix OHLC logic
    data['high'] = data[['open', 'close', 'high']].max(axis=1)
    data['low'] = data[['open', 'close', 'low']].min(axis=1)

    print(f"\nDati generati: {len(data)} bars")
    print(f"Range: {data['close'].min():.2f} - {data['close'].max():.2f}")

    # ========================================================================
    # INIZIALIZZA FILTRO HMM
    # ========================================================================

    print("\n" + "-" * 70)
    print("Inizializzazione HMM Trend Filter...")
    print("-" * 70)

    filter_hmm = HMMTrendFilter()

    # ========================================================================
    # TRAINING INIZIALE
    # ========================================================================

    print("\nTraining iniziale con primi 1000 bars...")
    training_data = data.iloc[:1000]
    filter_hmm.fit_initial(training_data)

    # ========================================================================
    # PREDIZIONI SU TEST SET
    # ========================================================================

    print("\n" + "-" * 70)
    print("Predizioni su test set (bars 1000-1500)...")
    print("-" * 70)

    test_data = data.iloc[1000:]
    results = []

    for idx in range(len(test_data)):
        # Dati fino a questo punto
        current_window = data.iloc[:1000 + idx + 1]

        # Predizione
        result = filter_hmm.predict(current_window.tail(100), return_details=True)

        results.append({
            'time': test_data.index[idx],
            'close': test_data['close'].iloc[idx],
            'regime': result['regime'],
            'regime_name': result['regime_name'],
            'confidence': result['confidence']
        })

        # Print ogni 50 bars
        if idx % 50 == 0:
            print(
                f"Bar {idx:4d}: "
                f"Close={test_data['close'].iloc[idx]:7.2f} | "
                f"Regime={result['regime']} ({result['regime_name']:8s}) | "
                f"Confidence={result['confidence']:.2%}"
            )

    # ========================================================================
    # STATISTICHE FINALI
    # ========================================================================

    print("\n" + "=" * 70)
    print("STATISTICHE FINALI")
    print("=" * 70)

    results_df = pd.DataFrame(results)

    regime_counts = results_df['regime'].value_counts().sort_index()
    print("\nDistribuzione Regimi (test set):")
    print(f"  BULLISH (1): {regime_counts.get(1, 0):4d} bars ({regime_counts.get(1, 0)/len(results_df)*100:5.1f}%)")
    print(f"  BEARISH (2): {regime_counts.get(2, 0):4d} bars ({regime_counts.get(2, 0)/len(results_df)*100:5.1f}%)")
    print(f"  LATERAL (3): {regime_counts.get(3, 0):4d} bars ({regime_counts.get(3, 0)/len(results_df)*100:5.1f}%)")

    avg_confidence = results_df['confidence'].mean()
    print(f"\nConfidence Media: {avg_confidence:.2%}")

    # Statistiche sistema
    sys_stats = filter_hmm.get_statistics()
    print("\nOnline Learning Stats:")
    for key, value in sys_stats['online_learning'].items():
        print(f"  {key}: {value}")

    return filter_hmm, results_df


def example_with_csv():
    """
    Esempio caricando dati da CSV
    """
    print("\n\n" + "=" * 70)
    print("ESEMPIO 2: Caricamento da CSV")
    print("=" * 70)

    # Path al file CSV (da configurare)
    csv_path = "./data/gold_10min.csv"

    if not Path(csv_path).exists():
        print(f"\nFile non trovato: {csv_path}")
        print("Saltando esempio CSV...")
        return None

    # Carica dati
    data = pd.read_csv(csv_path, parse_dates=['time'])
    data.set_index('time', inplace=True)

    print(f"Dati caricati: {len(data)} bars")

    # Inizializza filtro
    filter_hmm = HMMTrendFilter()

    # Training su 80% dati
    split_idx = int(len(data) * 0.8)
    filter_hmm.fit_initial(data.iloc[:split_idx])

    # Test su 20% rimanente
    test_results = []
    for idx in range(split_idx, len(data)):
        window = data.iloc[max(0, idx - 100):idx + 1]
        regime = filter_hmm.predict(window, return_details=False)
        test_results.append(regime)

    print(f"\nPredizioni completate su {len(test_results)} bars")

    return filter_hmm


def example_realtime_simulation():
    """
    Esempio simulazione real-time
    Mostra come usare il filtro bar-by-bar
    """
    print("\n\n" + "=" * 70)
    print("ESEMPIO 3: Simulazione Real-Time")
    print("=" * 70)

    # Genera dati
    n_bars = 1200
    dates = pd.date_range('2024-01-01', periods=n_bars, freq='10min')

    np.random.seed(123)
    close = 1960 + np.cumsum(np.random.randn(n_bars) * 0.5)

    data = pd.DataFrame({
        'time': dates,
        'open': close + np.random.randn(n_bars) * 0.3,
        'high': close + np.abs(np.random.randn(n_bars)) * 0.8,
        'low': close - np.abs(np.random.randn(n_bars)) * 0.8,
        'close': close,
        'volume': np.random.randint(100, 1000, n_bars)
    })

    data.set_index('time', inplace=True)
    data['high'] = data[['open', 'close', 'high']].max(axis=1)
    data['low'] = data[['open', 'close', 'low']].min(axis=1)

    # Inizializza
    filter_hmm = HMMTrendFilter()
    filter_hmm.fit_initial(data.iloc[:1000])

    print("\nSimulazione trading real-time...")
    print("(mostra solo quando cambia regime)\n")

    current_regime = None
    regime_changes = []

    for idx in range(1000, len(data)):
        # Finestra ultimi 100 bars
        window = data.iloc[idx - 99:idx + 1]

        # Predizione
        result = filter_hmm.predict(window, return_details=True)
        new_regime = result['regime']

        # Detect cambio regime
        if new_regime != current_regime:
            regime_changes.append({
                'time': data.index[idx],
                'from': current_regime,
                'to': new_regime,
                'confidence': result['confidence']
            })

            print(
                f"{data.index[idx]} | "
                f"CAMBIO REGIME: {filter_hmm.get_regime_name(current_regime) if current_regime else 'START':8s} -> "
                f"{result['regime_name']:8s} "
                f"(confidence: {result['confidence']:.2%})"
            )

            current_regime = new_regime

        # Export signal (simula scrittura per MT5)
        filter_hmm.export_signal_to_file()

    print(f"\nTotale cambi regime: {len(regime_changes)}")

    return filter_hmm, regime_changes


def example_trading_integration():
    """
    Esempio integrazione con logica trading
    Mostra come usare output del filtro per bloccare trades
    """
    print("\n\n" + "=" * 70)
    print("ESEMPIO 4: Integrazione Trading Logic")
    print("=" * 70)

    # Simula signal generator del bot
    class TradingBot:
        def __init__(self, hmm_filter):
            self.filter = hmm_filter
            self.trades_executed = []
            self.trades_blocked = []

        def on_new_bar(self, data_window):
            """Chiamato ad ogni nuova barra"""

            # 1. Ottieni regime HMM
            regime = self.filter.predict(data_window, return_details=False)

            # 2. Genera segnale trading (esempio semplice)
            # Nella realtà useresti la tua strategia
            signal = self._generate_signal(data_window)

            # 3. Filtra con regime
            if regime == 3:  # LATERAL
                self.trades_blocked.append({
                    'time': data_window.index[-1],
                    'signal': signal,
                    'reason': 'LATERAL_REGIME'
                })
                print(f"{data_window.index[-1]} | Signal: {signal:6s} | BLOCKED (Lateral regime)")
                return None

            # 4. Esegui trade se regime permette
            if regime == 1 and signal == 'BUY':
                self.trades_executed.append({'time': data_window.index[-1], 'type': 'BUY'})
                print(f"{data_window.index[-1]} | Signal: {signal:6s} | EXECUTED (Bullish regime)")
                return 'BUY'

            elif regime == 2 and signal == 'SELL':
                self.trades_executed.append({'time': data_window.index[-1], 'type': 'SELL'})
                print(f"{data_window.index[-1]} | Signal: {signal:6s} | EXECUTED (Bearish regime)")
                return 'SELL'

            else:
                self.trades_blocked.append({
                    'time': data_window.index[-1],
                    'signal': signal,
                    'reason': 'REGIME_MISMATCH'
                })
                print(f"{data_window.index[-1]} | Signal: {signal:6s} | BLOCKED (Regime mismatch)")
                return None

        def _generate_signal(self, data):
            """Genera segnale (placeholder - usa la tua logica)"""
            # Esempio stupido: random
            return np.random.choice(['BUY', 'SELL', 'NONE'], p=[0.3, 0.3, 0.4])

    # Setup
    data = pd.DataFrame({
        'time': pd.date_range('2024-01-01', periods=1100, freq='10min'),
        'open': 1960 + np.cumsum(np.random.randn(1100) * 0.3),
        'high': 1960 + np.cumsum(np.random.randn(1100) * 0.3) + 1,
        'low': 1960 + np.cumsum(np.random.randn(1100) * 0.3) - 1,
        'close': 1960 + np.cumsum(np.random.randn(1100) * 0.3),
        'volume': np.random.randint(100, 1000, 1100)
    })
    data.set_index('time', inplace=True)

    # Filtro HMM
    filter_hmm = HMMTrendFilter()
    filter_hmm.fit_initial(data.iloc[:1000])

    # Bot
    bot = TradingBot(filter_hmm)

    # Simula trading
    print("\nSimulazione trading (mostra solo primi 20 segnali)...\n")
    for idx in range(1000, min(1020, len(data))):
        window = data.iloc[idx - 99:idx + 1]
        bot.on_new_bar(window)

    print(f"\n\nRISULTATI:")
    print(f"Trades eseguiti: {len(bot.trades_executed)}")
    print(f"Trades bloccati: {len(bot.trades_blocked)}")

    if len(bot.trades_blocked) > 0:
        blocked_reasons = pd.DataFrame(bot.trades_blocked)['reason'].value_counts()
        print(f"\nMotivi blocco:")
        for reason, count in blocked_reasons.items():
            print(f"  {reason}: {count}")


if __name__ == '__main__':
    print("\n")
    print("╔" + "═" * 68 + "╗")
    print("║" + " " * 15 + "HMM TREND FILTER - EXAMPLES" + " " * 25 + "║")
    print("║" + " " * 20 + "GOLD 10min" + " " * 38 + "║")
    print("╚" + "═" * 68 + "╝")

    try:
        # Esempio 1: Dati sintetici
        filter1, results1 = example_with_synthetic_data()

        # Esempio 2: CSV (se disponibile)
        # filter2 = example_with_csv()

        # Esempio 3: Real-time simulation
        filter3, changes3 = example_realtime_simulation()

        # Esempio 4: Trading integration
        example_trading_integration()

        print("\n\n" + "=" * 70)
        print("ESEMPI COMPLETATI CON SUCCESSO!")
        print("=" * 70)

    except Exception as e:
        print(f"\nERRORE: {e}")
        import traceback
        traceback.print_exc()
