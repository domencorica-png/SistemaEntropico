"""
HMM Backtest Batch Processor
Processa dati storici esportati da MT5 e genera regimi per backtesting

Output: CSV con regime per ogni barra storica
"""

import pandas as pd
import numpy as np
from pathlib import Path
import argparse
import json
from datetime import datetime

from hmm_filter import HMMTrendFilter


class HMMBacktestProcessor:
    """
    Processor per calcolare regimi HMM su dati storici completi
    Per uso in backtesting MT5
    """

    def __init__(self, config_path: str = None):
        """
        Args:
            config_path: Path al file configurazione JSON (opzionale)
        """
        self.config = self._load_config(config_path)
        self.filter = HMMTrendFilter(self.config)

    def _load_config(self, config_path: str) -> dict:
        """Carica configurazione da JSON se fornita"""
        if config_path and Path(config_path).exists():
            with open(config_path, 'r') as f:
                return json.load(f)
        return None

    def process_historical_data(self, input_csv: str, output_csv: str = None):
        """
        Processa file CSV storico e genera regimi

        Args:
            input_csv: Path al CSV esportato da MT5
            output_csv: Path output (default: input + _regimes.csv)

        Returns:
            DataFrame con regimi
        """
        print("\n" + "="*70)
        print(" HMM BACKTEST BATCH PROCESSOR")
        print("="*70)

        # Carica dati
        print(f"\n1. Caricamento dati da: {input_csv}")
        df = self._load_mt5_csv(input_csv)

        print(f"   ✓ Caricate {len(df)} bars")
        print(f"   ✓ Periodo: {df.index[0]} -> {df.index[-1]}")

        # Configurazione walk-forward
        training_window = self.config.get('TRAINING_CONFIG', {}).get('training_window', 1000)
        retrain_freq = self.config.get('TRAINING_CONFIG', {}).get('retrain_frequency', 100)

        print(f"\n2. Configurazione Walk-Forward:")
        print(f"   Training window: {training_window} bars")
        print(f"   Retrain frequency: {retrain_freq} bars")

        # Training iniziale
        print(f"\n3. Training iniziale (primi {training_window} bars)...")
        initial_data = df.iloc[:training_window]
        self.filter.fit_initial(initial_data)
        print("   ✓ Training completato")

        # Predizioni walk-forward
        print(f"\n4. Walk-forward predictions...")
        regimes = []
        confidences = []
        regime_names = []

        total_bars = len(df)
        progress_step = max(1, total_bars // 20)  # 5% steps

        for idx in range(total_bars):
            # Finestra per predizione (ultimi 100 bars o disponibili)
            window_start = max(0, idx - 99)
            window = df.iloc[window_start:idx+1]

            # Predici regime
            result = self.filter.predict(window, return_details=True)

            regimes.append(result['regime'])
            confidences.append(result['confidence'])
            regime_names.append(result['regime_name'])

            # Progress
            if idx % progress_step == 0:
                progress_pct = (idx / total_bars) * 100
                print(f"   Progress: {progress_pct:.0f}% ({idx}/{total_bars})")

        print("   ✓ Predictions completate")

        # Crea output DataFrame
        output_df = pd.DataFrame({
            'time': df.index,
            'regime': regimes,
            'regime_name': regime_names,
            'confidence': confidences,
            'close': df['close'].values
        })

        output_df.set_index('time', inplace=True)

        # Statistiche
        print(f"\n5. Statistiche Regimi:")
        regime_counts = output_df['regime'].value_counts().sort_index()
        total = len(output_df)

        for regime_code in [1, 2, 3]:
            count = regime_counts.get(regime_code, 0)
            pct = (count / total) * 100
            name = self.filter.get_regime_name(regime_code)
            print(f"   {name:8s} ({regime_code}): {count:5d} bars ({pct:5.1f}%)")

        avg_confidence = output_df['confidence'].mean()
        print(f"\n   Average Confidence: {avg_confidence:.2%}")

        # Transizioni
        transitions = (output_df['regime'].diff() != 0).sum()
        print(f"   Regime Changes: {transitions}")

        # Salva output
        if output_csv is None:
            output_csv = Path(input_csv).stem + "_regimes.csv"

        output_path = Path("output") / output_csv
        output_path.parent.mkdir(parents=True, exist_ok=True)

        output_df.to_csv(output_path)

        print(f"\n6. Output salvato:")
        print(f"   File: {output_path}")
        print(f"   Size: {output_path.stat().st_size / 1024:.2f} KB")

        # Summary finale
        print("\n" + "="*70)
        print(" PROCESSING COMPLETATO")
        print("="*70)
        print(f"\nFile output: {output_path}")
        print("\nPROSSIMI PASSI:")
        print("1. Copia file in: MQL5/Files/hmm_data/")
        print("2. Compila Custom Indicator: HMMRegimeIndicator.mq5")
        print("3. Applica indicator al grafico in MT5")
        print("4. Esegui backtest EA con filtro HMM attivo")
        print("="*70)

        return output_df

    def _load_mt5_csv(self, csv_path: str) -> pd.DataFrame:
        """
        Carica CSV esportato da MT5

        Args:
            csv_path: Path al file CSV

        Returns:
            DataFrame con OHLCV
        """
        # Leggi CSV
        df = pd.read_csv(csv_path)

        # Parse time column
        df['time'] = pd.to_datetime(df['time'])
        df.set_index('time', inplace=True)

        # Verifica colonne richieste
        required_cols = ['open', 'high', 'low', 'close']
        missing = set(required_cols) - set(df.columns)

        if missing:
            raise ValueError(f"Colonne mancanti nel CSV: {missing}")

        # Se manca volume, aggiungi placeholder
        if 'volume' not in df.columns:
            if 'tick_volume' in df.columns:
                df['volume'] = df['tick_volume']
            else:
                df['volume'] = 1000  # Placeholder

        return df[['open', 'high', 'low', 'close', 'volume']]

    def create_mt5_indicator_data(self, regime_df: pd.DataFrame, output_path: str):
        """
        Crea file dati ottimizzato per Custom Indicator MT5

        Args:
            regime_df: DataFrame con regimi
            output_path: Path output file
        """
        # Formato: time,regime
        indicator_df = regime_df[['regime']].copy()

        indicator_df.to_csv(output_path)

        print(f"\n✓ Indicator data file creato: {output_path}")


def main():
    """Funzione principale"""

    parser = argparse.ArgumentParser(description="HMM Backtest Batch Processor")

    parser.add_argument('input_csv', type=str,
                        help="Path al CSV esportato da MT5")
    parser.add_argument('--output', '-o', type=str, default=None,
                        help="Path output CSV (default: input_regimes.csv)")
    parser.add_argument('--config', '-c', type=str, default=None,
                        help="Path al file configurazione JSON")
    parser.add_argument('--indicator-file', '-i', action='store_true',
                        help="Crea anche file dati per MT5 indicator")

    args = parser.parse_args()

    # Verifica input esiste
    if not Path(args.input_csv).exists():
        print(f"ERRORE: File non trovato: {args.input_csv}")
        return 1

    # Process
    processor = HMMBacktestProcessor(config_path=args.config)

    try:
        result_df = processor.process_historical_data(
            args.input_csv,
            args.output
        )

        # Crea file indicator se richiesto
        if args.indicator_file:
            indicator_path = Path("output") / "hmm_indicator_data.csv"
            processor.create_mt5_indicator_data(result_df, str(indicator_path))

        return 0

    except Exception as e:
        print(f"\nERRORE durante processing: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
