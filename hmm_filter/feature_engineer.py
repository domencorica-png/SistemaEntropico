"""
Feature Engineering Minimalista per HMM Trend Detection
GOLD 10min - Solo features essenziali e robuste
"""

import numpy as np
import pandas as pd
from typing import Dict, Optional
import warnings
warnings.filterwarnings('ignore')


class MinimalFeatureEngineer:
    """
    Feature engineering ottimizzato per GOLD 10min
    Solo 6-8 features core per evitare problemi di convergenza
    """

    def __init__(self, config: Dict):
        """
        Args:
            config: Dizionario configurazione da config.py
        """
        self.config = config
        self.feature_names = []

    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Trasforma OHLCV data in features per HMM

        Args:
            df: DataFrame con columns ['open', 'high', 'low', 'close', 'volume', 'time']

        Returns:
            DataFrame con features normalizzate
        """
        features = pd.DataFrame(index=df.index)

        # 1. MULTI-PERIOD RETURNS
        if self.config['returns']['enabled']:
            for period in self.config['returns']['periods']:
                col_name = f'ret_{period}p'
                features[col_name] = df['close'].pct_change(period)
                self.feature_names.append(col_name)

        # 2. VOLATILITY (ATR - essenziale per GOLD)
        if self.config['volatility']['enabled']:
            atr_period = self.config['volatility']['atr_period']
            features['atr'] = self._calculate_atr(df, atr_period)
            features['atr_normalized'] = features['atr'] / df['close']
            self.feature_names.extend(['atr', 'atr_normalized'])

        # 3. DIRECTIONALITY (ADX)
        if self.config['directionality']['enabled']:
            adx_period = self.config['directionality']['adx_period']
            adx_data = self._calculate_adx(df, adx_period)
            features['adx'] = adx_data['adx']
            features['di_diff'] = adx_data['di_plus'] - adx_data['di_minus']
            self.feature_names.extend(['adx', 'di_diff'])

        # 4. RANGE COMPRESSION
        if self.config['range']['enabled']:
            features['range_norm'] = (df['high'] - df['low']) / df['close']
            self.feature_names.append('range_norm')

        # 5. VOLUME ANALYSIS
        if self.config['volume']['enabled']:
            ma_period = self.config['volume']['ma_period']
            vol_ma = df['volume'].rolling(ma_period).mean()
            features['volume_ratio'] = df['volume'] / vol_ma
            # Clamp outliers
            features['volume_ratio'] = features['volume_ratio'].clip(0, 5)
            self.feature_names.append('volume_ratio')

        # 6. PRICE POSITION IN BAR
        if self.config['price_position']['enabled']:
            bar_range = df['high'] - df['low']
            # Evita divisione per zero
            bar_range = bar_range.replace(0, np.nan)
            features['price_position'] = (df['close'] - df['low']) / bar_range
            # Fill NaN con 0.5 (centro della barra)
            features['price_position'] = features['price_position'].fillna(0.5)
            self.feature_names.append('price_position')

        # PREPROCESSING
        # 1. Rimuovi infiniti e NaN
        features = features.replace([np.inf, -np.inf], np.nan)

        # 2. Forward fill limitato (max 3 bars)
        features = features.fillna(method='ffill', limit=3)

        # 3. Backward fill per i primi valori
        features = features.fillna(method='bfill', limit=3)

        # 4. Fill rimanenti con 0
        features = features.fillna(0)

        # 5. Normalizzazione Z-score (rolling per adattività)
        features_normalized = self._normalize_features(features, window=100)

        return features_normalized

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

    def _calculate_adx(self, df: pd.DataFrame, period: int = 14) -> Dict[str, pd.Series]:
        """
        Calcola ADX (Average Directional Index) e DI+/DI-

        Args:
            df: DataFrame OHLC
            period: Periodo ADX

        Returns:
            Dict con 'adx', 'di_plus', 'di_minus'
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

        return {
            'adx': adx,
            'di_plus': plus_di,
            'di_minus': minus_di
        }

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
        Ottiene ultimo valore ADX (usato per validazione stato laterale)

        Args:
            df: DataFrame OHLC

        Returns:
            Ultimo valore ADX
        """
        if not self.config['directionality']['enabled']:
            return None

        adx_period = self.config['directionality']['adx_period']
        adx_data = self._calculate_adx(df, adx_period)

        return adx_data['adx'].iloc[-1]


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def validate_dataframe(df: pd.DataFrame) -> bool:
    """
    Valida che il DataFrame abbia le colonne richieste

    Args:
        df: DataFrame da validare

    Returns:
        True se valido, altrimenti solleva eccezione
    """
    required_columns = ['open', 'high', 'low', 'close', 'volume']

    missing = set(required_columns) - set(df.columns)

    if missing:
        raise ValueError(f"DataFrame mancante di colonne: {missing}")

    # Check valori NaN
    if df[required_columns].isna().any().any():
        raise ValueError("DataFrame contiene valori NaN")

    # Check valori negativi
    if (df[['high', 'low', 'close', 'volume']] < 0).any().any():
        raise ValueError("DataFrame contiene valori negativi")

    # Check logica OHLC
    if (df['high'] < df['low']).any():
        raise ValueError("Trovati High < Low")

    if (df['close'] > df['high']).any() or (df['close'] < df['low']).any():
        raise ValueError("Close fuori dal range High-Low")

    return True


def resample_to_timeframe(df: pd.DataFrame, timeframe: str) -> pd.DataFrame:
    """
    Ricampiona dati a diverso timeframe (per multi-timeframe analysis)

    Args:
        df: DataFrame con index datetime
        timeframe: '30min', '1H', ecc.

    Returns:
        DataFrame ricampionato
    """
    # Assicurati che index sia datetime
    if not isinstance(df.index, pd.DatetimeIndex):
        if 'time' in df.columns:
            df = df.set_index('time')
        else:
            raise ValueError("DataFrame deve avere datetime index o colonna 'time'")

    # Ricampiona
    resampled = df.resample(timeframe).agg({
        'open': 'first',
        'high': 'max',
        'low': 'min',
        'close': 'last',
        'volume': 'sum'
    })

    # Rimuovi NaN
    resampled = resampled.dropna()

    return resampled
