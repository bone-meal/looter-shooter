# Purpose: developer-time script (polish1 D4f). Synthesises the main quest's own sounds (no recordings) into
# assets/audio/game/<name>.wav: the drowned bell's toll (a deep bronze bell, three strokes) and a logbook's pages
# turning. Kept apart from tools/make_game_sounds.py so running it does not re-roll the other sounds. Loudness:
# data/sounds.json. Run: python3 tools/make_quest_sounds.py   (from the project folder; needs pip package numpy)
# Dependencies: tools/make_fantasy_sounds.py (helpers).
import os

import numpy as np

import make_fantasy_sounds as F
from make_fantasy_sounds import RATE, at, band, env, highpass, mix, noise

F.OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "game")


def n(seconds):
    return int(RATE * seconds)


def stroke(hz, seconds):
    """One bell stroke: a bronze bell's partials (hum, prime, tierce, quint, nominal) dying away at their own rates."""
    t = np.arange(n(seconds)) / RATE
    partials = ((0.5, 0.35, 0.6), (1.0, 0.6, 1.0), (1.2, 0.9, 0.5), (1.5, 1.3, 0.35), (2.0, 1.6, 0.45), (2.6, 2.4, 0.2), (3.3, 3.2, 0.12))
    tone = sum(np.sin(2 * np.pi * hz * f * t + f) * np.exp(-t * d) * a for f, d, a in partials)
    strike = highpass(noise(0.03), 2000) * env(n(0.03), 0.0005, 2) * 0.6
    return mix(tone * (1.0 + 0.08 * np.sin(2 * np.pi * 1.7 * t)), strike)


def main():
    os.makedirs(F.OUT, exist_ok=True)
    save = F.save
    save("bell_toll", mix(stroke(98, 6.0), at(stroke(98, 6.0) * 0.85, 2.2), at(stroke(98, 7.0) * 0.75, 4.4)), 0.85)
    save("book_page", mix(*[at(band(noise(0.22), 1500, 7000) * env(n(0.22), 0.05, 1.5) * 0.5, 0.3 * k) for k in range(3)]), 0.6)


if __name__ == "__main__":
    main()
