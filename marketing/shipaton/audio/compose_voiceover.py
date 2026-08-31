#!/usr/bin/env python3
"""Place mono WAV narration clips at exact timestamps in one master WAV."""

from __future__ import annotations

import sys
import wave
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    if len(sys.argv) < 6 or (len(sys.argv) - 3) % 2:
        fail("usage: compose_voiceover.py OUTPUT.wav DURATION START FILE.wav [START FILE.wav ...]")

    output = Path(sys.argv[1])
    duration = float(sys.argv[2])
    pairs = list(zip(sys.argv[3::2], sys.argv[4::2], strict=True))

    rate = 48_000
    channels = 1
    width = 2
    total_frames = round(duration * rate)
    silence = b"\0" * total_frames * channels * width
    master = bytearray(silence)

    for start_text, clip_text in pairs:
        start = float(start_text)
        clip_path = Path(clip_text)
        with wave.open(str(clip_path), "rb") as clip:
            fmt = (clip.getframerate(), clip.getnchannels(), clip.getsampwidth())
            expected = (rate, channels, width)
            if fmt != expected:
                fail(f"unexpected audio format for {clip_path}: {fmt}, expected {expected}")
            frames = clip.readframes(clip.getnframes())

        offset = round(start * rate) * channels * width
        end = offset + len(frames)
        if end > len(master):
            fail(f"clip {clip_path} extends beyond the {duration:.1f} second master")
        master[offset:end] = frames

    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as result:
        result.setnchannels(channels)
        result.setsampwidth(width)
        result.setframerate(rate)
        result.writeframes(master)


if __name__ == "__main__":
    main()
