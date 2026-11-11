# Purpose: developer-time script. Synthesises every sound of the fantasy world (no recordings, no music) into
# assets/audio/fantasy/<name>.wav: spell casts (one per kind of substance, so a spell is also heard apart), the element
# plucks while channelling, impacts, gathering and crafting, UI ticks, creature and boss sounds, and one looping
# ambience per region (wind, birds, surf, storm ...). 22.05 kHz mono 16 bit keeps them small. Which sound plays when,
# and how loud, is data/fantasy/sounds.json.
# Run: python3 tools/make_fantasy_sounds.py   (from the project folder; needs pip package numpy)
import os
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "fantasy")
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def noise(seconds):
    return rng.uniform(-1.0, 1.0, int(RATE * seconds))


def lowpass(x, hz):
    """One-pole low-pass; hz may be a number or an array as long as x (a moving cutoff)."""
    a = 1.0 - np.exp(-2.0 * np.pi * np.broadcast_to(np.asarray(hz, dtype=float), x.shape) / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, hz):
    return x - lowpass(x, hz)


def band(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def env(n, attack, decay_power=2.0):
    """Rises over `attack` seconds, then falls away to nothing at the end."""
    e = np.linspace(1.0, 0.0, n) ** decay_power
    a = max(int(RATE * attack), 1)
    e[:a] *= np.linspace(0.0, 1.0, a)
    return e


def tone(freq, seconds, shape="sine"):
    """freq may be a number or an array (a glide)."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (int(RATE * seconds),))
    phase = 2.0 * np.pi * np.cumsum(f) / RATE
    if shape == "saw":
        return 2.0 * ((phase / (2.0 * np.pi)) % 1.0) - 1.0
    if shape == "square":
        return np.sign(np.sin(phase))
    return np.sin(phase)


def glide(a, b, seconds):
    return np.geomspace(a, b, int(RATE * seconds))


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, seconds):
    """x delayed by `seconds`."""
    return np.concatenate([np.zeros(int(RATE * seconds)), x])


def save(name, x, peak=0.9, loop=False):
    x = np.asarray(x, dtype=float)
    if loop:  # the end fades into the start so the loop has no click
        n = int(RATE * 0.5)
        fade = np.linspace(0.0, 1.0, n)
        x = np.concatenate([x[n:-n], x[-n:] * (1.0 - fade) + x[:n] * fade])
    x = x / max(np.abs(x).max(), 1e-9) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767.0).astype("<i2").tobytes())
    print(name, round(len(x) / RATE, 2), "s")


def chirps(seconds, count, lo, hi, length=0.09):
    """Scattered bird-like chirps."""
    out = np.zeros(int(RATE * seconds))
    for _ in range(count):
        start = rng.integers(0, len(out) - int(RATE * 0.5))
        f0 = rng.uniform(lo, hi)
        for k in range(rng.integers(1, 4)):
            n = int(RATE * length)
            c = tone(glide(f0, f0 * rng.uniform(0.8, 1.35), length), length) * env(n, 0.01, 1.5) * rng.uniform(0.2, 0.6)
            s = start + int(k * RATE * length * 1.4)
            out[s:s + n] += c[:len(out[s:s + n])]
    return out


def gusts(seconds, lo, hi, speed):
    """Wind: noise through a cutoff that wanders."""
    n = int(RATE * seconds)
    wander = lowpass(rng.uniform(-1, 1, n), speed)
    wander = (wander - wander.min()) / (wander.max() - wander.min() + 1e-9)
    w = lowpass(noise(seconds), lo + (hi - lo) * wander)
    return w * (0.55 + 0.45 * wander)


def main():
    os.makedirs(OUT, exist_ok=True)
    # --- spell casts: one per shape of substance ---
    n = int(RATE * 0.55)
    save("cast_drop", lowpass(noise(0.55), glide(2600, 500, 0.55)) * env(n, 0.03) + 0.4 * tone(glide(700, 240, 0.55), 0.55) * env(n, 0.02, 3))
    save("cast_flame", highpass(lowpass(noise(0.6), glide(900, 3200, 0.6)), 200) * env(int(RATE * 0.6), 0.08, 1.5) * (0.7 + 0.3 * np.sign(noise(0.6))))
    save("cast_rock", mix(tone(glide(110, 45, 0.5), 0.5) * env(int(RATE * 0.5), 0.005, 2.5), 0.6 * lowpass(noise(0.35), 500) * env(int(RATE * 0.35), 0.002, 3)))
    save("cast_gust", band(noise(0.6), 900, glide(1500, 5000, 0.6)) * env(int(RATE * 0.6), 0.15, 1.2))
    save("cast_puff", highpass(noise(0.7), 2500) * env(int(RATE * 0.7), 0.05, 1.4) * 0.8)
    save("cast_shard", mix(sum(tone(f, 0.5) for f in (2093, 2794, 3520)) * env(int(RATE * 0.5), 0.002, 3) * 0.3, highpass(noise(0.08), 3000) * env(int(RATE * 0.08), 0.001, 2)))
    save("cast_leaf", mix(sum(tone(f, 0.7) for f in (659, 880, 1319)) * env(int(RATE * 0.7), 0.12, 1.5) * 0.25, 0.3 * highpass(noise(0.7), 4000) * env(int(RATE * 0.7), 0.2, 1.5)))
    zap = tone(glide(1800, 300, 0.35), 0.35, "saw") * (rng.uniform(0, 1, int(RATE * 0.35)) > 0.35) * env(int(RATE * 0.35), 0.001, 1.5)
    save("cast_spark", mix(zap, 0.5 * highpass(noise(0.12), 2000) * env(int(RATE * 0.12), 0.001, 2)))
    bub = mix(*[at(tone(glide(f, f * 1.8, 0.07), 0.07) * env(int(RATE * 0.07), 0.01, 1.5), d) for f, d in ((180, 0.0), (240, 0.09), (150, 0.2), (300, 0.27), (200, 0.38))])
    save("cast_blob", mix(bub, 0.5 * lowpass(noise(0.5), 400) * env(int(RATE * 0.5), 0.05, 1.5)))
    save("cast_grain", band(noise(0.6), 1800, 6000) * env(int(RATE * 0.6), 0.1, 1.3) * (0.6 + 0.4 * tone(18, 0.6)))
    save("cast_prism", sum(tone(f, 0.9) * env(int(RATE * 0.9), 0.05 + 0.03 * i, 2) for i, f in enumerate((523, 659, 784, 988, 1175))) * 0.2)
    save("cast_big", mix(tone(glide(50, 140, 1.4), 1.4, "saw") * env(int(RATE * 1.4), 0.5, 1.2) * 0.5, lowpass(noise(1.6), glide(300, 4000, 1.6)) * env(int(RATE * 1.6), 0.7, 1.5)))
    save("impact", mix(tone(glide(160, 40, 0.4), 0.4) * env(int(RATE * 0.4), 0.002, 2.5), 0.7 * lowpass(noise(0.3), 1500) * env(int(RATE * 0.3), 0.001, 3)))
    # --- channelling: one pluck per element, a dull knock when the box is full or mana is out ---
    for name, f in (("element_w", 392), ("element_f", 523), ("element_e", 262), ("element_a", 659)):
        save(name, mix(tone(f, 0.25), 0.4 * tone(f * 2, 0.25), 0.2 * tone(f * 3, 0.25)) * env(int(RATE * 0.25), 0.003, 3), 0.7)
    save("refuse", tone(glide(160, 110, 0.18), 0.18, "square") * env(int(RATE * 0.18), 0.005, 1.5) * 0.5, 0.5)
    # --- gathering and crafting ---
    save("gather_woodcutting", mix(band(noise(0.12), 300, 2500) * env(int(RATE * 0.12), 0.001, 3), 0.7 * tone(glide(220, 150, 0.12), 0.12) * env(int(RATE * 0.12), 0.001, 3)))
    save("gather_mining", mix(sum(tone(f, 0.3) for f in (1760, 2637, 3951)) * env(int(RATE * 0.3), 0.001, 4) * 0.3, band(noise(0.06), 800, 5000) * env(int(RATE * 0.06), 0.001, 2)))
    save("gather_fishing", mix(lowpass(noise(0.4), glide(3000, 600, 0.4)) * env(int(RATE * 0.4), 0.01, 2), at(tone(glide(300, 620, 0.09), 0.09) * env(int(RATE * 0.09), 0.01, 1.5), 0.12)))
    save("gather_farming", band(noise(0.35), 1500, 7000) * env(int(RATE * 0.35), 0.04, 1.5) * (0.5 + 0.5 * np.abs(tone(9, 0.35))))
    save("gather_alchemy", mix(band(noise(0.2), 2000, 7000) * env(int(RATE * 0.2), 0.02, 2), 0.3 * tone(988, 0.2) * env(int(RATE * 0.2), 0.01, 3)))
    anvil = sum(tone(f, 0.6) * env(int(RATE * 0.6), 0.001, 3 + i) for i, f in enumerate((880, 1320, 2210, 3300))) * 0.25
    save("craft_forge", mix(anvil, band(noise(0.05), 500, 4000) * env(int(RATE * 0.05), 0.001, 2)))
    save("craft_workbench", mix(*[at(band(noise(0.07), 200, 1800) * env(int(RATE * 0.07), 0.001, 3), d) for d in (0.0, 0.16, 0.3)]))
    save("craft_fire", highpass(noise(0.9), 3000) * env(int(RATE * 0.9), 0.05, 1.2) * (0.5 + 0.5 * (rng.uniform(0, 1, int(RATE * 0.9)) > 0.6)))
    save("craft_cauldron", mix(*[at(tone(glide(f, f * 1.7, 0.08), 0.08) * env(int(RATE * 0.08), 0.01, 1.5), d) for f, d in ((200, 0.0), (260, 0.13), (170, 0.22), (320, 0.36), (230, 0.5), (280, 0.61))]))
    save("fire_light", highpass(lowpass(noise(0.8), glide(600, 3500, 0.8)), 150) * env(int(RATE * 0.8), 0.2, 1.3))
    save("item", mix(tone(784, 0.12), 0.5 * tone(1568, 0.12)) * env(int(RATE * 0.12), 0.003, 2.5), 0.5)
    save("drink", mix(*[at(tone(glide(240, 420, 0.07), 0.07) * env(int(RATE * 0.07), 0.01, 1.5), d) for d in (0.0, 0.12, 0.24)]), 0.6)
    arp = lambda notes, step, hold: mix(*[at(mix(tone(f, hold), 0.4 * tone(f * 2, hold)) * env(int(RATE * hold), 0.005, 2.5), i * step) for i, f in enumerate(notes)])
    save("level_up", arp((523, 659, 784, 1047), 0.09, 0.5), 0.75)
    save("quest_accept", arp((440, 587), 0.14, 0.4), 0.65)
    save("quest_step", arp((587, 740), 0.1, 0.3), 0.6)
    save("quest_done", arp((392, 523, 659, 784, 1047), 0.12, 0.8), 0.8)
    # --- UI ---
    save("ui_open", tone(glide(500, 760, 0.09), 0.09) * env(int(RATE * 0.09), 0.005, 2), 0.4)
    save("ui_close", tone(glide(700, 460, 0.09), 0.09) * env(int(RATE * 0.09), 0.005, 2), 0.4)
    save("ui_click", tone(900, 0.04) * env(int(RATE * 0.04), 0.002, 2), 0.35)
    save("ui_map", band(noise(0.25), 1200, 5000) * env(int(RATE * 0.25), 0.03, 1.5), 0.45)  # paper
    # --- creatures and bosses ---
    save("creature_fall", mix(tone(glide(140, 50, 0.45), 0.45) * env(int(RATE * 0.45), 0.01, 2), 0.5 * lowpass(noise(0.3), 700) * env(int(RATE * 0.3), 0.02, 2)))
    roar = tone(glide(95, 60, 1.3), 1.3, "saw") * (0.6 + 0.4 * tone(27, 1.3)) + 0.5 * lowpass(noise(1.3), 900)
    save("boss_wake", lowpass(roar, 1400) * env(int(RATE * 1.3), 0.15, 1.3))
    save("boss_warn", tone(glide(300, 620, 0.5), 0.5, "saw") * (0.5 + 0.5 * np.sign(tone(14, 0.5))) * env(int(RATE * 0.5), 0.03, 1.0) * 0.7, 0.6)
    save("boss_hit", mix(tone(glide(120, 32, 0.7), 0.7) * env(int(RATE * 0.7), 0.002, 2), lowpass(noise(0.5), 900) * env(int(RATE * 0.5), 0.001, 2.5)))
    save("clash", mix(sum(tone(f, 0.25) for f in (1245, 1870, 2960)) * env(int(RATE * 0.25), 0.001, 4) * 0.3, band(noise(0.05), 1000, 6000) * env(int(RATE * 0.05), 0.001, 2)), 0.6)
    # --- ambience, one loop per region (6 s, the end blends into the start) ---
    L = 6.5
    save("amb_amberfield", mix(0.5 * gusts(L, 300, 1100, 0.4), 0.35 * chirps(L, 9, 2400, 4200)), 0.5, True)
    save("amb_greenwald", mix(0.4 * gusts(L, 500, 2200, 0.6), 0.45 * chirps(L, 16, 1800, 5200), 0.2 * chirps(L, 3, 500, 700, 0.25)), 0.5, True)
    surf = lowpass(noise(L), 1300) * (0.35 + 0.65 * np.abs(np.sin(np.pi * t(L) / 3.25)) ** 2)
    save("amb_brinemouth", mix(surf, 0.2 * chirps(L, 4, 1400, 2100, 0.2)), 0.55, True)
    save("amb_sunscar", mix(0.7 * gusts(L, 200, 900, 0.3), 0.25 * band(noise(L), 3000, 7000) * (0.3 + 0.7 * np.abs(tone(0.2, L)))), 0.45, True)
    save("amb_frostmere", mix(gusts(L, 400, 1900, 0.8), 0.25 * tone(430 + 60 * lowpass(noise(L), 1.5), L) * (0.3 + 0.7 * np.abs(tone(0.17, L)))), 0.5, True)
    crackle = highpass(noise(L), 3500) * (rng.uniform(0, 1, int(RATE * L)) > 0.93)
    save("amb_cinderreach", mix(0.8 * lowpass(noise(L), 120) * 3.0, 0.5 * crackle, 0.3 * gusts(L, 200, 600, 0.3)), 0.5, True)
    thunder = at(lowpass(noise(2.2), glide(600, 60, 2.2)) * env(int(RATE * 2.2), 0.05, 1.6), 2.4)
    save("amb_stormcrown", mix(gusts(L, 500, 2600, 1.0), 0.8 * thunder), 0.55, True)
    save("amb_hollow_crown", mix(0.5 * tone(73, L) * (0.6 + 0.4 * tone(0.31, L)), 0.35 * tone(110.5, L) * (0.6 + 0.4 * tone(0.23, L)), 0.2 * gusts(L, 200, 700, 0.2)), 0.4, True)


if __name__ == "__main__":
    main()
