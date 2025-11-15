"""
Feature Engineering SEMPLIFICATO per HMM Trend Detection
GOLD 10min - SOLO 3 features essenziali per convergenza ottimale

Features:
1. Returns (momentum multi-periodo)
2. Volatility (ATR normalizzato)
3. Directionality (ADX)
"""

import numpy as np
import pandas as pd
from typing import Dict
import warnings
warnings.filterwarnings('ignore')


class SimpleFeatureEngineer:
    """
    Feature engineering minimalista con SOLO 3 features
    Ottimizzato per convergenza HMM
    """

    def __init__(self):
        """
        Configurazione hard-coded per semplicità
        Modificabile tramite config JSON esterno
        """
        # Periodi ottimizzati per GOLD 10min
        self.return_periods = [1, 3, 6]  # 10min, 30min, 1h
        self.atr_period = 14
        self.adx_period = 14

        self.feature_names = []

    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Trasforma OHLCV in 3 features essenziali

        Args:
            df: DataFrame con ['open', 'high', 'low', 'close', 'volume']

        Returns:
            DataFrame con 3 features normalizzate
        """
        features = pd.DataFrame(index=df.index)

        # 1. RETURNS MULTI-PERIODO (combinate in feature singola)
        returns_combined = self._calculate_combined_returns(df)
        features['momentum'] = returns_combined
        self.feature_names.append('momentum')

        # 2. VOLATILITY (ATR normalizzato)
        atr = self._calculate_atr(df, self.atr_period)
        atr_normalized = atr / df['close']  # Normalize by price
        features['volatility'] = atr_normalized
        self.feature_names.append('volatility')

        # 3. DIRECTIONALITY (ADX)
        adx = self._calculate_adx(df, self.adx_period)
        features['directionality'] = adx
        self.feature_names.append('directionality')

        # PREPROCESSING
        # 1. Remove inf/NaN
        features = features.replace([np.inf, -np.inf], np.nan)

        # 2. Forward fill (max 3 bars)
        features = features.fillna(method='ffill', limit=3)

        # 3. Backward fill for initial values
        features = features.fillna(method='bfill', limit=3)

        # 4. Fill remaining with 0
        features = features.fillna(0)

        # 5. Normalizzazione Z-score rolling
        features_normalized = self._normalize_features(features, window=100)

        return features_normalized

    def _calculate_combined_returns(self, df: pd.DataFrame) -> pd.Series:
        """
        Calcola returns combinati da multipli periodi
        Weighted average per catturare momentum su diverse scale

        Args:
            df: DataFrame OHLC

        Returns:
            Series con momentum combinato
        """
        returns_list = []
        weights = [0.5, 0.3, 0.2]  # Peso maggiore a short-term

        for i, period in enumerate(self.return_periods):
            ret = df['close'].pct_change(period)
            returns_list.append(ret * weights[i])

        # Combined weighted return
        combined = sum(returns_list)

        return combined

    def _calculate_atr(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
        """
        Calcola Average True Range

        Args:
            df: DataFrame OHLC
            period: Periodo ATR

        Returns:
            Series con valori ATR
        """
        high = df['high']
        low = df['low']
        close = df['close']

        # True Range
        tr1 = high - low
        tr2 = np.abs(high - close.shift(1))
        tr3 = np.abs(low - close.shift(1))

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

        # ATR = SMA del True Range
        atr = tr.rolling(period).mean()

        return atr

    def _calculate_adx(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
        """
        Calcola ADX (Average Directional Index)

        Args:
            df: DataFrame OHLC
            period: Periodo ADX

        Returns:
            Series con valori ADX
        """
        high = df['high']
        low = df['low']
        close = df['close']

        # Calcola +DM e -DM
        high_diff = high.diff()
        low_diff = -low.diff()

        plus_dm = high_diff.copy()
        minus_dm = low_diff.copy()

        plus_dm[~((high_diff > low_diff) & (high_diff > 0))] = 0
        minus_dm[~((low_diff > high_diff) & (low_diff > 0))] = 0

        # True Range
        tr1 = high - low
        tr2 = np.abs(high - close.shift(1))
        tr3 = np.abs(low - close.shift(1))
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

        # Smoothed TR e DM
        atr = tr.rolling(period).mean()
        plus_dm_smoothed = plus_dm.rolling(period).mean()
        minus_dm_smoothed = minus_dm.rolling(period).mean()

        # DI+ e DI-
        plus_di = 100 * (plus_dm_smoothed / atr)
        minus_di = 100 * (minus_dm_smoothed / atr)

        # DX
        dx = 100 * np.abs(plus_di - minus_di) / (plus_di + minus_di)

        # ADX
        adx = dx.rolling(period).mean()

        return adx

    def _normalize_features(self, df: pd.DataFrame, window: int = 100) -> pd.DataFrame:
        """
        Normalizzazione Z-score rolling (adattativa)

        Args:
            df: DataFrame features
            window: Finestra per calcolo media/std

        Returns:
            DataFrame normalizzato
        """
        normalized = pd.DataFrame(index=df.index)

        for col in df.columns:
            # Media e std rolling
            rolling_mean = df[col].rolling(window, min_periods=20).mean()
            rolling_std = df[col].rolling(window, min_periods=20).std()

            # Evita divisione per zero
            rolling_std = rolling_std.replace(0, 1)

            # Z-score
            normalized[col] = (df[col] - rolling_mean) / rolling_std

            # Clamp outliers a +/- 3 sigma
            normalized[col] = normalized[col].clip(-3, 3)

        # Fill NaN iniziali con 0
        normalized = normalized.fillna(0)

        return normalized

    def get_feature_names(self) -> list:
        """Ritorna lista nomi features"""
        return self.feature_names

    def get_adx_value(self, df: pd.DataFrame) -> float:
        """
        Ottiene ultimo valore ADX (per validazione laterale)

        Args:
            df: DataFrame OHLC

        Returns:
            Ultimo valore ADX
        """
        adx = self._calculate_adx(df, self.adx_period)
        return adx.iloc[-1]


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def validate_dataframe(df: pd.DataFrame) -> bool:
    """
    Valida che il DataFrame abbia le colonne richieste

    Args:
        df: DataFrame da validare

    Returns:
        True se valido
    """
    required_columns = ['open', 'high', 'low', 'close', 'volume']

    missing = set(required_columns) - set(df.columns)

    if missing:
        raise ValueError(f"DataFrame mancante di colonne: {missing}")

    if df[required_columns].isna().any().any():
        raise ValueError("DataFrame contiene valori NaN")

    if (df[['high', 'low', 'close', 'volume']] < 0).any().any():
        raise ValueError("DataFrame contiene valori negativi")

    if (df['high'] < df['low']).any():
        raise ValueError("Trovati High < Low")

    if (df['close'] > df['high']).any() or (df['close'] < df['low']).any():
        raise ValueError("Close fuori dal range High-Low")

    return True
