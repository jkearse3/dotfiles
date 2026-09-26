"""Whether hashline's sessions take more or less time than stock's on a task,
and whether enough runs have been made to say.

Wall time is what the benchmark optimizes, but it is also its noisiest
metric, since API latency varies between runs. Rather than a fixed number of
runs, the runner adds runs to a task only while this comparison is unsure,
which spends sessions where the answer is in doubt.
"""

import math
from dataclasses import dataclass
from enum import StrEnum
from statistics import mean, stdev

# Ratios within this distance of 1 are too small to matter.
EQUIVALENCE_MARGIN = 0.1

# Two-sided 90% Student t critical values by degrees of freedom.
T_CRITICAL_90 = {1: 6.31, 2: 2.92, 3: 2.35, 4: 2.13, 5: 2.02, 6: 1.94, 7: 1.89, 8: 1.86, 9: 1.83}
T_CRITICAL_90_LARGE = 1.8


class Verdict(StrEnum):
    """How a task's hashline-to-stock ratio compares with 1."""

    LOWER = "lower"
    HIGHER = "higher"
    EQUIVALENT = "equivalent"
    UNSURE = "unsure"


@dataclass(frozen=True)
class RatioEstimate:
    """Mean hashline value over mean stock value, with a 90% confidence
    interval `low`..`high` and what it lets us conclude."""

    ratio: float
    low: float
    high: float
    verdict: Verdict


def compare_means(hashline: list[float], stock: list[float]) -> RatioEstimate | None:
    """Estimate the ratio of the means of two positive samples.

    The interval comes from the delta method on the log of the ratio, with
    the smaller sample's degrees of freedom. The verdict is `LOWER` or
    `HIGHER` when the interval excludes 1, `EQUIVALENT` when it lies within
    `EQUIVALENCE_MARGIN` of 1, and otherwise `UNSURE`. Returns None when
    either sample has fewer than two values or a non-positive mean.
    """
    if len(hashline) < 2 or len(stock) < 2:
        return None
    hashline_mean, stock_mean = mean(hashline), mean(stock)
    if hashline_mean <= 0 or stock_mean <= 0:
        return None

    ratio = hashline_mean / stock_mean
    spread = math.sqrt(
        stdev(hashline) ** 2 / (len(hashline) * hashline_mean**2)
        + stdev(stock) ** 2 / (len(stock) * stock_mean**2)
    )
    degrees = min(len(hashline), len(stock)) - 1
    critical = T_CRITICAL_90.get(degrees, T_CRITICAL_90_LARGE)
    low, high = ratio * math.exp(-critical * spread), ratio * math.exp(critical * spread)

    if high < 1:
        verdict = Verdict.LOWER
    elif low > 1:
        verdict = Verdict.HIGHER
    elif 1 - EQUIVALENCE_MARGIN <= low and high <= 1 + EQUIVALENCE_MARGIN:
        verdict = Verdict.EQUIVALENT
    else:
        verdict = Verdict.UNSURE
    return RatioEstimate(ratio=ratio, low=low, high=high, verdict=verdict)
