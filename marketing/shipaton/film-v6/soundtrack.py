#!/usr/bin/env python3
"""AirFliq film v6 - trailer-grade original score + sound design, 100% synthesized (numpy + scipy only).

Reads ./cues.json ({bpm, duration, sections:[{t, name, mood, end?}], sfx:[{t, type}]}) and renders
48 kHz / 24-bit stereo files into build/film-v6/audio/:

  music.wav    music only, same master chain + gain as the mix (music-only fallback)
  sfx.wav      effects only, pre-master (reference)
  mix.wav      final master: -14 LUFS integrated, limiter ceiling -2 dBTP (AAC encode adds ~0.5 dB)
  aac-test.m4a quick AAC 256k encode of mix.wav, measured for true peak
  report.json, review.png, NOTES.md

Sections with an 'end' are the arrangement; marker sections without 'end' are events: 'stop' = hard silence
until the next section, 'riser*' = where a riser starts.  Every impact-big cue is a riser target and a hit.
No samples, no downloads, no network.  Deterministic (fixed seeds).

Usage:  python3 soundtrack.py [--cues PATH] [--out DIR] [--ceiling -2.0]
"""
from __future__ import annotations

import argparse
import json
import math
import re
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

SR = 48000
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
T_START = time.time()


def log(*a):
    print(f"[{time.time() - T_START:6.1f}s wall {time.process_time():6.1f}s cpu]", *a, flush=True)


def warn(msg):
    print(f"WARNING: {msg}", file=sys.stderr, flush=True)


# ============================================================================
# Small DSP toolkit
# ============================================================================

def ns(sec):
    return int(round(float(sec) * SR))


def db2lin(d):
    return 10.0 ** (np.asarray(d, float) / 20.0)


def mtof(m):
    return 440.0 * 2.0 ** ((float(m) - 69.0) / 12.0)


def smoothstep(u):
    u = np.clip(u, 0.0, 1.0)
    return u * u * (3.0 - 2.0 * u)


def norm_peak(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def edge_fade(x, fin=0.001, fout=0.004):
    n = len(x)
    a = min(n, max(1, ns(fin)))
    b = min(n, max(1, ns(fout)))
    w = np.ones(n)
    w[:a] = np.sin(0.5 * np.pi * np.arange(a) / a) ** 2
    w[n - b:] *= np.cos(0.5 * np.pi * np.arange(1, b + 1) / b) ** 2
    return x * (w if x.ndim == 1 else w[:, None])


def ar_env(dur, attack, release):
    """Attack / sustain / release envelope; total length = dur + release."""
    n_on = max(1, ns(dur))
    nr = max(1, ns(release))
    i = np.arange(n_on + nr)
    return smoothstep(i / max(1, ns(attack))) * smoothstep((n_on + nr - i) / nr)


_SOS = {}


def sos(kind, f, order=2):
    fr = tuple(float(v) for v in np.atleast_1d(f))
    key = (kind, fr, order)
    s = _SOS.get(key)
    if s is None:
        s = signal.butter(order, fr[0] if len(fr) == 1 else list(fr), btype=kind, fs=SR, output='sos')
        _SOS[key] = s
    return s


def hp(x, f, order=2, zp=False):
    s = sos('highpass', f, order)
    return signal.sosfiltfilt(s, x, axis=0) if zp else signal.sosfilt(s, x, axis=0)


def lp(x, f, order=2, zp=False):
    s = sos('lowpass', f, order)
    return signal.sosfiltfilt(s, x, axis=0) if zp else signal.sosfilt(s, x, axis=0)


def bp(x, lo, hi, order=2, zp=False):
    s = sos('bandpass', [lo, hi], order)
    return signal.sosfiltfilt(s, x, axis=0) if zp else signal.sosfilt(s, x, axis=0)


def peq(x, f0, gain_db, q=0.8):
    """RBJ peaking EQ."""
    A = 10 ** (gain_db / 40.0)
    w = 2 * np.pi * f0 / SR
    al = np.sin(w) / (2 * q)
    b = np.array([1 + al * A, -2 * np.cos(w), 1 - al * A])
    a = np.array([1 + al / A, -2 * np.cos(w), 1 - al / A])
    return signal.lfilter(b / a[0], a / a[0], x, axis=0)


def shelf(x, f0, gain_db, kind='high', s=0.9):
    """RBJ shelving EQ."""
    A = 10 ** (gain_db / 40.0)
    w = 2 * np.pi * f0 / SR
    al = np.sin(w) / 2 * np.sqrt((A + 1 / A) * (1 / s - 1) + 2)
    c = np.cos(w)
    sa = 2 * np.sqrt(A) * al
    if kind == 'high':
        b = [A * ((A + 1) + (A - 1) * c + sa), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sa)]
        a = [(A + 1) - (A - 1) * c + sa, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sa]
    else:
        b = [A * ((A + 1) - (A - 1) * c + sa), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sa)]
        a = [(A + 1) + (A - 1) * c + sa, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sa]
    b = np.array(b) / a[0]
    a = np.array(a) / a[0]
    return signal.lfilter(b, a, x, axis=0)


def tv_lowpass(x, fc, order=4, block=256):
    """Time-varying Butterworth low-pass (block-wise coefficients, carried state)."""
    n = len(x)
    y = np.empty_like(x)
    zi = np.zeros((order // 2, 2) + x.shape[1:])
    cache = {}
    for i in range(0, n, block):
        j = min(n, i + block)
        f = float(fc[(i + j) // 2])
        q = int(round(math.log2(min(max(f, 30.0), 0.44 * SR)) * 48))
        s = cache.get(q)
        if s is None:
            s = signal.butter(order, min(2.0 ** (q / 48.0), 0.44 * SR), btype='lowpass', fs=SR, output='sos')
            cache[q] = s
        y[i:j], zi = signal.sosfilt(s, x[i:j], axis=0, zi=zi)
    return y


def place(buf, sig, t, gain=1.0, pan=0.0):
    """Add a mono (equal-power panned) or stereo (balance) signal into buf at time t."""
    if sig.ndim == 1:
        a = (float(np.clip(pan, -1, 1)) + 1.0) * np.pi / 4.0
        g = np.array([np.cos(a), np.sin(a)]) * np.sqrt(2.0) * gain
        s = sig[:, None] * g[None, :]
    else:
        g = np.array([min(1.0, 1.0 - pan), min(1.0, 1.0 + pan)]) * gain
        s = sig * g[None, :]
    i0 = int(round(t * SR))
    j0 = max(0, i0)
    j1 = min(len(buf), i0 + len(s))
    if j1 > j0:
        buf[j0:j1] += s[j0 - i0:j1 - i0]


def place_mono(buf, sig, t, gain=1.0):
    i0 = int(round(t * SR))
    j0 = max(0, i0)
    j1 = min(len(buf), i0 + len(sig))
    if j1 > j0:
        buf[j0:j1] += sig[j0 - i0:j1 - i0] * gain


def saw(freq, n, phase=0.0):
    """Band-limited (polyBLEP) sawtooth; freq scalar or per-sample array."""
    if np.ndim(freq) == 0:
        dt = float(freq) / SR
        ph = (phase + dt * np.arange(n)) % 1.0
        y = 2.0 * ph - 1.0
        m = ph < dt
        tt = ph[m] / dt
        y[m] -= tt + tt - tt * tt - 1.0
        m = ph > 1.0 - dt
        tt = (ph[m] - 1.0) / dt
        y[m] -= tt * tt + tt + tt + 1.0
        return y
    dt = np.asarray(freq, float) / SR
    ph = (phase + np.cumsum(dt)) % 1.0
    y = 2.0 * ph - 1.0
    m = ph < dt
    tt = ph[m] / dt[m]
    y[m] -= tt + tt - tt * tt - 1.0
    m = ph > 1.0 - dt
    tt = (ph[m] - 1.0) / dt[m]
    y[m] -= tt * tt + tt + tt + 1.0
    return y


def chorus(x, rate=0.21, depth_ms=2.4, base_ms=11.0, mix=0.3):
    n = len(x)
    t = np.arange(n) / SR
    idx = np.arange(n, dtype=float)
    out = np.empty_like(x)
    for ch, ph in ((0, 0.0), (1, 0.5 * np.pi)):
        d = (base_ms + depth_ms * np.sin(2 * np.pi * rate * t + ph)) * 1e-3 * SR
        p = idx - d
        i0 = np.floor(p).astype(np.int64)
        fr = p - i0
        i0 = np.clip(i0, 0, n - 2)
        src = x[:, 1 - ch]
        wet = src[i0] * (1.0 - fr) + src[i0 + 1] * fr
        out[:, ch] = x[:, ch] * (1.0 - mix) + wet * mix
    return out


def pingpong(x, delay_s, fb=0.42, taps=7, lp_hz=4200.0, hp_hz=320.0):
    """Tempo-synced ping-pong delay; each repeat alternates side and gets darker."""
    n = len(x)
    m = x.mean(axis=1) if x.ndim == 2 else x
    m = hp(lp(m, lp_hz), hp_hz)
    out = np.zeros((n, 2))
    d = ns(delay_s)
    b, a = signal.butter(1, lp_hz * 0.8, fs=SR)
    cur = m
    for k in range(1, taps + 1):
        if k > 1:
            cur = signal.lfilter(b, a, cur)
        off = k * d
        if off >= n:
            break
        out[off:, (k - 1) % 2] += cur[:n - off] * fb ** (k - 1)
    return out


def make_ir(length, rt_pts, predelay, seed, corr=0.25, lo=160.0, hi=9000.0, build=0.012):
    """Stereo reverb impulse: noise with frequency-dependent exponential decay (STFT-shaped)."""
    n = ns(length)
    rng = np.random.default_rng(seed)
    fpts = np.log([p[0] for p in rt_pts])
    rpts = [p[1] for p in rt_pts]
    chans = []
    for _ in range(2):
        z = rng.standard_normal(n)
        f, tt, Z = signal.stft(z, fs=SR, nperseg=1024, noverlap=768)
        rt = np.interp(np.log(np.maximum(f, 20.0)), fpts, rpts)
        Z = Z * np.exp(-6.91 * tt[None, :] / rt[:, None])
        _, y = signal.istft(Z, fs=SR, nperseg=1024, noverlap=768)
        y = y[:n]
        if len(y) < n:
            y = np.pad(y, (0, n - len(y)))
        chans.append(y)
    L, R = chans
    ir = np.stack([L + corr * R, R + corr * L], axis=1)
    ir = bp(ir, lo, hi, order=2)
    t = np.arange(n) / SR
    ir *= (1.0 - np.exp(-t / build))[:, None]
    k = ns(0.08)
    ir[-k:] *= np.linspace(1.0, 0.0, k)[:, None]
    ir = np.vstack([np.zeros((ns(predelay), 2)), ir])
    return ir / np.sqrt((ir ** 2).sum() / 2.0)


def reverb(send, ir):
    """Stereo-in / stereo-out convolution (light cross-feed keeps it wide but centred)."""
    n = len(send)
    out = np.zeros((n, 2))
    if send.ndim == 1:
        send = np.stack([send, send], 1)
    ins = (0.78 * send[:, 0] + 0.22 * send[:, 1], 0.78 * send[:, 1] + 0.22 * send[:, 0])
    for ch in range(2):
        if np.any(ins[ch]):
            out[:, ch] = signal.fftconvolve(ins[ch], ir[:, ch])[:n]
    return out


def noise_sweep(dur, fc_of_p, bw_oct, seed, stereo=True):
    """Noise through a moving log-Gaussian band (STFT domain); RMS-normalised."""
    n = max(ns(dur), 64)
    rng = np.random.default_rng(seed)
    outs = []
    for _ in range(2 if stereo else 1):
        z = rng.standard_normal(n + 1024)
        f, tt, Z = signal.stft(z, fs=SR, nperseg=1024, noverlap=768)
        p = np.clip(tt / max(dur, 1e-3), 0.0, 1.0)
        fc = np.maximum(np.asarray(fc_of_p(p), float), 20.0)
        lf = np.log2(np.maximum(f, 10.0))
        G = np.exp(-0.5 * ((lf[:, None] - np.log2(fc)[None, :]) / (bw_oct / 2.355)) ** 2)
        _, y = signal.istft(Z * G, fs=SR, nperseg=1024, noverlap=768)
        outs.append(y[:n])
    y = np.stack(outs, 1) if stereo else outs[0]
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-12)


# ============================================================================
# Instruments
# ============================================================================

def pad_note(midi, dur, attack, release, seed, n_osc=7, detune=13.0):
    """Detuned-saw supersaw voice, oscillators spread across the stereo field, slow drift."""
    rng = np.random.default_rng(seed)
    env = ar_env(dur, attack, release)
    n = len(env)
    t = np.arange(n) / SR
    f0 = mtof(midi)
    spread = np.linspace(-1.0, 1.0, n_osc)
    pans = np.linspace(-0.9, 0.9, n_osc)[np.argsort(rng.random(n_osc))]
    out = np.zeros((n, 2))
    for i in range(n_osc):
        cents = spread[i] * detune + 1.8 * np.sin(2 * np.pi * (0.05 + 0.12 * rng.random()) * t + 6.283 * rng.random())
        s = saw(f0 * 2.0 ** (cents / 1200.0), n, rng.random())
        a = (pans[i] + 1.0) * np.pi / 4.0
        out[:, 0] += s * np.cos(a)
        out[:, 1] += s * np.sin(a)
    return out * (env / np.sqrt(n_osc))[:, None]


_PLUCK = {}


def pluck(midi, bright=0.6, decay=0.2):
    """Additive 'filtered saw' pluck: harmonic k is shaped by a decaying 3-pole low-pass."""
    b = round(float(np.clip(bright, 0.05, 1.2)) * 20.0) / 20.0
    d = round(float(decay), 3)
    key = (int(midi), b, d)
    y = _PLUCK.get(key)
    if y is not None:
        return y
    f = mtof(midi)
    L = min(1.6, 0.08 + 5.0 * d)
    n = ns(L)
    t = np.arange(n) / SR
    kmax = int(max(1, min(30, 15000.0 / f)))
    fc0 = f * (1.8 + 14.0 * b)
    fc1 = f * (1.05 + 1.2 * b)
    fc = fc1 + (fc0 - fc1) * np.exp(-t / (0.02 + 0.06 * b))
    r6 = (f / fc) ** 6
    th = 2.0 * np.pi * f * t
    c2 = 2.0 * np.cos(th)
    s_prev = np.zeros(n)
    s = np.sin(th)
    acc = np.zeros(n)
    for k in range(1, kmax + 1):
        acc += s / (k * np.sqrt(1.0 + (k ** 6) * r6))
        s_prev, s = s, c2 * s - s_prev
    amp = np.exp(-t / d) * smoothstep(t / 0.0012) * smoothstep((L - t) / 0.03)
    y = acc * amp * 0.9
    _PLUCK[key] = y
    return y


def glass(midi, dur, attack=0.035, release=0.5):
    """Soft 1:1 FM 'glass' lead with delayed vibrato (counter-melody / motif double)."""
    env = ar_env(dur, attack, release)
    n = len(env)
    t = np.arange(n) / SR
    f = mtof(midi)
    vib = 1.0 + 0.0028 * np.sin(2 * np.pi * 4.8 * t) * smoothstep((t - 0.3) / 0.5)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    idx = 0.2 + 0.8 * np.exp(-t / 0.15)
    y = np.sin(ph + idx * np.sin(ph)) + 0.06 * np.sin(3.5 * ph) * np.exp(-t / 0.04)
    return y * env


def sub_note(midi, dur, attack=0.02, release=0.1):
    env = ar_env(dur, attack, release)
    t = np.arange(len(env)) / SR
    ph = 2 * np.pi * mtof(midi) * t
    return (np.sin(ph) + 0.28 * np.sin(2 * ph + 0.2) + 0.08 * np.sin(3 * ph + 0.4)) * env


def midbass_note(midi, dur, seed, attack=0.02, release=0.12, cutoff=680.0):
    env = ar_env(dur, attack, release)
    n = len(env)
    f = mtof(midi)
    rng = np.random.default_rng(seed)
    y = saw(f * 2 ** (-6 / 1200), n, rng.random()) + saw(f * 2 ** (6 / 1200), n, rng.random())
    return lp(y, cutoff, order=4) * env * 0.5


def make_kick():
    n = ns(0.48)
    t = np.arange(n) / SR
    f = 49.0 + 105.0 * np.exp(-t / 0.038) + 70.0 * np.exp(-t / 0.0045)
    ph = 2 * np.pi * np.cumsum(f) / SR
    amp = smoothstep(t / 0.0007) * (0.72 * np.exp(-t / 0.13) + 0.28 * np.exp(-t / 0.32))
    rng = np.random.default_rng(5)
    click = bp(rng.standard_normal(n), 1500, 5000) * np.exp(-t / 0.0016) * 0.38
    knock = np.sin(2 * np.pi * 1100 * t) * np.exp(-t / 0.0035) * 0.12
    y = np.tanh(2.0 * (np.sin(ph) * amp + click + knock)) / np.tanh(2.0)
    return edge_fade(hp(y, 28), 0.0003, 0.03)


def make_hat(open_=False, seed=11):
    n = ns(0.36 if open_ else 0.09)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    metal = sum(signal.square(2 * np.pi * f * 1.6 * t + rng.random() * 6.28) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0))
    y = 0.72 * rng.standard_normal(n) + 0.28 * metal / 6.0
    y = lp(hp(y, 7200, order=4), 15500, order=2)
    y *= np.exp(-t / (0.085 if open_ else 0.013)) * smoothstep(t / 0.0004)
    return norm_peak(edge_fade(y, 0.0002, 0.01))


def make_clap(seed=21):
    n = ns(0.45)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    e = np.zeros(n)
    for d, a in ((0.0, 1.0), (0.0085, 0.85), (0.0175, 0.75)):
        e += a * (t >= d) * np.exp(-np.maximum(t - d, 0) / 0.0035)
    e += 0.8 * (t >= 0.025) * np.exp(-np.maximum(t - 0.025, 0) / 0.07)
    y = bp(rng.standard_normal(n), 850, 5200, order=2) * e
    y = peq(y, 1700, 2.5, 1.0)
    y += 0.3 * np.sin(2 * np.pi * np.cumsum(175 + 40 * np.exp(-t / 0.01)) / SR) * np.exp(-t / 0.03)
    return norm_peak(edge_fade(y, 0.0002, 0.03))


def make_crash(seed=31):
    n = ns(2.2)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    y = hp(rng.standard_normal((n, 2)), 3800, order=2)
    y = lp(y, 13000, order=2)
    y *= (np.exp(-t / 0.7) * smoothstep(t / 0.003))[:, None]
    return norm_peak(edge_fade(y, 0.0005, 0.2))


# ============================================================================
# Sound effects (shared with v5)
# ============================================================================

def sfx_tick():
    n = ns(0.045)
    t = np.arange(n) / SR
    rng = np.random.default_rng(101)
    y = (0.45 * np.sin(2 * np.pi * 820 * t) * np.exp(-t / 0.009)
         + 0.6 * np.sin(2 * np.pi * 1850 * t + 0.3) * np.exp(-t / 0.0045)
         + 0.3 * np.sin(2 * np.pi * 2950 * t + 0.9) * np.exp(-t / 0.0028))
    y += 0.35 * bp(rng.standard_normal(n), 900, 4000) * np.exp(-t / 0.0015)
    y = lp(y * smoothstep(t / 0.0004), 5200)
    return norm_peak(edge_fade(y, 0.0002, 0.006))


def sfx_click():
    n = ns(0.05)
    t = np.arange(n) / SR
    rng = np.random.default_rng(202)
    z = bp(rng.standard_normal(n), 1500, 6000, order=2)
    e = np.exp(-t / 0.0011) + 0.55 * (t >= 0.008) * np.exp(-np.maximum(t - 0.008, 0) / 0.0009)
    y = z * e
    y += 0.08 * np.sin(2 * np.pi * 2900 * t) * np.exp(-t / 0.0015)
    y += 0.12 * np.sin(2 * np.pi * 210 * t) * np.exp(-t / 0.006) * smoothstep(t / 0.0005)
    y = lp(y * smoothstep(t / 0.00015), 5000)
    return norm_peak(edge_fade(y, 0.0001, 0.008))


def sfx_key():
    n = ns(0.11)
    t = np.arange(n) / SR
    rng = np.random.default_rng(303)
    body = np.sin(2 * np.pi * np.cumsum(205 + 55 * np.exp(-t / 0.012)) / SR) * np.exp(-t / 0.02)
    res = 0.32 * np.sin(2 * np.pi * 560 * t + 0.5) * np.exp(-t / 0.009)
    clack = 0.55 * bp(rng.standard_normal(n), 700, 3200) * np.exp(-t / 0.005)
    tick = 0.12 * bp(rng.standard_normal(n), 4000, 7500) * np.exp(-t / 0.0007)
    y = lp((0.85 * body + res + clack + tick) * smoothstep(t / 0.0006), 8000)
    return norm_peak(edge_fade(y, 0.0001, 0.02))


def sfx_pop():
    n = ns(0.13)
    t = np.arange(n) / SR
    rng = np.random.default_rng(404)
    ph = 2 * np.pi * np.cumsum(440.0 * 2.0 ** (1.0 - np.exp(-t / 0.011))) / SR   # A4 -> A5 blip
    y = (np.sin(ph) + 0.12 * np.sin(2 * ph)) * smoothstep(t / 0.002) * np.exp(-t / 0.032)
    y += 0.06 * hp(rng.standard_normal(n), 3500) * np.exp(-t / 0.004)
    return norm_peak(edge_fade(y, 0.0001, 0.015))


def sfx_whoosh(dur, seed=606):
    dur = float(np.clip(dur, 0.15, 3.0))
    rise = float(np.clip(0.55 * dur, 0.08, 0.4))
    total = dur + 0.18 + 0.35 * dur
    n = ns(total)
    t = np.arange(n) / SR
    pk = rise / total

    def fc(p):
        p = np.asarray(p, float)
        up = 650.0 * (2300.0 / 650.0) ** smoothstep(p / pk)
        down = 2300.0 * (1100.0 / 2300.0) ** smoothstep((p - pk) / (1 - pk))
        return np.where(p < pk, up, down)

    y = noise_sweep(total, fc, 1.7, seed)[:n] + 0.18 * noise_sweep(total, lambda p: 2.0 * fc(p), 0.18, seed + 1)[:n]
    env = np.where(t < rise, np.sin(0.5 * np.pi * t / rise) ** 2,
                   (0.5 + 0.5 * np.cos(np.pi * np.clip((t - rise) / (total - rise), 0, 1))) ** 1.6)
    y *= env[:, None]
    a = (-0.35 + 0.7 * smoothstep(t / total) + 1.0) * np.pi / 4.0
    y[:, 0] *= np.cos(a) * np.sqrt(2)
    y[:, 1] *= np.sin(a) * np.sqrt(2)
    y = lp(hp(y, 200, order=4), 9000)
    return norm_peak(edge_fade(y, 0.002, 0.02))


def sfx_land():
    n = ns(0.26)
    t = np.arange(n) / SR
    rng = np.random.default_rng(707)
    thud = np.sin(2 * np.pi * np.cumsum(64 + 60 * np.exp(-t / 0.02)) / SR) * np.exp(-t / 0.05) * smoothstep(t / 0.0025)
    felt = 0.3 * bp(rng.standard_normal(n), 250, 900) * np.exp(-t / 0.012)
    click = 0.14 * bp(rng.standard_normal(n), 2000, 4500) * np.exp(-t / 0.0012)
    return norm_peak(edge_fade(hp(thud + felt + click, 40), 0.0002, 0.03))


def chord_pcs(name):
    c = CHORDS[name]
    return {c['root']} | {m % 12 for m in c['ust']} | {m % 12 for m in c['pool']}


def chime_pair(chord):
    pcs = chord_pcs(chord)
    for a, b, m1, m2 in ((2, 6, 86, 90), (9, 1, 81, 85), (7, 11, 79, 83), (9, 4, 81, 88)):
        if a in pcs and b in pcs:
            return m1, m2
    return 86, 90


def sfx_chime(chord):
    n = ns(1.5)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    m1, m2 = chime_pair(chord)
    for i, (m, off, pan) in enumerate(((m1, 0.0, -0.18), (m2, 0.085, 0.18))):
        f = mtof(m)
        tt = np.maximum(t - off, 0.0)
        y = np.zeros(n)
        for ratio, amp, tau in ((1.0, 1.0, 0.75), (2.0, 0.22, 0.3), (3.0, 0.08, 0.14), (4.2, 0.05, 0.05)):
            y += amp * np.sin(2 * np.pi * f * ratio * tt) * np.exp(-tt / tau)
        y *= (t >= off) * smoothstep(tt / 0.0015) * (0.85 if i == 0 else 1.0)
        a = (pan + 1) * np.pi / 4
        out[:, 0] += y * np.cos(a) * np.sqrt(2)
        out[:, 1] += y * np.sin(a) * np.sqrt(2)
    return norm_peak(edge_fade(out, 0.0001, 0.1))


def sfx_impact():
    n = ns(1.1)
    t = np.arange(n) / SR
    rng = np.random.default_rng(909)
    sub = np.sin(2 * np.pi * np.cumsum(41.0 + 32.0 * np.exp(-t / 0.13)) / SR) * smoothstep(t / 0.003) * np.exp(-t / 0.3)
    body = 0.32 * np.sin(2 * np.pi * np.cumsum(90 + 60 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.055)
    nz = rng.standard_normal(n)
    trans = 0.3 * lp(nz, 1500) * np.exp(-t / 0.018) + 0.18 * lp(nz, 350) * np.exp(-t / 0.07)
    y = np.tanh(1.5 * (sub + body + trans)) / np.tanh(1.5)
    return norm_peak(edge_fade(hp(y, 26), 0.0002, 0.15))


def sfx_shimmer(chord, seed=1111):
    dur = 1.1
    total = dur + 0.6
    n = ns(total)
    rng = np.random.default_rng(seed)
    pcs = chord_pcs(chord)
    cand = [m for m in range(79, 101) if m % 12 in pcs]
    out = np.zeros((n, 2))
    G = 46
    for g in range(G):
        p = g / (G - 1)
        tg = dur * 0.92 * p ** 1.25 + rng.uniform(0, 0.02)
        target = 80 + 18 * p + rng.normal(0, 2.5)
        m = min(cand, key=lambda x: abs(x - target))
        gn = ns(rng.uniform(0.07, 0.16))
        tt = np.arange(gn) / SR
        f = mtof(m) * (1 + rng.uniform(-0.002, 0.002))
        y = np.sin(2 * np.pi * f * tt + 0.6 * np.sin(2 * np.pi * 2 * f * tt)) * np.sin(np.pi * np.arange(gn) / gn) ** 2
        amp = (0.35 + 0.65 * p) * (1.0 - 0.5 * max(0.0, p - 0.85) / 0.15)
        place(out, y, tg, gain=amp, pan=rng.uniform(-0.75, 0.75))
    t = np.arange(n) / SR
    nz = noise_sweep(total, lambda p: 5000.0 * 2.0 ** (1.3 * p), 1.0, seed + 7)[:n]
    out += 0.12 * nz * (smoothstep(t / (dur * 0.8)) * smoothstep((total - t) / 0.5))[:, None]
    return norm_peak(edge_fade(hp(out, 900), 0.002, 0.08))



# ============================================================================
# v6 instruments (harder drums, supersaw stabs, risers)
# ============================================================================

def make_kick_v6():
    """Tight, hard kick: fast 230->47 Hz sweep, short body, click transient, driven."""
    n = ns(0.32)
    t = np.arange(n) / SR
    f = 47.0 + 140.0 * np.exp(-t / 0.022) + 90.0 * np.exp(-t / 0.004)
    ph = 2 * np.pi * np.cumsum(f) / SR
    amp = smoothstep(t / 0.0005) * (0.8 * np.exp(-t / 0.075) + 0.2 * np.exp(-t / 0.2))
    rng = np.random.default_rng(6)
    click = bp(rng.standard_normal(n), 2000, 7000) * np.exp(-t / 0.0012) * 0.55
    click += np.sin(2 * np.pi * 3200 * t) * np.exp(-t / 0.002) * 0.15
    y = np.tanh(2.6 * (np.sin(ph) * amp + click)) / np.tanh(2.6)
    return edge_fade(hp(y, 30), 0.0003, 0.03)


def make_snare(seed=41):
    n = ns(0.35)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    body = 0.6 * np.sin(2 * np.pi * np.cumsum(200 + 60 * np.exp(-t / 0.01)) / SR) * np.exp(-t / 0.05)
    z = rng.standard_normal(n)
    nz = 0.8 * bp(z, 1200, 9000) * np.exp(-t / 0.11) + 0.3 * hp(z, 5000) * np.exp(-t / 0.05)
    y = np.tanh(1.5 * (body + nz) * smoothstep(t / 0.0006))
    return norm_peak(edge_fade(y, 0.0002, 0.04))


_STAB = {}


def stab(notes, bright=1.0, dur=0.2):
    """Supersaw chord stab (7 detuned saws per note, stereo spread) with a fast filter envelope."""
    key = (tuple(notes), round(float(bright), 2), round(dur, 3))
    if key in _STAB:
        return _STAB[key]
    n = ns(dur + 0.3)
    t = np.arange(n) / SR
    rng = np.random.default_rng(sum(notes) * 7 + int(bright * 100))
    y = np.zeros((n, 2))
    for m in notes:
        f = mtof(m)
        for i in range(7):
            s = saw(f * 2 ** ((i - 3) / 3 * 17 / 1200), n, rng.random())
            a = ((i - 3) / 3 * 0.85 + 1) * np.pi / 4
            y[:, 0] += s * np.cos(a)
            y[:, 1] += s * np.sin(a)
    br = lp(y, min(15000.0, 9000.0 * bright), order=2)
    dk = lp(y, 1700.0, order=2)
    e = np.exp(-t / 0.07)[:, None]
    amp = smoothstep(t / 0.003) * (0.7 * np.exp(-t / 0.16) + 0.3 * np.exp(-t / 0.45)) * smoothstep((dur + 0.3 - t) / 0.3)
    out = (br * e + dk * (1 - e)) * (amp / (np.sqrt(7) * len(notes)))[:, None]
    _STAB[key] = out
    return out


def pitch_riser(dur, m0=50, m1=74, seed=5, floor=0.0):
    """Two detuned saws + sine gliding up two octaves through an opening low-pass, accelerating gate."""
    n = ns(dur)
    t = np.arange(n) / SR
    u = t / dur
    f = mtof(m0) * 2.0 ** ((m1 - m0) / 12.0 * u ** 1.6)
    rng = np.random.default_rng(seed)
    sine = 0.8 * np.sin(2 * np.pi * np.cumsum(f) / SR)
    y = np.stack([saw(f * 2 ** (-10 / 1200), n, rng.random()) + sine,
                  saw(f * 2 ** (10 / 1200), n, rng.random()) + sine], 1)
    y = tv_lowpass(y, 500.0 * (9000.0 / 500.0) ** u, order=2)
    rate = 4.0 + 12.0 * u ** 2
    gate = 1.0 - 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(rate) / SR))
    return y * ((floor + (1.0 - floor) * u ** 1.8) * gate)[:, None]



_REESE = {}


def reese_note(midi, dur, cutoff=700.0):
    """Reese bass: two saws +-12 cents + sine sub, driven, low-passed."""
    key = (int(midi), round(dur, 3), cutoff)
    if key in _REESE:
        return _REESE[key]
    n = ns(dur + 0.04)
    t = np.arange(n) / SR
    f = mtof(midi)
    y = 0.5 * (saw(2 * f * 2 ** (-12 / 1200), n, 0.1) + saw(2 * f * 2 ** (12 / 1200), n, 0.6)) + 0.12 * np.sin(2 * np.pi * f * t)
    y = lp(np.tanh(1.6 * y), cutoff, order=4)
    env = smoothstep(t / 0.003) * smoothstep((dur + 0.04 - t) / 0.04)
    _REESE[key] = y * env
    return _REESE[key]

# ============================================================================
# v6 sound effects
# ============================================================================

def _pop(f0, f1, tau, dur=0.13, air=0.06, h2=0.12, seed=404, air_tau=0.004):
    n = ns(dur)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    ph = 2 * np.pi * np.cumsum(f0 * (f1 / f0) ** (1.0 - np.exp(-t / 0.011))) / SR
    y = (np.sin(ph) + h2 * np.sin(2 * ph)) * smoothstep(t / 0.002) * np.exp(-t / tau)
    y += air * hp(rng.standard_normal(n), 3500) * np.exp(-t / air_tau)
    return norm_peak(edge_fade(y, 0.0001, 0.015))


def sfx_release():
    n = ns(0.04)
    t = np.arange(n) / SR
    rng = np.random.default_rng(212)
    y = bp(rng.standard_normal(n), 1000, 4000) * np.exp(-t / 0.0014)
    y += 0.1 * np.sin(2 * np.pi * 2300 * t) * np.exp(-t / 0.002)
    return norm_peak(edge_fade(lp(y * smoothstep(t / 0.0003), 4500), 0.0001, 0.006))


def sfx_pickup_tick():
    n = ns(0.06)
    t = np.arange(n) / SR
    rng = np.random.default_rng(111)
    y = (0.6 * np.sin(2 * np.pi * 620 * t) * np.exp(-t / 0.012) + 0.5 * np.sin(2 * np.pi * 1400 * t + 0.3) * np.exp(-t / 0.006)
         + 0.25 * np.sin(2 * np.pi * 2300 * t) * np.exp(-t / 0.003))
    y += 0.3 * bp(rng.standard_normal(n), 700, 3500) * np.exp(-t / 0.002)
    return norm_peak(edge_fade(lp(y * smoothstep(t / 0.0004), 4500), 0.0002, 0.008))


def sfx_key_heavy():
    n = ns(0.14)
    t = np.arange(n) / SR
    rng = np.random.default_rng(313)
    body = np.sin(2 * np.pi * np.cumsum(160 + 50 * np.exp(-t / 0.014)) / SR) * np.exp(-t / 0.03)
    res = 0.3 * np.sin(2 * np.pi * 430 * t + 0.5) * np.exp(-t / 0.012)
    clack = 0.6 * bp(rng.standard_normal(n), 500, 2600) * np.exp(-t / 0.007)
    tick = 0.1 * bp(rng.standard_normal(n), 3500, 7000) * np.exp(-t / 0.0008)
    return norm_peak(edge_fade(lp((0.9 * body + res + clack + tick) * smoothstep(t / 0.0006), 7000), 0.0001, 0.025))


def sfx_paper_fold(seed=515):
    n = ns(0.2)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    y = np.zeros(n)
    for _ in range(26):                                     # crinkle grains
        t0 = rng.uniform(0, 0.13) ** 1.3 / 0.13 ** 0.3
        gl = ns(rng.uniform(0.001, 0.004))
        g = rng.standard_normal(gl) * np.hanning(gl) * rng.uniform(0.3, 1.0)
        i0 = ns(t0)
        y[i0:i0 + gl] += g[:max(0, min(gl, n - i0))]
    y = bp(y, 1800, 9000)
    snap = bp(rng.standard_normal(n), 900, 5000) * (t >= 0.055) * np.exp(-np.maximum(t - 0.055, 0) / 0.0025)
    crackle = hp(rng.standard_normal(n), 6000) * (rng.random(n) < 0.004) * 1.5
    y = y + 1.4 * snap + 0.3 * crackle * np.exp(-t / 0.08)
    return norm_peak(edge_fade(y, 0.0002, 0.02))


def sfx_card_flip(seed=616):
    n = ns(0.09)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    env = np.exp(-t / 0.006) + 0.7 * (t >= 0.016) * np.exp(-np.maximum(t - 0.016, 0) / 0.01)
    y = bp(rng.standard_normal(n), 1000, 6500) * env
    y += 0.25 * np.sin(2 * np.pi * 300 * t) * np.exp(-t / 0.012)
    return norm_peak(edge_fade(y * smoothstep(t / 0.0005), 0.0002, 0.015))


def _whoosh(dur, seed, f0=650.0, fpk=2300.0, f1=1100.0, bw=1.7, hp_hz=200.0, tone=0.18):
    dur = float(np.clip(dur, 0.15, 3.0))
    rise = float(np.clip(0.55 * dur, 0.08, 0.4))
    total = dur + 0.18 + 0.35 * dur
    n = ns(total)
    t = np.arange(n) / SR
    pk = rise / total

    def fc(p):
        p = np.asarray(p, float)
        return np.where(p < pk, f0 * (fpk / f0) ** smoothstep(p / pk),
                        fpk * (f1 / fpk) ** smoothstep((p - pk) / (1 - pk)))

    y = noise_sweep(total, fc, bw, seed)[:n] + tone * noise_sweep(total, lambda p: 2.0 * fc(p), 0.18, seed + 1)[:n]
    env = np.where(t < rise, np.sin(0.5 * np.pi * t / rise) ** 2,
                   (0.5 + 0.5 * np.cos(np.pi * np.clip((t - rise) / (total - rise), 0, 1))) ** 1.6)
    y *= env[:, None]
    a = (-0.35 + 0.7 * smoothstep(t / total) + 1.0) * np.pi / 4.0
    y[:, 0] *= np.cos(a) * np.sqrt(2)
    y[:, 1] *= np.sin(a) * np.sqrt(2)
    return lp(hp(y, hp_hz, order=4), 10000), env, rise


def _grains(n, times, freqs, amps, lens, pans):
    out = np.zeros((n, 2))
    for t0, f, a, gl, pn in zip(times, freqs, amps, lens, pans):
        gn = max(16, ns(gl))
        tt = np.arange(gn) / SR
        g = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2.76 * f * tt)) * np.exp(-tt / (gl / 4)) * smoothstep(tt / 0.0008)
        place(out, g, t0, gain=a, pan=pn)
    return out


def sfx_fliq(dur, seed=707):
    """Airy jet whoosh + Doppler tone falling as it passes + glassy sparkle."""
    y, env, rise = _whoosh(dur, seed, 700.0, 2600.0, 1000.0, 1.6, 180.0, 0.12)
    n = len(y)
    t = np.arange(n) / SR
    p = t / t[-1]
    f = 1320.0 * 2.0 ** (0.3 * (1.0 - 2.0 * smoothstep((t - rise * 0.6) / (t[-1] * 0.5))))   # ~ +3.6 -> -3.6 st
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.35 * np.sin(2 * np.pi * np.cumsum(2.01 * f) / SR)
    a = (-0.5 + p + 1.0) * np.pi / 4.0
    y[:, 0] += 0.22 * tone * env * np.cos(a) * np.sqrt(2)
    y[:, 1] += 0.22 * tone * env * np.sin(a) * np.sqrt(2)
    rng = np.random.default_rng(seed + 9)
    k = 18 if dur < 1.0 else 34
    times = rise * 0.5 + rng.random(k) ** 0.8 * (t[-1] * 0.6)
    sp = _grains(n, times, rng.choice([2349.3, 2637.0, 2960.0, 3520.0, 4434.9, 4698.6], k), rng.uniform(0.05, 0.16, k),
                 rng.uniform(0.02, 0.06, k), rng.uniform(-0.8, 0.8, k))
    return norm_peak(edge_fade(hp(y + sp, 180, order=4), 0.002, 0.02))


def sfx_whoosh_v6(dur, seed, dark=1.0, flutter=False):
    y, env, _ = _whoosh(dur, seed, 650.0 * dark, 2300.0 * dark, 1100.0 * dark)
    if flutter:
        n = len(y)
        t = np.arange(n) / SR
        rng = np.random.default_rng(seed + 3)
        fl = 1.0 + 0.45 * np.sin(2 * np.pi * np.cumsum(28 + 10 * rng.random(n).cumsum() / n) / SR)
        y *= fl[:, None]
        pf = sfx_paper_fold(seed + 4)[:n]
        y[:len(pf)] += 0.25 * np.stack([pf, pf], 1)
    return norm_peak(edge_fade(y, 0.002, 0.02))


def sfx_shatter(dur=0.7, seed=808):
    y, env, rise = _whoosh(dur, seed, 900.0, 3200.0, 1600.0, 1.4, 250.0, 0.1)
    n = len(y)
    rng = np.random.default_rng(seed + 1)
    k = 70
    times = 0.05 + rng.random(k) ** 1.6 * 0.6
    tink = _grains(n, times, rng.uniform(3000, 9500, k), rng.uniform(0.08, 0.3, k) * np.exp(-times / 0.5),
                   rng.uniform(0.01, 0.05, k), rng.uniform(-0.9, 0.9, k))
    z = rng.standard_normal((n, 2))
    t = np.arange(n) / SR
    cracks = np.zeros((n, 2))
    for c0 in sorted(rng.uniform(0.04, 0.3, 9)):
        cracks += hp(z, 3000) * ((t >= c0) * np.exp(-np.maximum(t - c0, 0) / 0.0015))[:, None] * rng.uniform(0.3, 0.8)
    return norm_peak(edge_fade(y * 0.8 + tink + 0.5 * cracks, 0.002, 0.03))


def sfx_boom_sparkle(seed=919):
    n = ns(1.6)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    sub = np.sin(2 * np.pi * np.cumsum(40.0 + 55.0 * np.exp(-t / 0.06)) / SR) * smoothstep(t / 0.002) * np.exp(-t / 0.28)
    z = rng.standard_normal(n)
    crack = bp(z, 1500, 9000) * np.exp(-t / 0.006) * 0.9 + lp(z, 900) * np.exp(-t / 0.05) * 0.35
    mono = np.tanh(1.8 * (sub + crack)) / np.tanh(1.8)
    k = 40
    times = 0.02 + rng.random(k) ** 1.4 * 0.9
    glit = _grains(n, times, rng.choice([2349.3, 2960.0, 3520.0, 4698.6, 5919.9, 7040.0], k),
                   rng.uniform(0.06, 0.2, k) * np.exp(-times / 0.6), rng.uniform(0.03, 0.09, k), rng.uniform(-0.9, 0.9, k))
    out = np.stack([mono, mono], 1) + 0.9 * hp(glit, 2000)
    return norm_peak(edge_fade(hp(out, 28), 0.0002, 0.2))


def sfx_mag_hum(dur, seed=1212):
    """Resonant, slightly detuned rising hum with tremolo; swells, then cuts on the release."""
    dur = float(np.clip(dur, 0.3, 3.0))
    n = ns(dur)
    t = np.arange(n) / SR
    u = t / dur
    f = 146.83 * 2.0 ** (2.0 / 12.0 * u ** 1.5)
    rng = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    fc = 350.0 * (1800.0 / 350.0) ** u
    for ch, det in ((0, -5), (1, 5)):
        ph = 2 * np.pi * np.cumsum(f * 2 ** (det / 1200)) / SR
        acc = np.zeros(n)
        for k in range(1, 22):
            res = 1.0 + 5.0 * np.exp(-((k * f - fc) / (0.25 * fc)) ** 2)
            acc += res / k * np.sin(k * ph + rng.random() * 6.283)
        y[:, ch] = acc
    trem = 1.0 - (0.12 + 0.18 * u) * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(6.0 + 4.0 * u) / SR))
    y *= ((0.15 + 0.85 * u ** 1.1) * trem * smoothstep(t / 0.08))[:, None]
    y[-ns(0.008):] *= np.linspace(1, 0, ns(0.008))[:, None]
    return norm_peak(hp(y, 120))


def sfx_progress(dur, seed=1313):
    dur = float(np.clip(dur, 0.3, 3.0))
    n = ns(dur + 0.05)
    t = np.arange(n) / SR
    u = np.clip(t / dur, 0, 1)
    f = 587.33 * 2.0 ** u                                       # D5 -> D6
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph + 0.4 * np.sin(2 * ph)) * (0.25 + 0.75 * u ** 1.5)
    air = noise_sweep(dur + 0.05, lambda p: 2500.0 * 2.0 ** (1.5 * np.asarray(p)), 0.8, seed, stereo=False)[:n]
    y = y + 0.12 * air * u
    y *= smoothstep(t / 0.04) * smoothstep((n / SR - t) / 0.05)
    return norm_peak(y)


def sfx_chime_v6(notes, taus=(0.9, 0.35, 0.16, 0.05), gap=0.07):
    n = ns(1.8)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for i, m in enumerate(notes):
        f = mtof(m)
        off = i * gap
        tt = np.maximum(t - off, 0.0)
        y = np.zeros(n)
        for (ratio, amp), tau in zip(((1.0, 1.0), (2.0, 0.22), (3.0, 0.08), (4.2, 0.05)), taus):
            y += amp * np.sin(2 * np.pi * f * ratio * tt) * np.exp(-tt / tau)
        y *= (t >= off) * smoothstep(tt / 0.0015)
        pan = -0.25 + 0.5 * i / max(1, len(notes) - 1)
        a = (pan + 1) * np.pi / 4
        out[:, 0] += y * np.cos(a) * np.sqrt(2)
        out[:, 1] += y * np.sin(a) * np.sqrt(2)
    return norm_peak(edge_fade(out, 0.0001, 0.12))


def sfx_impact_big(seed=1414):
    """Trailer hit: pitched boom + sub, bright crack, mid whomp (the reverb tail comes from the SFX hall send)."""
    n = ns(2.2)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    boom = np.sin(2 * np.pi * np.cumsum(33.0 + 80.0 * np.exp(-t / 0.09)) / SR) * smoothstep(t / 0.002) * np.exp(-t / 0.55)
    sub = 0.5 * np.sin(2 * np.pi * 41.2 * t) * smoothstep(t / 0.01) * np.exp(-t / 0.8)
    z = rng.standard_normal((n, 2))
    crack = bp(z, 2000, 11000) * (np.exp(-t / 0.007))[:, None] * 0.9 + hp(z, 6000) * (np.exp(-t / 0.03))[:, None] * 0.25
    whomp = lp(z, 700) * (np.exp(-t / 0.09))[:, None] * 0.5
    low = np.tanh(1.6 * (boom + sub)) / np.tanh(1.6)
    out = np.stack([low, low], 1) + crack + whomp
    return norm_peak(edge_fade(hp(out, 24), 0.0002, 0.3))


def sfx_impact_low(seed=1515):
    y = sfx_impact()
    n = len(y)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    y = y + 0.18 * bp(rng.standard_normal(n), 1500, 7000) * np.exp(-t / 0.005)
    return norm_peak(y)


V6_SFX = ('ui-pop-small', 'mouse-click', 'mouse-release', 'menu-open', 'pop-open', 'tick', 'pickup-tick', 'key-click',
          'key-click-heavy', 'paper-fold', 'fliq-whoosh', 'fliq-whoosh-long', 'whoosh-in', 'whoosh-soft', 'sheet-whoosh',
          'shatter-whoosh', 'boom-sparkle', 'magnetic-hum-start', 'progress-rise', 'success-chime', 'soft-chime',
          'card-flip', 'check-pop', 'chip-pop', 'shimmer', 'impact-low', 'impact-big')

# peak level (dBFS, pre-master), reverb sends (plate, hall), broadband music duck (dB)
V6_LEVEL = {'ui-pop-small': -22, 'mouse-click': -14, 'mouse-release': -18, 'menu-open': -17, 'pop-open': -17,
            'tick': -17.5, 'pickup-tick': -16, 'key-click': -13.5, 'key-click-heavy': -12.5, 'paper-fold': -16,
            'fliq-whoosh': -10.5, 'fliq-whoosh-long': -12.5, 'whoosh-in': -12, 'whoosh-soft': -16, 'sheet-whoosh': -12,
            'shatter-whoosh': -13, 'boom-sparkle': -4, 'magnetic-hum-start': -9, 'progress-rise': -18,
            'success-chime': -14.5, 'soft-chime': -17, 'card-flip': -17, 'check-pop': -16, 'chip-pop': -17,
            'shimmer': -13, 'impact-low': -6, 'impact-big': -2.5}
V6_SEND = {'impact-big': (0.0, 0.35), 'boom-sparkle': (0.1, 0.25), 'impact-low': (0.05, 0.3), 'shimmer': (0.4, 0.15),
           'success-chime': (0.3, 0.1), 'soft-chime': (0.35, 0.15), 'shatter-whoosh': (0.2, 0.1), 'fliq-whoosh': (0.12, 0.05),
           'fliq-whoosh-long': (0.12, 0.08), 'progress-rise': (0.2, 0.0), 'magnetic-hum-start': (0.1, 0.0)}
V6_DUCK = {'ui-pop-small': 1.5, 'mouse-click': 2.5, 'mouse-release': 1.5, 'menu-open': 2.0, 'pop-open': 2.0, 'tick': 1.5,
           'pickup-tick': 2.0, 'key-click': 2.0, 'key-click-heavy': 2.5, 'paper-fold': 2.0, 'card-flip': 1.5,
           'check-pop': 2.5, 'chip-pop': 2.5, 'success-chime': 3.0, 'soft-chime': 2.5, 'whoosh-in': 1.5,
           'fliq-whoosh': 1.5, 'fliq-whoosh-long': 1.5, 'sheet-whoosh': 1.5, 'shatter-whoosh': 0.0, 'whoosh-soft': 1.0}
NO_DIP = {'shatter-whoosh'}          # never carve the music for these (they ride the launch riser)
FAMILY = {'pop': ('ui-pop-small', 'menu-open', 'pop-open', 'check-pop', 'chip-pop'),
          'click': ('mouse-click', 'mouse-release', 'tick', 'pickup-tick', 'key-click', 'key-click-heavy', 'card-flip', 'paper-fold'),
          'whoosh': ('fliq-whoosh', 'fliq-whoosh-long', 'whoosh-in', 'whoosh-soft', 'sheet-whoosh', 'shatter-whoosh'),
          'chime': ('success-chime', 'soft-chime', 'progress-rise', 'shimmer'),
          'impact': ('impact-low', 'impact-big', 'boom-sparkle'),
          'hum': ('magnetic-hum-start',)}


def family_of(typ):
    for fam, members in FAMILY.items():
        if typ in members:
            return fam
    return 'click'


def resolve_sfx(typ):
    if typ in V6_SFX:
        return typ
    low = typ.lower()
    for keys, tgt in ((('impact', 'boom', 'hit', 'slam'), 'impact-low'), (('whoosh', 'swoosh', 'swish', 'fly'), 'whoosh-in'),
                      (('chime', 'bell', 'success', 'ding'), 'soft-chime'), (('shimmer', 'sparkle', 'glitter'), 'shimmer'),
                      (('rise', 'riser', 'progress'), 'progress-rise'), (('hum', 'drone'), 'magnetic-hum-start'),
                      (('key', 'type'), 'key-click'), (('click', 'press'), 'mouse-click'), (('pop', 'open', 'appear'), 'pop-open'),
                      (('paper', 'fold', 'crinkle'), 'paper-fold'), (('flip', 'card'), 'card-flip'), (('tick', 'hover'), 'tick')):
        if any(k in low for k in keys):
            warn(f"unknown cue type '{typ}': using closest family '{tgt}'")
            return tgt
    warn(f"unknown cue type '{typ}': using 'tick'")
    return 'tick'


def make_sfx(typ, cue, ctx):
    """Render one SFX (stereo, peak 1).  ctx gives the chord at the cue and the next cue time."""
    if typ == 'ui-pop-small':
        y = _pop(700.0, 1318.5, 0.022, 0.09, 0.04)
    elif typ == 'mouse-click':
        y = sfx_click()
    elif typ == 'mouse-release':
        y = sfx_release()
    elif typ in ('menu-open', 'pop-open'):
        y = _pop(440.0, 880.0, 0.04, 0.22, 0.1, 0.12, 405, air_tau=0.03)
    elif typ == 'tick':
        y = sfx_tick()
    elif typ == 'pickup-tick':
        y = sfx_pickup_tick()
    elif typ == 'key-click':
        y = sfx_key()
    elif typ == 'key-click-heavy':
        y = sfx_key_heavy()
    elif typ == 'paper-fold':
        y = sfx_paper_fold()
    elif typ == 'card-flip':
        y = sfx_card_flip()
    elif typ == 'check-pop':
        y = _pop(880.0, 1760.0, 0.03, 0.12, 0.05, 0.25, 406)
    elif typ == 'chip-pop':
        y = _pop(660.0, 1174.7, 0.028, 0.11, 0.05, 0.18, 407)
    elif typ == 'fliq-whoosh':
        y = sfx_fliq(float(cue.get('dur') or 0.6), 707)
    elif typ == 'fliq-whoosh-long':
        y = sfx_fliq(float(cue.get('dur') or 1.4), 717)
    elif typ == 'whoosh-in':
        y = sfx_whoosh_v6(float(cue.get('dur') or 0.5), 727)
    elif typ == 'whoosh-soft':
        y = sfx_whoosh_v6(float(cue.get('dur') or 0.8), 737, dark=0.7)
    elif typ == 'sheet-whoosh':
        y = sfx_whoosh_v6(float(cue.get('dur') or 0.6), 747, flutter=True)
    elif typ == 'shatter-whoosh':
        y = sfx_shatter()
    elif typ == 'boom-sparkle':
        y = sfx_boom_sparkle()
    elif typ == 'magnetic-hum-start':
        y = sfx_mag_hum(ctx['next_t'] - cue['t'] if ctx.get('next_t') else 1.5)
    elif typ == 'progress-rise':
        y = sfx_progress(ctx['chime_t'] - cue['t'] if ctx.get('chime_t') else 1.4)
    elif typ == 'success-chime':
        m1, m2 = chime_pair(ctx['chord'])
        y = sfx_chime_v6([m1, m2, m1 + 7 if (m1 + 7) % 12 in chord_pcs(ctx['chord']) else m2 + 3])
    elif typ == 'soft-chime':
        m1, m2 = chime_pair(ctx['chord'])
        y = sfx_chime_v6([m1 - 12, m2 - 12], taus=(1.4, 0.5, 0.2, 0.06), gap=0.12)
    elif typ == 'shimmer':
        y = sfx_shimmer(ctx['chord'])
    elif typ == 'impact-low':
        y = sfx_impact_low()
    elif typ == 'impact-big':
        y = sfx_impact_big()
    else:
        y = sfx_tick()
    return y if y.ndim == 2 else np.stack([y, y], 1)


# ============================================================================
# Timeline helpers, metering, master, files, review image (shared with v5)
# ============================================================================

def build_bars(secs, BAR, final_t):
    bars = []
    for si, s in enumerate(secs):
        st = s['style']
        chords = st['chords']
        t, i = s['start'], 0
        while t < s['end'] - 0.05:
            t1 = min(t + BAR, s['end'])
            chord = chords[i % len(chords)]
            fin = False
            if 'final' in st and final_t is not None and s['start'] - 1e-6 <= final_t < s['end']:
                if t >= final_t - 1e-6:
                    chord, fin = st['final'], True
                elif t1 > final_t + 1e-6:
                    t1 = final_t
            bars.append(dict(t0=t, t1=t1, si=si, i=i, chord=chord, st=st, sec=s, final=fin))
            t, i = t1, i + 1
    return bars


def tie_segments(bars, notes_of, breaks):
    """Merge consecutive bars holding the same note per voice slot -> (t0, t1, midi, slot)."""
    V = max((len(notes_of(b) or []) for b in bars), default=0)
    cur = [None] * V
    segs = []
    for b in bars:
        notes = notes_of(b) or []
        brk = any(abs(b['t0'] - x) < 1e-6 for x in breaks)
        for v in range(V):
            m = notes[v] if v < len(notes) else None
            c = cur[v]
            if c is not None and (brk or m != c[2] or abs(c[1] - b['t0']) > 1e-6):
                segs.append((c[0], c[1], c[2], v))
                c = None
            if m is not None:
                if c is None:
                    c = [b['t0'], b['t1'], m]
                else:
                    c[1] = b['t1']
            cur[v] = c
    for v, c in enumerate(cur):
        if c is not None:
            segs.append((c[0], c[1], c[2], v))
    return segs


def interp_curve(pts, N, log_=False):
    pts = sorted(pts, key=lambda p: p[0])
    ts = np.array([p[0] for p in pts])
    vs = np.array([p[1] for p in pts], float)
    tt = np.arange(N) / SR
    if log_:
        return np.exp(np.interp(tt, ts, np.log(np.maximum(vs, 1e-6))))
    return np.interp(tt, ts, vs)


def sec_curve(secs, key, N, ramp=0.012):
    pts = []
    for s in secs:
        v = float(s['style'].get(key, 0.0))
        pts += [(s['start'] + ramp / 2, v), (s['end'] - ramp / 2, v)]
    return interp_curve(pts, N)


def cutoff_curve(secs, key, N):
    pts = []
    for s in secs:
        L = s['end'] - s['start']
        for fr, v in s['style'][key]:
            pts.append((min(max(s['start'] + fr * L, s['start'] + 0.004), s['end'] - 0.004), v))
    return interp_curve(pts, N, log_=True)


def duck_shape(times, N, pre=0.003, hold=0.025, rel=0.23):
    shp = np.zeros(N)
    npre, nh, nr = max(1, ns(pre)), ns(hold), max(1, ns(rel))
    tpl = np.concatenate([np.linspace(0, 1, npre, endpoint=False), np.ones(nh), 1 - smoothstep(np.arange(nr) / nr)])
    for t in times:
        i0 = ns(t) - npre
        j0, j1 = max(0, i0), min(N, i0 + len(tpl))
        if j1 > j0:
            shp[j0:j1] = np.maximum(shp[j0:j1], tpl[j0 - i0:j1 - i0])
    return shp


# ============================================================================
# Loudness metering (BS.1770 / EBU R128 style, own implementation for iteration)
# ============================================================================

_KB1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
_KA1 = [1.0, -1.69065929318241, 0.73248077421585]
_KB2 = [1.0, -2.0, 1.0]
_KA2 = [1.0, -1.99004745483398, 0.99007225036621]


def kweight(x):
    return signal.lfilter(_KB2, _KA2, signal.lfilter(_KB1, _KA1, x, axis=0), axis=0)


def block_power(x, win=0.4, hop=0.1):
    y = kweight(x)
    p = (y ** 2).sum(axis=1) if y.ndim == 2 else y ** 2
    c = np.concatenate([[0.0], np.cumsum(p)])
    w, h = ns(win), ns(hop)
    st = np.arange(0, max(1, len(p) - w + 1), h)
    return (c[np.minimum(st + w, len(p))] - c[st]) / w


def lufs_p(pw):
    return -0.691 + 10 * np.log10(np.maximum(pw, 1e-20))


def integrated(x):
    pw = block_power(x)
    lv = lufs_p(pw)
    g = pw[lv > -70]
    if len(g) == 0:
        return -70.0
    rel = lufs_p(g.mean()) - 10.0
    g2 = pw[(lv > -70) & (lv > rel)]
    return float(lufs_p(g2.mean()))


def loudness_seg(x):
    if len(x) < ns(0.05):
        return -99.0
    return float(lufs_p(np.mean((kweight(x) ** 2).sum(axis=1))))


def os_peak(x, chunk=4 * SR, pad=256):
    """Per-sample max |x| of the 4x-oversampled signal (inter-sample peaks), computed in chunks."""
    n = len(x)
    out = np.empty(n)
    for i in range(0, n, chunk):
        a, b = max(0, i - pad), min(n, i + chunk + pad)
        up = signal.resample_poly(x[a:b], 4, 1, axis=0)
        pk = np.abs(up).max(axis=1).reshape(-1, 4).max(axis=1)
        j1 = min(n, i + chunk)
        out[i:j1] = pk[i - a:j1 - a]
    return np.maximum(out, np.abs(x).max(axis=1))


def true_peak_db(x):
    return float(20 * np.log10(os_peak(x).max() + 1e-12))


# ============================================================================
# Master: 4x-oversampled look-ahead true-peak limiter
# ============================================================================

def window_max(a, back, fwd):
    size = back + fwd + 1
    return maximum_filter1d(a, size=size, origin=back - size // 2, mode='constant', cval=0.0)


def limiter(x, ceiling_db=-1.3, look_ms=1.5, hold_ms=6.0, release_dbps=38.0):
    """Gain computed from the 4x-oversampled peak; look-ahead via forward window max,
    exponential (linear-in-dB) release via a running maximum, then a box-smoothed attack."""
    n = len(x)
    pk = os_peak(x)
    need = np.maximum(0.0, 20 * np.log10(np.maximum(pk, 1e-12)) - ceiling_db)
    L, H = max(1, ns(look_ms / 1000)), ns(hold_ms / 1000)
    a = window_max(need, H, L)
    k = np.arange(n) * (release_dbps / SR)
    env = np.maximum.accumulate(a + k) - k
    size = L + 1
    env = uniform_filter1d(env, size=size, origin=L - size // 2, mode='nearest')
    return x * db2lin(-env)[:, None], env


def finalize(y, dur):
    """5 ms fade-in; raised-cosine fade to digital silence over the last 2 s."""
    N = len(y)
    out = y.copy()
    fi = ns(0.005)
    out[:fi] *= (np.sin(0.5 * np.pi * np.arange(fi) / fi) ** 2)[:, None]
    f0, f1 = ns(max(0.0, dur - 2.0)), ns(dur - 0.05)
    w = np.ones(N)
    if f1 > f0:
        w[f0:f1] = 0.5 + 0.5 * np.cos(np.pi * np.arange(f1 - f0) / (f1 - f0))
    w[f1:] = 0.0
    return out * w[:, None]


def master(x, gain_db, ceiling_db, dur):
    y, env = limiter(x * db2lin(gain_db), ceiling_db)
    return finalize(y, dur), env


def master_to_target(x, target, ceiling_db, dur, gain0=None):
    g = gain0 if gain0 is not None else target - integrated(x)
    y = env = None
    for _ in range(8):
        y, env = master(x, g, ceiling_db, dur)
        L = integrated(y)
        if abs(L - target) < 0.03:
            break
        g += target - L
    return y, g, env


# ============================================================================
# Files / ffmpeg
# ============================================================================

def _pcm24_bytes(path):
    raw = Path(path).read_bytes()
    i = raw.index(b'data')
    nbytes = struct.unpack('<I', raw[i + 4:i + 8])[0]
    return raw[i + 8:i + 8 + nbytes]


def read_pcm24(path):
    b = np.frombuffer(_pcm24_bytes(path), np.uint8).reshape(-1, 3)
    q = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
    q = np.where(q >= 1 << 23, q - (1 << 24), q)
    return (q / 8388607.0).reshape(-1, 2)


def write_wav24(path, x, prefix_from=None, prefix_n=0):
    q = np.clip(np.round(np.asarray(x, float) * 8388607.0), -8388608, 8388607).astype('<i4')
    data = q.reshape(-1).view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    if prefix_from is not None and prefix_n > 0:          # byte-exact splice of an approved opening
        pre = _pcm24_bytes(prefix_from)[:prefix_n * 6]
        data = pre + data[len(pre):]
    nch = x.shape[1]
    ba = nch * 3
    hdr = (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVE' + b'fmt '
           + struct.pack('<IHHIIHH', 16, 1, nch, SR, SR * ba, ba, 24) + b'data' + struct.pack('<I', len(data)))
    Path(path).write_bytes(hdr + data)


def ffmpeg_ebur128(path):
    cmd = ['ffmpeg', '-hide_banner', '-nostats', '-nostdin', '-i', str(path),
           '-af', 'ebur128=peak=true:framelog=info', '-f', 'null', '-']
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    txt = r.stderr
    frames = [(float(m.group(1)), float(m.group(2)), float(m.group(3))) for m in re.finditer(
        r't:\s*([0-9.]+)\s+TARGET:\S+\s+LUFS\s+M:\s*(-?[0-9.]+|-?inf)\s+S:\s*(-?[0-9.]+|-?inf)', txt)]
    summ = txt[txt.rfind('Summary:'):]

    def grab(pat):
        m = re.search(pat, summ)
        return float(m.group(1)) if m else float('nan')

    return dict(I=grab(r'I:\s+(-?[0-9.]+|-inf)\s+LUFS'), LRA=grab(r'LRA:\s+(-?[0-9.]+)\s+LU'),
                TP=grab(r'Peak:\s+(-?[0-9.]+|-inf)\s+dBFS'), frames=frames)


# ============================================================================
# Review image (own PNG writer + 5x7 bitmap font; no matplotlib needed)
# ============================================================================

FONT = {
    'A': [14, 17, 17, 31, 17, 17, 17], 'B': [30, 17, 17, 30, 17, 17, 30], 'C': [14, 17, 16, 16, 16, 17, 14],
    'D': [30, 17, 17, 17, 17, 17, 30], 'E': [31, 16, 16, 30, 16, 16, 31], 'F': [31, 16, 16, 30, 16, 16, 16],
    'G': [14, 17, 16, 23, 17, 17, 15], 'H': [17, 17, 17, 31, 17, 17, 17], 'I': [14, 4, 4, 4, 4, 4, 14],
    'J': [7, 2, 2, 2, 2, 18, 12], 'K': [17, 18, 20, 24, 20, 18, 17], 'L': [16, 16, 16, 16, 16, 16, 31],
    'M': [17, 27, 21, 21, 17, 17, 17], 'N': [17, 17, 25, 21, 19, 17, 17], 'O': [14, 17, 17, 17, 17, 17, 14],
    'P': [30, 17, 17, 30, 16, 16, 16], 'Q': [14, 17, 17, 17, 21, 18, 13], 'R': [30, 17, 17, 30, 20, 18, 17],
    'S': [15, 16, 16, 14, 1, 1, 30], 'T': [31, 4, 4, 4, 4, 4, 4], 'U': [17, 17, 17, 17, 17, 17, 14],
    'V': [17, 17, 17, 17, 17, 10, 4], 'W': [17, 17, 17, 21, 21, 21, 10], 'X': [17, 17, 10, 4, 10, 17, 17],
    'Y': [17, 17, 17, 10, 4, 4, 4], 'Z': [31, 1, 2, 4, 8, 16, 31],
    '0': [14, 17, 19, 21, 25, 17, 14], '1': [4, 12, 4, 4, 4, 4, 14], '2': [14, 17, 1, 2, 4, 8, 31],
    '3': [31, 2, 4, 2, 1, 17, 14], '4': [2, 6, 10, 18, 31, 2, 2], '5': [31, 16, 30, 1, 1, 17, 14],
    '6': [6, 8, 16, 30, 17, 17, 14], '7': [31, 1, 2, 4, 8, 8, 8], '8': [14, 17, 17, 14, 17, 17, 14],
    '9': [14, 17, 17, 15, 1, 2, 12], '-': [0, 0, 0, 31, 0, 0, 0], '.': [0, 0, 0, 0, 0, 12, 12],
    ':': [0, 12, 12, 0, 12, 12, 0], '/': [0, 1, 2, 4, 8, 16, 0], '=': [0, 0, 31, 0, 31, 0, 0],
    '(': [2, 4, 8, 8, 8, 4, 2], ')': [8, 4, 2, 2, 2, 4, 8], '+': [0, 4, 4, 31, 4, 4, 0],
    '#': [10, 10, 31, 10, 31, 10, 10], ',': [0, 0, 0, 0, 12, 4, 8], '%': [24, 25, 2, 4, 8, 19, 3],
    '_': [0, 0, 0, 0, 0, 0, 31], ' ': [0] * 7, '>': [8, 4, 2, 1, 2, 4, 8], '<': [2, 4, 8, 16, 8, 4, 2],
}


def draw_text(img, x, y, text, color, scale=2):
    H, W = img.shape[:2]
    for chh in str(text).upper():
        g = FONT.get(chh, FONT[' '])
        for r, bits in enumerate(g):
            for c in range(5):
                if bits & (1 << (4 - c)):
                    y0, x0 = y + r * scale, x + c * scale
                    if 0 <= y0 < H and 0 <= x0 < W:
                        img[y0:y0 + scale, x0:x0 + scale] = color
        x += 6 * scale
    return x


def blend(img, ys, xs, color, alpha=1.0):
    if alpha >= 1.0:
        img[ys, xs] = color
    else:
        img[ys, xs] = (img[ys, xs] * (1 - alpha) + np.array(color) * alpha).astype(np.uint8)


def write_png(path, img):
    h, w, _ = img.shape
    raw = np.concatenate([np.zeros((h, 1), np.uint8), img.reshape(h, w * 3)], axis=1).tobytes()

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


FAM_COLORS = {'pop': (255, 135, 215), 'click': (110, 215, 255), 'whoosh': (150, 160, 255), 'chime': (255, 238, 110),
              'impact': (255, 85, 85), 'hum': (190, 255, 150)}
CUE_COLORS = {'tick': (170, 170, 175), 'click': (110, 215, 255), 'key': (255, 196, 110), 'pop': (255, 135, 215),
              'whoosh': (150, 160, 255), 'land': (190, 255, 150), 'chime': (255, 238, 110),
              'impact': (255, 85, 85), 'shimmer': (205, 150, 255)}
CUE_ABBR = {'tick': 'T', 'click': 'C', 'key': 'K', 'pop': 'P', 'whoosh': 'W', 'land': 'L', 'chime': 'CH',
            'impact': 'I', 'shimmer': 'SH'}


def render_review(path, mix, tl, meas):
    dur = tl['duration']
    W, H = 1800, 1000
    ML, MR = 80, 24
    PW = W - ML - MR
    y_spec, SH = 100, 500
    y_cue, CH = y_spec + SH + 4, 52
    y_ld, LH = y_cue + CH + 16, 250
    y_ax = y_ld + LH + 6
    img = np.empty((H, W, 3), np.uint8)
    img[:] = (11, 14, 28)

    def X(t):
        return int(round(ML + (float(t) / dur) * (PW - 1)))

    # --- spectrogram (0-12 kHz, log-ish axis)
    mono = mix.mean(axis=1)
    nper, hop = 2048, 480
    _, tt, Z = signal.stft(mono, fs=SR, nperseg=nper, noverlap=nper - hop, boundary=None, padded=False)
    S = 20 * np.log10(np.abs(Z) + 1e-10)
    S -= S.max()
    tc = tt + 0.5 * nper / SR - nper / SR / 2
    cols = np.clip((tc / dur * PW).astype(int), 0, PW - 1)
    starts = np.searchsorted(cols, np.arange(PW))
    starts = np.minimum(starts, S.shape[1] - 1)
    acc = np.maximum.reduceat(S.T, starts, axis=0)
    u = 1.0 - np.arange(SH) / (SH - 1)
    fr = 250.0 * ((1 + 12000.0 / 250.0) ** u - 1.0)
    bins = np.clip(np.round(fr / (SR / nper)).astype(int), 0, S.shape[0] - 1)
    spec = acc[:, bins].T
    v = np.clip((spec + 95.0) / 95.0, 0, 1)
    anchors = [(0.0, (0, 0, 4)), (0.15, (31, 12, 72)), (0.3, (85, 15, 109)), (0.45, (136, 34, 106)),
               (0.6, (186, 54, 85)), (0.72, (227, 89, 51)), (0.84, (249, 140, 10)), (0.93, (249, 201, 50)),
               (1.0, (252, 255, 164))]
    xs = np.linspace(0, 1, 256)
    lut = np.stack([np.interp(xs, [a[0] for a in anchors], [a[1][c] for a in anchors]) for c in range(3)], 1).astype(np.uint8)
    img[y_spec:y_spec + SH, ML:ML + PW] = lut[(v * 255).astype(int)]
    for fl, lab in ((100, '100'), (250, '250'), (500, '500'), (1000, '1K'), (2000, '2K'), (5000, '5K'), (10000, '10K')):
        r = int(round((1 - math.log(1 + fl / 250.0) / math.log(1 + 12000 / 250.0)) * (SH - 1)))
        img[y_spec + r, ML - 6:ML] = (200, 200, 210)
        draw_text(img, ML - 8 - 6 * 2 * len(lab), y_spec + r - 7, lab, (200, 200, 210), 2)
    draw_text(img, 8, y_spec - 18, 'HZ', (150, 150, 170), 2)

    # --- loudness panel
    img[y_ld:y_ld + LH, ML:ML + PW] = (18, 22, 42)

    def Y(l):
        return int(round(y_ld + (-5.0 - np.clip(l, -45, -5)) / 40.0 * (LH - 1)))

    for l in (-10, -14, -20, -23, -30, -40):
        c = (90, 200, 140) if l == -14 else (55, 62, 92)
        img[Y(l), ML:ML + PW] = c
        draw_text(img, ML - 8 - 12 * len(str(l)), Y(l) - 7, str(l), (170, 170, 190), 2)
    draw_text(img, W - 560, y_ld + 6, 'LUFS  SHORT-TERM = CYAN, MOMENTARY = GREY', (150, 150, 170), 1)
    fr_ = meas.get('frames') or []
    for idx, col, th in ((1, (100, 110, 150), 1), (2, (80, 225, 255), 2)):
        pts = [(X(f[0]), Y(f[idx])) for f in fr_ if f[idx] > -70]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            if x1 < x0 or x1 - x0 > 6:
                continue
            for xx in range(x0, x1 + 1):
                yy = int(round(y0 + (y1 - y0) * ((xx - x0) / max(1, x1 - x0))))
                lo_, hi_ = min(yy, y0 if xx == x0 else yy), max(yy, y0 if xx == x0 else yy)
                img[max(y_ld, lo_ - th + 1):min(y_ld + LH, hi_ + th), xx] = col

    # --- cue lines + labels
    for k, c in enumerate(tl['cues']):
        x = X(c['t'])
        col = FAM_COLORS[family_of(c['type'])]
        blend(img, slice(y_spec, y_spec + SH), x, col, 0.55)
        row = k % 3
        img[y_cue:y_cue + 4 + row * 16, x] = col
        draw_text(img, x + 2, y_cue + 4 + row * 16, ''.join(w[0] for w in c['type'].split('-')).upper()[:3], col, 2)
    # --- riser targets (dashed)
    for t in tl['risers']:
        x = X(t)
        for yy in range(y_spec, y_spec + SH, 10):
            img[yy:yy + 6, max(0, x - 1):x + 2] = (80, 255, 190)
        draw_text(img, x + 4, y_spec + 4, 'R', (80, 255, 190), 2)
    # --- section boundaries
    for k, s in enumerate(tl['sections']):
        x = X(s['start'])
        img[y_spec - 30:y_ax, x:x + 2] = (235, 235, 245)
        draw_text(img, x + 5, y_spec - 52 + (k % 2) * 20, f"{s['name']} {s['start']:g}", (235, 235, 245), 2)
    x = X(dur)
    img[y_spec - 30:y_ax, x - 1:x + 1] = (235, 235, 245)
    # --- time axis
    for t in np.arange(0, dur + 1e-6, 2.0):
        x = X(t)
        img[y_ax:y_ax + (10 if t % 4 == 0 else 5), x] = (180, 180, 195)
        if t % 4 == 0:
            draw_text(img, x - 6, y_ax + 14, f'{t:g}', (180, 180, 195), 2)
    draw_text(img, 8, y_ax + 14, 'SEC', (150, 150, 170), 2)
    # --- title + legend
    title = (f"AIRFLIQ FILM V6 MIX   I {meas['I']:.1f} LUFS   TP {meas['TP']:.1f} DBTP   LRA {meas['LRA']:.1f} LU"
             f"   {tl['bpm']:g} BPM   SPECTROGRAM 0-12 KHZ (LOG-ISH)")
    draw_text(img, 10, 8, title, (240, 240, 250), 2)
    x = 10
    for fam, col in FAM_COLORS.items():
        img[30:40, x:x + 10] = col
        x = draw_text(img, x + 14, 31, fam + ' sfx', (200, 200, 215), 1) + 12
    img[30:40, x:x + 10] = (80, 255, 190)
    draw_text(img, x + 14, 31, 'R=RISER TARGET / IMPACT (DASHED)   WHITE=SECTION STARTS   LABEL=CUE INITIALS', (200, 200, 215), 1)
    write_png(path, img)


BANDS = [(45, 90), (90, 180), (180, 355), (355, 710), (710, 1400), (1400, 2800), (2800, 5600), (5600, 11200)]
# A-weighting at the band centres: picks the band an effect is actually heard in (not its low body)
BAND_AW_DB = np.array([-26.2, -16.1, -8.6, -3.2, 0.0, 1.2, 1.0, -1.1])


def active_len(sig, frac=0.9):
    e = np.cumsum((sig ** 2).sum(axis=1))
    return int(np.searchsorted(e, frac * e[-1])) + 1 if e[-1] > 0 else len(sig)


def cue_band_snr(inst, music, target=3.5, max_dip=9.0):
    """Per cue: SFX vs music energy in the octave band the effect is heard in (A-weighted dominant band),
    over the effect's active window.  Where the music would mask it, carve a short zero-phase band dip
    (dynamic-EQ style) into the music.  Returns (music_out, rows)."""
    N = len(music)
    mband = {}

    def music_band(b):
        if b not in mband:
            mband[b] = bp(music, BANDS[b][0], BANDS[b][1], order=3, zp=True)
        return mband[b]

    rows, todo = [], []
    for c in inst:
        s = c['sig']
        n_act = max(ns(0.03), min(len(s), active_len(s)))
        x = np.pad(s.mean(axis=1), (2048, 2048))
        es = np.array([np.mean(bp(x, lo, hi, order=3, zp=True)[2048:2048 + n_act] ** 2) for lo, hi in BANDS])
        b = int(np.argmax(10 * np.log10(es + 1e-20) + BAND_AW_DB))
        i0 = ns(c['t'])
        i1 = min(N, i0 + n_act)
        em = float(np.mean(music_band(b)[i0:i1].mean(axis=1) ** 2)) + 1e-14
        snr = 10 * math.log10(es[b] / em + 1e-14)
        rows.append(dict(t=round(c['t'], 3), type=c['type'], band_hz=list(BANDS[b]), snr_db_before=round(snr, 1),
                         window_ms=round(1000 * n_act / SR, 1)))
        todo.append((b, c['t'], n_act, snr, i0, i1, es[b], c['type'] in NO_DIP))
    gdb = {}
    for b, t, n_act, snr, i0, i1, _, nodip in todo:
        if snr >= target:
            continue
        need = min(3.0 if nodip else max_dip, target - snr + 0.5)    # riser-borne cues: band-only, <= 3 dB
        g = gdb.setdefault(b, np.zeros(N))
        t0, t1 = t - 0.015, t + n_act / SR + 0.04
        i = np.arange(max(0, ns(t0 - 0.03)), min(N, ns(t1 + 0.14)))
        tt = i / SR
        shp = np.minimum(smoothstep((tt - (t0 - 0.03)) / 0.03), 1 - smoothstep((tt - t1) / 0.14))
        g[i] = np.minimum(g[i], -need * shp)
    out = music.copy()
    for b, g in gdb.items():
        out -= (1 - db2lin(g))[:, None] * music_band(b)
    for r, (b, t, n_act, snr, i0, i1, esb, _) in zip(rows, todo):
        gl = db2lin(gdb[b][i0:i1]) if b in gdb else 1.0
        em = float(np.mean((music_band(b)[i0:i1].mean(axis=1) * gl) ** 2)) + 1e-14
        r['snr_db'] = round(10 * math.log10(esb / em + 1e-14), 1)
        r['music_dip_db'] = round(float(-gdb[b][i0:i1].min()), 1) if b in gdb else 0.0
    return out, rows



# ============================================================================
# v6 score data (D major / B minor, 120 BPM)
# ============================================================================

CHORDS = {
    'Dmaj9':    dict(root=2,  body=50, ust=[57, 61, 64, 66], pool=[69, 73, 74, 76, 78, 81]),
    'Dmaj9/F#': dict(root=6,  body=50, ust=[57, 61, 64, 66], pool=[69, 73, 74, 76, 78, 81]),
    'A6/C#':    dict(root=1,  body=52, ust=[57, 59, 64, 66], pool=[69, 71, 73, 76, 78, 81]),
    'Bm9':      dict(root=11, body=50, ust=[54, 57, 61, 66], pool=[69, 71, 73, 74, 78, 81]),
    'Gmaj9#11': dict(root=7,  body=50, ust=[57, 59, 62, 66], pool=[67, 71, 73, 74, 78, 81]),
    'Em9':      dict(root=4,  body=52, ust=[55, 59, 62, 66], pool=[67, 71, 74, 76, 78, 83]),
    'A13sus4':  dict(root=9,  body=52, ust=[55, 59, 62, 66], pool=[69, 71, 74, 76, 78, 81]),
    # v6.1 (B minor, plain triad / octave voicings)
    'Bm':     dict(root=11, body=47, ust=[59, 62, 66, 71], pool=[71, 74, 78, 81, 83, 86]),
    'G':      dict(root=7,  body=50, ust=[59, 62, 67, 71], pool=[71, 74, 79, 83, 86, 91]),
    'D':      dict(root=2,  body=50, ust=[57, 62, 66, 69], pool=[69, 74, 78, 81, 86, 90]),
    'A':      dict(root=9,  body=52, ust=[57, 61, 64, 69], pool=[69, 73, 76, 81, 85, 88]),
    'Em':     dict(root=4,  body=52, ust=[59, 64, 67, 71], pool=[71, 76, 79, 83, 88, 91]),
    'F#sus4': dict(root=6,  body=54, ust=[61, 66, 71, 73], pool=[73, 78, 83, 85, 90, 95]),
    'F#':     dict(root=6,  body=54, ust=[61, 66, 70, 73], pool=[73, 78, 82, 85, 90, 94]),
    'B':      dict(root=11, body=47, ust=[59, 63, 66, 71], pool=[71, 75, 78, 83, 87, 90]),
}

P_A1 = [(4, 1.0), (1, .42), (2, .52), (3, .86), (1, .42), (2, .52), (5, .95), (2, .48),
        (4, .9), (1, .42), (2, .52), (3, .82), (1, .42), (2, .52), (5, .9), (2, .48)]
P_A2 = [(4, 1.0), (1, .42), (2, .52), (3, .86), (1, .42), (2, .52), (5, .95), (2, .48),
        (3, .9), (1, .42), (2, .52), (2, .8), (0, .45), (1, .5), (0, .85), (1, .46)]
P_B1 = [(5, 1.0), (2, .42), (3, .52), (4, .86), (2, .42), (3, .52), (5, .95), (3, .48),
        (4, .9), (2, .42), (3, .52), (5, .85), (2, .42), (3, .52), (4, .9), (3, .48)]
P_B2 = [(5, 1.0), (2, .42), (3, .52), (4, .86), (2, .42), (3, .52), (5, .95), (3, .48),
        (4, .9), (2, .42), (3, .52), (3, .8), (1, .42), (2, .5), (1, .85), (2, .46)]
P_SOFT = [(4, .8), None, (1, .4), (3, .6), None, (2, .4), (5, .7), None,
          (4, .7), None, (1, .4), (3, .55), None, (2, .4), (1, .6), None]
P_SPARK = [(5, .7), (2, .35), (4, .5), (1, .35), (5, .6), (3, .35), (4, .5), (2, .35),
           (5, .65), (2, .35), (4, .5), (1, .35), (3, .6), (2, .35), (4, .5), (0, .4)]
P_T1 = [(4, .9), None, (4, .5), None, (4, .72), None, (4, .5), None,
        (4, .85), None, (4, .5), None, (4, .72), None, (4, .5), None]
P_T3 = [e if e is not None else ((5 if i % 4 == 3 else 2), .28 + .3 * i / 15) for i, e in enumerate(P_T1)]


def _thin(p):
    return [None if (e is None or i % 4 == 1) else (e[0], e[1] if e[1] >= .8 else e[1] * .8) for i, e in enumerate(p)]


PATTERNS = {'tick': ([P_T1, P_T3], -12), 'A': ([P_A1, P_A2], 0), 'B': ([P_B1, P_B2], 0),
            'Blite': ([_thin(P_B1), _thin(P_B2)], 0), 'soft': ([P_SOFT], 0), 'sparkle': ([P_SPARK], 12)}
# the hook: 2-bar supersaw stab figure (16th step, top-note pool index, velocity) - 3-3-4-2-2-2 / 3-3-2-3-3
STAB_BARS = [[(0, 0, 1.0), (6, 0, .9), (12, 0, .85)],
             [(0, 0, 1.0), (6, 0, .9), (10, 0, .8), (12, 0, .85), (14, 0, .75)]]
MOTIF = [(0, 78, 1.0), (2, 83, .9), (4, 81, .85), (7, 78, .95)]      # F#5-B5-A5-F#5, every 2 bars
FINAL_MOTIF = [(0.0, 78, .9), (1.5, 76, .8), (3.0, 81, .85), (4.0, 78, .7), (5.5, 76, .6), (6.5, 74, .7)]

_BASE = dict(pad=0.25, air=0.0, arp=None, arpl=0.0, motif=1.0, bright=0.7, bassmode='drive', bassl=1.0, kick=1.0, hats=0.9,
             clap=1.0, ghost=0.6, openhat=1.0, stab=0.9, sc=1.0, dbl=0.0, trem=0.0, retrig=False, bloom=False,
             clutter=0.0, mute=False, padcut=[(0, 2600), (1, 3000)], arpcut=[(0, 5000), (1, 6000)])


def _S(**kw):
    d = dict(_BASE)
    d.update(kw)
    return d


STYLES = {
    'cold-open': _S(chords=['Bm9'], pad=0.5, kick=0, hats=0, clap=0, ghost=0, sc=0, stab=0, arp='tick', arpl=0.6,
                    bright=0.3, bassmode='pulse', bassl=0.6, clutter=1.0, trem=1.0, retrig=True,
                    padcut=[(0, 300), (1, 1700)], arpcut=[(0, 900), (1, 3500)]),
    'stop': _S(chords=['Bm9'], mute=True, pad=0, arp=None, arpl=0, kick=0, hats=0, clap=0, ghost=0, stab=0, bassl=0, sc=0, motif=0),
    'bass-hit': _S(chords=['Bm'], mute=True, pad=0, kick=0, hats=0, clap=0, ghost=0, openhat=0, stab=0, bassl=0, sc=0, motif=0),
    'launch-riser': _S(chords=['F#sus4'], pad=0.2, kick=0, hats=0, clap=0, ghost=0, openhat=0, stab=0, motif=0,
                       bassmode='none', bassl=0, sc=0, padcut=[(0, 600), (1, 4000)]),
    'drop-1': _S(chords=['Bm', 'G', 'D', 'A'], stab=1.0, bassmode='reese', retrig=True),
    'drag': _S(chords=['Bm', 'G', 'D', 'A'], stab=0.85, bassmode='reese'),
    'shortcut': _S(chords=['Em', 'Bm', 'G', 'A'], hats=0.55, openhat=0.6, ghost=0.0, stab=0.6, motif=0.7, bassmode='reese',
                   padcut=[(0, 2000), (1, 2400)]),
    'menu': _S(chords=['Bm', 'G', 'A'], stab=0.9, bassmode='reese'),
    'private': _S(chords=['Bm', 'G', 'F#sus4'], pad=0.42, kick=0, hats=0, clap=0, ghost=0, openhat=0, stab=0, motif=0, sc=0,
                  bassmode='pulse8', bassl=0.3, padcut=[(0, 900), (0.6, 800), (1, 3500)]),
    'drop-2': _S(chords=['Bm', 'G', 'Em'], pad=0.3, stab=1.15, bright=0.95, hats=1.05, ghost=1.0, bassmode='reese', bassl=1.1,
                 retrig=True, padcut=[(0, 3200), (1, 3800)]),
    'finale': _S(chords=['F#'], final='B', pad=0.55, air=0.4, kick=0, hats=0, clap=0, ghost=0, openhat=0, sc=0, stab=0,
                 motif=0, bright=0.7, bassmode='sustain', bassl=0.6, retrig=True, bloom=True,
                 padcut=[(0, 3500), (0.4, 3000), (1, 1800)]),
}


def style_for(name):
    if name in STYLES:
        return STYLES[name]
    low = name.lower()
    for keys, st in ((('stop', 'cut', 'silence'), 'stop'), (('open', 'intro', 'cold'), 'cold-open'),
                     (('logo', 'title', 'build'), 'logo-build'), (('final', 'close', 'outro', 'end'), 'finale'),
                     (('break', 'private', 'calm'), 'private'), (('drop-2', 'climax', 'pro'), 'drop-2'),
                     (('drop',), 'drop-1'), (('shortcut', 'light'), 'shortcut')):
        if any(k in low for k in keys):
            warn(f"section '{name}' has no style; using '{st}'")
            return STYLES[st]
    warn(f"section '{name}' has no style; using the 'menu' groove style")
    return STYLES['menu']


# ============================================================================
# Cue sheet (film-v6 format)
# ============================================================================

def load_cues(path):
    d = json.loads(Path(path).read_text())
    dur = float(d.get('duration') or 60.0)
    raw = sorted(d.get('sections') or [], key=lambda s: float(s.get('t', 0)))
    spans = [s for s in raw if s.get('end') is not None]
    marks = [s for s in raw if s.get('end') is None]
    secs = []
    for i, s in enumerate(spans):
        st = float(s['t'])
        en = min(float(s['end']), float(spans[i + 1]['t']) if i + 1 < len(spans) else dur, dur)
        if en - st > 0.05:
            secs.append({'name': str(s.get('name', f'section{i}')), 'start': st, 'end': en, 'mood': s.get('mood', '')})
    if not secs:
        secs = [{'name': 'menu', 'start': 0.0, 'end': dur, 'mood': ''}]
    secs[0]['start'] = 0.0
    for a, b in zip(secs, secs[1:]):
        a['end'] = b['start']
    secs[-1]['end'] = dur
    riser_marks = []
    for m in marks:
        t = float(m['t'])
        name = str(m.get('name', ''))
        low = name.lower()
        if any(k in low for k in ('stop', 'cut', 'silence', 'hit')):
            for i, s in enumerate(secs):
                if s['start'] < t < s['end'] - 0.05:
                    secs.insert(i + 1, {'name': name, 'start': t, 'end': s['end'], 'mood': m.get('mood', '')})
                    s['end'] = t
                    break
        elif any(k in low for k in ('riser', 'build', 'rise')):
            riser_marks.append(t)
        else:
            warn(f"marker section '{name}' at {t}s not understood; ignored")
    cues = []
    for c in d.get('sfx') or []:
        try:
            cues.append({'t': float(c['t']), 'type': str(c.get('type', '')), 'dur': c.get('dur'),
                         'gain': float(c.get('gain', 1.0)), 'pan': float(np.clip(float(c.get('pan', 0.0)), -1, 1))})
        except (KeyError, TypeError, ValueError):
            warn(f'unreadable cue {c!r}; skipped')
    cues.sort(key=lambda c: c['t'])
    impacts = sorted({c['t'] for c in cues if c['type'] == 'impact-big'})
    risers = []
    for s in secs:                                        # riser sections (e.g. launch-riser 4.3-6.0)
        if 'riser' in s['name'].lower() and s['end'] - s['start'] >= 0.5:
            risers.append((s['start'], s['end'], 'span'))
    for t in riser_marks:                                 # riser markers run into the next impact-big
        T = next((x for x in impacts if 0.5 <= x - t <= 4.5), None)
        if T is not None:
            risers.append((t, T, True))
    risers.sort()
    return dict(duration=dur, bpm=float(d.get('bpm') or 120.0), sections=secs, cues=cues, impacts=impacts,
                risers=risers, riser_marks=riser_marks, version=d.get('version', 'v6'))


# ============================================================================
# v6 composition
# ============================================================================

def compose_v6(tl):
    dur = tl['duration']
    N = ns(dur)
    BEAT = 60.0 / tl['bpm']
    BAR = 4 * BEAT
    S16 = BEAT / 4
    secs = tl['sections']
    for s in secs:
        s['style'] = style_for(s['name'])
    impacts = tl['impacts']
    fin = next((s for s in secs if 'final' in s['style']), None)
    final_t = None
    if fin is not None:
        final_t = next((T for T in impacts if fin['start'] - 1e-6 <= T < fin['end']), fin['start'])
    bars = build_bars(secs, BAR, final_t)
    log(f"{len(secs)} sections, {len(bars)} bars, impacts {impacts}, risers {[(a, b) for a, b, _ in tl['risers']]}, final {final_t}")

    def chord_at(t):
        for b in bars:
            if b['t0'] - 1e-6 <= t < b['t1'] - 1e-9:
                return b['chord']
        return bars[-1]['chord'] if t >= bars[-1]['t0'] else bars[0]['chord']

    def style_at(t):
        for s in secs:
            if s['start'] - 1e-6 <= t < s['end']:
                return s['style']
        return secs[-1]['style']

    sec_starts = [s['start'] for s in secs]
    retrig = [s['start'] for s in secs if s['style'].get('retrig')] + ([final_t] if final_t is not None else [])
    blooms = [s['start'] for s in secs if s['style'].get('bloom')] + ([final_t] if final_t is not None else [])
    booms = [c['t'] for c in tl['cues'] if c['type'] == 'boom-sparkle']
    no_drums = [(t - 0.3, t + 0.2) for t in booms]

    # ---------------------------------------------------------------- drums
    kick_s, snare_s, clap_s = make_kick_v6(), make_snare(), make_clap()
    hat_c, hat_o, crash_s = make_hat(False), make_hat(True, 12), make_crash()
    kick = np.zeros((N, 2))
    hats = np.zeros((N, 2))
    clap = np.zeros((N, 2))
    perc = np.zeros((N, 2))
    kick_times = []
    rng_h = np.random.default_rng(77)
    KV = (1.0, 0.94, 0.97, 0.94)
    for b in bars:
        st = b['st']
        for k in range(4):
            tb = b['t0'] + k * BEAT
            if tb > b['t1'] - 1e-4:
                break
            blocked = any(a - 1e-6 <= tb < z for a, z in no_drums)
            on_impact = any(abs(tb - T) < 1e-4 for T in impacts)
            if st['kick'] > 0 and not blocked and not on_impact:
                place(kick, kick_s, tb, gain=st['kick'] * KV[k])
                kick_times.append(tb)
            if st['clap'] > 0 and k in (1, 3) and not blocked:
                place(clap, clap_s, tb, gain=st['clap'])
                place(clap, snare_s, tb, gain=0.55 * st['clap'])
            if st['hats'] > 0 and not blocked:
                th = tb + 0.5 * BEAT
                if th < b['t1'] - 1e-4:
                    v = st['hats'] * rng_h.uniform(0.8, 1.0)
                    op = st['openhat'] > 0
                    place(hats, hat_o if op else hat_c, th, gain=v * (0.5 if op else 1.0), pan=0.12)
                if st['ghost'] > 0:
                    for off in (0.25, 0.75):
                        tg = tb + (off + 0.03) * BEAT
                        if tg < b['t1'] - 1e-4:
                            place(hats, hat_c, tg, gain=st['ghost'] * rng_h.uniform(0.22, 0.36), pan=-0.18)
    # cold-open clutter: a new layer joins on every beat, everything ends dead at the stop
    for s in secs:
        if s['style'].get('clutter', 0) <= 0:
            continue
        nb = int(round((s['end'] - s['start']) / BEAT))
        for k in range(nb):
            tb = s['start'] + k * BEAT
            lvl = 0.5 + 0.5 * k / max(1, nb - 1)
            place(perc, sub_note(33, 0.12, 0.004, 0.12) * np.exp(-np.arange(ns(0.24)) / SR / 0.08), tb, gain=0.9 * lvl)  # heartbeat
            if k >= 1:
                for j in range(4):
                    place(hats, hat_c, tb + j * S16, gain=0.25 * lvl * (1.0 if j == 0 else 0.6), pan=0.3 * (-1) ** j)
            if k >= 3:
                place(perc, pluck(85, 0.5, 0.05), tb + 2 * S16, gain=0.35 * lvl, pan=0.4)
            if k >= 5:
                for j in range(8):
                    place(perc, hp(make_hat(False, 13 + j)[:ns(0.03)], 4000), tb + j * S16 / 2, gain=0.18 * lvl, pan=-0.4)
            if k >= 6:
                place(perc, pluck(74, 0.4, 0.06), tb + S16, gain=0.3 * lvl, pan=-0.3)
                place(perc, pluck(73, 0.4, 0.06), tb + 3 * S16, gain=0.3 * lvl, pan=0.3)
    # risers: snare roll + build kicks (marker risers) + crash on every impact
    for (r0, T, marked) in tl['risers']:
        span = T - r0
        roll0 = r0 if marked else T - 2 * BEAT
        t = roll0
        while t < T - 0.05:
            u = (t - roll0) / max(1e-3, T - roll0)
            step = S16 * 2 if u < 0.5 else (S16 if u < 0.8 else S16 / 2)
            g_roll = (0.42 + 0.4 * u ** 1.3) if marked == 'span' else (0.15 + 0.6 * u ** 1.5)
            place(clap, snare_s, t, gain=g_roll, pan=0.1 * math.sin(t * 7))
            t += step
        if marked is True:                                  # build kicks only for marker risers (48->50, 55->57)
            existing = [k for k in kick_times if r0 - 1e-6 <= k < T]
            t = max([r0] + [k + BEAT for k in existing])
            while t < T - 1e-4:
                u = (t - r0) / span
                place(kick, kick_s, t, gain=0.55 + 0.35 * u)
                kick_times.append(t)
                t += BEAT if u < 0.5 else (BEAT / 2 if u < 0.75 else BEAT / 4)
    for T in impacts:
        place(hats, crash_s, T, gain=0.55)
    boom_hit = sfx_impact_big()
    t_sd = np.arange(ns(0.8)) / SR
    subdrop = np.sin(2 * np.pi * np.cumsum(32.0 + 38.0 * np.exp(-t_sd / 0.18)) / SR) * smoothstep(t_sd / 0.004) * np.exp(-t_sd / 0.3)
    for (r0, T, _) in tl['risers']:
        if all(abs(T - x) > 1e-3 for x in impacts):      # the drop downbeat itself is the hit (e.g. 6.0)
            place(hats, crash_s, T, gain=0.7)
            place(kick, boom_hit * 0.4, T)
            place(kick, np.stack([subdrop, subdrop], 1) * 0.6, T)
            kick_times.append(T)
    for T in impacts:
        if style_at(T - 0.01)['kick'] > 0:                # impact inside a running groove: add a sub drop
            place(kick, np.stack([subdrop, subdrop], 1) * 0.6, T)

    # ---------------------------------------------------------------- automation
    tt = np.arange(N) / SR
    decres = np.ones(N)
    out_t = min(dur - 0.5, dur)            # music fully out by 61.5 on a 62 s film
    if final_t is not None:
        pts = [(0.0, 1.0), (final_t + 0.5, 1.0), (out_t - 1.6, 0.75), (out_t, 0.0), (dur, 0.0)]
        decres = np.where(tt >= final_t, interp_curve(pts, N), 1.0)
    padlvl = sec_curve(secs, 'pad', N) * decres
    airlvl = sec_curve(secs, 'air', N) * decres
    arplvl = sec_curve(secs, 'arpl', N) * decres
    basslvl = sec_curve(secs, 'bassl', N) * decres
    sc_amt = sec_curve(secs, 'sc', N)
    pcut = cutoff_curve(secs, 'padcut', N) * 2.0 ** (0.12 * np.sin(2 * np.pi * 0.085 * tt))
    acut = cutoff_curve(secs, 'arpcut', N)
    shp = duck_shape(kick_times, N)
    shp_b = duck_shape(kick_times, N, pre=0.003, hold=0.07, rel=0.2)
    imp = duck_shape(impacts, N, pre=0.002, hold=0.08, rel=0.45)

    def sc(depth_db, imp_db=0.0):
        return db2lin(-depth_db * sc_amt * shp - imp_db * imp)

    trem_t = []
    for b in bars:
        if b['st'].get('trem'):
            trem_t += [t for t in np.arange(b['t0'], b['t1'] - 1e-4, 2 * S16)]
    trem = db2lin(-3.0 * sec_curve(secs, 'trem', N) * duck_shape(trem_t, N, pre=0.002, hold=0.01, rel=0.17))
    # stop mask: hard silence inside 'mute' sections (2 ms cut, dead quiet, clean restart)
    mask = np.ones(N)
    for s in secs:
        if s['style'].get('mute'):
            i0, i1 = ns(s['start']), ns(s['end'])
            k = ns(0.002)
            mask[max(0, i0 - k):i0] *= np.linspace(1, 0, min(k, i0))
            mask[i0:i1] = 0.0
    # ---------------------------------------------------------------- pads (supersaw, 7 voices, wide)
    pad = np.zeros((N, 2))
    segs = tie_segments(bars, lambda b: [CHORDS[b['chord']]['body']] + CHORDS[b['chord']]['ust'], retrig)
    for k, (t0, t1, m, slot) in enumerate(segs):
        if style_at(t0 + 1e-3).get('mute'):
            continue
        atk = 0.02 if t0 < 1e-6 else (0.05 if any(abs(t0 - x) < 1e-6 for x in blooms) else 0.2)
        rel = 1.2 if t1 >= dur - 1e-6 else 0.6
        if slot == 0:
            place(pad, pad_note(m, t1 - t0, atk, rel, 1000 + k, n_osc=5, detune=8.0), t0, gain=0.72)
        else:
            place(pad, pad_note(m, t1 - t0, atk, rel, 1000 + k, n_osc=9, detune=16.0), t0)
    pad = tv_lowpass(hp(pad, 110), pcut, order=4)
    pad = chorus(pad, mix=0.35)
    pad *= (padlvl * trem)[:, None]
    air = np.zeros((N, 2))
    abars = [b for b in bars if b['st']['air'] > 0]
    asegs = tie_segments(abars, lambda b: [m + 12 for m in CHORDS[b['chord']]['ust']] + [CHORDS[b['chord']]['pool'][-1] + 12],
                         retrig + sec_starts)
    for k, (t0, t1, m, slot) in enumerate(asegs):
        atk = 0.5 if any(abs(t0 - x) < 1e-6 for x in blooms) else 0.3
        place(air, pad_note(m, t1 - t0, atk, 1.4, 3000 + k, n_osc=7, detune=12.0), t0)
    air = lp(hp(air, 450), 9000) * airlvl[:, None]

    # ---------------------------------------------------------------- hook: supersaw stabs + arp
    stabs = np.zeros((N, 2))
    for b in bars:
        amt = b['st']['stab']
        if amt <= 0 or b['final']:
            continue
        c = CHORDS[b['chord']]
        pat = STAB_BARS[b['i'] % 2]
        for step, idx, vel in pat:
            t = b['t0'] + step * S16
            if t > b['t1'] - 1e-4 or any(a - 1e-6 <= t < z for a, z in no_drums):
                continue
            notes = [u + 12 for u in c['ust']]
            place(stabs, stab(notes, b['st']['bright'], 0.14), t, gain=amt * vel ** 1.3)
    arp = np.zeros((N, 2))
    for b in bars:
        st = b['st']
        name = st['arp']
        if not name or name not in PATTERNS or (b['final'] and name != 'sparkle'):
            continue
        pats, octv = PATTERNS[name]
        pat = pats[b['i'] % len(pats)]
        pool = CHORDS[b['chord']]['pool']
        for step, e in enumerate(pat):
            t = b['t0'] + step * S16
            if t > b['t1'] - 1e-4:
                break
            if e is None:
                continue
            idx, vel = e
            m = pool[min(idx, len(pool) - 1)] + octv
            acc_ = vel >= 0.7
            dec = 0.075 if name == 'tick' else (0.2 if acc_ else 0.14)
            pan = 0.25 if step % 2 else -0.25
            place(arp, pluck(m, st['bright'] * (1.0 if acc_ else 0.85), dec), t, gain=vel ** 1.4, pan=pan)
            if st['dbl'] > 0 and acc_:
                place(arp, pluck(m + 12, st['bright'], 0.12), t, gain=st['dbl'] * vel ** 1.4, pan=-pan)
    arp = hp(tv_lowpass(arp, acut, order=2), 200) * arplvl[:, None]
    motif = np.zeros((N, 2))
    for b in bars:
        amt = b['st'].get('motif', 0.0)
        if amt <= 0 or b['final'] or b['i'] % 2:
            continue
        for step, m, v in MOTIF:
            t = b['t0'] + step * S16
            if t < b['t1'] - 1e-4 and not any(a - 1e-6 <= t < z for a, z in no_drums):
                place(motif, pluck(m, 0.85, 0.13), t, gain=amt * v, pan=-0.05)
                place(motif, pluck(m - 12, 0.7, 0.13), t, gain=0.5 * amt * v, pan=0.05)

    # ---------------------------------------------------------------- bass
    prev = 38
    for b in bars:
        pc = CHORDS[b['chord']]['root']
        b['bass'] = min((m for m in range(31, 45) if m % 12 == pc), key=lambda c_: (abs(c_ - prev), c_))
        prev = b['bass']
    sub = np.zeros(N)
    mid = np.zeros((N, 2))
    for k, (t0, t1, m, _) in enumerate(tie_segments(bars, lambda b: [b['bass']], sec_starts + retrig)):
        st = style_at(t0 + 1e-3)
        if st.get('mute') or st['bassmode'] in ('pulse', 'reese', 'pulse8', 'none'):
            continue
        atk = 0.02 if any(abs(t0 - x) < 1e-6 for x in blooms) else 0.03
        place_mono(sub, sub_note(m, t1 - t0, atk, 0.8 if t1 >= dur - 1e-6 else 0.12), t0)
        if st['bassmode'] in ('sustain',):
            place(mid, midbass_note(m + 12, t1 - t0, 5000 + k, 0.04, 0.15), t0, gain=0.4)
    for b in bars:
        mode = b['st']['bassmode']
        if mode in ('reese', 'pulse8'):
            steps = (1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15) if mode == 'reese' else (0, 2, 4, 6, 8, 10, 12, 14)
            for stp in steps:
                t = b['t0'] + stp * S16
                if t < b['t1'] - 1e-4 and not any(a - 1e-6 <= t < z for a, z in no_drums):
                    v = (1.0 if stp % 4 == 2 else 0.78) if mode == 'reese' else 0.5
                    place(mid, reese_note(b['bass'], 0.115 if mode == 'reese' else 0.22, 700.0 if mode == 'reese' else 320.0),
                          t, gain=v)
            continue
        if mode not in ('drive', 'roll'):
            continue
        steps = (2, 6, 10, 14) if mode == 'drive' else (1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15)
        for stp in steps:
            t = b['t0'] + stp * S16
            if t < b['t1'] - 1e-4 and not any(a - 1e-6 <= t < z for a, z in no_drums):
                place(mid, pluck(b['bass'] + 12, 0.38, 0.09), t, gain=0.9 if stp % 4 == 2 else 0.6)
        place(mid, midbass_note(b['bass'] + 12, b['t1'] - b['t0'], 6000 + int(b['t0'] * 10), 0.02, 0.1, 400.0),
              b['t0'], gain=0.25)
    bass = hp(np.stack([sub, sub], 1) + mid, 28) * basslvl[:, None]

    # ---------------------------------------------------------------- risers (noise sweep + pitch rise), cut dead
    hall_ir = make_ir(4.5, [(80, 2.4), (400, 3.0), (1500, 2.7), (5000, 1.7), (12000, 0.8)], 0.02, 71, lo=170, hi=9000)
    fx = np.zeros((N, 2))
    for i, (r0, T, marked) in enumerate(tl['risers']):
        T = T - 0.04                                      # cut dead a 1/32-ish before the downbeat: contrast
        rd = T - r0
        n_r = ns(rd)
        u = np.linspace(0, 1, n_r)
        nz = noise_sweep(rd, lambda p: 350.0 * (9000.0 / 350.0) ** (np.asarray(p) ** 1.4), 1.0 + 1.2 * 0, 500 + i)[:n_r]
        fl = 0.38 if marked == 'span' else 0.0             # launch riser: starts strong straight out of the hit
        nz = hp(nz * ((fl + (1 - fl) * u ** 2.2) * smoothstep(u / (0.02 if fl else 0.05)))[:, None], 300)
        nz /= np.sqrt(np.mean(nz[-ns(0.3):] ** 2)) + 1e-12
        ch = chord_at(T + 0.01)
        root = CHORDS[ch]['root']
        m0 = 38 + ((root - 2) % 12)
        pr = pitch_riser(rd, m0, m0 + 24, 600 + i, floor=0.3 if marked == 'span' else 0.0)
        pr /= np.sqrt(np.mean(pr[-ns(0.3):] ** 2)) + 1e-12
        sig = 0.9 * nz + 0.7 * pr
        k = ns(0.003)
        sig[-k:] *= np.linspace(1, 0, k)[:, None]
        place(fx, sig, r0, gain=0.95 if marked == 'span' else 1.0)

    # ---------------------------------------------------------------- sidechain, gain staging, effects
    stems = {
        'kick': kick,
        'bass': bass * db2lin(-15.0 * sc_amt * shp_b - 12.0 * imp)[:, None],
        'pad': pad * sc(10.0, 8.0)[:, None],
        'air': air * sc(5.0, 6.0)[:, None],
        'stabs': stabs * sc(3.0, 0.0)[:, None],
        'arp': arp * sc(4.0, 6.0)[:, None],
        'motif': motif,
        'hats': hats,
        'clap': clap,
        'perc': perc,
        'fx': fx,
    }
    targets = {'kick': -17.0, 'bass': -22.0, 'pad': -23.5, 'air': -26.0, 'stabs': -20.5, 'arp': -24.0, 'hats': -27.5,
               'clap': -24.0, 'perc': -27.0, 'fx': -25.5}
    if tl.get('lock_until'):
        mask[:ns(tl['lock_until'])] = 0.0                 # opening is spliced from the approved render
    for k_ in stems:
        stems[k_] = stems[k_] * mask[:, None]
    gains = {}
    for k_, tgt in targets.items():
        L = integrated(stems[k_])
        gains[k_] = float(db2lin(tgt - L)) if L > -69 else 1.0
        stems[k_] = stems[k_] * gains[k_]
    Lm = integrated(stems['motif'])
    stems['motif'] = stems['motif'] * (float(db2lin(-22.5 - Lm)) if Lm > -69 else 1.0)
    log('stem gains (dB): ' + ', '.join(f'{k}={20 * math.log10(v):+.1f}' for k, v in gains.items()))
    for k_ in stems:
        stems[k_] = stems[k_] * mask[:, None]
    delay_in = stems['arp'] + 0.25 * stems['stabs'] + 0.35 * stems['motif']
    dly = pingpong(delay_in, 0.75 * BEAT, fb=0.4) * 0.28 * sc(4.0, 6.0)[:, None]
    hall_send = (0.3 * stems['pad'] + 0.7 * stems['air'] + 0.18 * stems['stabs'] + 0.2 * stems['arp'] + 0.3 * dly
                 + 0.15 * stems['motif'] + 0.15 * stems['clap'] + 0.25 * stems['fx'] + 0.2 * stems['perc'])
    hall = lp(reverb(hp(hall_send, 200), hall_ir) * 0.55, 9500) * sc(4.0, 6.0)[:, None]
    plate_ir = make_ir(1.8, [(100, 0.7), (1000, 1.1), (4000, 1.0), (10000, 0.55)], 0.008, 83, lo=250, hi=11000)
    plate = reverb(0.35 * stems['clap'] + 0.05 * stems['hats'], plate_ir) * 0.5
    stems['delay'] = dly * mask[:, None]
    stems['hall'] = hall * mask[:, None]
    stems['plate'] = plate * mask[:, None]
    ctx = dict(bars=bars, chord_at=chord_at, final_t=final_t, impacts=impacts, BEAT=BEAT, out_t=out_t, booms=booms,
               hall_ir=hall_ir, mask=mask)
    return stems, ctx


# ============================================================================
# v6 SFX render + interplay
# ============================================================================

def render_sfx_v6(tl, N, ctx, boost=None):
    sfx = np.zeros((N, 2))
    plate_send = np.zeros((N, 2))
    hall_send = np.zeros((N, 2))
    inst = []
    cache = {}
    cues = tl['cues']
    for j, c in enumerate(cues):
        typ = resolve_sfx(c['type'])
        nxt = next((x['t'] for x in cues[j + 1:] if x['t'] > c['t'] + 0.05), None)
        chime_t = next((x['t'] for x in cues[j + 1:] if 'chime' in x['type'] and x['t'] - c['t'] <= 3.0), None)
        cctx = {'chord': ctx['chord_at'](c['t'] + 0.05), 'next_t': nxt if nxt and nxt - c['t'] <= 3.0 else None,
                'chime_t': chime_t}
        key = (typ, cctx['chord'] if typ in ('success-chime', 'soft-chime', 'shimmer') else None,
               round(cctx['next_t'] - c['t'], 3) if typ == 'magnetic-hum-start' and cctx['next_t'] else None,
               round(chime_t - c['t'], 3) if typ == 'progress-rise' and chime_t else None, c.get('dur'))
        if key not in cache:
            cache[key] = make_sfx(typ, c, cctx)
        pan = c['pan']
        lvl = V6_LEVEL[typ] + (boost or {}).get(typ, 0.0)
        sig = cache[key] * np.array([min(1.0, 1.0 - pan), min(1.0, 1.0 + pan)])[None, :] * float(db2lin(lvl)) * c['gain']
        place(sfx, sig, c['t'])
        ps, hs = V6_SEND.get(typ, (0.06, 0.0))
        place(plate_send, sig, c['t'], gain=ps)
        if hs > 0:
            place(hall_send, sig, c['t'], gain=hs)
        inst.append(dict(t=c['t'], type=typ, sig=sig))
    plate_ir = make_ir(1.6, [(100, 0.6), (1000, 0.95), (4000, 0.85), (10000, 0.45)], 0.006, 97, lo=300, hi=12000)
    sfx += reverb(plate_send, plate_ir) * 0.6
    if np.any(hall_send):
        sfx += reverb(hall_send, ctx['hall_ir']) * 0.7
    return sfx, inst


def sfx_duck_v6(inst, N, booms):
    g = np.zeros(N)

    def dip(t0, t1, depth, a=0.012, r=0.2):
        i = np.arange(max(0, ns(t0 - a)), min(N, ns(t1 + r)))
        tt = i / SR
        shp = np.minimum(smoothstep((tt - (t0 - a)) / a), 1 - smoothstep((tt - t1) / r))
        g[i] = np.minimum(g[i], -depth * shp)

    for c in inst:
        d = V6_DUCK.get(c['type'], 0.0)
        if d > 0:
            hold = min(0.35, len(c['sig']) / SR) if family_of(c['type']) == 'whoosh' else 0.05
            dip(c['t'] - 0.01, c['t'] - 0.01 + hold, d)
        if c['type'] == 'magnetic-hum-start':
            dip(c['t'], c['t'] + len(c['sig']) / SR, 5.0, a=0.3, r=0.05)
    for t in booms:                       # make room so the release BOOM punches
        dip(t - 0.3, t + 0.15, 9.0, a=0.03, r=0.25)
    return db2lin(g)


# ============================================================================
# Main
# ============================================================================

def main():
    ap = argparse.ArgumentParser(description='AirFliq film v6 synthesized soundtrack + SFX')
    ap.add_argument('--cues', default=str(HERE / 'cues.json'))
    ap.add_argument('--out', default=str(REPO / 'build' / 'film-v6' / 'audio'))
    ap.add_argument('--target-lufs', type=float, default=-14.0)
    ap.add_argument('--ceiling', type=float, default=-2.0, help='limiter ceiling in dBTP (AAC adds ~0.5 dB)')
    ap.add_argument('--no-lock', action='store_true', help='do not splice the approved opening from prev-mix.wav')
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    tl = load_cues(args.cues)
    dur = tl['duration']
    N = ns(dur)
    lock = None
    cold = next((s for s in tl['sections'] if s['name'] == 'cold-open'), None)
    if not args.no_lock and cold is not None and all((out / f).exists() for f in ('prev-mix.wav', 'prev-music.wav', 'prev-report.json')):
        prev = json.loads((out / 'prev-report.json').read_text())
        lock = dict(t=cold['end'], n=ns(cold['end']), gain=prev['master']['gain_db'], ceil=prev['master']['limiter_ceiling_dbtp'],
                    boost=prev.get('sfx_type_boost_db') or {}, mix=read_pcm24(out / 'prev-mix.wav'),
                    music=read_pcm24(out / 'prev-music.wav'))
        tl['lock_until'] = lock['t']
        log(f"locking 0-{lock['t']:g} s to the approved render (prev-*.wav), master gain {lock['gain']} dB, ceiling {lock['ceil']}")
    log(f"cues: {dur:.2f}s, {tl['bpm']:g} BPM, {len(tl['cues'])} sfx, sections {[(s['name'], s['start'], s['end']) for s in tl['sections']]}")
    stems, ctx = compose_v6(tl)
    music = sum(stems.values())
    music = shelf(peq(peq(shelf(music, 6500.0, 2.0, 'high'), 140.0, 2.0, 0.7), 3800.0, 1.5, 0.8), 4000.0, 3.0, 'high')
    log('music rendered')
    sfx, inst = render_sfx_v6(tl, N, ctx)
    log(f'sfx rendered ({len(inst)} cues)')
    music = music * sfx_duck_v6(inst, N, ctx['booms'])[:, None]
    # raise weak SFX themselves (one level per type = its worst-masked instance), music band dips capped at 6 dB
    _, rows0 = cue_band_snr(inst, music, target=-99.0)
    boost = {}
    for r in rows0:
        cap = 3.0 if family_of(r['type']) == 'impact' else 9.0
        boost[r['type']] = float(np.clip(max(boost.get(r['type'], 0.0), 4.5 - r['snr_db_before'] - 3.0), 0.0, cap))
    if lock is not None:
        boost = {k: float(lock['boost'].get(k, v)) for k, v in boost.items()}      # keep the approved SFX levels
    log('sfx type boosts (dB): ' + ', '.join(f'{k}={v:+.1f}' for k, v in boost.items() if v > 0))
    sfx, inst = render_sfx_v6(tl, N, ctx, boost)
    _, rows1 = cue_band_snr(inst, music, target=4.5, max_dip=6.0)
    bump = {}
    for r in rows1:                                      # an effect the new music now masks: lift that type once
        if r['snr_db'] < 4.0:
            bump[r['type']] = max(bump.get(r['type'], 0.0), min(9.0, 4.6 - r['snr_db']))
    if bump:
        log('sfx bumps for newly masked cues (dB): ' + ', '.join(f'{k}={v:+.1f}' for k, v in bump.items()))
        boost = {k: v + bump.get(k, 0.0) for k, v in boost.items()}
        sfx, inst = render_sfx_v6(tl, N, ctx, boost)
    music, snr_rows = cue_band_snr(inst, music, target=4.5, max_dip=6.0)
    low = [f"{r['type']}@{r['t']:g}:{r['snr_db']:+.1f}" for r in snr_rows if r['snr_db'] < 3.0]
    log(f"cue band SNR: min {min(r['snr_db'] for r in snr_rows):+.1f} dB, median "
        f"{float(np.median([r['snr_db'] for r in snr_rows])):+.1f}; below +3 dB: {low}")
    music = hp(music, 20)
    sfx = hp(sfx, 20)
    # after all bus filtering: hard digital silence in 'stop' sections, music fully out by out_t
    music *= ctx['mask'][:, None]
    music[ns(ctx['out_t']):] = 0.0
    mix = music + sfx
    hdr = ['section'] + list(stems.keys()) + ['sfx', 'mix']
    print('  ' + ' '.join(f'{h[:7]:>7}' for h in hdr))
    for s in tl['sections']:
        i0, i1 = ns(s['start']), ns(s['end'])
        vals = [loudness_seg(stems[k][i0:i1]) for k in stems] + [loudness_seg(sfx[i0:i1]), loudness_seg(mix[i0:i1])]
        print('  ' + f"{s['name'][:7]:>7} " + ' '.join(f'{v:7.1f}' for v in vals))

    target, ceil = args.target_lufs, args.ceiling
    gain = None
    aac = {}
    kdb = 0.0
    if lock is not None:
        ceil = min(ceil, lock['ceil'])
    for rnd in range(4):
        if lock is None:
            mix_m, gain, gr = master_to_target(mix, target, ceil, dur, gain)
            write_wav24(out / 'mix.wav', mix_m)
        else:
            gain = lock['gain']
            for _ in range(8):                            # loudness via the new music level, master gain frozen
                mix_m, gr = master(music * db2lin(kdb) + sfx, gain, ceil, dur)
                mix_m[:lock['n']] = lock['mix'][:lock['n']]
                Lx = integrated(mix_m)
                if abs(Lx - target) < 0.03:
                    break
                kdb += (target - Lx) * 1.1
            write_wav24(out / 'mix.wav', mix_m, prefix_from=out / 'prev-mix.wav', prefix_n=lock['n'])
        meas = ffmpeg_ebur128(out / 'mix.wav')
        m4a = out / 'aac-test.m4a'
        subprocess.run(['ffmpeg', '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', '-i', str(out / 'mix.wav'),
                        '-c:a', 'aac', '-b:a', '256k', str(m4a)], check=True, timeout=300)
        aac = ffmpeg_ebur128(m4a)
        log(f"round {rnd}: gain {gain:+.2f} dB, ceiling {ceil:.2f}: WAV I={meas['I']:.2f} TP={meas['TP']:.2f} "
            f"LRA={meas['LRA']:.1f}; AAC256 I={aac['I']:.2f} TP={aac['TP']:.2f}; max GR {gr.max():.1f} dB")
        ok = aac['TP'] <= -1.05 and meas['TP'] <= ceil + 0.15 and abs(meas['I'] - target) <= 0.2
        if ok:
            break
        if aac['TP'] > -1.05:
            ceil -= (aac['TP'] + 1.05) + 0.1
        if abs(meas['I'] - target) > 0.2:
            if lock is None:
                gain += target - meas['I']
            else:
                kdb += target - meas['I']
    music_m, _ = master(music * db2lin(kdb), gain, ceil, dur)
    if lock is not None:
        music_m[:lock['n']] = lock['music'][:lock['n']]
        write_wav24(out / 'music.wav', music_m, prefix_from=out / 'prev-music.wav', prefix_n=lock['n'])
    else:
        write_wav24(out / 'music.wav', music_m)
    write_wav24(out / 'sfx.wav', finalize(sfx, dur))
    meas_music = ffmpeg_ebur128(out / 'music.wav')
    log(f"music.wav: I={meas_music['I']:.2f} TP={meas_music['TP']:.2f} LRA={meas_music['LRA']:.1f}")
    st_by_t = {int(round(f[0] * 10)): f[2] for f in meas['frames']}
    per_sec = []
    for s_ in range(1, int(math.floor(dur)) + 1):
        v = st_by_t.get(s_ * 10)
        per_sec.append(None if v is None or v < -70 else round(v, 1))
    sec_rows = []
    for s in tl['sections']:
        vals = [f[2] for f in meas['frames'] if s['start'] + 0.05 <= f[0] <= s['end'] and f[2] > -70]
        mvals = [f[1] for f in meas['frames'] if s['start'] + 0.05 <= f[0] <= s['end'] and f[1] > -70]
        sec_rows.append(dict(name=s['name'], start=s['start'], end=s['end'],
                             short_term_mean=round(float(np.mean(vals)), 1) if vals else None,
                             momentary_mean=round(float(np.mean(mvals)), 1) if mvals else None,
                             momentary_max=round(float(np.max(mvals)), 1) if mvals else None))
    gsel = np.concatenate([np.arange(ns(s['start']), ns(s['end'])) for s in tl['sections'] if s['style']['kick'] > 0]
                          or [np.arange(len(mix_m))])
    gm = mix_m[gsel].mean(axis=1)
    bpw = [float(np.mean(bp(gm, lo, hi, order=3) ** 2)) + 1e-20 for lo, hi in BANDS]
    balance = {f'{lo}-{hi}': round(10 * math.log10(v / bpw[4]), 1) for (lo, hi), v in zip(BANDS, bpw)}
    stop_rms = {}
    for s in tl['sections']:
        if s['style'].get('mute'):
            seg = music_m[ns(s['start']):ns(s['end'])]
            stop_rms[s['name']] = 'digital silence' if not np.any(seg) else round(float(20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-12)), 1)
    runtime = time.time() - T_START
    report = {
        'file': 'mix.wav', 'duration_s': round(len(mix_m) / SR, 4), 'samples': len(mix_m), 'sample_rate': SR,
        'bit_depth': 24, 'channels': 2,
        'integrated_lufs': meas['I'], 'true_peak_dbtp': meas['TP'], 'lra_lu': meas['LRA'],
        'aac_256k_test': {'file': 'aac-test.m4a', 'integrated_lufs': aac.get('I'), 'true_peak_dbtp': aac.get('TP')},
        'measured_with': 'ffmpeg -i <file> -af ebur128=peak=true -f null -',
        'short_term_lufs_per_second': per_sec,
        'short_term_lufs_per_second_note': 'index i = value at t=i+1 s (3 s window ending there); null = window not full / silence',
        'sections': sec_rows,
        'music_in_stop_sections': stop_rms,
        'music_wav': {'integrated_lufs': meas_music['I'], 'true_peak_dbtp': meas_music['TP'], 'lra_lu': meas_music['LRA'],
                      'last_nonzero_s': round(float((np.nonzero(np.abs(music_m).max(1))[0][-1] + 1) / SR), 3)},
        'master': {'gain_db': round(gain, 2), 'limiter_ceiling_dbtp': round(ceil, 2),
                   'limiter_max_gain_reduction_db': round(float(gr.max()), 2),
                   'limiter_gr_p95_db': round(float(np.percentile(gr, 95)), 2)},
        'impacts': ctx['impacts'], 'risers': [[a, b] for a, b, _ in tl['risers']], 'final_chord_t': ctx['final_t'],
        'cue_band_snr_db': snr_rows,
        'sfx_type_boost_db': {k: round(v, 1) for k, v in boost.items()},
        'octave_band_balance_db_groove': balance,
        'first_sample_abs': float(np.abs(mix_m[0]).max()),
        'last_50ms_is_digital_silence': bool(np.all(mix_m[-ns(0.05):] == 0.0)),
        'render_seconds_wall': round(runtime, 1), 'render_seconds_cpu': round(time.process_time(), 1),
        'music_scale_db_post_lock': round(kdb, 2),
    }
    if lock is not None:
        new_mix = read_pcm24(out / 'mix.wav')
        new_sfx = read_pcm24(out / 'sfx.wav')
        prev_sfx = read_pcm24(out / 'prev-sfx.wav') if (out / 'prev-sfx.wav').exists() else None
        n0, n1 = lock['n'], ns(lock['t'] + 0.3)
        report['lock'] = {
            'locked_until_s': lock['t'], 'source': 'prev-mix.wav / prev-music.wav (approved render)',
            'mix_max_abs_diff_0_to_lock': float(np.abs(new_mix[:n0] - lock['mix'][:n0]).max()),
            'mix_max_abs_diff_hit_first_300ms': float(np.abs(new_mix[n0:n1] - lock['mix'][n0:n1]).max()),
            'sfx_max_abs_diff_0_to_lock_plus_300ms': float(np.abs(new_sfx[:n1] - prev_sfx[:n1]).max()) if prev_sfx is not None else None,
            'master_gain_db_frozen': lock['gain']}
        log(f"lock check: max |diff| 0-{lock['t']:g}s = {report['lock']['mix_max_abs_diff_0_to_lock']:.3g}; "
            f"hit 0.3 s = {report['lock']['mix_max_abs_diff_hit_first_300ms']:.3g}; sfx = {report['lock']['sfx_max_abs_diff_0_to_lock_plus_300ms']}")
    (out / 'report.json').write_text(json.dumps(report, indent=2))
    tl_png = dict(duration=dur, bpm=tl['bpm'], sections=tl['sections'], cues=tl['cues'], risers=ctx['impacts'])
    render_review(out / 'review.png', mix_m, tl_png, meas)
    log('octave balance (groove): ' + ', '.join(f'{k}:{v:+.1f}' for k, v in balance.items()))
    write_notes_v6(out / 'NOTES.md', tl, report, ctx)
    log(f"done in {time.time() - T_START:.1f}s -> {out}")


def write_notes_v6(path, tl, rep, ctx):
    snr = [r['snr_db'] for r in rep['cue_band_snr_db']]
    L = [
        '# AirFliq film v6 - score + sound design notes', '',
        'Generated by `marketing/shipaton/film-v6/soundtrack.py` from `cues.json`. Fully synthesized (numpy/scipy), '
        'no samples, no third-party audio. Re-run after any cue change (~30-40 s).', '',
        '## Measured (ffmpeg ebur128)', '',
        f"- mix.wav: **{rep['integrated_lufs']:.1f} LUFS**, true peak **{rep['true_peak_dbtp']:.1f} dBTP**, "
        f"LRA **{rep['lra_lu']:.1f} LU**; AAC 256k test encode: {rep['aac_256k_test']['integrated_lufs']:.1f} LUFS, "
        f"true peak **{rep['aac_256k_test']['true_peak_dbtp']:.1f} dBTP**",
        f"- music.wav (same master): {rep['music_wav']['integrated_lufs']:.1f} LUFS / {rep['music_wav']['true_peak_dbtp']:.1f} dBTP; "
        f"music out at {rep['music_wav']['last_nonzero_s']} s; stop section(s): {rep['music_in_stop_sections']}",
        f"- {rep['duration_s']} s, 48 kHz / 24-bit stereo; last 50 ms digital silence: {rep['last_50ms_is_digital_silence']}; "
        f"limiter ceiling {rep['master']['limiter_ceiling_dbtp']} dBTP, max GR {rep['master']['limiter_max_gain_reduction_db']} dB",
        '- Section short-term means (LUFS): ' + ', '.join(f"{s['name']} {s['short_term_mean']}" for s in rep['sections']),
        f"- SFX vs music in each effect's own band: median {float(np.median(snr)):+.1f} dB, min {min(snr):+.1f} dB",
        '', '## Harmony (B minor, 120 BPM, 2 s bars restarting on every section start; cold open = approved v6 render)', '',
        '| section | chords |', '|---|---|']
    for s in tl['sections']:
        ch = [b['chord'] for b in ctx['bars'] if b['sec'] is s]
        L.append(f"| {s['name']} {s['start']:g}-{s['end']:g} | {' - '.join(ch)} |")
    lk = rep.get('lock') or {}
    L += ['', '## Arrangement (v6.1 rework: B minor, energetic)', '',
          f"- 0-{lk.get('locked_until_s', 4.0):g} s: the approved cold open is spliced byte-exact from prev-mix.wav / prev-music.wav "
          f"(max |diff| {lk.get('mix_max_abs_diff_0_to_lock')}); master gain frozen at {lk.get('master_gain_db_frozen')} dB so the "
          '4.0 bass hit (impact-low) keeps its level; music is silent 4.0-4.3 so the hit blooms alone.',
          '- 4.3-6.0 launch riser: noise sweep + 2-octave pitch rise + snare roll 8ths->16ths->32nds, cut dead 40 ms before 6.0.',
          '- 6.0 THE DROP: crash + boom + sub drop + first kick + first stab. Four-on-the-floor tight kick, clap+snare on 2/4, '
          'off-beat open hats + light 16th closed hats, rolling Reese bass (2 saws +-12 c + sine sub, driven, LP 700 Hz) on the 16ths '
          'between kicks with a deep 15 dB / 70 ms sidechain, plain minor triad supersaw stabs (9 voices) in a 3-3-2 rhythm, '
          'one dry pluck motif F#5-B5-A5-F#5 every 2 bars. No arpeggio, no sweet pads (only a dark ducked bed).',
          '- 8.0 logo accent: impact-big SFX + crash + sub drop inside the running groove (kick skipped on 8.0).',
          '- drag: 9 dB music duck + no drums 25.5-26.0 around the 25.8 boom; 5 dB under the magnetic hum.',
          '- shortcut: lighter top (fewer hats, softer stabs/motif) so the key clicks carry the rhythm.',
          '- private 44-50: filtered minor pads + soft 8th Reese pulse; marker riser 48->50 with build kicks and snare roll.',
          '- drop-2 50-56: biggest (brighter louder stabs, 16th ghosts, rolling Reese); riser 55->57.',
          '- finale: iv-V-I lift: Em (drop-2) -> F# (56-57) -> B MAJOR at the 57.0 hit, wide supersaw + air, out by 61.5.', '']
    Path(path).write_text('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
