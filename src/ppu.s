; VRAM write-queue appends (main thread) + direct helpers for init screens.

; Run entry: A=tile, X=len 1..47, t0/t1=addr hi/lo, t2=0 horiz/$40 vert.
; Carry set if it didn't fit (caller retries next frame); clobbers registers.
.proc ppu_queue_run
    sta t3
    txa
    clc
    adc #4                     ; entry overhead: PPUADDR setup in the NMI
    cmp vram_budget
    beq :+
    bcs fail
:   sta t4
    lda buf_idx
    clc
    adc #5                     ; ctl+hi+lo+val+terminator
    cmp #BUF_SIZE
    bcs fail
    lda vram_budget
    sec
    sbc t4
    sta vram_budget
    ldy buf_idx
    txa
    ora #$80
    ora t2
    sta PPUBUF,y
    iny
    lda t0
    sta PPUBUF,y
    iny
    lda t1
    sta PPUBUF,y
    iny
    lda t3
    sta PPUBUF,y
    iny
    lda #0
    sta PPUBUF,y
    sty buf_idx
    clc
    rts
fail:
    sec
    rts
.endproc

; Append a literal entry.  ptr0 = source, X = len (1..47), t0/t1 = addr.
; Carry set on failure.
.proc ppu_queue_lit
    txa
    clc
    adc #4                     ; entry overhead: PPUADDR setup in the NMI
    cmp vram_budget
    beq :+
    bcs fail
:   sta t6
    stx t4
    lda buf_idx
    sec                        ; +1 ctl +2 addr +1 terminator = len+4
    adc t4
    clc
    adc #3
    cmp #BUF_SIZE
    bcs fail
    lda vram_budget
    sec
    sbc t6
    sta vram_budget
    ldy buf_idx
    txa
    and #$3F
    sta PPUBUF,y
    iny
    lda t0
    sta PPUBUF,y
    iny
    lda t1
    sta PPUBUF,y
    iny
    sty t5                     ; dest index
    ldy #0
:   lda (ptr0),y
    ldx t5
    sta PPUBUF,x
    inc t5
    iny
    cpy t4
    bne :-
    ldx t5
    lda #0
    sta PPUBUF,x
    stx buf_idx
    clc
    rts
fail:
    sec
    rts
.endproc

; Render-off protocol: NMI ignores the PPU while frame_ready=0, so after one
; synced frame with PPUMASK=0 the main thread may write the PPU freely.

.proc render_off
    lda #0
    sta soft_2001
    sta PPUBUF
    lda #1
    sta frame_ready
    jmp wait_frame
.endproc

.proc render_on
    lda #%00011110             ; BG + sprites, no clipping
    sta soft_2001
    lda #0
    sta PPUBUF
    sta buf_idx
    lda #1
    sta frame_ready
    jmp wait_frame
.endproc

; direct helpers, rendering off only ----------------------------------------

; set PPUADDR from t0/t1
.proc ppu_addr
    bit PPUSTATUS
    lda t0
    sta PPUADDR
    lda t1
    sta PPUADDR
    rts
.endproc

; write A to PPUDATA X times (X >= 1)
.proc ppu_fill
:   sta PPUDATA
    dex
    bne :-
    rts
.endproc

; copy 32-byte palette from pal_src (ptr0) into shadow and mark dirty;
; while rendering is off, also push it immediately.
.proc load_palette
    ldy #0
:   lda (ptr0),y
    sta PAL_SHADOW,y
    iny
    cpy #32
    bne :-
    lda #1
    sta pal_dirty
    rts
.endproc

; draw length-X string at ptr0 to nametable addr t0/t1 (render off, direct)
.proc draw_text_direct
    jsr ppu_addr
    ldy #0
:   lda (ptr0),y
    sta PPUDATA
    iny
    dex
    bne :-
    rts
.endproc
