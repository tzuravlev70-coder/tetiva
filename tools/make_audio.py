"""Procedural audio for TETHER.

Generates a seamless music loop, a looping wind bed and all SFX as 16-bit WAV.
Run:  python tools/make_audio.py
"""
import math
import os
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "audio"))
os.makedirs(OUT, exist_ok=True)

rng = np.random.default_rng(7)


# ---------------------------------------------------------------- helpers
def n_of(dur):
    return int(round(dur * SR))


def tt(dur):
    return np.arange(n_of(dur)) / SR


def adsr(n, attack=0.005, decay=0.15, curve=2.5, sustain=0.0):
    """Fast attack, exponential decay."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    d = np.exp(-t * (3.0 / max(decay, 1e-4)))
    return a * d


def saw(phase):
    return 2.0 * (phase - np.floor(phase + 0.5))


def sine(freq, dur):
    t = tt(dur)
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * t)
    f = np.asarray(freq, dtype=np.float64)
    ph = np.cumsum(f) / SR
    return np.sin(2 * np.pi * ph)


def sweep(f0, f1, dur, curve=1.0):
    n = n_of(dur)
    x = np.linspace(0.0, 1.0, n) ** curve
    return f0 + (f1 - f0) * x


def lowpass_fft(x, cutoff, sr=SR, order=2.0):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    resp = 1.0 / np.sqrt(1.0 + (freqs / max(cutoff, 1.0)) ** (2 * order))
    return np.fft.irfft(spec * resp, len(x))


def highpass_fft(x, cutoff, sr=SR, order=2.0):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    ratio = (freqs / max(cutoff, 1.0)) ** (2 * order)
    resp = np.sqrt(ratio / (1.0 + ratio))
    return np.fft.irfft(spec * resp, len(x))


def fftconv(a, b):
    n = len(a) + len(b) - 1
    nfft = 1 << (n - 1).bit_length()
    fa = np.fft.rfft(a, nfft)
    fb = np.fft.rfft(b, nfft)
    return np.fft.irfft(fa * fb, nfft)[: len(a)]


def reverb(x, mix=0.22, decay=1.4, seed=3):
    n = n_of(decay)
    r = np.random.default_rng(seed)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / (0.30 * SR))
    ir[0] = 0.0
    ir = ir / np.sqrt(np.sum(ir ** 2))
    wet = fftconv(x, ir)
    wet = wet / (np.max(np.abs(wet)) + 1e-9)
    return (1.0 - mix) * x + mix * wet * np.max(np.abs(x) + 1e-9)


def fold_loop(x, n):
    """Wrap everything after n samples back onto the start (seamless loop)."""
    y = x[:n].copy()
    tail = x[n:]
    i = 0
    while i < len(tail):
        m = min(len(tail) - i, n)
        y[:m] += tail[i:i + m]
        i += m
    return y


def write_wav(name, left, right=None, sr=SR, gain=0.9):
    left = np.asarray(left, dtype=np.float64)
    if right is None:
        right = left
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)), 1e-9)
    left = np.tanh(left / peak * 1.1 * gain) / np.tanh(1.1)
    right = np.tanh(right / peak * 1.1 * gain) / np.tanh(1.1)
    data = np.empty(len(left) * 2, dtype=np.int16)
    data[0::2] = np.clip(left * 32767.0, -32768, 32767).astype(np.int16)
    data[1::2] = np.clip(right * 32767.0, -32768, 32767).astype(np.int16)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    print("wrote %-22s %.2fs" % (name, len(left) / sr))


# ---------------------------------------------------------------- music
def make_music():
    bpm = 92.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    bars = 4
    loop = bars * bar
    n_loop = n_of(loop)
    n_total = n_loop + n_of(2.5)
    L = np.zeros(n_total)
    R = np.zeros(n_total)
    arpL = np.zeros(n_total)
    arpR = np.zeros(n_total)

    def add(buf_l, buf_r, t0, mono, pan=0.0, gain=1.0):
        i = n_of(t0)
        if i >= n_total:
            return
        m = min(len(mono), n_total - i)
        gl = math.sqrt(0.5 * (1.0 - pan)) * gain
        gr = math.sqrt(0.5 * (1.0 + pan)) * gain
        buf_l[i:i + m] += mono[:m] * gl
        buf_r[i:i + m] += mono[:m] * gr

    # A minor / F major / C major / G major
    chords = [
        (55.00, [220.00, 261.63, 329.63, 392.00]),
        (43.65, [174.61, 220.00, 261.63, 329.63]),
        (65.41, [261.63, 329.63, 392.00, 493.88]),
        (49.00, [196.00, 246.94, 293.66, 392.00]),
    ]

    for b, (bass_note, chord) in enumerate(chords):
        t0 = b * bar

        # --- pad: detuned saws, slow swell
        for k, f in enumerate(chord[:3]):
            dur = bar + 0.9
            n = n_of(dur)
            t = np.arange(n) / SR
            ph1 = (f * 0.9985) * t
            ph2 = (f * 1.0015) * t
            v = (saw(ph1) + saw(ph2)) * 0.5
            v += np.sin(2 * np.pi * f * 0.5 * t) * 0.35
            env = np.minimum(t / 0.55, 1.0) * np.exp(-np.maximum(t - 0.9, 0) / 1.6)
            v = lowpass_fft(v * env, 1100.0)
            add(L, R, t0, v, pan=(-0.55 + 0.55 * k), gain=0.055)

        # --- bass: syncopated sub with a bit of grit
        pattern = [0.0, 1.5, 2.0, 3.5]
        for j, pos in enumerate(pattern):
            dur = beat * (0.8 if j != 3 else 0.6)
            n = n_of(dur)
            t = np.arange(n) / SR
            f = bass_note * (2.0 if j == 2 else 1.0)
            v = np.sin(2 * np.pi * f * t) + 0.25 * saw(f * 2.0 * t)
            env = adsr(n, 0.006, dur * 0.9, 2.0)
            add(L, R, t0 + pos * beat, lowpass_fft(v * env, 320.0), 0.0, 0.24)

        # --- arp: eight 8ths, chord tones up two octaves
        pattern_idx = [0, 2, 1, 3, 2, 1, 3, 2]
        for j, idx in enumerate(pattern_idx):
            note = chord[idx] * 2.0
            if j == 6:
                note *= 2.0
            dur = beat * 0.55
            n = n_of(dur)
            t = np.arange(n) / SR
            v = np.sin(2 * np.pi * note * t) + 0.42 * saw(note * 1.004 * t)
            env = adsr(n, 0.002, 0.16, 2.2)
            v = lowpass_fft(v * env, 4200.0)
            add(arpL, arpR, t0 + j * 0.5 * beat, v, pan=0.35 if j % 2 else -0.35, gain=0.085)

        # --- hats on offbeats
        for j in range(4):
            n = n_of(0.09)
            noise = rng.standard_normal(n)
            noise = highpass_fft(noise, 6500.0, order=1.0)
            env = adsr(n, 0.001, 0.035, 3.0)
            add(L, R, t0 + (j + 0.5) * beat, noise * env, pan=0.25, gain=0.05)

        # --- soft kick on 1 and 3
        for j in (0, 2):
            n = n_of(0.55)
            f = sweep(120.0, 44.0, 0.55, 0.45)
            t = np.arange(n) / SR
            v = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
            add(L, R, t0 + j * beat, v, 0.0, 0.30)

        # --- brushed snare on 2 and 4
        for j in (1, 3):
            n = n_of(0.28)
            noise = highpass_fft(rng.standard_normal(n), 1800.0, order=1.0)
            tone = np.sin(2 * np.pi * 185.0 * np.arange(n) / SR) * 0.4
            env = adsr(n, 0.001, 0.09, 2.0)
            add(L, R, t0 + j * beat, (noise * 0.8 + tone) * env, -0.1, 0.085)

    # ping-pong-ish delay on the arp
    d = n_of(0.75 * beat)
    arpL2, arpR2 = arpL.copy(), arpR.copy()
    for k in range(1, 5):
        g = 0.42 ** k
        shift = d * k
        arpL2[shift:] += arpR[: n_total - shift] * g
        arpR2[shift:] += arpL[: n_total - shift] * g

    L = L + arpL2
    R = R + arpR2

    # master: gentle tone shaping + space
    L = lowpass_fft(L, 9000.0)
    R = lowpass_fft(R, 9000.0)
    L = highpass_fft(L, 34.0)
    R = highpass_fft(R, 34.0)
    L = reverb(L, mix=0.26, decay=1.7, seed=11)
    R = reverb(R, mix=0.26, decay=1.7, seed=12)

    L = fold_loop(L, n_loop)
    R = fold_loop(R, n_loop)
    # remove DC and normalise the loop as a whole
    L -= np.mean(L)
    R -= np.mean(R)
    write_wav("music_loop.wav", L, R, gain=0.82)


# ---------------------------------------------------------------- sfx
def make_sfx():
    # attach: bright upward pluck
    dur = 0.20
    n = n_of(dur)
    t = np.arange(n) / SR
    f = sweep(620.0, 1500.0, dur, 0.55)
    v = np.sin(2 * np.pi * np.cumsum(f) / SR) * adsr(n, 0.002, 0.09, 2.0)
    v += 0.18 * rng.standard_normal(n) * adsr(n, 0.0005, 0.012, 3.0)
    write_wav("sfx_attach.wav", v, gain=0.55)

    # release: airy whoosh
    dur = 0.30
    n = n_of(dur)
    noise = rng.standard_normal(n)
    noise = lowpass_fft(noise, 3000.0) - lowpass_fft(noise, 700.0)
    env = np.exp(-np.arange(n) / (0.075 * SR)) * np.minimum(np.arange(n) / (0.008 * SR), 1.0)
    tone = np.sin(2 * np.pi * np.cumsum(sweep(520.0, 170.0, dur, 0.7)) / SR) * 0.25
    write_wav("sfx_release.wav", (noise * 0.8 + tone) * env, gain=0.5)

    # gem: two-note sparkle
    n1 = n_of(0.07)
    n2 = n_of(0.22)
    v1 = np.sin(2 * np.pi * 1318.5 * np.arange(n1) / SR) * adsr(n1, 0.001, 0.05, 2.0)
    v2 = (np.sin(2 * np.pi * 1975.5 * np.arange(n2) / SR) + 0.3 * np.sin(2 * np.pi * 2637.0 * np.arange(n2) / SR))
    v2 *= adsr(n2, 0.001, 0.10, 2.4)
    out = np.zeros(n_of(0.35))
    out[:n1] += v1
    out[n_of(0.055):n_of(0.055) + n2] += v2
    out = reverb(out, mix=0.18, decay=0.5, seed=5)
    write_wav("sfx_gem.wav", out, gain=0.5)

    # hurt: crunch + falling saw
    dur = 0.42
    n = n_of(dur)
    t = np.arange(n) / SR
    f = sweep(240.0, 55.0, dur, 0.8)
    body = saw(np.cumsum(f) / SR) * 0.6 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.7
    crunch = highpass_fft(rng.standard_normal(n), 500.0) * 0.9
    env = adsr(n, 0.002, 0.16, 1.6)
    out = lowpass_fft((body + crunch) * env, 2400.0)
    write_wav("sfx_hurt.wav", out, gain=0.75)

    # death: long power-down
    dur = 1.5
    n = n_of(dur)
    f = sweep(420.0, 38.0, dur, 1.3)
    body = saw(np.cumsum(f) / SR) * 0.55 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.8
    noise = lowpass_fft(rng.standard_normal(n), 1200.0) * 0.5
    env = np.minimum(np.arange(n) / (0.01 * SR), 1.0) * np.exp(-np.arange(n) / (0.5 * SR))
    out = lowpass_fft((body + noise) * env, 3000.0)
    out = reverb(out, mix=0.3, decay=1.2, seed=9)
    write_wav("sfx_death.wav", out, gain=0.8)

    # ui click
    n = n_of(0.06)
    v = np.sin(2 * np.pi * 1150.0 * np.arange(n) / SR) * adsr(n, 0.001, 0.018, 3.0)
    write_wav("sfx_ui.wav", v, gain=0.28)

    # new best: rising arpeggio
    notes = [880.0, 1108.73, 1318.51, 1760.0]
    step = 0.085
    total = n_of(step * len(notes) + 0.5)
    out = np.zeros(total)
    for i, f in enumerate(notes):
        n = n_of(0.4)
        seg = (np.sin(2 * np.pi * f * np.arange(n) / SR) + 0.25 * np.sin(4 * np.pi * f * np.arange(n) / SR))
        seg *= adsr(n, 0.003, 0.13, 2.5)
        i0 = n_of(i * step)
        out[i0:i0 + n] += seg[: total - i0]
    out = reverb(out, mix=0.3, decay=0.8, seed=13)
    write_wav("sfx_best.wav", out, gain=0.5)

    # start: soft rising two-note
    n1, n2 = n_of(0.28), n_of(0.5)
    a = np.sin(2 * np.pi * 392.0 * np.arange(n1) / SR) * adsr(n1, 0.005, 0.22, 1.5)
    b = np.sin(2 * np.pi * 587.33 * np.arange(n2) / SR) * adsr(n2, 0.01, 0.35, 1.4)
    out = np.zeros(n_of(0.9))
    out[:n1] += a
    out[n_of(0.12):n_of(0.12) + n2] += b * 0.9
    write_wav("sfx_start.wav", out, gain=0.45)


# ---------------------------------------------------------------- wind
def make_wind():
    dur = 4.0
    n = n_of(dur)
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    resp = 1.0 / np.sqrt(1.0 + (freqs / 420.0) ** 4)
    resp *= np.sqrt(1.0 + (40.0 / np.maximum(freqs, 1.0)) ** 6)  # trim rumble
    w = np.fft.irfft(spec * resp, n)
    w /= np.max(np.abs(w))
    # periodic slow swell so the loop breathes but stays seamless
    ph = np.arange(n) / n
    sway = 0.72 + 0.28 * (0.5 + 0.5 * np.sin(2 * np.pi * ph * 2 + 0.7))
    w = w * sway
    write_wav("wind_loop.wav", w, gain=0.6)


if __name__ == "__main__":
    make_music()
    make_sfx()
    make_wind()
    print("done ->", OUT)
