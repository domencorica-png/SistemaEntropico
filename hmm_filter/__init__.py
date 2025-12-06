"""
HMM Trend Filter for GOLD 10min
Sistema avanzato per identificazione regimi di mercato

Output:
    1 = BULLISH TREND (permetti trades long)
    2 = BEARISH TREND (permetti trades short)
    3 = LATERAL/CHAOTIC (blocca tutti i trades)
"""

from .hmm_trend_filter import HMMTrendFilter
from .config import (
    FEATURES_CONFIG,
    HMM_CONFIG,
    STATE_CONFIG,
    TRAINING_CONFIG,
    DATA_CONFIG
)

__version__ = "1.0.0"
__author__ = "Sistema Entropico"

__all__ = [
    'HMMTrendFilter',
    'FEATURES_CONFIG',
    'HMM_CONFIG',
    'STATE_CONFIG',
    'TRAINING_CONFIG',
    'DATA_CONFIG'
]
