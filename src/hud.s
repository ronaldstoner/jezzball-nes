; HUD: LEVEL/LIVES/TIME on row 2, SCORE/CLEAR% on row 3.  Fields redraw
; lazily via hud_flags; one that misses the VRAM budget retries next frame.

; t0/t1 (lo/hi) -> DIGITS[0..4], most significant first.  Clobbers t0/t1.
.proc bin16_to_digits
    ldx #0
@pow:
    lda #0
    sta DIGITS,x
@sub:
    lda t1
    cmp pow10_hi,x
    bcc @nextpow
    bne @dosub
    lda t0
    cmp pow10_lo,x
    bcc @nextpow
@dosub:
    lda t0
    sec
    sbc pow10_lo,x
    sta t0
    lda t1
    sbc pow10_hi,x
    sta t1
    inc DIGITS,x
    jmp @sub
@nextpow:
    inx
    cpx #4
    bne @pow
    lda t0
    sta DIGITS+4
    rts
.endproc

; score += 16-bit binary in t0/t1 (9-digit decimal array, clamps at
; 999,999,999 -- saturation, never rollover)
.proc score_add
    jsr bin16_to_digits
    lda #0
    sta t6                     ; carry between digits
    ldx #4
@add:
    lda score_digits+4,x       ; DIGITS[0..4] align with digits 4..8
    clc
    adc DIGITS,x
    clc
    adc t6
    ldy #0
    cmp #10
    bcc :+
    sec
    sbc #10
    ldy #1
:   sta score_digits+4,x
    sty t6
    dex
    bpl @add
    ldx #3                     ; ripple any carry through digits 3..0
@carry:
    lda t6
    beq @flag
    lda score_digits,x
    clc
    adc t6
    ldy #0
    cmp #10
    bcc :+
    sec
    sbc #10
    ldy #1
:   sta score_digits,x
    sty t6
    dex
    bpl @carry
    lda t6
    beq @flag
    ldx #8                     ; clamp at 999,999,999
    lda #9
:   sta score_digits,x
    dex
    bpl :-
@flag:
    lda hud_flags
    ora #HUD_SCORE
    sta hud_flags
    rts
.endproc

.proc hud_update
    lda hud_flags
    bne :+
    rts

:   and #HUD_LEVEL
    beq f_lives
    lda #<str_h_level
    sta ptr0
    lda #>str_h_level
    sta ptr0+1
    ldx #8
    jsr str_to_buf
    jsr patch_level_digits
    lda #$20
    sta t0
    lda #$41
    sta t1
    ldx #8
    jsr ppu_queue_lit
    bcc :+
    jmp done
:   lda hud_flags
    and #$FF^HUD_LEVEL
    sta hud_flags

f_lives:
    lda hud_flags
    and #HUD_LIVES
    beq f_time
    lda #<str_h_lives
    sta ptr0
    lda #>str_h_lives
    sta ptr0+1
    ldx #7
    jsr str_to_buf
    lda lives
    ora #FONT_DIGIT_BASE
    sta STRBUF+6
    lda #$20
    sta t0
    lda #$4B
    sta t1
    ldx #7
    jsr ppu_queue_lit
    bcc :+
    jmp done
:   lda hud_flags
    and #$FF^HUD_LIVES
    sta hud_flags

f_time:
    lda hud_flags
    and #HUD_TIME
    beq f_score
    lda #<str_h_time
    sta ptr0
    lda #>str_h_time
    sta ptr0+1
    ldx #8
    jsr str_to_buf
    lda time_lo
    sta t0
    lda time_hi
    sta t1
    jsr bin16_to_digits
    ldx #2
:   lda DIGITS+2,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+5,x
    dex
    bpl :-
    lda #$20
    sta t0
    lda #$54
    sta t1
    ldx #8
    jsr ppu_queue_lit
    bcc :+
    jmp done
:   lda hud_flags
    and #$FF^HUD_TIME
    sta hud_flags

f_score:
    lda hud_flags
    and #HUD_SCORE
    beq f_pct
    lda #<str_h_score
    sta ptr0
    lda #>str_h_score
    sta ptr0+1
    ldx #15
    jsr str_to_buf
    ldx #8
:   lda score_digits,x
    ora #FONT_DIGIT_BASE
    sta STRBUF+6,x
    dex
    bpl :-
    lda #$20
    sta t0
    lda #$61
    sta t1
    ldx #15
    jsr ppu_queue_lit
    bcs done
    lda hud_flags
    and #$FF^HUD_SCORE
    sta hud_flags

f_pct:
    lda hud_flags
    and #HUD_PCT
    beq done
    lda #<str_h_pct
    sta ptr0
    lda #>str_h_pct
    sta ptr0+1
    ldx #10
    jsr str_to_buf
    lda percent
    cmp #100
    bcc @under
    lda #FONT_DIGIT_BASE+1
    sta STRBUF+6
    lda #FONT_DIGIT_BASE
    sta STRBUF+7
    sta STRBUF+8
    jmp @queue
@under:
    ldx #0
:   cmp #10
    bcc :+
    sbc #10
    inx
    bne :-
:   ora #FONT_DIGIT_BASE       ; ones digit
    sta STRBUF+8
    txa
    beq @queue                 ; blank leading tens
    ora #FONT_DIGIT_BASE
    sta STRBUF+7
@queue:
    lda #$20
    sta t0
    lda #$74
    sta t1
    ldx #10
    jsr ppu_queue_lit
    bcs done
    lda hud_flags
    and #$FF^HUD_PCT
    sta hud_flags
done:
    rts
.endproc
