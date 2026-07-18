#!/usr/bin/env python3
"""Audio lifecycle audit: replays a scripted state tour in NEStoner with APU
capture and asserts per-frame RMS -- silence where channels must be cleared,
sound where music/sfx must play.
"""
import os
import re
import subprocess
import sys

from nes_py import NESEnv

ROOT = os.path.join(os.path.dirname(__file__), "..")
EMU = os.path.join(ROOT, "..", "nes-emulator-mine", "nestoner-headless")
ROM = os.path.join(ROOT, "build", "jezzball.nes")

LABELS = {}
for line in open(os.path.join(ROOT, "build", "labels.txt")):
    m = re.match(r"al ([0-9A-F]{6}) \.(\w+)", line)
    if m:
        LABELS[m.group(2)] = int(m.group(1), 16)

A, START, UP, DOWN, LEFT, RIGHT = 1, 8, 16, 32, 64, 128
env = NESEnv(ROM)
env.reset()
log = []
marks = {}


def R(n):
    return int(env.ram[LABELS[n]])


def step(act=0):
    env.step(act)
    log.append(act)


def frames(n, act=0):
    for _ in range(n):
        step(act)


# ---- the tour --------------------------------------------------------------
frames(150)                      # title music
marks["title_music"] = (40, 145)
frames(2, START)
frames(16)
marks["start_blip"] = (152, 168)
frames(90)                       # splash is silent
frames(30)                       # play, idle
marks["play_silence_1"] = (len(log) - 100, len(log) - 2)
step(A)                          # wall: start sfx + ratchet + anchor
step()
marks["wall_audio"] = (len(log), len(log) + 45)
frames(160)                      # resolve + any capture sweep
frames(80)
marks["play_silence_2"] = (len(log) - 60, len(log) - 2)
frames(1, START)                 # pause blip
frames(20, 0)
frames(1, START)                 # unpause blip
frames(20, 0)
guard = 0                        # die twice by clicking atoms
while R("lives") > 0 and guard < 3000:
    guard += 1
    bx, by = int(env.ram[LABELS["ball_x"]]), int(env.ram[LABELS["ball_y"]])
    tc, tr = bx // 8 - 1, by // 8 - 4
    cx, cy = R("cursor_x"), R("cursor_y")
    if (cx, cy) == (tc, tr):
        step(A)
        step()
    else:
        act = 0
        if cx > tc:
            act |= LEFT
        elif cx < tc:
            act |= RIGHT
        if cy > tr:
            act |= UP
        elif cy < tr:
            act |= DOWN
        step(act)
        step()
marks["gameover_jingle"] = (len(log) + 2, len(log) + 60)
frames(200)                      # jingle plays; auto-recap at +180
assert R("game_state") == 5, f"expected recap, got {R('game_state')}"
frames(60)                       # recap lockout: must be silent
marks["recap_silence"] = (len(log) - 50, len(log) - 2)
frames(75, START)                # HOLD start -> exit to title
frames(20)
assert R("game_state") == 0, f"expected title, got {R('game_state')}"
frames(150)                      # title music resumed
marks["title_music_again"] = (len(log) - 130, len(log) - 5)
total = len(log)
print(f"tour scripted: {total} frames, marks={ {k: v for k, v in marks.items()} }")

# ---- replay in NEStoner with APU capture -----------------------------------
NAMES = {A: "A", 2: "B", 4: "Sel", START: "Start",
         UP: "Up", DOWN: "Down", LEFT: "Left", RIGHT: "Right"}
events = []
prev = 0
for f, act in enumerate(log):
    if act != prev:
        btns = "+".join(NAMES[b] for b in NAMES if act & b)
        events.append(f"{f}:{btns}")
        prev = act
scratch = os.environ.get("TMPDIR", "/tmp")
wav = os.path.join(scratch, "audio_audit.wav")
cmd = [EMU, ROM, "--frames", str(total + 10), "--no-test-detect",
       "--nes-audio-wav", wav]
if events:
    cmd += ["--nes-input", ",".join(events)]
out = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
rms = {}
for line in (out.stdout + out.stderr).splitlines():
    m = re.match(r"AUDIO f=(\d+) rms=([0-9.]+)", line)
    if m:
        rms[int(m.group(1))] = float(m.group(2))

def window_rms(a, b):
    vals = [rms.get(f, 0.0) for f in range(a, b)]
    return sum(vals) / max(1, len(vals))

FAILS = []
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        FAILS.append(msg)

LOUD, QUIET = 0.02, 0.004
for name, (a, b) in marks.items():
    v = window_rms(a, b)
    if "silence" in name:
        check(v < QUIET, f"{name}: rms {v:.4f} < {QUIET} (channels cleared)")
    else:
        check(v > LOUD, f"{name}: rms {v:.4f} > {LOUD} (audio present)")

print()
if FAILS:
    print(f"{len(FAILS)} FAILURES")
    sys.exit(1)
print("audio lifecycle audit passed")
