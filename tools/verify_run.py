#!/usr/bin/env python3
"""Replay-verify a run: replays an fceux .fm2 movie or a .jbl input log
against the pinned ROM and prints the score/stats/SEED/CODE the recap screen
must show, plus per-level checkpoint codes.  See README for the trust model.
"""
import argparse
import hashlib
import os
import re
import sys

from nes_py import NESEnv

ROOT = os.path.join(os.path.dirname(__file__), "..")
ROM = os.path.join(ROOT, "build", "jezzball.nes")

# fm2 port field, chars left to right (fceux): R L D U T S B A
FM2_ORDER = "RLDUTSBA"
# internal pad byte: A=$80 B=$40 Sel=$20 Start=$10 U=$08 D=$04 L=$02 R=$01
PAD_BITS = {"A": 0x80, "B": 0x40, "S": 0x20, "T": 0x10,
            "U": 0x08, "D": 0x04, "L": 0x02, "R": 0x01}
STATE_RECAP = 5


def load_fm2(path):
    pads = []
    for line in open(path, errors="replace"):
        if not line.startswith("|"):
            continue
        fields = line.strip().split("|")
        port0 = fields[2] if len(fields) > 2 else ""
        pad = 0
        for ch, name in zip(port0, FM2_ORDER):
            if ch not in ". ":
                pad |= PAD_BITS[name]
        pads.append(pad)
    return pads


def load_jbl(path):
    pads = []
    for line in open(path):
        line = line.split("#")[0].strip()
        if line:
            pads.append(int(line, 16) & 0xFF)
    return pads


def bitrev(b):
    r = 0
    for i in range(8):
        if b & (1 << i):
            r |= 0x80 >> i
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("movie", help=".fm2 or .jbl input recording")
    ap.add_argument("--png", help="write the replayed recap screen here")
    ap.add_argument("--grace", type=int, default=900,
                    help="frames to run past the log end (default 900)")
    args = ap.parse_args()

    rom_sha = hashlib.sha256(open(ROM, "rb").read()).hexdigest()
    labels = {}
    for line in open(os.path.join(ROOT, "build", "labels.txt")):
        m = re.match(r"al ([0-9A-F]{6}) \.(\w+)", line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)

    pads = (load_fm2(args.movie) if args.movie.lower().endswith(".fm2")
            else load_jbl(args.movie))
    if not pads:
        sys.exit("no input frames found in movie")

    env = NESEnv(ROM)
    env.reset()

    def R(name):
        return int(env.ram[labels[name]])

    checkpoints = []
    prev_state = 0

    def watch():
        nonlocal prev_state
        st = R("game_state")
        if st == 3 and prev_state != 3:   # level clear: checkpoint code
            code = "".join(f"{int(env.ram[labels['chk' + str(i)]]):02X}"
                           for i in (3, 2, 1, 0))
            checkpoints.append((R("level"), code))
        prev_state = st

    for pad in pads:                      # nes-py wants LSB-first buttons
        env.step(bitrev(pad))
        watch()
    for _ in range(args.grace):           # let the game reach the recap
        if R("game_state") == STATE_RECAP:
            break
        env.step(0)
        watch()
    for _ in range(5):
        env.step(0)                       # settle the drawn screen

    ok = R("game_state") == STATE_RECAP
    score = "".join(str(int(env.ram[labels["score_digits"] + i]))
                    for i in range(9))
    code = "".join(f"{int(env.ram[labels['crc' + str(i)]]) ^ 0xFF:02X}"
                   for i in (3, 2, 1, 0))
    seed = f"{R('seed_hi'):02X}{R('seed_lo'):02X}"
    walls = R("stat_walls_lo") | R("stat_walls_hi") << 8
    caps = R("stat_caps_lo") | R("stat_caps_hi") << 8
    secs = (R("play_sec_lo") | R("play_sec_hi") << 8
            | R("play_sec_ex") << 16)

    print(f"rom sha256 : {rom_sha}")
    print(f"movie      : {args.movie} ({len(pads)} input frames)")
    print(f"reached recap screen: {'YES' if ok else 'NO'}")
    print(f"SCORE      : {score}")
    print(f"LEVEL      : {R('level'):02d}")
    print(f"WALLS      : {walls}")
    print(f"CAPTURES   : {caps}")
    print(f"DEATHS     : {R('stat_deaths')}")
    print(f"TIME       : {secs // 3600:04d}:{secs // 60 % 60:02d}:{secs % 60:02d}")
    for lvl, ck in checkpoints:
        print(f"checkpoint : level {lvl:02d} clear, CODE {ck}")
    print(f"SEED       : {seed}")
    print(f"CODE       : {code}")
    print("compare SCORE/SEED/CODE against the claimant's recap photo")

    if args.png:
        from PIL import Image
        Image.fromarray(env.screen).save(args.png)
        print(f"recap screen written to {args.png}")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
