"""
Online Learning Manager
Gestisce adaptive training con walk-forward
"""

import numpy as np
import pandas as pd
from typing import Dict, Optional
from collections import deque
import logging


class OnlineLearningManager:
    """
    Gestisce online/adaptive learning per HMM
    Walk-forward training con finestra mobile
    """

    def __init__(self, config: Dict):
        """
        Args:
            config: Configurazione training
        """
        self.config = config
        self.training_window = config['training_window']
        self.retrain_frequency = config['retrain_frequency']
        self.min_samples = config['min_samples']
        self.walk_forward = config['walk_forward']

        # Buffer dati
        self.data_buffer = deque(maxlen=self.training_window)
        self.feature_buffer = deque(maxlen=self.training_window)
        self.return_buffer = deque(maxlen=self.training_window)

        # Contatori
        self.total_bars = 0
        self.bars_since_last_training = 0
        self.training_count = 0

        # Logging
        self.logger = logging.getLogger(__name__)

    def add_data(self, ohlcv_row: pd.Series, features_row: pd.Series,
                 return_value: float = None) -> None:
        """
        Aggiungi nuova barra di dati al buffer

        Args:
            ohlcv_row: Serie con OHLCV data
            features_row: Serie con features calcolate
            return_value: Return value (opzionale)
        """
        self.data_buffer.append(ohlcv_row.to_dict())
        self.feature_buffer.append(features_row.to_dict())

        if return_value is not None:
            self.return_buffer.append(return_value)

        self.total_bars += 1
        self.bars_since_last_training += 1

    def should_train(self) -> bool:
        """
        Determina se è il momento di (re)trainare il modello

        Returns:
            True se bisogna trainare, False altrimenti
        """
        # Primo training: aspetta min_samples
        if self.training_count == 0:
            if len(self.feature_buffer) >= self.min_samples:
                self.logger.info(f"Primo training con {len(self.feature_buffer)} samples")
                return True
            else:
                return False

        # Retraining periodico
        if self.bars_since_last_training >= self.retrain_frequency:
            if len(self.feature_buffer) >= self.min_samples:
                self.logger.info(
                    f"Retraining #{self.training_count + 1} - "
                    f"Bars since last: {self.bars_since_last_training}"
                )
                return True

        return False

    def get_training_data(self) -> tuple:
        """
        Ottiene dati per training

        Returns:
            (features_df, returns_series)
        """
        if len(self.feature_buffer) == 0:
            raise ValueError("Buffer vuoto - nessun dato disponibile")

        # Converti buffer in DataFrame
        features_df = pd.DataFrame(list(self.feature_buffer))

        # Returns (se disponibili)
        if len(self.return_buffer) > 0:
            returns_series = pd.Series(list(self.return_buffer))
        else:
            returns_series = None

        return features_df, returns_series

    def mark_training_completed(self) -> None:
        """Marca che il training è stato completato"""
        self.training_count += 1
        self.bars_since_last_training = 0
        self.logger.info(f"Training #{self.training_count} completato")

    def get_stats(self) -> Dict:
        """
        Ottiene statistiche online learning

        Returns:
            Dict con stats
        """
        return {
            'total_bars': self.total_bars,
            'buffer_size': len(self.feature_buffer),
            'training_count': self.training_count,
            'bars_since_last_training': self.bars_since_last_training,
            'next_training_in': max(0, self.retrain_frequency - self.bars_since_last_training),
            'buffer_utilization': len(self.feature_buffer) / self.training_window
        }

    def reset(self) -> None:
        """Reset completo del learning manager"""
        self.data_buffer.clear()
        self.feature_buffer.clear()
        self.return_buffer.clear()
        self.total_bars = 0
        self.bars_since_last_training = 0
        self.training_count = 0
        self.logger.info("Online learning manager reset")


# ============================================================================
# PERFORMANCE TRACKER
# ============================================================================

class PerformanceTracker:
    """
    Traccia performance delle predizioni HMM
    Utile per monitorare qualità del modello nel tempo
    """

    def __init__(self, window_size: int = 100):
        """
        Args:
            window_size: Dimensione finestra per metriche rolling
        """
        self.window_size = window_size

        # Storici
        self.regime_history = deque(maxlen=window_size)
        self.confidence_history = deque(maxlen=window_size)
        self.return_history = deque(maxlen=window_size)

        # Tracking transizioni
        self.transition_counts = {
            (1, 1): 0, (1, 2): 0, (1, 3): 0,
            (2, 1): 0, (2, 2): 0, (2, 3): 0,
            (3, 1): 0, (3, 2): 0, (3, 3): 0
        }

        self.last_regime = None

    def update(self, regime: int, confidence: float, return_value: float = None) -> None:
        """
        Aggiorna tracker con nuova predizione

        Args:
            regime: Regime predetto (1/2/3)
            confidence: Confidence score
            return_value: Return osservato (opzionale)
        """
        self.regime_history.append(regime)
        self.confidence_history.append(confidence)

        if return_value is not None:
            self.return_history.append(return_value)

        # Track transizione
        if self.last_regime is not None:
            key = (self.last_regime, regime)
            self.transition_counts[key] = self.transition_counts.get(key, 0) + 1

        self.last_regime = regime

    def get_regime_performance(self) -> Dict:
        """
        Calcola performance per ogni regime

        Returns:
            Dict con statistiche per regime
        """
        if len(self.regime_history) == 0 or len(self.return_history) == 0:
            return {}

        df = pd.DataFrame({
            'regime': list(self.regime_history)[-len(self.return_history):],
            'return': list(self.return_history)
        })

        stats = {}
        for regime in [1, 2, 3]:
            regime_data = df[df['regime'] == regime]

            if len(regime_data) > 0:
                stats[regime] = {
                    'count': len(regime_data),
                    'mean_return': regime_data['return'].mean(),
                    'std_return': regime_data['return'].std(),
                    'win_rate': (regime_data['return'] > 0).sum() / len(regime_data),
                    'sharpe': self._calculate_sharpe(regime_data['return'])
                }

        return stats

    def _calculate_sharpe(self, returns: pd.Series, periods_per_year: int = 252 * 24 * 6) -> float:
        """
        Calcola Sharpe Ratio
        Per 10min: 6 bars/ora × 24 ore × 252 giorni trading = ~36288 bars/anno
        """
        if len(returns) < 2:
            return 0.0

        mean_return = returns.mean()
        std_return = returns.std()

        if std_return == 0:
            return 0.0

        # Annualized Sharpe
        sharpe = (mean_return / std_return) * np.sqrt(periods_per_year)

        return sharpe

    def get_transition_stats(self) -> Dict:
        """
        Ottiene statistiche transizioni tra regimi

        Returns:
            Dict con conteggi transizioni
        """
        total = sum(self.transition_counts.values())

        if total == 0:
            return {}

        transition_probs = {
            k: v / total for k, v in self.transition_counts.items()
        }

        return {
            'counts': self.transition_counts.copy(),
            'probabilities': transition_probs,
            'persistence_rate': {
                1: self.transition_counts.get((1, 1), 0) / max(1, sum(
                    v for k, v in self.transition_counts.items() if k[0] == 1)),
                2: self.transition_counts.get((2, 2), 0) / max(1, sum(
                    v for k, v in self.transition_counts.items() if k[0] == 2)),
                3: self.transition_counts.get((3, 3), 0) / max(1, sum(
                    v for k, v in self.transition_counts.items() if k[0] == 3))
            }
        }

    def get_confidence_stats(self) -> Dict:
        """
        Statistiche sulla confidence

        Returns:
            Dict con stats confidence
        """
        if len(self.confidence_history) == 0:
            return {}

        confidences = list(self.confidence_history)

        return {
            'mean': np.mean(confidences),
            'std': np.std(confidences),
            'min': np.min(confidences),
            'max': np.max(confidences),
            'median': np.median(confidences),
            'pct_high_confidence': sum(1 for c in confidences if c > 0.7) / len(confidences)
        }
