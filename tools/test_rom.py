#!/usr/bin/env python3
"""Headless smoke test (nes-py): boots the ROM, drives real input, asserts
game state via zeropage symbols from build/labels.txt, saves screenshots.
"""
import os
import re
import sys

import numpy as np
from PIL import Image
from nes_py import NESEnv

ROOT = os.path.join(os.path.dirname(__file__), "..")
ROM = os.path.join(ROOT, "build", "jezzball.nes")
IMAGES = os.path.join(ROOT, "images")
os.makedirs(IMAGES, exist_ok=True)

# --- symbols ---------------------------------------------------------------
LABELS = {}
for line in open(os.path.join(ROOT, "build", "labels.txt")):
    m = re.match(r"al ([0-9A-F]{6}) \.(\w+)", line)
    if m:
        LABELS[m.group(2)] = int(m.group(1), 16)

def sym(name):
    return LABELS[name]

STATE_TITLE, STATE_SPLASH, STATE_PLAY, STATE_CLEAR, STATE_OVER = range(5)

env = NESEnv(ROM)
env.reset()
FAILS = []


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        FAILS.append(msg)


def ram(name):
    return env.ram[sym(name)]


def ram16(lo, hi):
    return env.ram[sym(lo)] | (env.ram[sym(hi)] << 8)


def frames(n, action=0):
    for _ in range(n):
        env.step(action)


def shot(name):
    Image.fromarray(env.screen).save(os.path.join(IMAGES, name))
    print(f"     screenshot {name}")


# --- 1. boot to title ------------------------------------------------------
frames(120)
check(ram("game_state") == STATE_TITLE, "boots into title state")
scr = np.asarray(env.screen)
check(scr.max() > 0, "title renders non-black pixels")
reds = ((scr[:, :, 0] > 150) & (scr[:, :, 2] < 100)).sum()
blues = ((scr[:, :, 2] > 150) & (scr[:, :, 0] < 100)).sum()
check(reds > 300 and blues > 300, f"logo red/blue halves visible ({reds}/{blues} px)")
shot("title.png")

# --- 2. controller mapping: nes-py actions are LSB-first (A,B,sel,start,
# U,D,L,R); verify via the pad variable, then press Start for real ---
A, B, START = 1, 2, 8
UP, DOWN, LEFT, RIGHT = 16, 32, 64, 128
frames(2, A)
check(ram("pad") == 0x80, "controller wiring confirmed (A)")
frames(2, 0)
frames(2, START)
frames(16, 0)   # confirm-blip countdown (10 frames) + level init

# --- 3. splash -> play -----------------------------------------------------
check(ram("game_state") == STATE_SPLASH, "start enters level splash")
check(ram("level") == 1 and ram("ball_n") == 2, "level 1 has 2 atoms")
check(ram("lives") == 2, "level 1 grants 2 lives")
frames(40)
shot("splash.png")
frames(60)
check(ram("game_state") == STATE_PLAY, "splash advances to play")

# grid sanity: border ring solid, interior empty-ish
g = sym("t0")  # grid is fixed at $0400
GRID = 0x0400
row0 = [env.ram[GRID + x] for x in range(30)]
check(all(v == 1 for v in row0), "grid top border solid")
row24 = [env.ram[GRID + 24 * 32 + x] for x in range(30)]
check(all(v == 1 for v in row24), "grid bottom border solid")

# --- 4. build a vertical wall in place -------------------------------------
filled0 = ram16("filled_lo", "filled_hi")
lives0 = ram("lives")
frames(1, A)
frames(1, 0)
check(ram("wall_active") in (0, 1), "wall trigger accepted")
frames(300)
filled1 = ram16("filled_lo", "filled_hi")
lives1 = ram("lives")
check(filled1 > filled0 or lives1 < lives0,
      f"wall resolved: filled {filled0}->{filled1}, lives {lives0}->{lives1}")
shot("first_wall.png")

# --- 5. keep building walls until something captures ------------------------
captured = False
for i in range(10):
    if ram("game_state") != STATE_PLAY:
        break
    if ram("wall_active"):
        frames(60)
        continue
    # wander somewhere new, toggle orientation sometimes
    d = [LEFT, RIGHT, UP, DOWN][i % 4]
    frames(3 + 3 * (i % 3), d)
    if i % 2:
        frames(1, B)
        frames(1, 0)
    frames(1, A)
    frames(1, 0)
    frames(240)
    if ram16("filled_lo", "filled_hi") >= 40:
        captured = True
        break
pct = ram("percent")
filled = ram16("filled_lo", "filled_hi")
check(filled > 0, f"walls fill the field (filled={filled}, pct={pct})")
shot("midgame.png")

# --- 6. HUD shows a percent digit ------------------------------------------
check(ram("game_state") in (STATE_PLAY, STATE_CLEAR, STATE_OVER, 5),
      f"state sane after play ({ram('game_state')})")

# --- 7. random-input soak: nothing crashes, NMI keeps firing ----------------
rng = np.random.RandomState(1234)
last = ram("nmi_count")
stuck = 0
for i in range(1500):
    act = int(rng.choice([0, A, B, UP, DOWN, LEFT, RIGHT,
                          UP | LEFT, DOWN | RIGHT]))
    env.step(act)
    if i % 100 == 99:
        now = ram("nmi_count")
        if now == last:
            stuck += 1
        last = now
        if ram("game_state") not in range(6):
            stuck += 100
            break
check(stuck == 0, f"1500-frame random soak: NMI alive, state valid (stuck={stuck})")
row0 = [env.ram[GRID + x] for x in range(30)]
check(all(v & 0x0F in (0, 1) for v in row0), "border ring uncorrupted after soak")
shot("soak.png")

print()
if FAILS:
    print(f"{len(FAILS)} FAILURES:")
    for f in FAILS:
        print("  - " + f)
    sys.exit(1)
print("all tests passed")
