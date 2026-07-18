#!/usr/bin/env python3
"""Stress test at the 12-atom maximum: counts dropped frames (game frame
counter vs NMI counter), checks level-99 behavior and score saturation.
"""
import os
import re
import sys

from PIL import Image
from nes_py import NESEnv

ROOT = os.path.join(os.path.dirname(__file__), "..")
LABELS = {}
for line in open(os.path.join(ROOT, "build", "labels.txt")):
    m = re.match(r"al ([0-9A-F]{6}) \.(\w+)", line)
    if m:
        LABELS[m.group(2)] = int(m.group(1), 16)

A, START, UP, DOWN, LEFT, RIGHT = 1, 8, 16, 32, 64, 128
GRID = 0x0400
env = NESEnv(os.path.join(ROOT, "build", "jezzball.nes"))
env.reset()
FAILS = []


def R(n):
    return int(env.ram[LABELS[n]])


def R16(lo, hi):
    return R(lo) | (R(hi) << 8)


def frames(n, act=0):
    for _ in range(n):
        env.step(act)


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        FAILS.append(msg)


def goto_level(n):
    env.ram[LABELS["level"]] = n
    env.ram[LABELS["init_request"]] = 2
    frames(6)                   # render-off init spans a few frames
    frames(100)                 # splash -> play
    return R("game_state")


def count_dropped(nframes, act_fn=lambda i: 0):
    """run nframes; return how many the main loop failed to complete."""
    ticks = 0
    last = R("tick_cnt")
    for i in range(nframes):
        env.step(act_fn(i))
        now = R("tick_cnt")
        if now != last:
            ticks += 1
            last = now
    return nframes - ticks


# --- enter the game --------------------------------------------------------
frames(60)
frames(2, START)
frames(16)
frames(100)
assert R("game_state") == 2

# --- level 11: first 12-atom level ----------------------------------------
st = goto_level(11)
check(st == 2, f"level 11 reaches play state ({st})")
check(R("ball_n") == 12, f"level 11 spawns 12 atoms ({R('ball_n')})")
check(R("lives") == 9, f"lives clamp at 9 ({R('lives')})")
check(R16("time_lo", "time_hi") == 300, f"time clamps at 300 ({R16('time_lo','time_hi')})")
# all atoms inside the interior, on distinct-ish positions
pos = [(int(env.ram[LABELS["ball_x"] + i]), int(env.ram[LABELS["ball_y"] + i]))
       for i in range(12)]
ok = all(16 <= x <= 232 and 40 <= y <= 216 for x, y in pos)
check(ok, f"all 12 atoms spawn inside the field")
Image.fromarray(env.screen).save(os.path.join(ROOT, "images", "stress_12atoms.png"))

# --- frame health: 12 atoms bouncing, idle --------------------------------
dropped = count_dropped(600)
check(dropped == 0, f"12 atoms idle: 0/600 frames dropped (got {dropped})")

# --- full load: hammer walls so capture sweeps + wipes run with 12 atoms;
# deaths are fine (9 lives) ---
def hammer(i):
    step = i % 120
    if step < 20:
        return [LEFT, RIGHT, UP, DOWN][(i // 120) % 4] if step % 2 == 0 else 0
    if step == 20 or step == 21:
        return A
    if step == 60:
        return 2  # B: toggle orientation now and then
    return 0

drops, sweeps_seen, walls_seen = 0, 0, 0
total = 3000
last = R("tick_cnt")
for i in range(total):
    env.step(hammer(i))
    if R("cap_state"):
        sweeps_seen += 1
    if R("wall_active"):
        walls_seen += 1
    now = R("tick_cnt")
    if now == last:
        drops += 1
    last = now
    if R("game_state") != 2:
        total = i + 1
        break
check(sweeps_seen > 0, f"capture sweeps exercised ({sweeps_seen} frames)")
check(walls_seen > 0, f"walls exercised ({walls_seen} frames)")
check(drops == 0, f"full load: 0/{total} frames dropped (got {drops})")
print(f"     load run: {total} frames, pct={R('percent')} lives={R('lives')} "
      f"state={R('game_state')}")
Image.fromarray(env.screen).save(os.path.join(ROOT, "images", "stress_load.png"))

# --- level 99: cap behavior ------------------------------------------------
st = goto_level(99)
check(st == 2, "level 99 reaches play state")
check(R("ball_n") == 12, "level 99 still 12 atoms")
# score saturation: 99,999,900 + clear bonus must clamp, never roll over
for i, d in enumerate([9, 9, 9, 9, 9, 9, 9, 0, 0]):
    env.ram[LABELS["score_digits"] + i] = d
# force a legitimate clear via one wall anchor at the threshold
env.ram[LABELS["filled_lo"]] = 0xE0
env.ram[LABELS["filled_hi"]] = 0x01
guard = 0
while R("game_state") == 2 and guard < 3000:
    guard += 1
    if not R("wall_active") and guard % 40 == 1:
        env.step(A)
    env.step(0)
check(R("game_state") in (3, 4), f"level 99 resolves (state {R('game_state')})")
if R("game_state") == 3:
    digits = [int(env.ram[LABELS["score_digits"] + i]) for i in range(9)]
    check(digits == [9] * 9, f"score saturates at 999,999,999 (got {digits})")
    frames(260)
    check(R("level") == 99, f"level caps at 99 (got {R('level')})")
    check(R("game_state") in (1, 2), "level 99 clear replays level 99")

# --- endurance: 10000-frame random soak at 12 atoms -------------------------
import numpy as np
if R("game_state") not in (1, 2):
    goto_level(11)
else:
    st = goto_level(11)
rng = np.random.RandomState(99)
bad = 0
last_nmi = R("nmi_count")
for i in range(10000):
    env.step(int(rng.choice([0, A, 2, UP, DOWN, LEFT, RIGHT, UP | RIGHT, DOWN | LEFT])))
    if i % 250 == 249:
        if R("nmi_count") == last_nmi:
            bad += 1
        last_nmi = R("nmi_count")
        if R("game_state") not in range(6):
            bad += 100
            break
        if R("game_state") != 2:      # died/cleared: restart a fresh level 11
            goto_level(11)
row0 = [int(env.ram[GRID + x]) for x in range(30)]
row24 = [int(env.ram[GRID + 24 * 32 + x]) for x in range(30)]
check(bad == 0, f"10000-frame random soak at 12 atoms (bad={bad})")
check(all(v & 0x0F == 1 for v in row0 + row24), "borders intact after soak")

print()
if FAILS:
    print(f"{len(FAILS)} FAILURES:")
    for f in FAILS:
        print("  - " + f)
    sys.exit(1)
print("all stress tests passed")
