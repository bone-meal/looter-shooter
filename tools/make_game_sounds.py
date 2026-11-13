# Purpose: developer-time script. Synthesises the gun side's sounds and every enemy's attack sound (no recordings)
# into assets/audio/game/<name>.wav: the round stings, the islands' weather (thunder, the storm's rain loop), one shot per kind of gun, reloads, the dry click, explosions, and the blows,
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


def note(hz, seconds, wave="sine", vol=1.0, soft=2200):
    """One held note that dies away (the round stings are built from these)."""
    return lowpass(tone(hz, seconds, wave), soft) * env(n(seconds), 0.012, 1.6) * vol


def main():
    os.makedirs(F.OUT, exist_ok=True)
    save = F.save
    # --- the island's rounds: short musical stings ---
    save("sting_round", mix(note(196, 1.4, "saw", 0.5), at(note(233, 1.3, "saw", 0.5), 0.18), at(note(294, 1.7, "saw", 0.6), 0.36), lowpass(noise(2.0), 500) * env(n(2.0), 0.3, 1.2) * 0.2), 0.6)
    save("sting_round_end", mix(note(294, 1.2), at(note(370, 1.2), 0.12), at(note(440, 1.6), 0.24), at(note(587, 2.0), 0.36)), 0.55)
    save("sting_boss", mix(lowpass(tone(glide(55, 49, 2.4), 2.4, "saw"), 700) * env(n(2.4), 0.05, 1.0), at(note(98, 1.9, "saw", 0.7, 900), 0.3), at(note(104, 1.9, "saw", 0.6, 900), 0.3), lowpass(noise(2.4), 300) * env(n(2.4), 0.2, 1.0) * 0.5), 0.8)
    save("sting_special", mix(lowpass(tone(glide(440, 880, 0.9), 0.9, "saw"), 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * np.arange(n(0.9)) / RATE)) * env(n(0.9), 0.02, 1.0) * 0.5, at(note(659, 1.1, "saw", 0.4), 0.5), band(noise(1.3), 2000, 6000) * env(n(1.3), 0.1, 1.5) * 0.15), 0.6)
    # --- power-ups: one appears, one is taken, the nuke goes off ---
    save("powerup_drop", mix(note(784, 0.5, "sine", 0.5), at(note(988, 0.5, "sine", 0.5), 0.09), at(note(1175, 0.9, "sine", 0.6), 0.18), band(noise(1.1), 5000, 9000) * env(n(1.1), 0.05, 2.0) * 0.08), 0.5)
    save("powerup_grab", mix(note(392, 0.5, "saw", 0.5), note(494, 0.5, "saw", 0.4), at(note(587, 0.6, "saw", 0.5), 0.1), at(note(784, 1.2, "saw", 0.6), 0.2), at(note(1175, 1.0, "sine", 0.3), 0.2)), 0.6)
    save("powerup_nuke", mix(lowpass(noise(2.6), 900) * env(n(2.6), 0.004, 1.4), tone(glide(110, 28, 2.2), 2.2) * env(n(2.2), 0.002, 1.6) * 1.2, at(highpass(noise(0.5), 3000) * env(n(0.5), 0.001, 4) * 0.4, 0.0), at(lowpass(noise(1.8), 300) * env(n(1.8), 0.3, 1.2) * 0.7, 0.5)), 0.9)
    # --- the islands: debris sinks away, a wall gun is bought, a board is nailed back or torn off ---
    save("debris_clear", mix(lowpass(noise(1.8), 700) * env(n(1.8), 0.02, 1.3), at(crack(0.25, 120, 900, 1.2), 0.05), at(crack(0.3, 90, 700, 1.0), 0.35), at(crack(0.3, 70, 600, 0.9), 0.75), at(lowpass(noise(1.2), 2500) * env(n(1.2), 0.2, 1.5) * 0.35, 0.7)), 0.8)
    save("wall_buy", mix(click(1800, 0.04), at(click(900, 0.05), 0.07), at(note(659, 0.25, "sine", 0.5), 0.12), at(note(988, 0.6, "sine", 0.5), 0.22)), 0.6)
    save("board_fix", mix(crack(0.12, 220, 1500, 0.9, 4.0), at(crack(0.1, 260, 1800, 0.7, 4.0), 0.16)), 0.7)
    save("board_tear", mix(band(noise(0.35), 300, 1800) * env(n(0.35), 0.05, 1.2) * (0.6 + 0.4 * np.sin(2 * np.pi * 31 * np.arange(n(0.35)) / RATE)), at(crack(0.18, 150, 1000, 1.0), 0.28)), 0.75)
    # --- the islands' machines: power, perks, the mystery box and its seagull, the upgrade machine, traps ---
    save("part_take", mix(click(1400, 0.05), at(click(700, 0.06), 0.06), at(note(523, 0.3, "sine", 0.4), 0.08)), 0.6)
    save("power_on", mix(lowpass(tone(glide(40, 120, 1.6), 1.6, "saw"), 900) * env(n(1.6), 0.6, 0.6) * 0.9, at(crack(0.2, 180, 1200, 1.2), 0.0), at(note(392, 1.4, "saw", 0.3), 0.9), at(note(587, 1.6, "saw", 0.35), 1.1), band(noise(2.2), 100, 400) * env(n(2.2), 0.8, 0.8) * 0.3), 0.8)
    save("perk_buy", mix(click(1200, 0.05), at(lowpass(noise(0.5), 1800) * env(n(0.5), 0.02, 2.5) * 0.4, 0.05), at(note(523, 0.3, "saw", 0.4), 0.3), at(note(659, 0.3, "saw", 0.4), 0.42), at(note(784, 0.9, "saw", 0.5), 0.54)), 0.6)
    save("box_spin", mix(*[at(note(440 * 2 ** ((i * 5 % 12) / 12), 0.22, "sine", 0.45), 0.2 * i) for i in range(14)], at(note(880, 1.0, "sine", 0.5), 2.85)), 0.55)
    save("box_gull", mix(tone(glide(1500, 900, 0.35), 0.35, "saw") * env(n(0.35), 0.05, 1.2) * 0.4, at(tone(glide(1700, 1000, 0.3), 0.3, "saw") * env(n(0.3), 0.05, 1.2) * 0.4, 0.45), at(tone(glide(1600, 800, 0.5), 0.5, "saw") * env(n(0.5), 0.05, 1.0) * 0.4, 0.9)), 0.5)
    save("upgrade_done", mix(lowpass(tone(glide(200, 1200, 1.2), 1.2, "saw"), 3000) * env(n(1.2), 0.5, 0.8) * 0.5, at(crack(0.2, 300, 2500, 0.8), 1.15), at(note(988, 1.2, "sine", 0.5), 1.2)), 0.65)
    save("trap_zap", mix(band(noise(1.5), 1500, 7000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 55 * np.arange(n(1.5)) / RATE))) * env(n(1.5), 0.02, 0.7) * 0.6, tone(110, 1.5, "saw") * env(n(1.5), 0.02, 0.7) * 0.3), 0.6)
    save("trap_fire", mix(lowpass(noise(1.8), 1500) * env(n(1.8), 0.15, 0.8), band(noise(1.8), 300, 900) * env(n(1.8), 0.3, 0.7) * 0.6), 0.65)
    # --- the islands' weather: a thunderclap, and the storm rounds' looping bed (rain over a low wind with gusts, single drops ticking) ---
    save("thunder", mix(crack(0.25, 70, 900, 1.4, 1.5) * 0.7, at(lowpass(noise(3.2), glide(500, 50, 3.2)) * env(n(3.2), 0.04, 1.5), 0.05), at(lowpass(noise(2.0), 120) * env(n(2.0), 0.3, 1.2) * 0.8, 0.9)), 0.85)
    patter = highpass(noise(13.5), 5000) * (F.rng.uniform(0, 1, n(13.5)) > 0.985)
    save("amb_island_storm", mix(0.22 * band(noise(13.5), 700, 4200), 0.5 * F.breeze(13.5, 150, 800, 0.55), 0.12 * patter), 0.5, True)
    # --- buildables: a thing is hammered together; the shield stops a blow, bashes, and breaks ---
    save("build_done", mix(crack(0.12, 220, 1500, 0.9, 4.0), at(crack(0.12, 240, 1600, 0.9, 4.0), 0.22), at(crack(0.12, 200, 1400, 1.0, 4.0), 0.44), at(note(523, 0.5, "sine", 0.4), 0.6), at(note(784, 0.9, "sine", 0.45), 0.72)), 0.7)
    save("shield_block", mix(tone(glide(170, 90, 0.16), 0.16) * env(n(0.16), 0.002, 2.5), band(noise(0.1), 300, 1800) * env(n(0.1), 0.001, 3.0) * 0.7, at(tone(1900, 0.08) * env(n(0.08), 0.001, 4) * 0.15, 0.0)), 0.7)
    save("shield_bash", mix(band(noise(0.22), 250, glide(600, 2200, 0.22)) * env(n(0.22), 0.08, 1.2) * 0.6, at(tone(glide(140, 60, 0.2), 0.2) * env(n(0.2), 0.002, 2.5), 0.14)), 0.7)
    save("shield_break", mix(crack(0.3, 110, 900, 1.3, 2.0), at(band(noise(0.5), 400, 3000) * env(n(0.5), 0.01, 1.8) * 0.6, 0.05), at(crack(0.2, 160, 1300, 0.8, 3.0), 0.22), at(crack(0.15, 200, 1700, 0.6, 3.0), 0.4)), 0.8)
    # --- secrets: a hidden float or a quest lamp is hit (a glassy clink), a quest step is done (a low bell with a bright chord) ---
    save("secret_clink", mix(tone(2350, 0.5) * env(n(0.5), 0.001, 3.0) * 0.6, tone(3520, 0.35) * env(n(0.35), 0.001, 4.0) * 0.35, at(tone(2790, 0.4) * env(n(0.4), 0.001, 3.5) * 0.3, 0.05)), 0.55)
    save("quest_step", mix(tone(196, 2.4) * env(n(2.4), 0.003, 1.2) * 0.8, tone(392.5, 2.0) * env(n(2.0), 0.003, 1.4) * 0.35, tone(588, 1.6) * env(n(1.6), 0.003, 1.6) * 0.2, at(note(784, 0.9, "sine", 0.35), 0.35), at(note(988, 1.1, "sine", 0.35), 0.5)), 0.7)
    save("course_go", mix(note(660, 0.18, "square", 0.25), at(note(990, 0.25, "square", 0.25), 0.12)), 0.5)
    save("course_checkpoint", mix(note(880, 0.2, "sine", 0.5), at(note(1175, 0.3, "sine", 0.45), 0.09), at(note(1320, 0.35, "sine", 0.3), 0.18)), 0.6)
    save("course_finish", mix(note(523, 0.3, "sine", 0.45), at(note(659, 0.3, "sine", 0.45), 0.12), at(note(784, 0.3, "sine", 0.45), 0.24), at(note(1047, 0.8, "sine", 0.5), 0.36)), 0.7)
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
