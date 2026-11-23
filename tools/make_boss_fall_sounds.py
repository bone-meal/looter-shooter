# Purpose: developer-time script (polish1 E4, item 131). Synthesises the two sounds of a great creature's end into
# assets/audio/fantasy/: boss_fall (a deep bell toll, the earth settling, a rising bright chord: the moment it is
# beaten) and echo_fade (a phantom thinning out: a hollow glassy swell falling away). No recordings, no music.
# Uses the helpers of tools/make_fantasy_sounds.py; loudness and range are data/fantasy/sounds.json.
# Run: python3 tools/make_boss_fall_sounds.py   (from the project folder; needs pip package numpy)
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import make_fantasy_sounds as s  # noqa: E402


def toll(freq, seconds):
    """A bell: a few inharmonic partials, each dying away at its own pace."""
    n = int(s.RATE * seconds)
    out = np.zeros(n)
    for ratio, loud, power in ((0.5, 0.5, 1.2), (1.0, 1.0, 1.8), (1.19, 0.45, 2.4), (1.56, 0.35, 3.0), (2.0, 0.3, 3.4), (2.74, 0.18, 4.0)):
        out += loud * s.tone(freq * ratio, seconds) * s.env(n, 0.004, power)
    return out


def boss_fall():
    L = 4.2
    n = int(s.RATE * L)
    settle = s.lowpass(s.noise(L), s.glide(900, 60, L)) * s.env(n, 0.02, 2.5) * 0.9  # the body comes down
    chord = s.mix(*[0.22 * s.tone(f, 3.2) * s.env(int(s.RATE * 3.2), 1.1, 1.6) for f in (220.0, 277.2, 329.6, 440.0)])  # a bright chord rising
    shimmer = s.highpass(s.noise(3.0), 3000) * s.env(int(s.RATE * 3.0), 1.4, 2.0) * 0.12
    return s.mix(toll(98.0, L) * 0.9, settle, s.at(chord, 0.5), s.at(shimmer, 0.7))


def echo_fade():
    L = 3.0
    n = int(s.RATE * L)
    hollow = s.mix(0.5 * s.tone(s.glide(660, 330, L), L), 0.35 * s.tone(s.glide(990, 495, L), L), 0.25 * s.tone(s.glide(1320, 520, L), L))
    swell = np.minimum(np.linspace(0.0, 4.0, n), 1.0) * np.linspace(1.0, 0.0, n) ** 1.5
    air = s.band(s.noise(L), 1500, 6000) * swell * 0.25
    return s.mix(hollow * swell * (0.75 + 0.25 * s.tone(5.5, L)), air)


if __name__ == "__main__":
    s.save("boss_fall", boss_fall(), 0.9)
    s.save("echo_fade", echo_fade(), 0.8)
