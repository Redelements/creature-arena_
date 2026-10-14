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


# ---------------------------------------------------------------- Barkley

def creak(d=0.4, f0=180, f1=120):
    """Old wood bending: a slow, grainy squeak with a rough edge."""
    grain = 1 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * t(d)))
    v = osc(sweep(f0, f1, d) * (1 + 0.03 * np.sin(2 * np.pi * 7 * t(d))), d, "saw") * grain
    v = bandpass(np.tanh(v * 1.5), 250, 2200) * env(d, attack=0.05, curve=1.4)
    return v * 0.8


def snag():
    """Branch Grab: a whip of a branch, a creak as it hooks on, a yank back."""
    total = 0.5
    out = at(swing(500, 2000, 0.14), 0.0, total)
    out += at(creak(0.3, 260, 170), 0.1, total) * 0.8
    out += at(thump(140, 70, 0.12) * 0.5, 0.12, total)
    return out


def pinecone():
    """Pinecone Bomb lands: a dry crunchy pop and scattering scales."""
    total = 0.45
    pop = at(np.tanh(thump(220, 90, 0.18, 2.5) * 2.0) * 0.7, 0.0, total)
    out = pop
    for k in range(9):
        c = (bandpass(noise(0.02), 1500, 5000) + osc(900 + 160 * k, 0.02) * 0.3) * env(0.02, curve=3)
        out += at(c * 0.5, 0.03 + k * 0.03 + rng.uniform(0, 0.01), total)
    return out


def twister():
    """Timber Twister's last hit: a gust of wind and a rush of rustling leaves."""
    d = 0.7
    gust = bandpass(noise(d), 300, 1800) * env(d, attack=0.15, curve=1.8)
    rustle = bandpass(noise(d), 2500, 7000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 23 * t(d)))) \
        * env(d, attack=0.05, curve=2.2) * 0.6
    return mix(gust, rustle, at(thump(120, 60, 0.2) * 0.5, 0.0, d))


def roots():
    """Root Eruption: a deep rumble and wood splitting as roots burst out of the floor."""
    total = 1.2
    rumble = lowpass(noise(total), 180) * env(total, attack=0.05, curve=1.5) * 1.5
    boom = at(np.tanh(thump(60, 30, 0.7, 1.6) * 3.0), 0.0, total)
    out = mix(rumble, boom)
    for k in range(6):
        out += at(crack() * 0.35, 0.05 + k * 0.12, total)
    return out


def timber():
    """A felled tree: a long creak as it leans over."""
    return creak(0.9, 150, 70)


# ---------------------------------------------------------------- Gillbert

def flop():
    """A wet fish slapping the floor: a soft smack with a splash on top."""
    total = 0.22
    smack = at(np.tanh(thump(260, 110, 0.08, 2.0) * 2.5) * 0.7, 0.0, total)
    wet = at(bandpass(noise(0.16), 900, 5000) * env(0.16, attack=0.002, curve=3.0) * 0.7, 0.005, total)
    return mix(smack, wet)


def reel():
    """Cast Line hooks on: a zipping reel, ratcheting fast."""
    d = 0.45
    tick = (np.sin(2 * np.pi * 70 * t(d) * (1 + t(d) * 2)) > 0.6).astype(float)
    click = bandpass(noise(d), 2500, 7000) * tick * env(d, attack=0.01, curve=1.2)
    whir = osc(sweep(900, 1400, d), d, "tri") * env(d, attack=0.02, curve=2.0) * 0.25
    return mix(click, whir, at(swing(800, 2600, 0.12) * 0.6, 0.0, d))


def bellyflop():
    """The One That Got Away comes down: a huge slap and a wall of water."""
    total = 1.2
    slap = at(np.tanh(thump(90, 40, 0.4, 1.6) * 3.0), 0.0, total)
    water = lowpass(noise(total), 2600) * env(total, attack=0.01, curve=1.6) * 1.1
    drops = np.zeros(int(SR * total))
    for k in range(14):
        c = bandpass(noise(0.04), 1200, 4500) * env(0.04, curve=3) * 0.5
        drops += at(c, 0.25 + k * 0.05 + rng.uniform(0, 0.02), total)
    return mix(slap, water, drops)


# ---------------------------------------------------------------- Chef Cerebro

def knife_throw():
    """A small knife flicked: a thin, fast whoosh with a metallic shing."""
    d = 0.16
    whoosh = swing(1500, 6000, d, 0.8)
    shing = (osc(3400, d) * 0.5 + osc(5150, d) * 0.3) * env(d, attack=0.01, curve=4.0) * 0.35
    return mix(whoosh, shing)


def knife_hit():
    """A knife sinking in: a short, dull chunk."""
    d = 0.09
    return mix(thump(420, 160, d, 3.0) * 0.8, bandpass(noise(0.03), 1500, 5000) * env(0.03, curve=3) * 0.6)


def thwack():
    """Tenderize: a wooden meat mallet pounding down, with a meaty slap."""
    total = 0.3
    wood = (osc(sweep(520, 300, 0.12), 0.12, "tri") * env(0.12, curve=5)) * 0.8
    slap = bandpass(noise(0.08), 400, 2500) * env(0.08, curve=3) * 0.9
    return mix(at(np.tanh(thump(140, 60, 0.2, 2.0) * 2.0), 0.0, total), at(wood, 0.0, total), at(slap, 0.0, total))


def flip():
    """Flip Out: a spatula scrape, then a rising whoosh as they go over his head."""
    total = 0.5
    scrape = bandpass(noise(0.1), 2500, 7000) * env(0.1, attack=0.01, curve=2) * 0.5
    rise = swing(300, 2400, 0.32, 0.9)
    boing = osc(sweep(220, 520, 0.25), 0.25, "tri") * env(0.25, curve=3) * 0.3
    return mix(at(scrape, 0.0, total), at(rise, 0.06, total), at(boing, 0.1, total))


def chop_chop():
    """His voice line: two quick knife chops on a cutting board."""
    total = 0.42
    chop = mix(thump(300, 120, 0.07, 3.0), highpass(noise(0.02), 2500) * env(0.02) * 0.6)
    return mix(at(chop, 0.0, total), at(chop * 0.9, 0.18, total))


def fizzle():
    """The brain fizzles out: a sizzle that dies away, and a deflating squeak."""
    d = 0.9
    sizzle = highpass(noise(d), 3000) * env(d, attack=0.02, curve=1.5) * 0.4
    squeak = osc(sweep(700, 180, d, 0.7), d, "square", 0.3) * env(d, attack=0.05, curve=2.0) * 0.18
    return mix(sizzle, lowpass(squeak, 2000))


# ---------------------------------------------------------------- Hissy Fitz

def hiss():
    """Her voice line ("Hiss off!") and her KO: a long snake hiss that swells and fades."""
    d = 0.8
    h = bandpass(noise(d), 3500, 9000) * env(d, attack=0.12, curve=1.4) * 0.7
    rattle = (np.sin(2 * np.pi * 28 * t(d)) > 0.3).astype(float) * 0.35 + 0.65
    return h * rattle


def spit():
    """Venom Spit: a sharp wet "ptoo", a little hiss in front of it."""
    total = 0.24
    hs = bandpass(noise(0.08), 3000, 8000) * env(0.08, attack=0.03, curve=1.0) * 0.4
    pop = at(thump(500, 180, 0.06, 3.0) * 0.8, 0.07, total)
    wet = at(bandpass(noise(0.1), 900, 4000) * env(0.1, curve=3.0) * 0.5, 0.07, total)
    return mix(at(hs, 0.0, total), pop, wet)


def splat():
    """The glob lands: a soft wet splat."""
    d = 0.18
    return mix(bandpass(noise(d), 500, 2500) * env(d, attack=0.003, curve=2.5),
               thump(180, 90, 0.08, 2.5) * 0.6)


def poison_tick():
    """A poison pulse: a small sour bubble pop."""
    d = 0.12
    blip = osc(sweep(380, 760, d), d, "tri") * env(d, attack=0.005, curve=3.0) * 0.5
    return mix(blip, bandpass(noise(0.03), 1500, 4000) * env(0.03, curve=3) * 0.3)


def petrify():
    """Petrify Punch lands: a deep grinding rumble as the target turns to stone."""
    total = 0.9
    grind = lowpass(noise(total), 500) * env(total, attack=0.02, curve=1.6) * 1.2
    crunch = bandpass(noise(0.3), 800, 3000) * env(0.3, curve=2.0) * 0.4
    boom = np.tanh(thump(70, 35, 0.5, 1.8) * 2.5)
    return mix(at(boom, 0.0, total), grind, at(crunch, 0.05, total))


def shatter():
    """A statue shatters: a hard crack and a spill of stone chips."""
    total = 0.7
    out = at(crack() * 0.9, 0.0, total)
    for k in range(10):
        chip = bandpass(noise(0.03), 1800, 6000) * env(0.03, curve=3) * 0.35
        out = out + at(chip, 0.06 + k * 0.045 + rng.uniform(0, 0.02), total)
    return out


def gaze():
    """Stone Gaze: an eerie rising shimmer."""
    d = 0.7
    a = osc(sweep(600, 900, d), d, "sine") * 0.25
    b = osc(sweep(905, 1360, d), d, "sine") * 0.18
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 9 * t(d))
    return (a + b) * trem * env(d, attack=0.25, curve=1.2)


# ---------------------------------------------------------------- Digby

def dig():
    """Burrow: a scrabble of claws in loose dirt, sinking away."""
    d = 0.6
    out = np.zeros(int(SR * d))
    for k in range(9):
        c = bandpass(noise(0.05), 300, 1800) * env(0.05, curve=2.5) * (0.8 - k * 0.06)
        out += at(c, k * 0.06 + rng.uniform(0, 0.015), d)
    return mix(out, lowpass(noise(d), 250) * env(d, attack=0.1, curve=1.5) * 0.4)


def pop():
    """Bursting out of the ground: a soft thump and a spray of dirt."""
    total = 0.35
    thud = np.tanh(thump(150, 70, 0.18, 2.0) * 2.0)
    spray = bandpass(noise(0.25), 500, 3000) * env(0.25, attack=0.01, curve=2.2) * 0.6
    return mix(at(thud, 0.0, total), at(spray, 0.02, total))


def flash():
    """Headlamp Flash: a switch click and a bright electric zap."""
    total = 0.3
    click = highpass(noise(0.01), 3000) * env(0.01) * 0.8
    zap = osc(sweep(1800, 900, 0.22), 0.22, "square", 0.3) * env(0.22, attack=0.005, curve=2.5) * 0.25
    return mix(at(click, 0.0, total), at(lowpass(zap, 5000), 0.015, total))


def miss():
    """A blinded attack misses: an empty whoosh and a little falling "womp"."""
    d = 0.32
    return mix(swing(400, 1400, 0.18, 0.6), at(osc(sweep(330, 180, 0.2), 0.2, "tri") * env(0.2, curve=2) * 0.3,
                                                0.1, d))


def cave_in():
    """Cave-In: the floor gives way: a deep crunch, then rocks rumbling down."""
    total = 1.1
    rumble = lowpass(noise(total), 220) * env(total, attack=0.02, curve=1.4) * 1.3
    boom = at(np.tanh(thump(55, 28, 0.6, 1.6) * 3.0), 0.0, total)
    out = mix(rumble, boom)
    for k in range(8):
        out += at(crack() * 0.25, 0.08 + k * 0.1 + rng.uniform(0, 0.03), total)
    return out


def dig_it():
    """Placeholder for his voice line (a short rising "dig-dig!" of claws); the real one is
    his voice."""
    total = 0.4
    tap = mix(thump(500, 250, 0.05, 3.0), bandpass(noise(0.03), 800, 3000) * env(0.03) * 0.5)
    return mix(at(tap, 0.0, total), at(tap * 0.9, 0.12, total), at(tap * 1.1, 0.22, total))


# ---------------------------------------------------------------- Sneaky Pete

def coins():
    """Coins spilling: a handful of bright metallic chinks."""
    total = 0.5
    out = np.zeros(int(SR * total))
    for k in range(8):
        f = rng.uniform(3000, 5200)
        c = (osc(f, 0.06) * 0.5 + osc(f * 1.5, 0.06) * 0.3) * env(0.06, curve=4.0) * 0.4
        out += at(c, k * 0.045 + rng.uniform(0, 0.02), total)
    return out


def poof():
    """A puff of smoke: a soft airy whoomph."""
    d = 0.3
    return lowpass(noise(d), 1400) * env(d, attack=0.02, curve=2.2) * 0.9


def finders():
    """Placeholder for his voice line ("Finders keepers!"): a sly two-note whistle; the real
    one is his voice."""
    total = 0.5
    a = osc(1250, 0.16, "sine") * env(0.16, attack=0.02, curve=1.5) * 0.4
    b = osc(sweep(1400, 1100, 0.22), 0.22, "sine") * env(0.22, attack=0.02, curve=1.5) * 0.4
    return mix(at(a, 0.0, total), at(b, 0.2, total))


# ---------------------------------------------------------------- Sno Mercy

def freeze():
    """Frozen solid: a rising crackle of ice forming, a glassy ping on top."""
    d = 0.7
    out = np.zeros(int(SR * d))
    for k in range(14):
        c = highpass(noise(0.02), 4000) * env(0.02, curve=3) * (0.3 + k * 0.03)
        out += at(c, k * 0.035 + rng.uniform(0, 0.01), d)
    ping = (osc(2600, 0.5) * 0.4 + osc(3900, 0.5) * 0.2) * env(0.5, attack=0.01, curve=3.0) * 0.4
    return mix(out, at(ping, 0.2, d))


def shards():
    """Shaved Ice Spray: an icy hiss with little crystal tinkles."""
    d = 0.45
    hiss = bandpass(noise(d), 4000, 10000) * env(d, attack=0.02, curve=1.8) * 0.5
    out = hiss
    for k in range(6):
        f = rng.uniform(3500, 6000)
        out = out + at(osc(f, 0.05) * env(0.05, curve=4) * 0.25, k * 0.06 + 0.03, d)
    return out


def slosh():
    """Syrup Slick: a thick, sticky glug and splat."""
    total = 0.45
    glug = osc(sweep(220, 120, 0.25), 0.25, "sine") * env(0.25, attack=0.02, curve=2.0) * 0.6
    splat = bandpass(noise(0.2), 300, 1500) * env(0.2, attack=0.005, curve=2.5) * 0.6
    return mix(at(glug, 0.0, total), at(splat, 0.15, total))


def melt():
    """Sno Mercy's knockout: a slow sizzle and drip as he melts away."""
    d = 1.0
    sizzle = highpass(noise(d), 2500) * env(d, attack=0.05, curve=1.3) * 0.3
    out = sizzle
    for k in range(4):
        out = out + at(osc(sweep(900, 500, 0.08), 0.08, "sine") * env(0.08, curve=3) * 0.4, 0.15 + k * 0.2, d)
    return out


def chill():
    """Placeholder for his voice line ("Chill out."): a cold whistling gust; the real one is
    his voice."""
    d = 0.6
    gust = bandpass(noise(d), 600, 2400) * env(d, attack=0.15, curve=1.5) * 0.6
    tone = osc(sweep(900, 600, d), d, "sine") * env(d, attack=0.15, curve=1.5) * 0.2
    return mix(gust, tone)


def warp():
    """Chef Cerebro's teleport: a rising psychic shimmer that snaps off, then a soft pop."""
    d = 0.32
    rise = osc(sweep(500, 1900, 0.18), 0.18, "sine") * env(0.18, attack=0.06, curve=1.2) * 0.4
    shimmer = osc(sweep(1200, 3200, 0.18), 0.18, "sine") * osc(38, 0.18, "sine") * env(0.18, attack=0.05, curve=1.5) * 0.2
    pop = osc(sweep(900, 300, 0.1), 0.1, "sine") * env(0.1, curve=3.0) * 0.5
    return mix(at(rise, 0.0, d), at(shimmer, 0.0, d), at(pop, 0.17, d))


def surge_ready_ally():
    """Your (or your team's) Surge is ready: a rising power-up whoosh that blooms into a
    bright major chord with a sparkle on top. It should feel like a reward."""
    d = 1.0
    whoosh = bandpass(noise(0.55), 300, 3500)
    whoosh = lowpass(whoosh, sweep(500, 6000, 0.55, 1.6)) * env(0.55, attack=0.45, curve=1.2) * 0.55
    hum = osc(sweep(110, 220, 0.55, 1.5), 0.55, "saw")
    hum = lowpass(hum, 900) * env(0.55, attack=0.4, curve=1.0) * 0.25
    chord = np.zeros(int(SR * 0.6))
    for f in (523.25, 659.25, 783.99, 1046.5):  # C major, bright
        chord = chord + osc(f, 0.6, "square", 0.3) * 0.12 + osc(f * 1.003, 0.6, "sine") * 0.12
    chord = chord * env(0.6, attack=0.01, curve=2.2)
    sparkle = np.zeros(int(SR * 0.45))
    for i, f in enumerate((2093, 2637, 3136, 4186)):
        sparkle = sparkle + at(osc(f, 0.12, "sine") * env(0.12, curve=3.0) * 0.18, i * 0.05, 0.45)
    return mix(at(whoosh, 0.0, d), at(hum, 0.0, d), at(chord, 0.42, d), at(sparkle, 0.48, d))


def surge_ready_foe():
    """An opponent's Surge is ready: a low, uneasy swell of two clashing notes that throbs,
    then a dark gong. A warning, not a reward."""
    d = 1.1
    throb = osc(9, 0.7, "sine") * 0.35 + 0.65
    a = osc(sweep(98, 92, 0.7), 0.7, "saw")
    b = osc(sweep(104, 97, 0.7), 0.7, "saw")  # a semitone above: it grinds
    growl = lowpass(a + b, 700) * throb * env(0.7, attack=0.35, curve=1.3) * 0.35
    rumble = lowpass(noise(0.7), 180) * env(0.7, attack=0.3, curve=1.3) * 0.6
    gong_d = 0.7
    gong = (osc(73.4, gong_d) + osc(73.4 * 2.41, gong_d) * 0.5 + osc(73.4 * 3.9, gong_d) * 0.25)
    gong = gong * env(gong_d, attack=0.003, curve=2.6) * 0.5
    sting = osc(sweep(330, 311, 0.25), 0.25, "square", 0.4) * env(0.25, curve=2.0) * 0.12
    return mix(at(growl, 0.0, d), at(rumble, 0.0, d), at(gong, 0.38, d), at(sting, 0.4, d))


# Added after the first batch, so they're generated last and the older placeholders
# (which share one random stream) come out the same as before.
NEW_SOUNDS = {
    "roar": roar, "stoneskin": stoneskin, "shield_break": shield_break, "lash": lash,
    "avalanche": avalanche,
    "snag": snag, "pinecone": pinecone, "twister": twister, "roots": roots, "timber": timber,
    "flop": flop, "reel": reel, "bellyflop": bellyflop,
    "knife_throw": knife_throw, "knife_hit": knife_hit, "thwack": thwack, "flip": flip,
    "chop_chop": chop_chop, "fizzle": fizzle,
    "hiss": hiss, "spit": spit, "splat": splat, "poison_tick": poison_tick, "petrify": petrify,
    "shatter": shatter, "gaze": gaze,
    "dig": dig, "pop": pop, "flash": flash, "miss": miss, "cave_in": cave_in, "dig_it": dig_it,
    "coins": coins, "poof": poof, "finders": finders,
    "freeze": freeze, "shards": shards, "slosh": slosh, "melt": melt, "chill": chill,
    "warp": warp,
    "surge_ready_ally": surge_ready_ally, "surge_ready_foe": surge_ready_foe,
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
    # The placeholder music is retired (the composer's track replaced it), but it's still
    # generated and thrown away so the random draws, and the sounds made after it, stay
    # exactly as they were.
    music_fight()
    music_menu()
    for name, fn in NEW_SOUNDS.items():
        save(name, fn())


if __name__ == "__main__":
    main()
