; JEZZBALL: global constants, zeropage and RAM layout.

; --- PPU / APU registers ---
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014

; PPUCTRL base: NMI on, BG pattern $0000, sprites $1000, inc +1
CTRL_BASE = %10001000
CTRL_VERT = %00000100          ; +32 increment for vertical runs

; --- controller bits (after 8x LSR/ROL read) ---
PAD_A     = $80
PAD_B     = $40
PAD_SEL   = $20
PAD_START = $10
PAD_U     = $08
PAD_D     = $04
PAD_L     = $02
PAD_R     = $01

; Grid: 30x25 cells of 8x8px incl. the solid border ring, stride 32; cell
; (x,y) -> tile (x+1,y+4).  Interior x 1..28, y 1..23 = 644 cells.
GRID       = $0400             ; 25 rows * 32 = 800 bytes ($0400-$071F)
GRID_W     = 30
GRID_H     = 25
INT_XMIN   = 1
INT_XMAX   = 28
INT_YMIN   = 1
INT_YMAX   = 23
WIN_FILLED = 483               ; 75% of 644 interior cells

; cell type (low nibble); bit7 = flood mark, bit6 = dirty (needs redraw)
CELL_EMPTY = 0
CELL_WALL  = 1
CELL_CAP   = 2
CELL_GROWA = 3                 ; red half (up / left, includes origin)
CELL_GROWB = 4                 ; blue half (down / right)
MARK_BIT   = $80
DIRTY_BIT  = $40

; --- fixed RAM pages --------------------------------------------------------
OAM        = $0200
PPUBUF     = $0300             ; queued VRAM writes, drained in NMI
BUF_SIZE   = 192
PAL_SHADOW = $03C0             ; 32-byte palette shadow
DIGITS    = $03E0              ; scratch for binary->decimal (5 digits)
STRBUF     = $03F0             ; 16-byte string build buffer (RAM-patchable)

VRAM_BUDGET = 64               ; vblank cost units per frame; an entry costs
                               ; len + 4 (the +4 models per-entry PPUADDR
                               ; setup) so the NMI drain always fits vblank

; --- game tuning ------------------------------------------------------------
STATE_TITLE  = 0
STATE_SPLASH = 1
STATE_PLAY   = 2
STATE_CLEAR  = 3
STATE_OVER   = 4
STATE_RECAP  = 5               ; post-death stats + verification code

WALL_SPEED   = 3               ; frames per growth step per half
REPEAT_DELAY = 8               ; cursor auto-repeat: first delay
REPEAT_RATE  = 2               ; then this fast (30 cells/sec)
MAX_BALLS    = 12
SWEEP_ROWS   = 6               ; flood-sweep rows/frame at 12 atoms: sized so
                               ; the worst frame never overruns (stress-tested)
SPLASH_TIME  = 90
CLEAR_TIME   = 240

; ---------------------------------------------------------------------------
.segment "ZEROPAGE"

nmi_t0:     .res 1             ; NMI-only scratch (never touched by main)
t0:         .res 1             ; scratch (callee-owned, main thread only)
t1:         .res 1
t2:         .res 1
t3:         .res 1
t4:         .res 1
t5:         .res 1
t6:         .res 1
t7:         .res 1
ptr0:       .res 2
ptr1:       .res 2

nmi_count:  .res 1
frame_ready:.res 1             ; main -> NMI: OAM + buffer are complete
soft_2001:  .res 1             ; PPUMASK shadow (render on/off, grayscale)
pal_dirty:  .res 1
buf_idx:    .res 1
vram_budget:.res 1

pad:        .res 1
pad_prev:   .res 1
pad_new:    .res 1
rep_timer:  .res 1

game_state: .res 1
state_timer:.res 1
init_request:.res 1            ; 1 = title, 2 = level (handled in main loop)
pause_flag: .res 1

rng_lo:     .res 1
rng_hi:     .res 1

cursor_x:   .res 1             ; grid cell coords
cursor_y:   .res 1
cursor_dir: .res 1             ; 0 = vertical wall, 1 = horizontal wall

wall_active:.res 1
wall_dir:   .res 1             ; copy of cursor_dir at press
wall_ox:    .res 1
wall_oy:    .res 1
wall_timer: .res 1
wa_state:   .res 1             ; 0 dead/none, 1 growing, 2 anchored
wa_head:    .res 1             ; row (vertical) / col (horizontal)
wb_state:   .res 1
wb_head:    .res 1

ball_n:     .res 1
level:      .res 1
lives:      .res 1
time_lo:    .res 1             ; seconds remaining, 16-bit
time_hi:    .res 1
tick_cnt:   .res 1             ; 60-frame divider

filled_lo:  .res 1             ; interior cells that are wall or captured
filled_hi:  .res 1
percent:    .res 1             ; display percent 0..100

score_digits:.res 9            ; decimal digits, MSD first (999,999,999 cap
hi_digits:  .res 9             ; = 240+ hours at max rate; saturates, never
                               ; rolls over)

hud_flags:  .res 1             ; bit0 level, 1 lives, 2 time, 3 score, 4 pct
HUD_LEVEL  = $01
HUD_LIVES  = $02
HUD_TIME   = $04
HUD_SCORE  = $08
HUD_PCT    = $10

cap_state:  .res 1             ; 0 idle, 1 clearing marks, 2 sweeping, 3 fill
cap_dir:    .res 1             ; 0 forward, 1 backward
cap_row:    .res 1
cap_changed:.res 1
cap_quiet:  .res 1             ; consecutive no-change passes
cap_req:    .res 1
cap_cnt_lo: .res 1
cap_cnt_hi: .res 1

dirty_lo:   .res 1             ; count of DIRTY cells awaiting redraw
dirty_hi:   .res 1
wipe_row:   .res 1
wipe_end:   .res 1             ; current run end col (survives queue calls)

gameover_pending:.res 1
clear_pending:   .res 1

oam_pos:    .res 1
oam_rot:    .res 1
blink_timer:.res 1

mus_on:     .res 1
mus_mel_ptr:.res 2
mus_mel_tmr:.res 1
mus_bas_ptr:.res 2
mus_bas_tmr:.res 1
mus_echo_ptr:.res 2            ; pulse2 echo voice (melody, half a bar late)
mus_echo_tmr:.res 1
mus_hat_ptr:.res 2             ; noise hi-hat loop
mus_hat_tmr:.res 1
mus_p1_frame:.res 1            ; frames since melody note-on (env/vibrato)
mus_p1_blo: .res 1             ; melody base period
mus_p1_bhi: .res 1             ; ($FF = rest)
mus_p1_lhi: .res 1             ; last $4003 write (avoid phase-reset clicks)
wall_steps: .res 1             ; growth ticks: the build-ratchet pitch rises
sfx_p_ptr:  .res 2             ; pulse 2 sfx stream (0 hi = inactive)
sfx_p_tmr:  .res 1
sfx_n_ptr:  .res 2             ; noise sfx stream
sfx_n_tmr:  .res 1

ball_nx:    .res 1             ; ball movement scratch (kill path safe)
ball_edge:  .res 1
ball_blk:   .res 1
life_frame: .res 1             ; a ball hit already cost a life this frame

rep_accel:  .res 1             ; held-cursor repeats; ramps 30 -> 60 cells/s
sweep_rows: .res 1             ; capture rows/frame (adaptive by atom count)

; run-verification state: CRC32 over seed + every gameplay input frame +
; final stats.  Deterministic, so a replayed input log reproduces the code.
crc0:       .res 1
crc1:       .res 1
crc2:       .res 1
crc3:       .res 1
seed_lo:    .res 1             ; RNG seed at run start (shown on recap)
seed_hi:    .res 1
stat_walls_lo:.res 1
stat_walls_hi:.res 1
stat_caps_lo: .res 1
stat_caps_hi: .res 1
stat_deaths:  .res 1
play_sec_lo:  .res 1           ; unpaused play time in seconds, 24-bit
play_sec_hi:  .res 1           ; (16-bit wraps at 18h -- marathons go longer)
play_sec_ex:  .res 1
chk0:       .res 1             ; running-CRC snapshot at each level clear:
chk1:       .res 1             ; per-level checkpoint codes let a verifier
chk2:       .res 1             ; localize divergence in a marathon replay
chk3:       .res 1

ball_x:     .res MAX_BALLS     ; pixel coords of 8x8 ball, top-left
ball_y:     .res MAX_BALLS
ball_dx:    .res MAX_BALLS     ; $01 or $FF
ball_dy:    .res MAX_BALLS
