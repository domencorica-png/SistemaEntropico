"""
HMM Trend Filter - Main System
Sistema completo integrato per GOLD 10min
Output: 1 (BULLISH) | 2 (BEARISH) | 3 (LATERAL)
"""

import numpy as np
import pandas as pd
from typing import Dict, Optional, Union
import logging
from pathlib import Path

from .config import (
    FEATURES_CONFIG, HMM_CONFIG, STATE_CONFIG,
    TRAINING_CONFIG, DATA_CONFIG, LOGGING_CONFIG
)
from .feature_engineer import MinimalFeatureEngineer, validate_dataframe
from .hmm_detector import HMMRegimeDetector, EnsembleHMMDetector
from .online_learner import OnlineLearningManager, PerformanceTracker


class HMMTrendFilter:
    """
    Sistema completo HMM Trend Filter

    Usage:
        # Inizializzazione
        filter = HMMTrendFilter()

        # Training iniziale
        filter.fit_initial(historical_data)

        # Predizione real-time
        result = filter.predict(current_data)
        regime = result['regime']  # 1, 2, or 3
    """

    def __init__(self, config: Optional[Dict] = None):
        """
        Args:
            config: Configurazione custom (opzionale)
                   Se None, usa config di default
        """
        # Configurazione
        self.config = config or self._get_default_config()

        # Setup logging
        self._setup_logging()

        # Componenti
        self.feature_engineer = MinimalFeatureEngineer(FEATURES_CONFIG)
        self.hmm_detector = HMMRegimeDetector(self.config)
        self.online_learner = OnlineLearningManager(TRAINING_CONFIG)
        self.performance_tracker = PerformanceTracker()

        # Opzionale: ensemble
        self.use_ensemble = TRAINING_CONFIG.get('n_historical_models', 1) > 1
        if self.use_ensemble:
            self.ensemble_detector = EnsembleHMMDetector(
                self.config,
                n_models=TRAINING_CONFIG['n_historical_models']
            )

        # Stato
        self.is_initialized = False
        self.last_prediction = None

        self.logger.info("HMM Trend Filter inizializzato")

    def _get_default_config(self) -> Dict:
        """Ottiene configurazione di default"""
        return {
            'FEATURES_CONFIG': FEATURES_CONFIG,
            'HMM_CONFIG': HMM_CONFIG,
            'STATE_CONFIG': STATE_CONFIG,
            'TRAINING_CONFIG': TRAINING_CONFIG,
            'DATA_CONFIG': DATA_CONFIG
        }

    def _setup_logging(self):
        """Setup sistema logging"""
        log_config = LOGGING_CONFIG

        # Crea logger
        self.logger = logging.getLogger('HMMTrendFilter')
        self.logger.setLevel(getattr(logging, log_config['level']))

        # Formatter
        formatter = logging.Formatter(log_config['format'])

        # File handler
        if log_config['enabled']:
            log_path = Path(log_config['file'])
            log_path.parent.mkdir(parents=True, exist_ok=True)

            fh = logging.FileHandler(log_config['file'])
            fh.setLevel(getattr(logging, log_config['level']))
            fh.setFormatter(formatter)
            self.logger.addHandler(fh)

        # Console handler
        if log_config['console']:
            ch = logging.StreamHandler()
            ch.setLevel(getattr(logging, log_config['level']))
            ch.setFormatter(formatter)
            self.logger.addHandler(ch)

    def fit_initial(self, historical_data: pd.DataFrame) -> None:
        """
        Training iniziale del sistema

        Args:
            historical_data: DataFrame con colonne ['open', 'high', 'low', 'close', 'volume']
                           e opzionalmente 'time' come index
        """
        self.logger.info(f"Inizio training iniziale con {len(historical_data)} bars")

        # Validazione dati
        validate_dataframe(historical_data)

        # Feature engineering
        self.logger.info("Calcolo features...")
        features = self.feature_engineer.transform(historical_data)

        # Returns per auto-mapping
        returns = historical_data['close'].pct_change()

        # Fit HMM
        self.logger.info("Training modello HMM...")
        self.hmm_detector.fit(features, returns)

        # Popola buffer online learner
        self.logger.info("Popolamento buffer online learner...")
        for idx in range(len(historical_data)):
            self.online_learner.add_data(
                historical_data.iloc[idx],
                features.iloc[idx],
                returns.iloc[idx]
            )

        # Se ensemble, aggiungi primo modello
        if self.use_ensemble:
            self.ensemble_detector.add_model(self.hmm_detector)

        self.is_initialized = True
        self.logger.info("Training iniziale completato")

        # Log statistiche iniziali
        stats = self.hmm_detector.get_regime_stats()
        if stats:
            self.logger.info(
                f"Regime distribution: "
                f"Bull={stats['bullish_pct']:.1f}% "
                f"Bear={stats['bearish_pct']:.1f}% "
                f"Lateral={stats['lateral_pct']:.1f}%"
            )

    def predict(self, data: Union[pd.DataFrame, pd.Series],
                return_details: bool = False) -> Union[int, Dict]:
        """
        Predice regime corrente

        Args:
            data: DataFrame OHLCV (può essere finestra o singola row)
                 Se Series, viene convertito in DataFrame
            return_details: Se True, ritorna dict con dettagli
                          Se False, ritorna solo regime (1/2/3)

        Returns:
            int: Regime (1=BULL, 2=BEAR, 3=LATERAL)
            oppure
            Dict: Dettagli completi predizione
        """
        if not self.is_initialized:
            raise ValueError("Sistema non inizializzato. Chiamare fit_initial() prima.")

        # Converti Series -> DataFrame se necessario
        if isinstance(data, pd.Series):
            data = data.to_frame().T

        # Validazione
        validate_dataframe(data)

        # Feature engineering
        features = self.feature_engineer.transform(data)

        # ADX corrente (per validazione)
        adx_current = self.feature_engineer.get_adx_value(data)

        # Predizione
        if self.use_ensemble and len(self.ensemble_detector.models) > 1:
            result = self.ensemble_detector.predict(features, adx_current)
        else:
            result = self.hmm_detector.predict(features, adx_current)

        # Update online learner
        if len(data) > 0:
            last_return = data['close'].pct_change().iloc[-1]
            self.online_learner.add_data(
                data.iloc[-1],
                features.iloc[-1],
                last_return
            )

        # Update performance tracker
        self.performance_tracker.update(
            result['regime'],
            result['confidence'],
            data['close'].pct_change().iloc[-1] if len(data) > 0 else None
        )

        # Check se serve retraining
        if self.online_learner.should_train():
            self.logger.info("Triggering adaptive retraining...")
            self._adaptive_retrain()

        # Salva ultima predizione
        self.last_prediction = result

        # Log
        self.logger.debug(
            f"Regime: {result['regime_name']} "
            f"(confidence: {result['confidence']:.2%})"
        )

        # Output
        if return_details:
            # Aggiungi statistiche extra
            result['online_learning_stats'] = self.online_learner.get_stats()
            result['performance_stats'] = self.performance_tracker.get_regime_performance()
            return result
        else:
            return result['regime']

    def _adaptive_retrain(self) -> None:
        """Retraining adattivo del modello"""
        try:
            # Ottieni dati da buffer
            features, returns = self.online_learner.get_training_data()

            self.logger.info(f"Retraining con {len(features)} samples...")

            # Crea nuovo detector
            new_detector = HMMRegimeDetector(self.config)
            new_detector.fit(features, returns)

            # Se ensemble, aggiungi nuovo modello
            if self.use_ensemble:
                self.ensemble_detector.add_model(new_detector)
                self.logger.info(
                    f"Nuovo modello aggiunto all'ensemble "
                    f"(totale: {len(self.ensemble_detector.models)})"
                )
            else:
                # Sostituisci detector corrente
                self.hmm_detector = new_detector

            # Marca training completato
            self.online_learner.mark_training_completed()

            self.logger.info("Retraining completato con successo")

        except Exception as e:
            self.logger.error(f"Errore durante retraining: {e}")

    def get_regime_name(self, regime_code: int) -> str:
        """Converte codice regime -> nome"""
        names = {1: 'BULLISH', 2: 'BEARISH', 3: 'LATERAL'}
        return names.get(regime_code, 'UNKNOWN')

    def get_statistics(self) -> Dict:
        """
        Ottiene statistiche complete del sistema

        Returns:
            Dict con statistiche dettagliate
        """
        stats = {
            'system': {
                'is_initialized': self.is_initialized,
                'use_ensemble': self.use_ensemble,
                'last_regime': self.last_prediction['regime_name'] if self.last_prediction else None
            },
            'hmm': self.hmm_detector.get_regime_stats(),
            'online_learning': self.online_learner.get_stats(),
            'performance': {
                'regime_performance': self.performance_tracker.get_regime_performance(),
                'transitions': self.performance_tracker.get_transition_stats(),
                'confidence': self.performance_tracker.get_confidence_stats()
            }
        }

        return stats

    def save(self, filepath: str) -> None:
        """Salva stato del sistema"""
        self.logger.info(f"Saving system to {filepath}")
        self.hmm_detector.save_model(filepath)

    def load(self, filepath: str) -> None:
        """Carica stato del sistema"""
        self.logger.info(f"Loading system from {filepath}")
        self.hmm_detector.load_model(filepath)
        self.is_initialized = True

    def export_signal_to_file(self, output_path: Optional[str] = None) -> None:
        """
        Esporta ultimo regime in file (per integrazione MT5)

        Args:
            output_path: Path file output (default da config)
        """
        if self.last_prediction is None:
            self.logger.warning("Nessuna predizione disponibile")
            return

        if output_path is None:
            output_path = DATA_CONFIG['output_file']['path']

        # Crea directory se non esiste
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)

        # Formato output
        regime = self.last_prediction['regime']
        confidence = self.last_prediction['confidence']

        if DATA_CONFIG['output_file']['format'] == 'simple':
            # Solo numero
            content = f"{regime}\n"
        else:
            # Formato dettagliato
            content = (
                f"regime={regime}\n"
                f"regime_name={self.last_prediction['regime_name']}\n"
                f"confidence={confidence:.4f}\n"
                f"timestamp={pd.Timestamp.now()}\n"
            )

        # Scrivi file
        with open(output_path, 'w') as f:
            f.write(content)

        self.logger.debug(f"Signal exported to {output_path}: regime={regime}")

    def __repr__(self) -> str:
        status = "INITIALIZED" if self.is_initialized else "NOT INITIALIZED"
        return f"<HMMTrendFilter status={status}>"
