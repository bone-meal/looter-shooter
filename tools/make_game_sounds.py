# Purpose: developer-time script. Synthesises the gun side's sounds and every enemy's attack sound (no recordings)
# into assets/audio/game/<name>.wav: one shot per kind of gun, reloads, the dry click, explosions, and the blows,
# bites, shots and wind-up of enemies and fantasy creatures. Which sound belongs to which gun or enemy is data
# (data/weapons.json "sound" / "reload_sound", "attack_sound" in data/enemies.json and data/fantasy/enemies.json);
# how loud and how far it carries is data/sounds.json. Uses the helpers of tools/make_fantasy_sounds.py.
# Run: python3 tools/make_game_sounds.py   (from the project folder; needs pip package numpy)
import os

import numpy as np

import make_fantasy_sounds as F
from make_fantasy_sounds import RATE, at, band, env, glide, highpass, lowpass, mix, noise, tone

F.OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "game")


def n(seconds):
    return int(RATE * seconds)


def crack(seconds, body_hz, bright_hz, thump=1.0, tail=2.5):
    """A gunshot: a bright burst of noise, a short low thump under it, and a duller tail."""
    snap = highpass(noise(0.03), bright_hz) * env(n(0.03), 0.0005, 3)
    body = tone(glide(body_hz, body_hz * 0.35, seconds), seconds) * env(n(seconds), 0.001, 3) * thump
    air = lowpass(noise(seconds), 2600) * env(n(seconds), 0.002, tail) * 0.6
    return mix(snap * 1.2, body, air)


def click(hz, seconds=0.03):
    return band(noise(seconds), hz * 0.6, hz * 1.6) * env(n(seconds), 0.0005, 3)


def main():
    os.makedirs(F.OUT, exist_ok=True)
    save = F.save
    # --- guns ---
    save("shot_pistol", crack(0.16, 190, 2500, 0.8))
    save("shot_rifle", crack(0.22, 150, 1800, 1.0))
    save("shot_carbine", crack(0.15, 210, 3000, 0.7))
    save("shot_lmg", crack(0.24, 110, 1500, 1.3))
    save("shot_sniper", mix(crack(0.3, 120, 2200, 1.2), at(lowpass(noise(0.6), 900) * env(n(0.6), 0.01, 1.6) * 0.5, 0.05)))
    save("shot_shotgun", mix(crack(0.3, 90, 1200, 1.5, 1.8), lowpass(noise(0.35), 1500) * env(n(0.35), 0.001, 2.2)))
    save("shot_rocket", mix(band(noise(0.55), 200, glide(600, 3500, 0.55)) * env(n(0.55), 0.02, 1.2), tone(glide(90, 50, 0.3), 0.3) * env(n(0.3), 0.002, 2.5)))
    save("shot_grenade", mix(tone(glide(170, 70, 0.22), 0.22) * env(n(0.22), 0.002, 2.5), lowpass(noise(0.12), 1200) * env(n(0.12), 0.001, 3) * 0.6))
    save("reload_mag", mix(click(1800), at(click(900, 0.05), 0.16), at(click(2400), 0.36), at(click(1300, 0.04), 0.42)), 0.6)
    save("reload_shells", mix(click(1100, 0.05), at(click(1000, 0.05), 0.2), at(click(2200), 0.44), at(click(700, 0.06), 0.5)), 0.6)
    save("reload_tube", mix(click(500, 0.08), at(tone(260, 0.1) * env(n(0.1), 0.002, 3) * 0.5, 0.05), at(click(1500, 0.04), 0.4)), 0.6)
    save("dry_fire", click(2600, 0.025), 0.4)
    save("explosion", mix(tone(glide(110, 30, 0.9), 0.9) * env(n(0.9), 0.002, 2.2) * 1.3, lowpass(noise(0.9), glide(3500, 300, 0.9)) * env(n(0.9), 0.001, 1.8), highpass(noise(0.05), 2000) * env(n(0.05), 0.0005, 3)))
    # --- enemies: the moment before a blow, and the blows ---
    save("atk_windup", mix(band(noise(0.3), 250, glide(500, 1800, 0.3)) * np.linspace(0.1, 1.0, n(0.3)), tone(glide(110, 190, 0.3), 0.3, "saw") * np.linspace(0.0, 0.5, n(0.3))) * env(n(0.3), 0.05, 0.4), 0.5)
    save("atk_blade", mix(band(noise(0.16), 900, glide(1500, 5000, 0.16)) * env(n(0.16), 0.05, 1.5), at(tone(glide(210, 90, 0.1), 0.1) * env(n(0.1), 0.001, 3), 0.11), at(tone(2900, 0.12) * env(n(0.12), 0.001, 4) * 0.25, 0.11)))
    save("atk_bite", mix(tone(glide(150, 95, 0.2), 0.2, "saw") * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * np.arange(n(0.2)) / RATE)) * env(n(0.2), 0.02, 1.5) * 0.7, at(click(1700, 0.04), 0.17), at(tone(glide(240, 110, 0.07), 0.07) * env(n(0.07), 0.001, 3), 0.17)))
    save("atk_claw", mix(band(noise(0.12), 1500, 6000) * env(n(0.12), 0.02, 1.5), at(band(noise(0.1), 1500, 6000) * env(n(0.1), 0.01, 1.8) * 0.8, 0.06), at(tone(glide(260, 120, 0.08), 0.08) * env(n(0.08), 0.001, 3) * 0.7, 0.12)))
    save("atk_slam", mix(tone(glide(120, 38, 0.4), 0.4) * env(n(0.4), 0.002, 2.5) * 1.3, lowpass(noise(0.25), 900) * env(n(0.25), 0.001, 2.5), at(band(noise(0.3), 200, 1500) * env(n(0.3), 0.02, 2) * 0.3, 0.08)))
    save("atk_squelch", mix(lowpass(noise(0.22), glide(2400, 500, 0.22)) * (0.5 + 0.5 * np.sin(2 * np.pi * 21 * np.arange(n(0.22)) / RATE)) * env(n(0.22), 0.01, 1.5), tone(glide(320, 140, 0.16), 0.16) * env(n(0.16), 0.005, 2) * 0.6))
    save("atk_swipe", mix(highpass(noise(0.2), 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * 55 * np.arange(n(0.2)) / RATE)) * env(n(0.2), 0.03, 1.2), at(tone(glide(200, 110, 0.07), 0.07) * env(n(0.07), 0.001, 3) * 0.6, 0.13)))
    save("atk_gust", band(noise(0.45), 250, glide(700, 2600, 0.45)) * env(n(0.45), 0.12, 1.2))
    save("atk_gun", crack(0.14, 230, 2800, 0.6), 0.7)
    save("atk_rifle", mix(crack(0.2, 160, 2200, 0.9), at(lowpass(noise(0.3), 1000) * env(n(0.3), 0.01, 1.8) * 0.4, 0.04)), 0.8)
    save("atk_dart", mix(band(noise(0.1), 2500, 7000) * env(n(0.1), 0.005, 2), tone(glide(1400, 700, 0.09), 0.09) * env(n(0.09), 0.002, 2.5) * 0.4), 0.6)
    save("atk_firebolt", mix(band(noise(0.35), 300, glide(2600, 700, 0.35)) * env(n(0.35), 0.02, 1.5), tone(glide(240, 120, 0.25), 0.25) * env(n(0.25), 0.005, 2) * 0.5))
    save("atk_hex", mix(tone(glide(900, 380, 0.3), 0.3) * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * np.arange(n(0.3)) / RATE)) * env(n(0.3), 0.01, 1.6), tone(glide(1350, 570, 0.3), 0.3) * env(n(0.3), 0.01, 2) * 0.4, highpass(noise(0.06), 3000) * env(n(0.06), 0.001, 3) * 0.4), 0.7)


if __name__ == "__main__":
    main()
