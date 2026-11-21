# Purpose: developer-time script (polish1 D4e). Synthesises the Re-forge quest's own sounds (no recordings) into
# assets/audio/game/<name>.wav: the cliff foghorn's blast, the Re-forge waking and its drop hammer striking. Kept apart
# from tools/make_game_sounds.py so running it does not re-roll the other sounds. Loudness: data/sounds.json.
# Run: python3 tools/make_reforge_sounds.py   (from the project folder; needs pip package numpy)
# Dependencies: tools/make_fantasy_sounds.py (helpers).
import os

import numpy as np

import make_fantasy_sounds as F
from make_fantasy_sounds import RATE, at, band, env, glide, highpass, lowpass, mix, noise, tone

F.OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "game")


def n(seconds):
    return int(RATE * seconds)


def horn(hz, seconds):
    """A deep reedy horn: two detuned saws through a low filter, swelling in and dying out slowly."""
    k = n(seconds)
    swell = np.minimum(np.arange(k) / (RATE * 0.35), 1.0) * np.linspace(1.0, 0.0, k) ** 0.6
    body = tone(hz, seconds, "saw") + tone(hz * 1.006, seconds, "saw") * 0.8 + tone(hz * 2.0, seconds, "square") * 0.15
    return lowpass(body, 520) * swell


def main():
    os.makedirs(F.OUT, exist_ok=True)
    save = F.save
    save("foghorn_blast", mix(horn(73, 2.6), at(horn(65, 2.8), 2.7), lowpass(noise(5.6), 200) * env(n(5.6), 0.3, 1.0) * 0.25), 0.85)
    save("reforge_wake", mix(lowpass(tone(glide(30, 70, 3.0), 3.0, "saw"), 400) * env(n(3.0), 1.2, 0.8),
                             band(noise(3.2), 60, 300) * env(n(3.2), 1.0, 0.9) * 0.6,
                             at(highpass(noise(0.6), 2500) * env(n(0.6), 0.2, 1.5) * 0.25, 1.6),
                             at(lowpass(tone(glide(400, 1400, 1.4), 1.4, "saw"), 2500) * env(n(1.4), 0.3, 1.2) * 0.3, 1.7),
                             at(tone(110, 2.0, "sine") * env(n(2.0), 0.01, 2.0) * 0.8, 2.6)), 0.85)
    ring_t = np.arange(n(1.6)) / RATE
    clang = sum(np.sin(2 * np.pi * f * ring_t) * np.exp(-ring_t * d) * a for f, d, a in ((523, 3.0, 0.6), (1190, 4.5, 0.4), (2210, 7.0, 0.25), (3480, 9.0, 0.15)))
    save("reforge_strike", mix(highpass(noise(0.02), 3000) * env(n(0.02), 0.0005, 2) * 1.2, clang, tone(glide(120, 50, 0.25), 0.25) * env(n(0.25), 0.001, 3) * 0.8), 0.8)


if __name__ == "__main__":
    main()
