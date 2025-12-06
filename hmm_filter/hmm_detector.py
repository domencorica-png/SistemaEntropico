"""
HMM Regime Detector - Core del sistema
Identifica 3 regimi: BULLISH (1), BEARISH (2), LATERAL (3)
"""

import numpy as np
import pandas as pd
from typing import Dict, Tuple, Optional
from collections import deque
import pickle
import warnings
warnings.filterwarnings('ignore')

# hmmlearn per Hidden Markov Models
from hmmlearn import hmm


class HMMRegimeDetector:
    """
    Detector di regime basato su Gaussian HMM a 3 stati
    Con validazione ADX e persistence checking
    """

    def __init__(self, config: Dict):
        """
        Args:
            config: Configurazione HMM
        """
        self.config = config
        self.hmm_config = config['HMM_CONFIG']
        self.state_config = config['STATE_CONFIG']

        # Modello HMM
        self.model = self._create_hmm_model()

        # Stato interno
        self.is_fitted = False
        self.state_mapping = {}  # Mappa stato HMM -> regime (BULL/BEAR/LATERAL)
        self.state_history = deque(maxlen=50)
        self.regime_history = deque(maxlen=50)

        # Per persistence checking
        self.current_regime = None
        self.consecutive_count = 0

        # Statistics per auto-mapping
        self.state_statistics = {}

    def _create_hmm_model(self) -> hmm.GaussianHMM:
        """
        Crea modello Gaussian HMM

        Returns:
            GaussianHMM model
        """
        model = hmm.GaussianHMM(
            n_components=self.hmm_config['n_components'],
            covariance_type=self.hmm_config['covariance_type'],
            n_iter=self.hmm_config['n_iter'],
            random_state=self.hmm_config['random_state'],
            tol=self.hmm_config['tol'],
            verbose=self.hmm_config['verbose'],
            algorithm=self.hmm_config['algorithm']
        )

        return model

    def fit(self, features: pd.DataFrame, returns: pd.Series = None) -> None:
        """
        Fit del modello HMM

        Args:
            features: DataFrame features normalizzate
            returns: Series dei returns (per auto-mapping stati)
        """
        # Converti in numpy array
        X = features.values

        # Fit del modello
        self.model.fit(X)

        # Calcola mapping automatico stati -> regimi
        if self.state_config['mapping_strategy'] == 'auto':
            self._auto_map_states(features, returns)

        self.is_fitted = True

    def predict(self, features: pd.DataFrame, adx_current: Optional[float] = None) -> Dict:
        """
        Predice regime corrente

        Args:
            features: DataFrame features (può essere rolling window o solo ultimo)
            adx_current: Valore ADX corrente (per validazione laterale)

        Returns:
            Dict: {
                'regime': int (1=BULL, 2=BEAR, 3=LATERAL),
                'regime_name': str,
                'probabilities': array([p_bull, p_bear, p_lateral]),
                'confidence': float (0-1),
                'hmm_state': int,
                'adx_validation': bool,
                'is_persistent': bool
            }
        """
        if not self.is_fitted:
            raise ValueError("Modello non ancora trainato. Chiamare fit() prima.")

        # Converti features in numpy
        X = features.values

        # Predizione HMM
        hidden_states = self.model.predict(X)
        state_probs = self.model.predict_proba(X)

        # Ultimo stato e probabilità
        current_state = hidden_states[-1]
        current_probs = state_probs[-1]

        # Mappa stato HMM -> regime
        regime = self.state_mapping.get(current_state, 3)  # Default: LATERAL

        # Probabilità per ogni regime (riordinate secondo mapping)
        regime_probs = self._remap_probabilities(current_probs)

        # Confidence (max probabilità)
        confidence = regime_probs[regime - 1]  # -1 perché regime è 1-indexed

        # Validazione ADX (se abilitata)
        adx_validated = self._validate_with_adx(regime, adx_current)

        # Persistence check
        is_persistent = self._check_persistence(regime, confidence)

        # Se non è persistente, mantieni regime precedente
        if not is_persistent and self.current_regime is not None:
            regime = self.current_regime
            regime_probs = self._get_previous_probs()

        # Aggiorna storia
        self.state_history.append(current_state)
        self.regime_history.append(regime)

        # Mappa regime -> nome
        regime_names = {1: 'BULLISH', 2: 'BEARISH', 3: 'LATERAL'}

        result = {
            'regime': regime,
            'regime_name': regime_names[regime],
            'probabilities': regime_probs,
            'confidence': confidence,
            'hmm_state': int(current_state),
            'adx_validation': adx_validated,
            'is_persistent': is_persistent,
            'transition_matrix': self.model.transmat_.tolist()
        }

        return result

    def _auto_map_states(self, features: pd.DataFrame, returns: pd.Series) -> None:
        """
        Mapping automatico stati HMM -> regimi
        Basato su statistiche (mean return, volatility, ADX)

        Args:
            features: DataFrame features
            returns: Series returns
        """
        # Predici stati su dati training
        X = features.values
        states = self.model.predict(X)

        # Calcola statistiche per ogni stato
        n_states = self.hmm_config['n_components']

        state_stats = []
        for state in range(n_states):
            mask = (states == state)

            if returns is not None and mask.sum() > 0:
                mean_return = returns[mask].mean()
                std_return = returns[mask].std()
            else:
                mean_return = 0
                std_return = 0

            # Media ADX se disponibile
            if 'adx' in features.columns:
                mean_adx = features.loc[mask, 'adx'].mean()
            else:
                mean_adx = 50  # Default alto

            state_stats.append({
                'state': state,
                'mean_return': mean_return,
                'std_return': std_return,
                'mean_adx': mean_adx,
                'count': mask.sum()
            })

        # Ordina stati per mean_return
        state_stats_sorted = sorted(state_stats, key=lambda x: x['mean_return'])

        # Mapping:
        # - Stato con return più basso -> BEARISH (2)
        # - Stato con return più alto -> BULLISH (1)
        # - Stato medio -> LATERAL (3)

        if n_states == 3:
            self.state_mapping = {
                state_stats_sorted[0]['state']: 2,  # BEARISH
                state_stats_sorted[1]['state']: 3,  # LATERAL
                state_stats_sorted[2]['state']: 1   # BULLISH
            }

            # Se lo stato "medio" ha ADX basso, conferma come LATERAL
            middle_state = state_stats_sorted[1]['state']
            if state_stats_sorted[1]['mean_adx'] < self.state_config['adx_validation']['threshold']:
                # Conferma LATERAL
                pass
            else:
                # Se ADX alto anche per stato medio, potrebbe essere transizione
                # Manteniamo comunque come LATERAL per semplicità
                pass

        else:
            # Fallback: mapping semplice
            self.state_mapping = {i: (i % 3) + 1 for i in range(n_states)}

        # Salva statistiche
        self.state_statistics = {s['state']: s for s in state_stats}

    def _remap_probabilities(self, hmm_probs: np.ndarray) -> np.ndarray:
        """
        Rimappa probabilità da stati HMM a regimi

        Args:
            hmm_probs: Array probabilità stati HMM

        Returns:
            Array probabilità regimi [p_bull, p_bear, p_lateral]
        """
        regime_probs = np.zeros(3)

        for hmm_state, regime in self.state_mapping.items():
            regime_probs[regime - 1] += hmm_probs[hmm_state]

        return regime_probs

    def _validate_with_adx(self, regime: int, adx_current: Optional[float]) -> bool:
        """
        Valida regime con ADX
        Se regime è LATERAL e ADX è basso -> conferma
        Se regime è BULL/BEAR e ADX è alto -> conferma

        Args:
            regime: Regime predetto
            adx_current: Valore ADX corrente

        Returns:
            True se validato, False altrimenti
        """
        if not self.state_config['adx_validation']['enabled']:
            return True

        if adx_current is None:
            return True

        threshold = self.state_config['adx_validation']['threshold']

        if regime == 3:  # LATERAL
            # Se ADX basso -> conferma laterale
            return adx_current < threshold
        else:  # BULL o BEAR
            # Se ADX alto -> conferma trend
            return adx_current >= threshold

    def _check_persistence(self, regime: int, confidence: float) -> bool:
        """
        Check persistence per evitare flip-flop tra regimi

        Args:
            regime: Nuovo regime
            confidence: Confidence score

        Returns:
            True se cambio regime è persistente, False altrimenti
        """
        if not self.state_config['persistence']['enabled']:
            return True

        min_bars = self.state_config['persistence']['min_bars']
        hysteresis = self.state_config['persistence']['hysteresis']
        conf_threshold = self.state_config['confidence_threshold']

        # Se è il primo regime, accetta
        if self.current_regime is None:
            self.current_regime = regime
            self.consecutive_count = 1
            return True

        # Se regime uguale al precedente
        if regime == self.current_regime:
            self.consecutive_count += 1
            return True

        # Se regime diverso
        else:
            # Richiedi confidence maggiore per cambio
            required_confidence = conf_threshold + hysteresis

            if confidence >= required_confidence:
                self.consecutive_count = 1
                self.current_regime = regime
                return True
            else:
                # Mantieni regime precedente
                return False

    def _get_previous_probs(self) -> np.ndarray:
        """Ottieni probabilità del regime precedente (placeholder)"""
        # In caso di non-persistence, restituisce probs uniformi
        # Idealmente dovremmo memorizzare le probs precedenti
        if self.current_regime:
            probs = np.zeros(3)
            probs[self.current_regime - 1] = 0.8
            probs[probs == 0] = 0.1
            return probs
        else:
            return np.array([0.33, 0.33, 0.34])

    def get_transition_probabilities(self) -> np.ndarray:
        """
        Ottiene matrice di transizione tra regimi

        Returns:
            Matrice 3x3 probabilità transizione
        """
        if not self.is_fitted:
            return np.eye(3)

        # Transition matrix HMM
        hmm_transmat = self.model.transmat_

        # Rimappa a regimi (approssimazione)
        # Questo è semplificato - idealmente vorremmo aggregare correttamente
        return hmm_transmat

    def save_model(self, filepath: str) -> None:
        """Salva modello su file"""
        model_data = {
            'model': self.model,
            'state_mapping': self.state_mapping,
            'state_statistics': self.state_statistics,
            'is_fitted': self.is_fitted
        }

        with open(filepath, 'wb') as f:
            pickle.dump(model_data, f)

    def load_model(self, filepath: str) -> None:
        """Carica modello da file"""
        with open(filepath, 'rb') as f:
            model_data = pickle.load(f)

        self.model = model_data['model']
        self.state_mapping = model_data['state_mapping']
        self.state_statistics = model_data['state_statistics']
        self.is_fitted = model_data['is_fitted']

    def get_regime_stats(self) -> Dict:
        """
        Ottiene statistiche sui regimi identificati

        Returns:
            Dict con statistiche
        """
        if len(self.regime_history) == 0:
            return {}

        regime_counts = pd.Series(list(self.regime_history)).value_counts()

        return {
            'total_bars': len(self.regime_history),
            'bullish_count': regime_counts.get(1, 0),
            'bearish_count': regime_counts.get(2, 0),
            'lateral_count': regime_counts.get(3, 0),
            'bullish_pct': (regime_counts.get(1, 0) / len(self.regime_history)) * 100,
            'bearish_pct': (regime_counts.get(2, 0) / len(self.regime_history)) * 100,
            'lateral_pct': (regime_counts.get(3, 0) / len(self.regime_history)) * 100
        }


# ============================================================================
# ENSEMBLE DETECTOR (opzionale - per maggiore robustezza)
# ============================================================================

class EnsembleHMMDetector:
    """
    Ensemble di più modelli HMM per maggiore robustezza
    Mantiene N modelli storici e fa voting
    """

    def __init__(self, config: Dict, n_models: int = 3):
        """
        Args:
            config: Configurazione
            n_models: Numero modelli nell'ensemble
        """
        self.config = config
        self.n_models = n_models
        self.models = deque(maxlen=n_models)

    def add_model(self, detector: HMMRegimeDetector) -> None:
        """Aggiungi modello all'ensemble"""
        self.models.append(detector)

    def predict(self, features: pd.DataFrame, adx_current: Optional[float] = None) -> Dict:
        """
        Predizione ensemble tramite voting

        Args:
            features: DataFrame features
            adx_current: Valore ADX corrente

        Returns:
            Dict risultato (stesso formato di HMMRegimeDetector.predict)
        """
        if len(self.models) == 0:
            raise ValueError("Ensemble vuoto. Aggiungere modelli con add_model()")

        # Predizioni di tutti i modelli
        predictions = []
        for model in self.models:
            pred = model.predict(features, adx_current)
            predictions.append(pred)

        # Voting sui regimi
        regimes = [p['regime'] for p in predictions]
        regime_counts = pd.Series(regimes).value_counts()
        final_regime = regime_counts.idxmax()

        # Media delle probabilità
        all_probs = np.array([p['probabilities'] for p in predictions])
        mean_probs = all_probs.mean(axis=0)

        # Confidence = max probabilità media
        confidence = mean_probs.max()

        regime_names = {1: 'BULLISH', 2: 'BEARISH', 3: 'LATERAL'}

        return {
            'regime': final_regime,
            'regime_name': regime_names[final_regime],
            'probabilities': mean_probs,
            'confidence': confidence,
            'ensemble_agreement': regime_counts.max() / len(self.models),
            'individual_predictions': predictions
        }
