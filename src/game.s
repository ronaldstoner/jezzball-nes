; Level setup + play state: cursor, two-half wall building (A red up/left
; incl. origin, B blue down/right; anchor on solid, die on atom touch),
; timers, transitions.  Anchors trigger capture.s; 75% filled clears.

; --- small shared helpers ---------------------------------------------------

; t0 = gx, t1 = gy -> A = raw cell, ptr0 = grid row, Y = gx (for stores)
.proc grid_get
    ldy t1
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    ldy t0
    lda (ptr0),y
    rts
.endproc

; t0 = gx, t1 = gy -> t0/t1 = nametable address hi/lo of that cell
.proc cell_nt_addr
    ldy t1
    lda nt_row_lo,y
    sec                        ; +1: grid col 0 is nametable col 1
    adc t0
    sta t1
    lda nt_row_hi,y
    adc #0
    sta t0
    rts
.endproc

; t0 = gx, t1 = gy: carry set if any ball's 8x8 box overlaps the cell
.proc cell_ball_overlap
    lda t0
    clc
    adc #1
    asl
    asl
    asl
    sta t2                     ; cell pixel x
    lda t1
    clc
    adc #4
    asl
    asl
    asl
    sta t3                     ; cell pixel y
    ldx ball_n
    dex
loop:
    lda ball_x,x
    sec
    sbc t2
    bcs :+
    eor #$FF
    adc #1
:   cmp #8
    bcs next
    lda ball_y,x
    sec
    sbc t3
    bcs :+
    eor #$FF
    adc #1
:   cmp #8
    bcs next
    sec
    rts
next:
    dex
    bpl loop
    clc
    rts
.endproc

; t0/t1 (lo/hi) * A -> t2/t3/t4 (24-bit).  Clobbers t0/t1/t5/t6.
.proc mul16x8
    sta t5
    lda #0
    sta t2
    sta t3
    sta t4
    sta t6
    ldx #8
@bit:
    lsr t5
    bcc @no
    clc
    lda t2
    adc t0
    sta t2
    lda t3
    adc t1
    sta t3
    lda t4
    adc t6
    sta t4
@no:
    asl t0
    rol t1
    rol t6
    dex
    bne @bit
    rts
.endproc

; percent = (filled*159+4)>>10 = floor(100*filled/644) exactly, so the HUD
; hits 75% on the same cell that trips the win check (filled = 483)
.proc update_percent
    lda filled_lo
    sta t0
    lda filled_hi
    sta t1
    lda #159
    jsr mul16x8
    lda t2
    clc
    adc #4
    sta t2
    lda t3
    adc #0
    sta t3
    lda t4
    adc #0
    sta t4
    lsr t4
    ror t3
    lsr t4
    ror t3
    lda t3
    sta percent
    lda hud_flags
    ora #HUD_PCT
    sta hud_flags
    rts
.endproc

.proc check_win
    lda filled_hi
    cmp #>WIN_FILLED
    bcc done
    bne win
    lda filled_lo
    cmp #<WIN_FILLED
    bcc done
win:
    lda #1
    sta clear_pending
done:
    rts
.endproc

.proc life_lost
    lda life_frame             ; a double wall touch costs one life, not two
    beq :+
    rts
:   lda #1
    sta life_frame
    lda stat_deaths
    cmp #$FF
    beq :+
    inc stat_deaths
:   jsr sfx_death
    lda lives
    beq @over                  ; lives already 0: straight to game over
    dec lives
    lda hud_flags
    ora #HUD_LIVES
    sta hud_flags
    lda lives
    bne @done
@over:
    lda #1
    sta gameover_pending
@done:
    rts
.endproc

; --- level construction -----------------------------------------------------

.proc level_init
    jsr sound_silence
    jsr render_off

    lda #<pal_game
    sta ptr0
    lda #>pal_game
    sta ptr0+1
    jsr load_palette

    lda #$20                   ; clear nametable 0
    sta t0
    lda #$00
    sta t1
    jsr ppu_addr
    lda #0
    ldx #240
    jsr ppu_fill
    ldx #240
    jsr ppu_fill
    ldx #240
    jsr ppu_fill
    ldx #240
    jsr ppu_fill
    lda #$AA                   ; attr rows 0-3: HUD text palette 2
    ldx #8
    jsr ppu_fill
    lda #$00                   ; rest of attributes: playfield palette 0
    ldx #56
    jsr ppu_fill

    lda #$20                   ; top border, tile row 4
    sta t0
    lda #$81
    sta t1
    jsr ppu_addr
    lda #TILE_PANEL
    ldx #30
    jsr ppu_fill
    lda #$23                   ; bottom border, tile row 28
    sta t0
    lda #$81
    sta t1
    jsr ppu_addr
    lda #TILE_PANEL
    ldx #30
    jsr ppu_fill
    lda #CTRL_BASE|CTRL_VERT   ; side borders as two vertical runs
    sta PPUCTRL
    lda #$20
    sta t0
    lda #$A1                   ; col 1, tile row 5
    sta t1
    jsr ppu_addr
    lda #TILE_PANEL
    ldx #23
    jsr ppu_fill
    lda #$20
    sta t0
    lda #$BE                   ; col 30, tile row 5
    sta t1
    jsr ppu_addr
    lda #TILE_PANEL
    ldx #23
    jsr ppu_fill
    lda #CTRL_BASE
    sta PPUCTRL

    lda #<str_splash           ; "LEVEL nn" splash, patched in RAM
    sta ptr0
    lda #>str_splash
    sta ptr0+1
    ldx #8
    jsr str_to_buf
    jsr patch_level_digits
    lda #$22
    sta t0
    lda #$0C
    sta t1
    ldx #8
    jsr draw_text_direct

    ; ---- game RAM ----
    ldx #0                     ; grid: border ring solid, interior empty
@grow:
    txa
    tay
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    cpx #0
    beq @solidrow
    cpx #GRID_H-1
    beq @solidrow
    ldy #0
    lda #CELL_WALL
    sta (ptr0),y
    lda #CELL_EMPTY
    ldy #1
@gi: sta (ptr0),y
    iny
    cpy #GRID_W-1
    bne @gi
    lda #CELL_WALL
    sta (ptr0),y
    jmp @nextrow
@solidrow:
    lda #CELL_WALL
    ldy #0
@gs: sta (ptr0),y
    iny
    cpy #GRID_W
    bne @gs
@nextrow:
    inx
    cpx #GRID_H
    bne @grow

    lda #0
    sta filled_lo
    sta filled_hi
    sta percent
    sta cap_state
    sta cap_req
    sta cap_cnt_lo
    sta cap_cnt_hi
    sta dirty_lo
    sta dirty_hi
    sta wall_active
    sta wa_state
    sta wb_state
    sta pause_flag
    sta gameover_pending
    sta clear_pending
    sta oam_rot
    sta rep_timer
    sta rep_accel
    lda #1
    sta wipe_row
    lda #14
    sta cursor_x
    lda #12
    sta cursor_y
    lda #0
    sta cursor_dir
    lda #60
    sta tick_cnt

    lda level                  ; lives = level + 1, capped at 9
    clc
    adc #1
    cmp #10
    bcc :+
    lda #9
:   sta lives

    ldx level                  ; time limit (seconds) from table
    cpx #8
    bcc :+
    ldx #7
:   lda time_tab_lo,x
    sta time_lo
    lda time_tab_hi,x
    sta time_hi

    jsr spawn_balls

    lda #18                    ; capture sweep rows/frame: spend the CPU
    sec                        ; headroom fewer atoms leave (6 + 12 - atoms,
    sbc ball_n                 ; clamped to 12; 12 atoms -> the stress-tested 6)
    cmp #13
    bcc :+
    lda #12
:   sta sweep_rows

    lda #$1F                   ; redraw every HUD field
    sta hud_flags
    lda #STATE_SPLASH
    sta game_state
    lda #SPLASH_TIME
    sta state_timer
    jsr oam_clear              ; no stale sprites on the first frame
    jmp render_on
.endproc

; copy X bytes from (ptr0) into STRBUF and point ptr0 at it (ROM templates
; are patched in RAM before being drawn/queued)
.proc str_to_buf
    stx t6
    ldy #0
:   lda (ptr0),y
    sta STRBUF,y
    iny
    cpy t6
    bne :-
    lda #<STRBUF
    sta ptr0
    lda #>STRBUF
    sta ptr0+1
    rts
.endproc

; write level as two digit tiles at (ptr0)+6
.proc patch_level_digits
    lda level
    ldx #0
:   cmp #10
    bcc :+
    sbc #10
    inx
    bne :-
:   sta t6
    txa
    ora #FONT_DIGIT_BASE
    ldy #6
    sta (ptr0),y
    lda t6
    ora #FONT_DIGIT_BASE
    iny
    sta (ptr0),y
    rts
.endproc

.proc spawn_balls
    lda level
    clc
    adc #1
    cmp #MAX_BALLS+1
    bcc :+
    lda #MAX_BALLS
:   sta ball_n
    ldx #0                     ; X = ball being placed
place:
    lda #40
    sta t7                     ; bounded separation retries
genx:
    jsr rand8
    and #$1F
    cmp #2
    bcc genx
    cmp #28
    bcs genx
    clc
    adc #1
    asl
    asl
    asl
    sta t2                     ; pixel x
geny:
    jsr rand8
    and #$1F
    cmp #2
    bcc geny
    cmp #23
    bcs geny
    clc
    adc #4
    asl
    asl
    asl
    sta t3                     ; pixel y
    dec t7
    beq accept                 ; give up on separation, position is legal
    stx t6
    ldy #0                     ; check distance to already-placed balls
@sep:
    cpy t6
    beq accept
    lda ball_x,y
    sec
    sbc t2
    bcs :+
    eor #$FF
    adc #1
:   cmp #12
    bcs @next
    lda ball_y,y
    sec
    sbc t3
    bcs :+
    eor #$FF
    adc #1
:   cmp #12
    bcc genx                   ; too close: pick a fresh spot
@next:
    iny
    bne @sep
accept:
    lda t2
    sta ball_x,x
    lda t3
    sta ball_y,x
    jsr rand8
    lsr
    lda #$01
    bcc :+
    lda #$FF
:   sta ball_dx,x
    jsr rand8
    lsr
    lda #$01
    bcc :+
    lda #$FF
:   sta ball_dy,x
    inx
    cpx ball_n
    beq :+
    jmp place
:   rts
.endproc

; --- splash / play / clear / over states ------------------------------------

.proc splash_update
    jsr hud_update
    dec state_timer
    bne @draw
    lda #$22                   ; erase "LEVEL nn"
    sta t0
    lda #$0C
    sta t1
    lda #0
    sta t2
    ldx #8
    lda #TILE_BLANK
    jsr ppu_queue_run
    lda #STATE_PLAY
    sta game_state
@draw:
    jmp draw_game_oam
.endproc

.proc play_update
    lda pad_new
    and #PAD_START
    beq @nopause
    lda pause_flag
    eor #1
    sta pause_flag
    jsr sfx_pause
    lda pause_flag
    beq @unpause
    lda soft_2001
    ora #$01                   ; grayscale = paused
    sta soft_2001
    lda #<str_paused
    sta ptr0
    lda #>str_paused
    sta ptr0+1
    lda #$20
    sta t0
    lda #$54
    sta t1
    ldx #8
    jsr ppu_queue_lit
    lda hud_flags              ; a deferred TIME redraw must not overwrite it
    and #$FF^HUD_TIME
    sta hud_flags
    jmp @nopause
@unpause:
    lda soft_2001
    and #$FE
    sta soft_2001
    lda hud_flags
    ora #HUD_TIME
    sta hud_flags
    lda #0                     ; a press consumed while paused must not
    sta rep_timer              ; resume at full auto-repeat speed
    sta rep_accel
@nopause:
    lda pause_flag
    beq @live
    jsr hud_update
    jmp draw_game_oam
@live:
    lda #0
    sta life_frame
    jsr cursor_update
    lda pad_new
    and #PAD_B
    beq :+
    lda cursor_dir
    eor #1
    sta cursor_dir
    jsr sfx_blip
:   lda pad_new
    and #PAD_A
    beq :+
    jsr wall_start
:   jsr wall_update
    jsr balls_update
    jsr capture_step
    jsr wipe_update
    jsr time_update
    jsr hud_update

    ; 75% outranks a same-window death; both transitions retry across
    ; frames until the VRAM budget fits their text writes
    lda clear_pending
    beq @over
    lda dirty_lo
    ora dirty_hi
    bne @oam
    lda cap_state
    bne @oam
    lda vram_budget            ; CLEAR + BONUS lits cost 19 + 15
    cmp #36
    bcc @oam
    jmp do_clear
@over:
    lda gameover_pending
    beq @oam
    jmp go_gameover
@oam:
    jmp draw_game_oam
.endproc

.proc cursor_update
    lda pad
    and #PAD_U|PAD_D|PAD_L|PAD_R
    bne held
    lda #0
    sta rep_timer
    rts
held:
    ldy pad_new
    tya
    and #PAD_U|PAD_D|PAD_L|PAD_R
    bne @fresh
    lda rep_timer              ; 0 = the press was consumed while paused or
    beq @fresh                 ; in splash: treat as fresh, never underflow
    dec rep_timer
    beq :+
    rts
:   lda rep_accel              ; ramp: 30 cells/s, then 60 after 8 repeats
    cmp #8
    bcs :+
    inc rep_accel
    lda #REPEAT_RATE
    sta rep_timer
    bne @move
:   lda #1
    sta rep_timer
    bne @move
@fresh:
    lda #REPEAT_DELAY
    sta rep_timer
    lda #0
    sta rep_accel
@move:
    lda pad
    and #PAD_U
    beq :+
    lda cursor_y
    cmp #INT_YMIN+1
    bcc :+
    dec cursor_y
:   lda pad
    and #PAD_D
    beq :+
    lda cursor_y
    cmp #INT_YMAX
    bcs :+
    inc cursor_y
:   lda pad
    and #PAD_L
    beq :+
    lda cursor_x
    cmp #INT_XMIN+1
    bcc :+
    dec cursor_x
:   lda pad
    and #PAD_R
    beq :+
    lda cursor_x
    cmp #INT_XMAX
    bcs :+
    inc cursor_x
:   rts
.endproc

; --- wall building ----------------------------------------------------------

.proc wall_start
    lda wall_active
    ora gameover_pending       ; no new walls once the outcome is decided
    ora clear_pending
    beq :+
    rts
:
    lda cursor_x
    sta t0
    lda cursor_y
    sta t1
    jsr grid_get
    and #$0F
    bne done                   ; must start on empty field
    lda cursor_x
    sta t0
    lda cursor_y
    sta t1
    jsr cell_ball_overlap
    bcc ok
    jmp life_lost              ; clicked on a ball: instant loss, no wall
ok:
    lda #0
    sta wall_steps
    lda stat_walls_lo          ; saturating count (marathons hit 16 bits)
    and stat_walls_hi
    cmp #$FF
    beq :+
    inc stat_walls_lo
    bne :+
    inc stat_walls_hi
:   lda #1
    sta wall_active
    lda cursor_dir
    sta wall_dir
    lda cursor_x
    sta wall_ox
    sta t0
    lda cursor_y
    sta wall_oy
    sta t1
    lda #1
    sta wa_state
    sta wb_state
    lda #WALL_SPEED
    sta wall_timer
    lda wall_dir
    beq @vert
    lda wall_ox
    sta wa_head
    sta wb_head
    jmp @claim
@vert:
    lda wall_oy
    sta wa_head
    sta wb_head
@claim:
    jsr grid_get
    lda #CELL_GROWA
    sta (ptr0),y
    lda cursor_x
    sta t0
    lda cursor_y
    sta t1
    jsr cell_nt_addr
    lda #0
    sta t2
    ldx #1
    lda #TILE_RED
    jsr ppu_queue_run
    jsr sfx_wall_start
done:
    rts
.endproc

.proc wall_update
    lda wall_active
    beq done
    dec wall_timer
    beq :+
done:
    rts
:   lda #WALL_SPEED
    sta wall_timer

    ; build ratchet: rising-pitch blip per growth step; direct pulse2 pokes
    ; are safe -- the NMI leaves the channel alone unless an sfx owns it
    lda wall_steps
    cmp #46
    bcs :+
    inc wall_steps
:   lda sfx_p_ptr+1
    bne @notick
    lda wall_steps
    clc
    adc #24                    ; start at C3, rise ~2 octaves
    tax
    lda note_period_lo,x
    sta $4006
    lda #$04                   ; 12.5%, one-shot envelope + live length
    sta $4004                  ; counter: always self-mutes
    lda note_period_hi,x
    sta $4007
@notick:

    lda wa_state               ; ---- half A: up / left ----
    cmp #1
    bne halfB
    lda wall_dir
    beq :+
    lda wa_head                ; horizontal: next col left
    sec
    sbc #1
    sta t0
    lda wall_oy
    sta t1
    jmp @probe
:   lda wall_ox                ; vertical: next row up
    sta t0
    lda wa_head
    sec
    sbc #1
    sta t1
@probe:
    jsr grid_get
    and #$0F
    beq @open
    jsr anchor_a               ; hit wall/captured: half A anchors
    jmp halfB
@open:
    jsr cell_ball_overlap
    bcc @claim
    jsr kill_a                 ; grew into a ball
    jmp halfB
@claim:
    jsr grid_get
    lda #CELL_GROWA
    sta (ptr0),y
    jsr cell_nt_addr
    lda #0
    sta t2
    ldx #1
    lda #TILE_RED
    jsr ppu_queue_run
    lda wa_head
    sec
    sbc #1
    sta wa_head

halfB:
    lda wb_state               ; ---- half B: down / right ----
    cmp #1
    bne finish
    lda wall_dir
    beq :+
    lda wb_head
    clc
    adc #1
    sta t0
    lda wall_oy
    sta t1
    jmp @probe
:   lda wall_ox
    sta t0
    lda wb_head
    clc
    adc #1
    sta t1
@probe:
    jsr grid_get
    and #$0F
    beq @open
    jsr anchor_b
    jmp finish
@open:
    jsr cell_ball_overlap
    bcc @claim
    jsr kill_b
    jmp finish
@claim:
    jsr grid_get
    lda #CELL_GROWB
    sta (ptr0),y
    jsr cell_nt_addr
    lda #0
    sta t2
    ldx #1
    lda #TILE_BLUE
    jsr ppu_queue_run
    lda wb_head
    clc
    adc #1
    sta wb_head
finish:
    rts
.endproc

; paint half A (head..origin) with cell value t5 / tile t6 + queue the
; redraw run; used by anchor (wall) and erase (blank).  Carry = queue result
.proc paint_half_a
    lda wall_dir
    bne @horiz
    lda wall_oy                ; vertical: rows wa_head..oy, col ox
    sec
    sbc wa_head
    clc
    adc #1
    sta t7                     ; count
    ldx t7
    lda wa_head
    sta t1
@vloop:
    lda wall_ox
    sta t0
    jsr grid_get
    lda t5
    sta (ptr0),y
    inc t1
    dex
    bne @vloop
    lda wall_ox
    sta t0
    lda wa_head
    sta t1
    jsr cell_nt_addr
    lda #$40
    sta t2
    ldx t7
    lda t6
    jmp ppu_queue_run
@horiz:
    lda wall_ox                ; horizontal: cols wa_head..ox, row oy
    sec
    sbc wa_head
    clc
    adc #1
    sta t7
    lda wa_head
    sta t0
    lda wall_oy
    sta t1
    jsr grid_get
    ldx t7
    lda t5
@hloop:
    sta (ptr0),y
    iny
    dex
    bne @hloop
    lda wa_head
    sta t0
    lda wall_oy
    sta t1
    jsr cell_nt_addr
    lda #0
    sta t2
    ldx t7
    lda t6
    jmp ppu_queue_run
.endproc

; same for half B: cells origin+1..head (may be zero cells -> no-op)
.proc paint_half_b
    lda wall_dir
    bne @horiz
    lda wb_head                ; vertical: rows oy+1..wb_head, col ox
    sec
    sbc wall_oy
    sta t7
    beq none
    ldx t7
    lda wall_oy
    clc
    adc #1
    sta t1
@vloop:
    lda wall_ox
    sta t0
    jsr grid_get
    lda t5
    sta (ptr0),y
    inc t1
    dex
    bne @vloop
    lda wall_ox
    sta t0
    lda wall_oy
    clc
    adc #1
    sta t1
    jsr cell_nt_addr
    lda #$40
    sta t2
    ldx t7
    lda t6
    jmp ppu_queue_run
@horiz:
    lda wb_head
    sec
    sbc wall_ox
    sta t7
    beq none
    lda wall_ox
    clc
    adc #1
    sta t0
    lda wall_oy
    sta t1
    jsr grid_get
    ldx t7
    lda t5
@hloop:
    sta (ptr0),y
    iny
    dex
    bne @hloop
    lda wall_ox
    clc
    adc #1
    sta t0
    lda wall_oy
    sta t1
    jsr cell_nt_addr
    lda #0
    sta t2
    ldx t7
    lda t6
    jmp ppu_queue_run
none:
    clc                        ; zero-cell half: a successful no-op
    rts
.endproc

.proc anchor_a
    lda #CELL_WALL
    sta t5
    lda #TILE_PANEL
    sta t6
    jsr paint_half_a
    lda #2
    sta wa_state
    lda filled_lo              ; walls count as cleared area
    clc
    adc t7
    sta filled_lo
    bcc :+
    inc filled_hi
:   jsr update_percent
    jsr check_win
    lda #1
    sta cap_req
    jsr sfx_anchor
    jmp wall_half_done
.endproc

.proc anchor_b
    lda #CELL_WALL
    sta t5
    lda #TILE_PANEL
    sta t6
    jsr paint_half_b
    lda #2
    sta wb_state
    lda t7
    beq @nocells               ; zero-length half can't seal anything
    lda filled_lo
    clc
    adc t7
    sta filled_lo
    bcc :+
    inc filled_hi
:   jsr update_percent
    jsr check_win
    lda #1
    sta cap_req
@nocells:
    jsr sfx_anchor
    jmp wall_half_done
.endproc

.proc kill_a
    lda #CELL_EMPTY
    sta t5
    lda #TILE_BLANK
    sta t6
    jsr paint_half_a
    lda #0
    sta wa_state
    jsr capture_poke
    jsr life_lost
    jmp wall_half_done
.endproc

.proc kill_b
    lda #CELL_EMPTY
    sta t5
    lda #TILE_BLANK
    sta t6
    jsr paint_half_b
    lda #0
    sta wb_state
    jsr capture_poke
    jsr life_lost
    jmp wall_half_done
.endproc

; erasing wall cells can un-mark territory a running capture sweep already
; visited; restart it so freed cells can't be falsely captured
.proc capture_poke
    lda cap_state
    beq :+
    lda #1
    sta cap_req
:   rts
.endproc

.proc wall_half_done
    lda wa_state
    cmp #1
    beq active
    lda wb_state
    cmp #1
    beq active
    lda #0
    sta wall_active
active:
    rts
.endproc

; --- timers / transitions ---------------------------------------------------

.proc time_update
    dec tick_cnt
    beq :+
    rts
:   lda #60
    sta tick_cnt
    inc play_sec_lo            ; unpaused play time for the recap (24-bit)
    bne :+
    inc play_sec_hi
    bne :+
    inc play_sec_ex
:   lda time_lo
    ora time_hi
    bne :+
    rts
:   lda time_lo
    bne :+
    dec time_hi
:   dec time_lo
    lda hud_flags
    ora #HUD_TIME
    sta hud_flags
    lda time_hi
    bne @done
    lda time_lo
    beq @timeout
    cmp #11
    bcs @done
    jsr sfx_tick
@done:
    rts
@timeout:
    lda #1
    sta gameover_pending
    rts
.endproc

.proc do_clear
    lda #0
    sta clear_pending
    jsr sfx_clear
    ; bonus = time * 10 + (percent - 75) * 100
    lda time_lo
    sta t0
    lda time_hi
    sta t1
    lda #10
    jsr mul16x8
    lda t2
    sta ptr1
    lda t3
    sta ptr1+1
    lda percent
    sec
    sbc #75
    bcc @nopct
    sta t0
    lda #0
    sta t1
    lda #100
    jsr mul16x8
    lda ptr1
    clc
    adc t2
    sta ptr1
    lda ptr1+1
    adc t3
    sta ptr1+1
@nopct:
    lda ptr1
    sta t0
    lda ptr1+1
    sta t1
    jsr score_add
    ; "LEVEL nn CLEAR!"
    lda #<str_clear
    sta ptr0
    lda #>str_clear
    sta ptr0+1
    ldx #15
    jsr str_to_buf
    jsr patch_level_digits
    lda #$21
    sta t0
    lda #$C8
    sta t1
    ldx #15
    jsr ppu_queue_lit
    ; "BONUS nnnnn"
    lda ptr1
    sta t0
    lda ptr1+1
    sta t1
    jsr bin16_to_digits
    lda #<str_bonus
    sta ptr0
    lda #>str_bonus
    sta ptr0+1
    ldx #11
    jsr str_to_buf
    ldx #4
:   lda DIGITS,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+6,x
    dex
    bpl :-
    lda #$22
    sta t0
    lda #$0A
    sta t1
    ldx #11
    jsr ppu_queue_lit
    ; per-level checkpoint: snapshot the running CRC (not displayed -- the
    ; verifier prints one per cleared level to localize replay divergence)
    lda crc0
    eor #$FF
    sta chk0
    lda crc1
    eor #$FF
    sta chk1
    lda crc2
    eor #$FF
    sta chk2
    lda crc3
    eor #$FF
    sta chk3
    lda #STATE_CLEAR
    sta game_state
    lda #CLEAR_TIME
    sta state_timer
    jmp draw_game_oam
.endproc

.proc clear_update
    jsr hud_update
    lda pad_new
    and #PAD_START
    bne @next
    dec state_timer
    bne @draw
@next:
    lda level
    cmp #99
    bcs :+
    inc level
:   lda #2
    sta init_request
@draw:
    jmp draw_game_oam
.endproc

; deferrable: gameover_pending stays set until the erases and both text
; writes fit a frame's budget; paint_half_* is idempotent so retries are safe
.proc go_gameover
    lda wa_state               ; erase any half still growing, retryable
    cmp #1
    bne :+
    lda #CELL_EMPTY
    sta t5
    lda #TILE_BLANK
    sta t6
    jsr paint_half_a
    bcs defer
    lda #0
    sta wa_state
    jsr capture_poke
:   lda wb_state
    cmp #1
    bne :+
    lda #CELL_EMPTY
    sta t5
    lda #TILE_BLANK
    sta t6
    jsr paint_half_b
    bcs defer
    lda #0
    sta wb_state
    jsr capture_poke
:   lda #0
    sta wall_active
    lda vram_budget            ; both lits cost 13 + 15
    cmp #30
    bcc defer
    lda #<str_gameover
    sta ptr0
    lda #>str_gameover
    sta ptr0+1
    lda #$21
    sta t0
    lda #$CB
    sta t1
    ldx #9
    jsr ppu_queue_lit
    lda #<str_pressstart
    sta ptr0
    lda #>str_pressstart
    sta ptr0+1
    lda #$22
    sta t0
    lda #$2A
    sta t1
    ldx #11
    jsr ppu_queue_lit
    lda #0
    sta gameover_pending
    jsr sfx_gameover
    lda #STATE_OVER
    sta game_state
    lda #180                   ; linger, then the run recap
    sta state_timer
defer:
    jmp draw_game_oam
.endproc

.proc over_update
    jsr balls_update           ; atoms keep bouncing behind the text
    jsr capture_step           ; finish any capture/wipe already in flight
    jsr wipe_update
    jsr hud_update
    lda pad_new
    and #PAD_START             ; Start skips ahead to the recap
    bne @recap
    dec state_timer
    bne @draw
@recap:
    lda #3
    sta init_request
@draw:
    jmp draw_game_oam
.endproc

; --- sprites ----------------------------------------------------------------

.proc oam_clear
    lda #$F0
    ldx #0
:   sta OAM,x
    inx
    inx
    inx
    inx
    bne :-
    rts
.endproc

.proc draw_game_oam
    jsr oam_clear
    ldx #0
    lda game_state
    cmp #STATE_PLAY
    beq @cursor
    cmp #STATE_SPLASH
    beq @cursor
    jmp balls_to_oam
@cursor:
    lda cursor_x
    clc
    adc #1
    asl
    asl
    asl
    sta t0                     ; pixel x
    lda cursor_y
    clc
    adc #4
    asl
    asl
    asl
    sta t1                     ; pixel y
    lda cursor_dir
    bne @horiz
    lda t1
    sec
    sbc #9                     ; up arrow above the cell (OAM y = y-1)
    sta OAM+0
    lda #SPR_ARROW_U
    sta OAM+1
    lda #1
    sta OAM+2
    lda t0
    sta OAM+3
    lda t1
    clc
    adc #7
    sta OAM+4
    lda #SPR_ARROW_D
    sta OAM+5
    lda #1
    sta OAM+6
    lda t0
    sta OAM+7
    jmp @balls
@horiz:
    lda t1
    sec
    sbc #1
    sta OAM+0
    sta OAM+4
    lda #SPR_ARROW_L
    sta OAM+1
    lda #SPR_ARROW_R
    sta OAM+5
    lda #1
    sta OAM+2
    sta OAM+6
    lda t0
    sec
    sbc #8
    sta OAM+3
    lda t0
    clc
    adc #8
    sta OAM+7
@balls:
    ldx #8                     ; OAM byte offset after 2 cursor sprites
    jmp balls_to_oam
.endproc
