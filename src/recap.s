; Run verification + recap screen.  CODE = CRC32 over the seed, every
; gameplay input frame, and the final stats; the game is deterministic from
; power-on, so tools/verify_run.py reproduces it from an input recording.
; Recap exits on Start with a fade to black before the title reloads.

; 24-bit t0..t2 / 60 -> quotient in t0..t2, remainder in t3 (shift-subtract)
.proc div24_60
    lda #0
    sta t3
    ldx #24
@l: asl t0
    rol t1
    rol t2
    rol t3
    lda t3
    cmp #60
    bcc :+
    sbc #60
    sta t3
    inc t0
:   dex
    bne @l
    rts
.endproc

; crc = (crc >> 8) ^ T[(crc ^ A) & $FF]   (state in crc0..3, LSB first)
.proc crc_update
    eor crc0
    tax
    lda crc1
    eor crc_t0,x
    sta crc0
    lda crc2
    eor crc_t1,x
    sta crc1
    lda crc3
    eor crc_t2,x
    sta crc2
    lda crc_t3,x
    sta crc3
    rts
.endproc

; start-of-run: crc = $FFFFFFFF folded with the seed; stats cleared
.proc run_begin
    lda #$FF
    sta crc0
    sta crc1
    sta crc2
    sta crc3
    lda rng_lo
    sta seed_lo
    jsr crc_update
    lda rng_hi
    sta seed_hi
    jsr crc_update
    lda #0
    sta stat_walls_lo
    sta stat_walls_hi
    sta stat_caps_lo
    sta stat_caps_hi
    sta stat_deaths
    sta play_sec_lo
    sta play_sec_hi
    sta play_sec_ex
    rts
.endproc

; ---- recap screen ----------------------------------------------------------

; patch two decimal digits of A at (ptr0)+Y, Y+1
.proc patch_dec2
    ldx #0
:   cmp #10
    bcc :+
    sbc #10
    inx
    bne :-
:   sta t6
    txa
    ora #FONT_DIGIT_BASE
    sta (ptr0),y
    iny
    lda t6
    ora #FONT_DIGIT_BASE
    sta (ptr0),y
    rts
.endproc

; patch byte A as two hex tiles at (ptr0)+Y, Y+1
.proc patch_hex2
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @tile
    sta (ptr0),y
    iny
    pla
    and #$0F
    jsr @tile
    sta (ptr0),y
    rts
@tile:
    cmp #10
    bcc :+
    sbc #10
    clc
    adc #FONT_ALPHA_BASE
    rts
:   ora #FONT_DIGIT_BASE
    rts
.endproc

; blank up to X leading zero tiles at STRBUF+Y (the last digit always stays)
.proc blank_lead
:   lda STRBUF,y
    cmp #FONT_DIGIT_BASE
    bne @done
    lda #TILE_BLANK
    sta STRBUF,y
    iny
    dex
    bne :-
@done:
    rts
.endproc

; fade every palette entry one brightness row darker (used on recap exit)
.proc fade_step
    ldx #31
:   lda PAL_SHADOW,x
    and #$F0
    beq @black
    lda PAL_SHADOW,x
    sec
    sbc #$10
    jmp @st
@black:
    lda #$0F
@st:
    sta PAL_SHADOW,x
    dex
    bpl :-
    lda #1
    sta pal_dirty
    rts
.endproc

; copy 16-byte template X=idx (ptr1 preserved) -> STRBUF, leave ptr0=STRBUF
.proc recap_tpl
    ldy #0
:   lda (ptr1),y
    sta STRBUF,y
    iny
    cpy #16
    bne :-
    lda #<STRBUF
    sta ptr0
    lda #>STRBUF
    sta ptr0+1
    rts
.endproc

; draw STRBUF (16 chars) at row A, col 8 (rendering off)
.proc recap_draw
    sta t2
    lda #0
    sta t0
    lda t2
    asl                        ; row * 32 + 8, +$2000
    asl
    asl
    rol t0
    asl
    rol t0
    asl
    rol t0
    clc
    adc #8
    sta t1
    lda t0
    adc #$20
    sta t0
    jsr ppu_addr
    ldx #16
    ldy #0
:   lda (ptr0),y
    sta PPUDATA
    iny
    dex
    bne :-
    rts
.endproc

.proc recap_init
    ; ---- bind the outcome into the code, then finalize a display copy ----
    lda level
    jsr crc_update
    ldx #0
:   lda score_digits,x
    stx t7
    jsr crc_update
    ldx t7
    inx
    cpx #9
    bne :-
    lda stat_walls_lo
    jsr crc_update
    lda stat_walls_hi
    jsr crc_update
    lda stat_caps_lo
    jsr crc_update
    lda stat_caps_hi
    jsr crc_update
    lda stat_deaths
    jsr crc_update

    jsr render_off
    lda #$20                   ; blank nametable, all-white-text attributes
    sta t0
    lda #$00
    sta t1
    jsr ppu_addr
    lda #TILE_BLANK
    ldx #240
    jsr ppu_fill
    ldx #240
    jsr ppu_fill
    ldx #240
    jsr ppu_fill
    ldx #240
    jsr ppu_fill
    lda #$AA                   ; palette 2 everywhere
    ldx #64
    jsr ppu_fill

    lda #<str_r_title          ; "* RUN RECAP *" centered on row 5
    sta ptr0
    lda #>str_r_title
    sta ptr0+1
    lda #$20
    sta t0
    lda #$A9                   ; row 5, col 9
    sta t1
    ldx #13
    jsr draw_text_direct

    lda #<str_r_score          ; SCORE
    sta ptr1
    lda #>str_r_score
    sta ptr1+1
    jsr recap_tpl
    ldx #0
:   lda score_digits,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+7,x
    inx
    cpx #9
    bne :-
    ldy #7
    ldx #8
    jsr blank_lead
    lda #8
    jsr recap_draw

    lda #<str_r_level          ; LEVEL
    sta ptr1
    lda #>str_r_level
    sta ptr1+1
    jsr recap_tpl
    ldy #14
    lda level
    jsr patch_dec2
    ldy #14
    ldx #1
    jsr blank_lead
    lda #10
    jsr recap_draw

    lda #<str_r_walls          ; WALLS (5 digits)
    sta ptr1
    lda #>str_r_walls
    sta ptr1+1
    jsr recap_tpl
    lda stat_walls_lo
    sta t0
    lda stat_walls_hi
    sta t1
    jsr bin16_to_digits
    ldx #4
:   lda DIGITS,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+11,x
    dex
    bpl :-
    ldy #11
    ldx #4
    jsr blank_lead
    lda #12
    jsr recap_draw

    lda #<str_r_caps           ; CAPTURES (5 digits)
    sta ptr1
    lda #>str_r_caps
    sta ptr1+1
    jsr recap_tpl
    lda stat_caps_lo
    sta t0
    lda stat_caps_hi
    sta t1
    jsr bin16_to_digits
    ldx #4
:   lda DIGITS,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+11,x
    dex
    bpl :-
    ldy #11
    ldx #4
    jsr blank_lead
    lda #14
    jsr recap_draw

    lda #<str_r_deaths         ; DEATHS (3 digits)
    sta ptr1
    lda #>str_r_deaths
    sta ptr1+1
    jsr recap_tpl
    lda stat_deaths
    sta t0
    lda #0
    sta t1
    jsr bin16_to_digits
    ldx #2
:   lda DIGITS+2,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+13,x
    dex
    bpl :-
    ldy #13
    ldx #2
    jsr blank_lead
    lda #16
    jsr recap_draw

    lda #<str_r_time           ; TIME MMMM:SS
    sta ptr1
    lda #>str_r_time
    sta ptr1+1
    jsr recap_tpl
    lda play_sec_lo            ; 24-bit seconds -> HHHH:MM:SS
    sta t0
    lda play_sec_hi
    sta t1
    lda play_sec_ex
    sta t2
    jsr div24_60               ; t0..t2 = minutes, t3 = seconds
    lda t3
    pha
    jsr div24_60               ; t0..t2 = hours (<= 4660), t3 = minutes
    lda t3
    pha
    jsr bin16_to_digits        ; hours from t0/t1
    ldx #3
:   lda DIGITS+1,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+6,x
    dex
    bpl :-
    ldy #6
    ldx #3
    jsr blank_lead
    pla                        ; minutes
    ldy #11
    jsr patch_dec2
    pla                        ; seconds
    ldy #14
    jsr patch_dec2
    lda #18
    jsr recap_draw

    lda #<str_r_seed           ; SEED (4 hex)
    sta ptr1
    lda #>str_r_seed
    sta ptr1+1
    jsr recap_tpl
    ldy #12
    lda seed_hi
    jsr patch_hex2
    iny
    lda seed_lo
    jsr patch_hex2
    lda #20
    jsr recap_draw

    lda #<str_r_code           ; CODE (8 hex) = crc ^ $FFFFFFFF, big-endian
    sta ptr1
    lda #>str_r_code
    sta ptr1+1
    jsr recap_tpl
    ldy #8
    lda crc3
    eor #$FF
    jsr patch_hex2
    iny
    lda crc2
    eor #$FF
    jsr patch_hex2
    iny
    lda crc1
    eor #$FF
    jsr patch_hex2
    iny
    lda crc0
    eor #$FF
    jsr patch_hex2
    lda #22
    jsr recap_draw

    lda #<str_pressstart
    sta ptr0
    lda #>str_pressstart
    sta ptr0+1
    lda #$23
    sta t0
    lda #$4A                   ; row 26, col 10
    sta t1
    ldx #11
    jsr draw_text_direct

    lda #STATE_RECAP
    sta game_state
    lda #0
    sta state_timer
    sta blink_timer            ; fade-out countdown idle
    jsr oam_clear
    jmp render_on
.endproc

.proc recap_update
    lda blink_timer            ; leaving: fade to black, then load the title
    beq @armed
    dec blink_timer
    beq @go
    lda blink_timer
    and #$07
    bne @wait
    jsr fade_step
@wait:
    rts
@go:
    lda #1
    sta init_request
    rts
@armed:
    lda pad_new
    and #PAD_START
    beq @done
    ldx #0                     ; keep session best score
@cmp:
    lda score_digits,x
    cmp hi_digits,x
    bcc @nostore
    bne @store
    inx
    cpx #9
    bne @cmp
    beq @nostore
@store:
    ldx #8
:   lda score_digits,x
    sta hi_digits,x
    dex
    bpl :-
@nostore:
    jsr sfx_menu
    lda #33                    ; 4 fade steps over ~half a second
    sta blink_timer
@done:
    rts
.endproc
