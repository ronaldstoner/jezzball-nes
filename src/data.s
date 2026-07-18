; palettes, lookup tables, strings, sfx/music data.
.segment "RODATA"

; game: black field, gray panels, red/blue growing halves, white HUD text
pal_game:
  .byte $0F,$10,$16,$12, $0F,$10,$16,$12, $0F,$30,$10,$16, $0F,$30,$16,$12
  .byte $0F,$16,$12,$30, $0F,$30,$10,$0F, $0F,$16,$12,$30, $0F,$30,$10,$0F

; title: red logo top / blue logo bottom / white text / blink palette
pal_title:
  .byte $0F,$30,$16,$06, $0F,$30,$12,$02, $0F,$30,$10,$16, $0F,$30,$30,$30
  .byte $0F,$16,$12,$30, $0F,$30,$10,$0F, $0F,$16,$12,$30, $0F,$30,$10,$0F

grid_row_lo:
.repeat GRID_H, I
  .byte <(GRID + I*32)
.endrepeat
grid_row_hi:
.repeat GRID_H, I
  .byte >(GRID + I*32)
.endrepeat

; nametable address of grid row I (tile row I+4), column 0
nt_row_lo:
.repeat GRID_H, I
  .byte <($2000 + (I+4)*32)
.endrepeat
nt_row_hi:
.repeat GRID_H, I
  .byte >($2000 + (I+4)*32)
.endrepeat

tile_for_type:
  .byte TILE_BLANK, TILE_PANEL, TILE_PANEL, TILE_RED, TILE_BLUE

pow10_lo:
  .byte <10000, <1000, <100, <10
pow10_hi:
  .byte >10000, >1000, >100, >10

; per-level time limit in seconds (index clamped to 7)
time_tab_lo:
  .byte <120, <120, <150, <180, <210, <240, <270, <300
time_tab_hi:
  .byte >120, >120, >150, >180, >210, >240, >270, >300

; --- strings (charmap turns ASCII into font tiles) --------------------------
str_splash:      .byte "LEVEL 01"
str_paused:      .byte "PAUSED  "
str_clear:       .byte "LEVEL 01 CLEAR!"
str_bonus:       .byte "BONUS 00000"
str_gameover:    .byte "GAME OVER"
str_pressstart:  .byte "PRESS START"
str_h_level:     .byte "LEVEL 01"
str_h_lives:     .byte "LIVES 0"
str_h_time:      .byte "TIME 000"
str_h_score:     .byte "SCORE 000000000"
str_h_pct:       .byte "CLEAR   0%"
str_r_title:     .byte "* RUN RECAP *"
str_r_score:     .byte "SCORE  000000000"
str_r_level:     .byte "LEVEL         00"
str_r_walls:     .byte "WALLS      00000"
str_r_caps:      .byte "CAPTURES   00000"
str_r_deaths:    .byte "DEATHS       000"
str_r_time:      .byte "TIME  0000:00:00"
str_r_seed:      .byte "SEED        0000"
str_r_code:      .byte "CODE    00000000"

; --- note index constants (table index = midi - 23, 0 = rest) ---------------
N_A2  = 22
N_C3  = 25
N_E3  = 29
N_G3  = 32
N_A3  = 34
N_B3  = 36
N_C4  = 37
N_D4  = 39
N_E4  = 41
N_F4  = 42
N_G4  = 44
N_A4  = 46
N_B4  = 48
N_C5  = 49
N_D5  = 51
N_E5  = 53
N_F5  = 54
N_G5  = 56
N_A5  = 58
N_B5  = 60
N_C6  = 61
N_E6  = 65

.include "gen/notes.inc"
.include "gen/music.inc"
.include "gen/crc.inc"

; melody instrument: pluck envelope (per-frame volume), then the engine
; sustains 5<->6 (tremolo); vibrato offsets are signed period deltas
env_tab:
  .byte 12, 13, 11, 10, 9, 8, 7, 7, 6, 6, 6, 5
vib_tab:
  .byte $00,$01,$01,$02,$02,$02,$01,$01,$00,$FF,$FF,$FE,$FE,$FE,$FF,$FF

; --- sfx streams: pulse [dur, note, volreg], noise [dur, period, volreg] ----
sfx_d_start:
  .byte 2,N_E5,$B9, 2,N_A5,$B7, 0
sfx_d_blip:
  .byte 1,N_E6,$B4, 0
sfx_d_anchor:
  .byte 2,N_A3,$BA, 2,N_E3,$B7, 3,N_A2,$B4, 0
sfx_d_anchor_n:
  .byte 2,$0C,$36, 2,$0E,$33, 0
sfx_d_death:
  .byte 2,N_A4,$7B, 2,N_G4,$7A, 2,N_F4,$79, 2,N_E4,$78
  .byte 2,N_D4,$77, 2,N_C4,$76, 3,N_B3,$75, 4,N_A3,$74, 0
sfx_d_death_n:
  .byte 3,$0A,$38, 3,$0C,$35, 4,$0E,$32, 0
sfx_d_capture:
  .byte 3,N_C5,$BA, 3,N_E5,$BA, 3,N_G5,$BA, 6,N_C6,$BB, 0
sfx_d_clear:
  .byte 6,N_C5,$BB, 6,N_E5,$BB, 6,N_G5,$BB, 6,N_C6,$BB, 4,N_G5,$B8
  .byte 12,N_C6,$BC, 0
sfx_d_over:
  .byte 8,N_A4,$B8, 8,N_G4,$B7, 8,N_F4,$B6, 8,N_E4,$B5
  .byte 12,N_D4,$B4, 20,N_C4,$B6, 0
sfx_d_menu:
  .byte 2,N_A5,$BA, 2,0,$30, 3,N_E6,$BA, 0
sfx_d_pause:
  .byte 2,N_E5,$B6, 2,N_A4,$B6, 0
sfx_d_tick_n:
  .byte 1,$05,$34, 0
