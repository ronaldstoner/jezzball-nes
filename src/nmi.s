; NMI: OAM DMA + VRAM queue drain + palette/scroll, then sound (APU is safe
; past vblank).  With frame_ready clear, no PPU register is touched at all.
; Queue entry: ctl,addr_hi,addr_lo,payload; ctl 0=end, bit7=run (one payload
; byte written len times), bit6=vertical (+32 inc), bits5-0=len 1..47.

.proc nmi_handler
    pha
    txa
    pha
    tya
    pha

    lda frame_ready
    bne :+
    jmp done_gfx
:
    lda #0                     ; sprites
    sta OAMADDR
    lda #>OAM
    sta OAMDMA

    ldx #0                     ; drain queue
entry:
    lda PPUBUF,x
    beq drained
    sta nmi_t0                 ; ctl byte; bit6 -> PPUCTRL vertical inc
    and #$40
    beq :+
    lda #CTRL_VERT
:   ora #CTRL_BASE
    sta PPUCTRL
    inx
    lda PPUBUF,x
    sta PPUADDR
    inx
    lda PPUBUF,x
    sta PPUADDR
    inx
    lda nmi_t0
    and #$3F
    tay
    lda nmi_t0
    bmi run
lit:
    lda PPUBUF,x
    sta PPUDATA
    inx
    dey
    bne lit
    beq entry
run:
    lda PPUBUF,x
    inx
:   sta PPUDATA
    dey
    bne :-
    beq entry

drained:
    lda pal_dirty
    beq nopal
    lda #CTRL_BASE
    sta PPUCTRL
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldy #0
:   lda PAL_SHADOW,y
    sta PPUDATA
    iny
    cpy #32
    bne :-
    lda #0
    sta pal_dirty
nopal:
    lda #CTRL_BASE             ; restore scroll & mask
    sta PPUCTRL
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda soft_2001
    sta PPUMASK
    lda #0
    sta frame_ready
    sta PPUBUF

done_gfx:
    jsr sound_update
    inc nmi_count

    pla
    tay
    pla
    tax
    pla
    rti
.endproc
