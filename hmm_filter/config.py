"""
Configurazione per HMM Trend Filter - GOLD 10min
"""

# ============================================================================
# CONFIGURAZIONE GENERALE
# ============================================================================

SYMBOL = "XAUUSD"  # GOLD
TIMEFRAME = "10min"

# ============================================================================
# FEATURE ENGINEERING - MINIMAL SET (8 features core)
# ============================================================================

FEATURES_CONFIG = {
    # Multi-periodo returns (cattura momentum diverse scale temporali)
    'returns': {
        'periods': [1, 3, 6],  # 10min, 30min, 1h
        'enabled': True
    },

    # Volatilità (essenziale per GOLD)
    'volatility': {
        'atr_period': 14,
        'enabled': True
    },

    # Direzionalità (discrimina trend vs laterale)
    'directionality': {
        'adx_period': 14,
        'adx_threshold_lateral': 25,  # ADX < 25 = probabile laterale
        'enabled': True
    },

    # Range compression (identifica laterale/consolidamento)
    'range': {
        'enabled': True,
        'normalize': True  # (high-low)/close
    },

    # Volume analysis
    'volume': {
        'ma_period': 20,
        'enabled': True
    },

    # Price position in bar
    'price_position': {
        'enabled': True  # (close-low)/(high-low)
    }
}

# ============================================================================
# HMM CONFIGURATION
# ============================================================================

HMM_CONFIG = {
    # Numero di stati
    'n_components': 3,  # BULLISH (1), BEARISH (2), LATERAL (3)

    # Tipo di covarianza
    'covariance_type': 'full',  # Ogni stato ha propria matrice covarianza

    # Algoritmo
    'algorithm': 'viterbi',

    # Iterazioni per training
    'n_iter': 100,

    # Random state per riproducibilità
    'random_state': 42,

    # Toleranza convergenza
    'tol': 1e-2,

    # Verbose
    'verbose': False
}

# ============================================================================
# TRAINING & ONLINE LEARNING
# ============================================================================

TRAINING_CONFIG = {
    # Dimensione finestra training (circa 1 settimana di dati 10min)
    # 6 bars/ora × 24 ore × 5 giorni = 720 bars
    'training_window': 1000,

    # Minimo samples richiesti per primo training
    'min_samples': 500,

    # Frequenza retraining (ogni N nuove bars)
    'retrain_frequency': 100,

    # Walk-forward vs expanding window
    'walk_forward': True,  # True = finestra mobile, False = expanding

    # Numero di modelli storici da mantenere per ensemble
    'n_historical_models': 3
}

# ============================================================================
# STATE MAPPING & VALIDATION
# ============================================================================

STATE_CONFIG = {
    # Mapping stati HMM -> output
    # L'HMM identifica stati basandosi su features, poi li mappiamo
    # Stato con return medio più alto = BULLISH (1)
    # Stato con return medio più basso = BEARISH (2)
    # Stato intermedio o basso ADX = LATERAL (3)

    'mapping_strategy': 'auto',  # 'auto' = basato su statistiche, 'manual' = mapping fisso

    # Soglie per validazione stato
    'confidence_threshold': 0.65,  # Probabilità minima per accettare stato

    # Validazione ADX per conferma laterale
    'adx_validation': {
        'enabled': True,
        'threshold': 25,  # Se ADX < 25 e stato è lateral -> conferma
        'weight': 0.3  # Peso validazione ADX nella decisione finale
    },

    # Persistence check (evita flip-flop tra stati)
    'persistence': {
        'enabled': True,
        'min_bars': 3,  # Minimo 3 bars consecutivi per cambio stato
        'hysteresis': 0.1  # Margine isteresi per transizioni
    },

    # Output codes
    'output_codes': {
        'BULLISH': 1,
        'BEARISH': 2,
        'LATERAL': 3
    }
}

# ============================================================================
# DATA MANAGEMENT
# ============================================================================

DATA_CONFIG = {
    # Fonte dati
    'source': 'mt5',  # 'mt5', 'csv', 'api'

    # MetaTrader 5 integration
    'mt5': {
        'enabled': True,
        'terminal_path': None,  # None = auto-detect
        'login': None,  # Configurare se necessario
        'server': None
    },

    # CSV fallback
    'csv': {
        'input_path': './data/gold_10min.csv',
        'output_path': './output/hmm_regime.csv'
    },

    # File output per MT5
    'output_file': {
        'enabled': True,
        'path': './output/hmm_regime.txt',
        'format': 'simple'  # 'simple' = solo numero 1/2/3, 'detailed' = con metadata
    }
}

# ============================================================================
# LOGGING & MONITORING
# ============================================================================

LOGGING_CONFIG = {
    'enabled': True,
    'level': 'INFO',  # DEBUG, INFO, WARNING, ERROR
    'file': './logs/hmm_filter.log',
    'console': True,
    'format': '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
}

# ============================================================================
# BACKTESTING & VALIDATION
# ============================================================================

BACKTEST_CONFIG = {
    'enabled': False,
    'start_date': '2024-01-01',
    'end_date': '2024-12-31',
    'metrics': ['accuracy', 'regime_duration', 'transition_frequency']
}
