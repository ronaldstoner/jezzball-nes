#!/usr/bin/env python3
"""JEZZBALL asset generator: 8KB CHR (font, playfield, logo, sprites),
title-screen RLE, charmap/tile-id includes, note tables, music streams and
CRC32 tables.  All art and music are original; font is public-domain font8x8.
"""
import math
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
TABLE_TILES = 256


def encode_tile(rows):
    """rows: 8 lists of 8 pixel values 0..3 -> 16-byte NES planar tile."""
    lo, hi = [], []
    for r in rows:
        lb = hb = 0
        for x in range(8):
            p = r[x]
            if p & 1:
                lb |= 0x80 >> x
            if p & 2:
                hb |= 0x80 >> x
        lo.append(lb)
        hi.append(hb)
    return bytes(lo + hi)


BLANK = encode_tile([[0] * 8] * 8)


def tiles_from_pixels(pix, w_tiles, h_tiles):
    """pix[y][x] (h_tiles*8 rows) -> row-major list of encoded tiles."""
    out = []
    for ty in range(h_tiles):
        for tx in range(w_tiles):
            out.append(encode_tile(
                [[pix[ty * 8 + y][tx * 8 + x] for x in range(8)]
                 for y in range(8)]))
    return out


# ---------------------------------------------------------------- font ----
def load_font8x8():
    """Parse font8x8_basic.h -> {char: [8 row bitmasks]} (bit0 = leftmost)."""
    src = open(os.path.join(ROOT, "tools", "font8x8_basic.h")).read()
    body = src[src.index("{", src.index("font8x8_basic")):]
    rows = re.findall(r"\{([^}]*)\}", body)
    font = {}
    for code, row in enumerate(rows[:128]):
        vals = [int(v, 0) for v in re.findall(r"0x[0-9A-Fa-f]+|\d+", row)]
        if len(vals) == 8:
            font[chr(code)] = vals
    return font


FONT = load_font8x8()


def glyph_tile(ch, color=1):
    bm = FONT[ch]
    return encode_tile([[color if (bm[y] >> x) & 1 else 0 for x in range(8)]
                        for y in range(8)])


# BG tiles: $00 blank, $01 panel, $02/$03 red/blue growing, $10-$19 digits,
# $21-$3A A-Z, punctuation below, $40+ deduped title logo + atom tiles.
bg = [BLANK] * TABLE_TILES

TILE_BLANK, TILE_PANEL, TILE_RED, TILE_BLUE = 0x00, 0x01, 0x02, 0x03
FONT_DIGIT_BASE, FONT_ALPHA_BASE = 0x10, 0x21

# Bevel panel: gray fill (color 1), black seam bottom+right => tiled wall look.
bg[TILE_PANEL] = encode_tile(
    [[0 if (x == 7 or y == 7) else 1 for x in range(8)] for y in range(8)])
# Growing wall segments: bright core with a darker rim line top/bottom so a
# run of them reads as a striped energy bar (color 2 = red pal / 3 = blue).
bg[TILE_RED] = encode_tile(
    [[2 if 0 < y < 7 else 0 for x in range(8)] for y in range(8)])
bg[TILE_BLUE] = encode_tile(
    [[3 if 0 < y < 7 else 0 for x in range(8)] for y in range(8)])

for d in range(10):
    bg[FONT_DIGIT_BASE + d] = glyph_tile(chr(ord("0") + d))
for a in range(26):
    bg[FONT_ALPHA_BASE + a] = glyph_tile(chr(ord("A") + a))
PUNCT = {"%": 0x3B, ".": 0x3C, "!": 0x3D, "-": 0x3E, ":": 0x3F,
         "(": 0x0A, ")": 0x0B, "+": 0x0C, "/": 0x0D, "*": 0x0E}
for ch, tid in PUNCT.items():
    bg[tid] = glyph_tile(ch)

# Logo: 6x8 half-res glyphs scaled 4x -> 3x4 tiles per letter; col 5 is
# spacing.  Fill = color 2 (red/blue via attributes), auto outline = color 1.
L_J = ["#####.", "#####.", "...##.", "...##.",
       "...##.", "#..##.", "#####.", ".###.."]
L_E = ["#####.", "#####.", "##....", "####..",
       "####..", "##....", "#####.", "#####."]
L_Z = ["#####.", "#####.", "..##..", ".##...",
       "##....", "##....", "#####.", "#####."]
L_B = ["####..", "#####.", "##.##.", "####..",
       "####..", "##.##.", "#####.", "####.."]
L_A = [".###..", "#####.", "##.##.", "#####.",
       "#####.", "##.##.", "##.##.", "##.##."]
L_L = ["##....", "##....", "##....", "##....",
       "##....", "##....", "#####.", "#####."]
LOGO_TEXT = [L_J, L_E, L_Z, L_Z, L_B, L_A, L_L, L_L]


def letter_pixels(spec):
    """6x8 spec -> 24x32 px with fill=2 and 1px white outline=1."""
    w, h = 24, 32
    pix = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if spec[y // 4][x // 4] == "#":
                pix[y][x] = 2
    for y in range(h):
        for x in range(w):
            if pix[y][x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and pix[yy][xx] == 2:
                        pix[y][x] = 1
    return pix


class TileAlloc:
    def __init__(self, bank, start):
        self.bank, self.next, self.cache = bank, start, {}

    def add(self, tile):
        if tile in self.cache:
            return self.cache[tile]
        if self.next >= TABLE_TILES:
            raise SystemExit("BG tile overflow")
        tid = self.next
        self.bank[tid] = tile
        self.cache[tile] = tid
        self.next += 1
        return tid


alloc = TileAlloc(bg, 0x40)
alloc.cache[BLANK] = TILE_BLANK  # transparent letter corners reuse tile 0

LOGO_TILES = []  # per letter: 3x4 tile ids row-major
for spec in LOGO_TEXT:
    LOGO_TILES.append([alloc.add(t)
                       for t in tiles_from_pixels(letter_pixels(spec), 3, 4)])

# Atom: 32x32 circle, fill=2 (attr makes left red / right blue),
# white ring + specular = 1.
atom_pix = [[0] * 32 for _ in range(32)]
for y in range(32):
    for x in range(32):
        d = math.hypot(x - 15.5, y - 15.5)
        if d <= 13.2:
            atom_pix[y][x] = 2
        elif d <= 15.2:
            atom_pix[y][x] = 1
for y in range(32):
    for x in range(32):
        if math.hypot(x - 10, y - 10) <= 3.2 and atom_pix[y][x] == 2:
            atom_pix[y][x] = 1
ATOM_TILES = [alloc.add(t) for t in tiles_from_pixels(atom_pix, 4, 4)]

# ------------------------------------------------------------- sprites ----
spr = [BLANK] * TABLE_TILES
# Ball: 8x8 atom, red/blue split rotating over 4 frames (H+V sprite flips
# add phases 4-7).  The white shine orbits WITH the spin so flips carry it
# around coherently instead of teleporting.
for f in range(4):
    phi = f * math.pi / 4
    pix = [[0] * 8 for _ in range(8)]
    for y in range(8):
        for x in range(8):
            d = math.hypot(x - 3.5, y - 3.5)
            if d > 3.9:
                continue
            a = math.atan2(y - 3.5, x - 3.5) - phi
            pix[y][x] = 1 if math.sin(a) <= 0 else 2
    sa = math.radians(225) + phi
    sx = round(3.5 + 2.1 * math.cos(sa))
    sy = round(3.5 + 2.1 * math.sin(sa))
    pix[sy][sx] = 3
    spr[f] = encode_tile(pix)

ARROW_UP = ["...11...",
            "..1111..",
            ".111111.",
            "11111111",
            "...22...",
            "...22...",
            "........",
            "........"]


def artdecode(rows):
    return [[int(c) if c.isdigit() else 0 for c in r] for r in rows]


def flip_v(p):
    return p[::-1]


def transpose(p):
    return [[p[x][y] for x in range(8)] for y in range(8)]


up = artdecode(ARROW_UP)
spr[0x04] = encode_tile(up)                              # up
spr[0x05] = encode_tile(flip_v(up))                      # down
spr[0x06] = encode_tile(transpose(up))                   # left
spr[0x07] = encode_tile([r[::-1] for r in transpose(up)])  # right

# ------------------------------------------------------- title screen ----
NT = [[TILE_BLANK] * 32 for _ in range(30)]
PAL = [[2] * 16 for _ in range(15)]  # 2x2-tile attr blocks, default pal2


def put_text(row, text, col=None):
    ids = []
    for ch in text:
        if ch == " ":
            ids.append(TILE_BLANK)
        elif ch.isdigit():
            ids.append(FONT_DIGIT_BASE + int(ch))
        elif ch.isalpha():
            ids.append(FONT_ALPHA_BASE + ord(ch.upper()) - ord("A"))
        else:
            ids.append(PUNCT[ch])
    if col is None:
        col = (32 - len(ids)) // 2
    for i, t in enumerate(ids):
        NT[row][col + i] = t
    return col


# Logo: 8 letters x 3 tiles = 24 cols (4..27), rows 6..9.
for li, tiles in enumerate(LOGO_TILES):
    for ty in range(4):
        for tx in range(3):
            NT[6 + ty][4 + li * 3 + tx] = tiles[ty * 3 + tx]
for bx in range(2, 14):     # logo attr: top half pal0 (red), bottom pal1
    PAL[3][bx] = 0
    PAL[4][bx] = 1

put_text(11, "* ATOMIC WALL ACTION *")

# Atom graphic rows 14..17, cols 14..17 (attr-block aligned).
for ty in range(4):
    for tx in range(4):
        NT[14 + ty][14 + tx] = ATOM_TILES[ty * 4 + tx]
PAL[7][7] = 0   # left half red
PAL[8][7] = 0
PAL[7][8] = 1   # right half blue
PAL[8][8] = 1

ps_col = put_text(20, "PRESS START")
for bx in range(ps_col // 2, (ps_col + 11 + 1) // 2 + 1):
    PAL[10][bx] = 3     # blinking palette

put_text(24, "TOP 000000000")
put_text(26, "RON STONER * STONER.COM")

TOP_SCORE_COL = put_text(24, "TOP 000000000")  # recompute col for the .inc

nt_bytes = bytearray()
for row in NT:
    nt_bytes += bytes(row)
attr = bytearray(64)
for by in range(15):
    for bx in range(16):
        attr[(by // 2) * 8 + bx // 2] |= PAL[by][bx] << (((by & 1) << 2) |
                                                         ((bx & 1) << 1))
title = bytes(nt_bytes + attr)
assert len(title) == 1024


def rle(data):
    out = bytearray()
    i = 0
    while i < len(data):
        j = i
        while j < len(data) and j - i < 255 and data[j] == data[i]:
            j += 1
        out += bytes((j - i, data[i]))
        i = j
    out.append(0)
    return bytes(out)


title_rle = rle(title)

# ------------------------------------------------------------- music ----
CPU = 1789773.0


def midi(name):
    m = re.match(r"([A-G])([#b]?)(-?\d)", name)
    base = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[m.group(1)]
    base += {"#": 1, "b": -1, "": 0}[m.group(2)]
    return base + (int(m.group(3)) + 1) * 12


NOTE_LO, NOTE_HI = 24, 96  # C1..B6 -> table index = midi - NOTE_LO
periods = []
for n in range(NOTE_LO, NOTE_HI):
    f = 440.0 * 2 ** ((n - 69) / 12)
    periods.append(max(8, min(0x7FF, round(CPU / (16 * f)) - 1)))


def N(name):
    return midi(name) - NOTE_LO + 1  # 0 is reserved for rest


R = 0
E = 12   # frames per 8th note @ ~150bpm

# Title theme: two 8-bar verses on a 128-slot 8th-note grid; "-" sustains so
# phrase endings bloom into tremolo/vibrato.  A: Am arps; B: C-major answer.
GRID = []
for bar in [
    # --- verse A ---
    ["A4", "E5", "C5", "E5", "A5", "E5", "C5", "E5"],
    ["G4", "E5", "B4", "E5", "G5", "E5", "B4", "E5"],
    ["F4", "C5", "A4", "C5", "F5", "C5", "A5", "C5"],
    ["E4", "B4", "G4", "B4", "E5", "G5", "B5", "G5"],
    ["A4", "E5", "C5", "E5", "A5", "E5", "C5", "E5"],
    ["G4", "E5", "B4", "E5", "G5", "E5", "B4", "E5"],
    ["F4", "C5", "A5", "C5", "E4", "B4", "G5", "B4"],
    ["A4", "C5", "E5", "A5", "-",  "-",  "-",  "-"],
    # --- verse B ---
    ["C5", "G5", "E5", "G5", "C6", "G5", "E5", "G5"],
    ["B4", "G5", "D5", "G5", "B5", "G5", "D5", "G5"],
    ["A4", "E5", "C5", "E5", "A5", "C6", "A5", "E5"],
    ["E5", "B5", "G5", "B5", "E5", "B4", "G5", "-"],
    ["F5", "C6", "A5", "C6", "F5", "A5", "F5", "C5"],
    ["G5", "D6", "B5", "D6", "G5", "B5", "G5", "D5"],
    ["A5", "E5", "C6", "E5", "A5", "E5", "C5", "E5"],
    ["E5", "G#4", "B4", "G#5", "B5", "-",  "-",  "-"],
]:
    GRID.extend(bar)


def grid_events(grid):
    """8th-note grid -> (note, frames) events; '-' extends, leading '-'
    wraps the loop tail (continuous on loop, harmless at startup)."""
    n = len(grid)
    lead = 0
    while grid[lead] == "-":
        lead += 1
    ev = []
    cur = None
    dur = 0
    for slot in grid[lead:] + grid[:lead]:
        if slot == "-":
            dur += E
            continue
        if cur is not None:
            ev.append((cur, dur))
        cur = N(slot) if slot else R
        dur = E
    ev.append((cur, dur))
    return ev


MELODY = grid_events(GRID)
# echo voice on pulse 2: the same line half a bar (4 slots) behind, quiet
ECHO = grid_events(GRID[-4:] + GRID[:-4])
assert sum(d for _, d in MELODY) == len(GRID) * E
assert sum(d for _, d in ECHO) == len(GRID) * E

BASS = []
for bar in [["A2", "A2", "A3", "A2"], ["G2", "G2", "G3", "G2"],
            ["F2", "F2", "F3", "F2"], ["E2", "E2", "E3", "E2"],
            ["A2", "A2", "A3", "A2"], ["G2", "G2", "G3", "G2"],
            ["F2", "F3", "E2", "E3"], ["A2", "A3", "A2", R],
            ["C3", "C3", "C2", "C3"], ["G2", "G2", "G3", "G2"],
            ["A2", "A2", "A3", "A2"], ["E2", "E2", "E3", "E2"],
            ["F2", "F2", "F3", "F2"], ["G2", "G2", "G3", "G2"],
            ["A2", "A2", "A3", "A2"], ["E2", "E3", "E2", "E2"]]:
    for nt in bar:
        BASS.append((N(nt) if nt else R, E * 2))

# hi-hat loop, one byte per 8th: hi nibble = noise period, lo = volume
HATS = [0x54, 0x51, 0x52, 0x51, 0x53, 0x51, 0x52, 0x51]

# ------------------------------------------------------------- output ----
os.makedirs(os.path.join(ROOT, "assets", "chr"), exist_ok=True)
os.makedirs(os.path.join(ROOT, "src", "gen"), exist_ok=True)

with open(os.path.join(ROOT, "assets", "chr", "jezzball.chr"), "wb") as f:
    for t in bg:
        f.write(t)
    for t in spr:
        f.write(t)

with open(os.path.join(ROOT, "src", "gen", "tiles.inc"), "w") as f:
    f.write("; generated by tools/gen_chr.py -- do not edit\n")
    f.write(f"TILE_BLANK      = ${TILE_BLANK:02X}\n")
    f.write(f"TILE_PANEL      = ${TILE_PANEL:02X}\n")
    f.write(f"TILE_RED        = ${TILE_RED:02X}\n")
    f.write(f"TILE_BLUE       = ${TILE_BLUE:02X}\n")
    f.write(f"FONT_DIGIT_BASE = ${FONT_DIGIT_BASE:02X}\n")
    f.write(f"FONT_ALPHA_BASE = ${FONT_ALPHA_BASE:02X}\n")
    f.write("SPR_BALL        = $00   ; 4 anim frames\n")
    f.write("SPR_ARROW_U     = $04\nSPR_ARROW_D     = $05\n")
    f.write("SPR_ARROW_L     = $06\nSPR_ARROW_R     = $07\n")
    f.write(f"TITLE_TOP_ADDR  = ${0x2000 + 24 * 32 + TOP_SCORE_COL + 4:04X}"
            "   ; six digits after 'TOP '\n")
    f.write(f"TITLE_PS_ROW    = 20\n")

with open(os.path.join(ROOT, "src", "gen", "charmap.inc"), "w") as f:
    f.write("; generated by tools/gen_chr.py -- do not edit\n")
    f.write(".charmap $20, $00\n")
    for d in range(10):
        f.write(f".charmap ${0x30 + d:02X}, ${FONT_DIGIT_BASE + d:02X}\n")
    for a in range(26):
        f.write(f".charmap ${0x41 + a:02X}, ${FONT_ALPHA_BASE + a:02X}\n")
        f.write(f".charmap ${0x61 + a:02X}, ${FONT_ALPHA_BASE + a:02X}\n")
    for ch, tid in PUNCT.items():
        f.write(f".charmap ${ord(ch):02X}, ${tid:02X}\n")

with open(os.path.join(ROOT, "src", "gen", "title_rle.s"), "w") as f:
    f.write("; generated by tools/gen_chr.py -- do not edit\n")
    f.write(".export title_rle\n.segment \"RODATA\"\ntitle_rle:\n")
    for i in range(0, len(title_rle), 16):
        f.write(".byte " + ",".join(f"${b:02X}"
                                    for b in title_rle[i:i + 16]) + "\n")

with open(os.path.join(ROOT, "src", "gen", "notes.inc"), "w") as f:
    f.write("; generated by tools/gen_chr.py -- NTSC pulse periods C1..B6\n")
    f.write("note_period_lo:\n  .byte $00")
    for p in periods:
        f.write(f", ${p & 0xFF:02X}")
    f.write("\nnote_period_hi:\n  .byte $00")
    for p in periods:
        f.write(f", ${p >> 8:02X}")
    f.write("\n")


def emit_stream(f, label, ev):
    f.write(f"{label}:\n")
    for note, dur in ev:
        f.write(f"  .byte ${note:02X}, ${dur:02X}\n")
    f.write("  .byte $FF\n")


with open(os.path.join(ROOT, "src", "gen", "music.inc"), "w") as f:
    f.write("; generated by tools/gen_chr.py -- title theme\n")
    emit_stream(f, "music_melody", MELODY)
    emit_stream(f, "music_bass", BASS)
    emit_stream(f, "music_echo", ECHO)
    f.write("music_hats:\n")
    f.write("  .byte " + ", ".join(f"${b:02X}" for b in HATS) + "\n")
    f.write("  .byte $FF\n")

crc_tab = []
for i in range(256):
    c = i
    for _ in range(8):
        c = (c >> 1) ^ (0xEDB88320 if c & 1 else 0)
    crc_tab.append(c)
with open(os.path.join(ROOT, "src", "gen", "crc.inc"), "w") as f:
    f.write("; generated by tools/gen_chr.py -- CRC32 byte-lane tables\n")
    for lane in range(4):
        f.write(f"crc_t{lane}:\n")
        for i in range(0, 256, 16):
            f.write(".byte " + ",".join(
                f"${(crc_tab[i+k] >> (8*lane)) & 0xFF:02X}"
                for k in range(16)) + "\n")

print(f"chr: bg tiles used through ${alloc.next - 1:02X}, "
      f"title RLE {len(title_rle)} bytes, "
      f"melody {len(MELODY)} events")
