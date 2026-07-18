#!/usr/bin/env python3
"""Record video/gameplay.mp4: ~8s of title, Start, then a bot playthrough.
Frames come from nes-py; the identical input replays in NEStoner for audio
(the game is deterministic, so they sync); ffmpeg muxes at 2x scale.
"""
import os
import re
import subprocess
import sys
import wave

from PIL import Image
from nes_py import NESEnv

ROOT = os.path.join(os.path.dirname(__file__), "..")
EMU = os.path.join(ROOT, "..", "nes-emulator-mine", "nestoner-headless")
OUT = os.path.join(ROOT, "video", "gameplay.mp4")
TITLE_FRAMES = 480               # ~8s of title screen
PLAY_FRAMES = 2300               # ~38s after Start

LABELS = {}
for line in open(os.path.join(ROOT, "build", "labels.txt")):
    m = re.match(r"al ([0-9A-F]{6}) \.(\w+)", line)
    if m:
        LABELS[m.group(2)] = int(m.group(1), 16)

A, B, START, UP, DOWN, LEFT, RIGHT = 1, 2, 8, 16, 32, 64, 128
GRID = 0x0400
env = NESEnv(os.path.join(ROOT, "build", "jezzball.nes"))
env.reset()

workdir = os.path.join(os.environ.get("TMPDIR", "/tmp"), "jezzvid")
os.makedirs(workdir, exist_ok=True)
os.makedirs(os.path.join(ROOT, "video"), exist_ok=True)
log = []


def R(n):
    return int(env.ram[LABELS[n]])


def cell(gx, gy):
    return int(env.ram[GRID + int(gy) * 32 + int(gx)]) & 0x0F


def can_reach(bcol, brow, c):
    lo, hi = sorted((bcol, c))
    return all(cell(x, brow) in (0, 3, 4) for x in range(lo, hi + 1))


def step(act=0):
    env.step(act)
    Image.fromarray(env.screen).save(
        os.path.join(workdir, f"f{len(log):05d}.png"))
    log.append(act)


def frames(n, act=0):
    for _ in range(n):
        step(act)


# ---- title, then Start -----------------------------------------------------
frames(TITLE_FRAMES)
frames(2, START)
frames(16)

# ---- bot playthrough: build walls in safe columns --------------------------
budget = PLAY_FRAMES
while budget > 0 and R("game_state") in (1, 2, 3):
    if R("game_state") != 2 or R("wall_active") or R("cap_state") \
            or R("dirty_lo") or R("dirty_hi"):
        frames(1)
        budget -= 1
        continue
    n = R("ball_n")
    balls = [(int(env.ram[LABELS["ball_x"] + i]) // 8 - 1,
              int(env.ram[LABELS["ball_y"] + i]) // 8 - 4) for i in range(n)]
    cy = R("cursor_y")
    empties = [c for c in range(1, 29) if cell(c, cy) == 0]
    best, bestscore = None, -1
    for c in empties:
        dists = [abs(c - b) for b, br in balls if can_reach(b, br, c)]
        eff = min(dists) if dists else 99
        if eff < 9:
            continue
        reach = [b for b, br in balls if can_reach(b, br, c)]
        cap = 0
        if reach and all(b > c for b in reach):
            cap = sum(1 for e in empties if e < c)
        elif reach and all(b < c for b in reach):
            cap = sum(1 for e in empties if e > c)
        score = cap * 10 + eff
        if score > bestscore:
            best, bestscore = c, score
    if best is None:
        frames(min(12, budget))
        budget -= 12
        continue
    guard = 0
    while R("cursor_x") != best and guard < 60 and budget > 1:
        step(LEFT if R("cursor_x") > best else RIGHT)
        step()
        budget -= 2
        guard += 1
    ok = all(not can_reach(b, br, best) or abs(best - b) >= 9
             for b, br in [(int(env.ram[LABELS["ball_x"] + i]) // 8 - 1,
                            int(env.ram[LABELS["ball_y"] + i]) // 8 - 4)
                           for i in range(n)])
    if ok:
        step(A)
        step()
        budget -= 2
    else:
        frames(min(10, budget))
        budget -= 10

total = len(log)
print(f"recorded {total} frames, pct={R('percent')} score shown on HUD")

# ---- identical run in NEStoner for the audio track -------------------------
NAMES = {A: "A", B: "B", 4: "Sel", START: "Start",
         UP: "Up", DOWN: "Down", LEFT: "Left", RIGHT: "Right"}
events = []
prev = 0
for f, act in enumerate(log):
    if act != prev:
        btns = "+".join(NAMES[b] for b in NAMES if act & b)
        events.append(f"{f}:{btns}")
        prev = act
wav = os.path.join(workdir, "audio.wav")
cmd = [EMU, os.path.join(ROOT, "build", "jezzball.nes"),
       "--frames", str(total), "--no-test-detect", "--nes-audio-wav", wav]
if events:
    cmd += ["--nes-input", ",".join(events)]
subprocess.run(cmd, capture_output=True, text=True, timeout=900)

w = wave.open(wav)
dur = w.getnframes() / w.getframerate()
fps = total / dur
print(f"audio {dur:.2f}s -> {fps:.4f} fps")

# ---- mux -------------------------------------------------------------------
subprocess.run([
    "ffmpeg", "-y", "-framerate", f"{fps:.4f}",
    "-i", os.path.join(workdir, "f%05d.png"), "-i", wav,
    "-vf", "scale=512:480:flags=neighbor",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18",
    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
    "-movflags", "+faststart", "-shortest", OUT,
], check=True, capture_output=True, timeout=900)
sz = os.path.getsize(OUT)
print(f"wrote {OUT} ({sz/1e6:.1f} MB, {total/fps:.1f}s)")
sys.exit(0)
