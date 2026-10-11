#!/usr/bin/env python3
"""Generate PLACEHOLDER sound effects and music for Creature Arena.

    python3 tools/gen_audio.py        (needs numpy)

TODO(audio): every file this writes is a placeholder. Replace them with designed or
commissioned audio before release; docs/AUDIO.md lists each sound and what it's for.
Keep the same file names (or update data/audio.json) and nothing else has to change.

Everything here is synthesized from scratch (oscillators, filtered noise, envelopes), so
it is original and safe to ship in test builds. Output: 22.05 kHz, 16-bit mono WAV in
assets/audio/.
"""
import os
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 22050
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- building blocks

def t(dur):
    return np.arange(int(SR * dur)) / SR


def osc(freq, dur, shape="sine", duty=0.5):
    """An oscillator; `freq` is a number or an array (a sweep) of the same length."""
    n = int(SR * dur)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    phase = np.cumsum(f) / SR
    frac = phase % 1.0
    if shape == "sine":
        return np.sin(2 * np.pi * phase)
    if shape == "square":
        return np.where(frac < duty, 1.0, -1.0)
    if shape == "tri":
        return 4.0 * np.abs(frac - 0.5) - 1.0
    if shape == "saw":
        return 2.0 * frac - 1.0
    raise ValueError(shape)


def sweep(f0, f1, dur, curve=1.0):
    k = np.linspace(0.0, 1.0, int(SR * dur)) ** curve
    return f0 + (f1 - f0) * k


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(SR * dur))


def env(dur, attack=0.002, decay=None, curve=4.0):
    """A fast attack then an exponential-ish decay to silence at the end."""
    n = int(SR * dur)
    e = np.ones(n)
    a = max(1, int(SR * attack))
    e[:a] = np.linspace(0.0, 1.0, a)
    rest = n - a
    if rest > 0:
        e[a:] = (1.0 - np.linspace(0.0, 1.0, rest)) ** curve
    return e


def lowpass(x, cutoff):
    """One-pole low-pass; `cutoff` may be a number or an array."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def pad(x, dur):
    n = int(SR * dur)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:max(n, len(x))]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, start, total):
    """Place sound `x` at `start` seconds inside a buffer `total` seconds long."""
    out = np.zeros(int(SR * total))
    i = int(SR * start)
    j = min(len(out), i + len(x))
    out[i:j] += x[:j - i]
    return out


def save(name, x, peak_db=-3.0):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * (10 ** (peak_db / 20.0))
    # Tiny fades so nothing clicks.
    f = min(len(x) // 4, int(SR * 0.004))
    if f > 0:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {name}.wav  {len(x) / SR:.2f}s")


# ---------------------------------------------------------------- combat

def thump(f0, f1, dur, curve=3.0):
    return osc(sweep(f0, f1, dur, 0.5), dur) * env(dur, curve=curve)


def hit_light():
    d = 0.11
    return mix(thump(170, 70, d) * 0.9, lowpass(noise(0.045), 3500) * env(0.045, curve=3) * 0.8)


def hit_heavy():
    d = 0.24
    crunch = lowpass(noise(0.12), sweep(4000, 600, 0.12)) * env(0.12, curve=2)
    body = np.tanh(thump(120, 40, d, 2.5) * 2.2)
    return mix(body, crunch * 0.9)


def block():
    d = 0.09
    tick = (osc(1500, d, "square", 0.3) * 0.5 + osc(2350, d, "square", 0.25) * 0.4) * env(d, curve=6)
    return mix(tick, highpass(noise(0.03), 2500) * env(0.03) * 0.4)


def guard_break():
    d = 0.5
    glass = (osc(2800, d) + osc(3720, d) * 0.7 + osc(5100, d) * 0.4) * env(d, curve=5) * 0.4
    shatter = bandpass(noise(0.3), 1500, 7000) * env(0.3, curve=2)
    return mix(glass, shatter, thump(150, 50, 0.25) * 0.8)


def swing(lo, hi, dur, vol=1.0):
    n = noise(dur)
    s = bandpass(n, sweep(lo, hi * 0.6, dur), sweep(lo * 2, hi, dur))
    shape = np.sin(np.linspace(0, np.pi, len(s))) ** 1.5
    return s * shape * vol


def swing_light():
    return swing(600, 3200, 0.09)


def swing_heavy():
    return swing(250, 1400, 0.2)


def dodge():
    return swing(1800, 500, 0.16) * 0.8


def land():
    return mix(thump(110, 50, 0.12), lowpass(noise(0.05), 800) * env(0.05) * 0.6)


def slam():
    d = 0.7
    boom = np.tanh(thump(85, 28, d, 2.0) * 2.5)
    rumble = lowpass(noise(d), 300) * env(d, curve=1.5) * 1.5
    crack = highpass(noise(0.05), 1500) * env(0.05) * 0.7
    return mix(boom, rumble, crack)


def crack():
    total = 0.35
    out = np.zeros(int(SR * total))
    for k in range(9):
        s = rng.uniform(0, total * 0.7)
        c = highpass(noise(0.012), 1200) * env(0.012, curve=2) * rng.uniform(0.4, 1.0)
        out += at(c, s, total)
    return mix(out, lowpass(noise(total), 500) * env(total) * 0.3)


def bubbles(total, count, lo=500, hi=1300):
    out = np.zeros(int(SR * total))
    for k in range(count):
        d = rng.uniform(0.02, 0.05)
        f = rng.uniform(lo, hi)
        b = osc(sweep(f, f * 1.8, d), d) * env(d, curve=2) * rng.uniform(0.3, 0.8)
        out += at(b, rng.uniform(0, total - d), total)
    return out


def splash():
    d = 0.35
    wash = bandpass(noise(d), 700, 4500) * env(d, curve=2.5)
    return mix(wash, bubbles(d, 8) * 0.7)


def wave_launch():
    return mix(swing(400, 2200, 0.25) * 0.8, splash() * 0.8)


def gulp():
    d = 0.3
    vib = 1 + 0.08 * np.sin(2 * np.pi * 18 * t(d))
    g = osc(sweep(420, 110, d, 0.7) * vib, d, "tri") * env(d, curve=1.5)
    return mix(g, bubbles(d, 4, 300, 700) * 0.5)


def spit():
    return mix(swing(900, 3000, 0.12), splash()[: int(SR * 0.2)] * 0.6)


def grab():
    return mix(gulp(), at(spit(), 0.18, 0.5))


def parry():
    d = 0.4
    return (osc(2093, d) + osc(3136, d) * 0.6 + osc(4186, d) * 0.3) * env(d, curve=4)


def breakaway():
    return mix(swing(300, 2500, 0.3), parry() * 0.4)


def windup_red():
    beep = lambda f: osc(f, 0.07, "square", 0.25) * env(0.07, attack=0.001, curve=1.2)
    return mix(at(beep(1320), 0.0, 0.2), at(beep(990), 0.09, 0.2))


def windup_gold():
    d = 0.25
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 22 * t(d))
    return (osc(1760, d) + osc(2640, d) * 0.5) * trem * env(d, attack=0.01, curve=2)


def fall():
    d = 0.7
    return osc(sweep(1100, 180, d, 0.7), d, "tri") * np.linspace(1, 0, int(SR * d)) ** 1.5 * 0.7


def ko():
    d = 1.1
    boom = np.tanh(thump(70, 24, d, 1.8) * 3.0)
    bell = (osc(220, d) + osc(331, d) * 0.6 + osc(554, d) * 0.3) * env(d, curve=3) * 0.5
    return mix(boom, bell, lowpass(noise(0.4), 1200) * env(0.4) * 0.6)


def stones_scatter():
    total = 1.0
    out = np.zeros(int(SR * total))
    s = 0.0
    gap = 0.12
    amp = 1.0
    while s < total - 0.05 and gap > 0.012:
        for _ in range(rng.integers(1, 3)):
            f = rng.uniform(900, 2200)
            c = (osc(f, 0.04) * 0.6 + bandpass(noise(0.04), 800, 4000)) * env(0.04, curve=3) * amp
            out += at(c, s + rng.uniform(0, 0.02), total)
        s += gap
        gap *= 0.85
        amp *= 0.82
    return out


def water_gush():
    d = 1.2
    gurgle = 1 + 0.5 * np.sin(2 * np.pi * 7 * t(d)) * np.sin(2 * np.pi * 1.3 * t(d))
    flow = bandpass(noise(d), 400, 2500) * gurgle * env(d, attack=0.05, curve=1.2)
    return mix(flow, bubbles(d, 18, 300, 900) * 0.6)


def geysers():
    d = 0.9
    jet = highpass(noise(d), 1200) * env(d, attack=0.08, curve=1.5)
    return mix(jet * 0.8, bubbles(d, 14) * 0.5, splash() * 0.6)


def spire():
    return mix(slam()[: int(SR * 0.45)] * 0.7, crack())


def surge():
    """Rising arpeggio for a Surge cut-in."""
    notes = [440, 554, 659, 880, 1109, 1319, 1760]
    step = 0.045
    total = step * len(notes) + 0.25
    out = np.zeros(int(SR * total))
    for i, f in enumerate(notes):
        n = osc(f, 0.12, "square", 0.25) * env(0.12, curve=2) * 0.5
        out += at(n, i * step, total)
    rise = swing(400, 4000, total) * 0.6
    return mix(out, rise)


def crowd(dur, swell):
    """A stadium crowd: broad band noise with a slow swell and scattered voices."""
    base = bandpass(noise(dur), 250, 2600)
    k = np.linspace(0, 1, int(SR * dur))
    shape = np.sin(np.pi * np.clip(k * swell, 0, 1)) ** 0.7 * (1 - k) ** 0.6
    voices = np.zeros(int(SR * dur))
    for _ in range(int(dur * 20)):
        d = rng.uniform(0.08, 0.25)
        f = rng.uniform(300, 900)
        v = osc(sweep(f, f * rng.uniform(1.1, 1.5), d), d, "saw")
        voices += at(lowpass(v, 1800) * env(d, attack=0.02, curve=1.5) * rng.uniform(0.1, 0.3),
                     rng.uniform(0, dur - d), dur)
    return base * shape + voices * shape


# ---------------------------------------------------------------- UI and rounds

def ui_move():
    return osc(880, 0.035, "square", 0.25) * env(0.035, curve=1.5)


def ui_select():
    a = osc(880, 0.05, "square", 0.25) * env(0.05, curve=1.2)
    b = osc(1320, 0.08, "square", 0.25) * env(0.08, curve=1.5)
    return mix(at(a, 0, 0.14), at(b, 0.05, 0.14))


def bell(f=880, d=1.2):
    return (osc(f, d) + osc(f * 2.76, d) * 0.4 + osc(f * 5.4, d) * 0.15) * env(d, attack=0.001, curve=3)


def round_start():
    return bell(880, 1.0)


def round_end():
    return mix(at(bell(660, 0.9), 0, 1.6), at(bell(660, 0.9), 0.25, 1.6), at(bell(660, 0.9), 0.5, 1.6))


# ---------------------------------------------------------------- music

def note_freq(n):
    """MIDI note number to Hz."""
    return 440.0 * 2 ** ((n - 69) / 12.0)


def song(bpm, chords, lead, bass_oct=-2, swing_hats=False, bars=8):
    """A short chiptune loop: triangle bass, square lead, square arpeggios, noise drums.
    `chords` is one root note per bar (MIDI numbers, minor triads); `lead` is a list of
    (bar, beat, note, beats) events."""
    beat = 60.0 / bpm
    total = beat * 4 * bars
    n = int(SR * total)
    out = np.zeros(n)

    def place(x, when):
        i = int(SR * when)
        j = min(n, i + len(x))
        out[i:j] += x[:j - i]

    for b in range(bars):
        root = chords[b % len(chords)]
        triad = [root, root + 3, root + 7]
        t0 = b * 4 * beat
        # Bass: root on 1 and 3, fifth on 2 and 4, in eighths.
        for k in range(8):
            nn = root + 12 * bass_oct + (7 if k % 4 == 2 else 0)
            d = beat * 0.45
            place(osc(note_freq(nn), d, "tri") * env(d, attack=0.003, curve=0.8) * 0.55, t0 + k * beat / 2)
        # Arpeggio in sixteenths, quiet.
        for k in range(16):
            nn = triad[k % 3] + 12
            d = beat / 4 * 0.9
            place(osc(note_freq(nn), d, "square", 0.125) * env(d, curve=2) * 0.12, t0 + k * beat / 4)
        # Drums: kick on 1 and 3, snare on 2 and 4, hats on eighths.
        for k in range(4):
            if k % 2 == 0:
                place(thump(150, 45, 0.15) * 0.8, t0 + k * beat)
            else:
                place(bandpass(noise(0.12), 900, 6000) * env(0.12, curve=3) * 0.45, t0 + k * beat)
        for k in range(8):
            off = beat / 2 * k + (beat * 0.08 if swing_hats and k % 2 else 0)
            place(highpass(noise(0.03), 6000) * env(0.03, curve=3) * 0.18, t0 + off)

    for (bar, bt, nn, beats) in lead:
        d = beats * beat * 0.92
        vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t(d))
        place(osc(note_freq(nn) * vib, d, "square", 0.25) * env(d, attack=0.005, curve=0.6) * 0.3,
              (bar * 4 + bt) * beat)
    return out


def music_fight():
    # A minor, driving: Am F C G pattern.
    chords = [57, 53, 60, 55, 57, 53, 55, 52]
    lead = []
    phrase = [(0, 76, 1), (1, 74, 0.5), (1.5, 72, 0.5), (2, 71, 1), (3, 72, 1)]
    phrase2 = [(0, 77, 1.5), (1.5, 76, 0.5), (2, 74, 1), (3, 72, 1)]
    for bar in range(8):
        p = phrase if bar % 2 == 0 else phrase2
        shift = 0 if bar < 4 else (2 if bar % 2 == 0 else -1)
        for (bt, nn, beats) in p:
            lead.append((bar, bt, nn + shift, beats))
    return song(132, chords, lead)


def music_menu():
    chords = [57, 62, 53, 52]
    lead = []
    for bar in range(8):
        base = [69, 72, 76, 74][bar % 4]
        lead += [(bar, 0, base, 2), (bar, 2, base - 2, 1), (bar, 3, base - 5, 1)]
    return song(96, chords, lead, swing_hats=True)


# ---------------------------------------------------------------- Craglash

def roar():
    """A rumbling growl: a low buzzy voice with a wobble, over gravel."""
    d = 0.9
    wob = 1 + 0.08 * np.sin(2 * np.pi * 9 * t(d))
    voice = osc(sweep(95, 70, d) * wob, d, "saw") * 0.6 + osc(sweep(190, 140, d) * wob, d, "square", 0.3) * 0.2
    voice = lowpass(np.tanh(voice * 2.0), 900) * env(d, attack=0.06, curve=1.6)
    grit = bandpass(noise(d), 200, 1200) * env(d, attack=0.05, curve=2) * 0.5
    return mix(voice, grit)


def stoneskin():
    """Gravel clicking into place, rising, with a soft ring."""
    total = 0.45
    out = np.zeros(int(SR * total))
    for k in range(10):
        f = 700 + k * 140
        c = (osc(f, 0.03) * 0.5 + bandpass(noise(0.03), 600, 3500)) * env(0.03, curve=3) * (0.4 + k * 0.05)
        out += at(c, k * 0.032, total)
    ring = (osc(660, total) + osc(990, total) * 0.5) * env(total, attack=0.2, curve=3) * 0.25
    return mix(out, ring)


def shield_break():
    return mix(crack() * 0.8, stones_scatter()[: int(SR * 0.5)] * 0.7, thump(160, 60, 0.2) * 0.6)


def lash():
    """A whip of stone: a fast whoosh, then a clatter of segments snapping straight."""
    total = 0.35
    out = at(swing(300, 2400, 0.18), 0.0, total)
    for k in range(5):
        c = (osc(1100 + 120 * k, 0.025) * 0.4 + bandpass(noise(0.025), 900, 4000)) * env(0.025, curve=3)
        out += at(c * 0.6, 0.14 + k * 0.022, total)
    return out


def avalanche():
    """The neck crashing down: a deep boom, then rocks raining and rolling."""
    total = 1.4
    boom = at(np.tanh(thump(70, 22, 0.9, 1.8) * 3.0), 0.0, total)
    rumble = lowpass(noise(total), 250) * env(total, attack=0.02, curve=1.3) * 1.4
    rocks = at(stones_scatter(), 0.15, total) * 0.8
    return mix(boom, rumble, rocks)


# Added after the first batch, so they're generated last and the older placeholders
# (which share one random stream) come out the same as before.
NEW_SOUNDS = {
    "roar": roar, "stoneskin": stoneskin, "shield_break": shield_break, "lash": lash,
    "avalanche": avalanche,
}


# ---------------------------------------------------------------- main

SOUNDS = {
    "hit_light": hit_light, "hit_heavy": hit_heavy, "block": block, "guard_break": guard_break,
    "swing_light": swing_light, "swing_heavy": swing_heavy, "dodge": dodge, "land": land,
    "slam": slam, "crack": crack, "splash": splash, "wave": wave_launch, "grab": grab,
    "parry": parry, "breakaway": breakaway, "windup_red": windup_red, "windup_gold": windup_gold,
    "fall": fall, "ko": ko, "stones_scatter": stones_scatter, "water_gush": water_gush,
    "geysers": geysers, "spire": spire, "surge": surge,
    "crowd_cheer": lambda: crowd(1.6, 3.0), "crowd_roar": lambda: crowd(3.0, 4.0),
    "ui_move": ui_move, "ui_select": ui_select, "round_start": round_start, "round_end": round_end,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Writing PLACEHOLDER audio to", OUT)
    for name, fn in SOUNDS.items():
        save(name, fn())
    save("music_fight", music_fight(), peak_db=-6.0)
    save("music_menu", music_menu(), peak_db=-6.0)
    for name, fn in NEW_SOUNDS.items():
        save(name, fn())


if __name__ == "__main__":
    main()
