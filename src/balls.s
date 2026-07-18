; Atoms: 8x8 sprites at 1px/frame diagonals, per-axis move + bounce (1px
; steps make tunneling impossible).  Solid cells bounce the atom; touching a
; growing wall half kills that half (life lost) and the atom rolls on.

; t0 = pixel x, t1 = pixel y -> A = raw grid cell under that pixel
.proc cell_at_px
    lda t1
    lsr
    lsr
    lsr
    sec
    sbc #4                     ; tile row - 4 = grid row
    tay
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    lda t0
    lsr
    lsr
    lsr
    sec
    sbc #1                     ; tile col - 1 = grid col
    tay
    lda (ptr0),y
    rts
.endproc

; probe one cell for ball X: A = raw cell -> ball_blk = 1 (solid) / kills the
; wall half on growing cells.  Preserves X via stack around the kill path.
.proc probe_cell
    and #$0F
    beq done
    cmp #CELL_GROWA
    beq hit_a
    cmp #CELL_GROWB
    beq hit_b
    lda #1                     ; wall or captured: solid
    sta ball_blk
done:
    rts
hit_a:
    lda wa_state
    cmp #1
    bne done                   ; already resolved this frame
    txa
    pha
    jsr kill_a
    pla
    tax
    rts
hit_b:
    lda wb_state
    cmp #1
    bne done
    txa
    pha
    jsr kill_b
    pla
    tax
    rts
.endproc

.proc balls_update
    ldx ball_n
    dex
loop:
    ; ---- X axis ----
    lda ball_x,x
    clc
    adc ball_dx,x
    sta ball_nx                ; candidate x (survives kill paths)
    lda ball_dx,x
    bmi @lft
    lda ball_nx
    clc
    adc #7                     ; moving right: probe right edge
    bne @edge
@lft:
    lda ball_nx
@edge:
    sta ball_edge
    lda #0
    sta ball_blk
    lda ball_edge
    sta t0
    lda ball_y,x
    sta t1
    jsr cell_at_px
    jsr probe_cell
    lda ball_edge
    sta t0
    lda ball_y,x
    clc
    adc #7
    sta t1
    jsr cell_at_px
    jsr probe_cell
    lda ball_blk
    beq @movex
    lda ball_dx,x              ; bounce
    eor #$FE
    sta ball_dx,x
    jmp @yaxis
@movex:
    lda ball_nx
    sta ball_x,x

@yaxis:
    lda ball_y,x
    clc
    adc ball_dy,x
    sta ball_nx
    lda ball_dy,x
    bmi @up
    lda ball_nx
    clc
    adc #7
    bne @yedge
@up:
    lda ball_nx
@yedge:
    sta ball_edge
    lda #0
    sta ball_blk
    lda ball_x,x
    sta t0
    lda ball_edge
    sta t1
    jsr cell_at_px
    jsr probe_cell
    lda ball_x,x
    clc
    adc #7
    sta t0
    lda ball_edge
    sta t1
    jsr cell_at_px
    jsr probe_cell
    lda ball_blk
    beq @movey
    lda ball_dy,x
    eor #$FE
    sta ball_dy,x
    jmp @next
@movey:
    lda ball_nx
    sta ball_y,x

@next:
    dex
    bmi pairs
    jmp loop

; ---- ball vs ball: on overlap swap velocities along approaching axes ----
pairs:
    lda ball_n
    cmp #2
    bcs :+
    rts
:   ldx ball_n
    dex
outer:
    txa
    tay
    dey
inner:
    ; |xi - xj| < 8 ?
    lda ball_x,x
    sec
    sbc ball_x,y
    bcs :+
    eor #$FF
    adc #1
:   cmp #8
    bcs @skip
    lda ball_y,x
    sec
    sbc ball_y,y
    bcs :+
    eor #$FF
    adc #1
:   cmp #8
    bcs @skip
    ; overlap: X axis approaching?
    lda ball_x,x
    cmp ball_x,y
    beq @yax                   ; same column: only y matters
    bcc @x_ilow
    ; xj < xi: approaching iff dxj=+1 and dxi=-1
    lda ball_dx,y
    cmp #$01
    bne @yax
    lda ball_dx,x
    cmp #$FF
    bne @yax
    beq @swapx
@x_ilow:
    lda ball_dx,x
    cmp #$01
    bne @yax
    lda ball_dx,y
    cmp #$FF
    bne @yax
@swapx:
    lda ball_dx,x
    pha
    lda ball_dx,y
    sta ball_dx,x
    pla
    sta ball_dx,y
@yax:
    lda ball_y,x
    cmp ball_y,y
    beq @skip
    bcc @y_ilow
    lda ball_dy,y
    cmp #$01
    bne @skip
    lda ball_dy,x
    cmp #$FF
    bne @skip
    beq @swapy
@y_ilow:
    lda ball_dy,x
    cmp #$01
    bne @skip
    lda ball_dy,y
    cmp #$FF
    bne @skip
@swapy:
    lda ball_dy,x
    pha
    lda ball_dy,y
    sta ball_dy,x
    pla
    sta ball_dy,y
@skip:
    dey
    bmi :+
    jmp inner
:   dex
    beq done
    jmp outer
done:
    rts
.endproc

; append ball sprites to OAM starting at byte offset X; slot order rotates
; each frame so scanline-overflow flicker is shared fairly
.proc balls_to_oam
    stx t0                     ; OAM write offset
    inc oam_rot
    lda oam_rot
    cmp ball_n
    bcc :+
    lda #0
    sta oam_rot
:   lda nmi_count              ; 8-phase spin: 4 CHR frames x H+V flip.
    lsr                        ; Spin follows travel: moving right rolls
    lsr                        ; clockwise, moving left counter-clockwise.
    and #$07
    sta t1                     ; clockwise phase
    lda #0
    sec
    sbc t1
    and #$07
    sta t3                     ; counter-clockwise phase
    lda #0
    sta t2                     ; balls emitted
    lda oam_rot
    tay                        ; Y = rotating ball index
next:
    lda t2
    cmp ball_n
    bcs done
    ldx t0
    lda ball_y,y
    sec
    sbc #1
    sta OAM,x
    inx
    lda ball_dx,y
    bmi :+
    lda t1                     ; rightward: clockwise
    bpl :++
:   lda t3                     ; leftward: counter-clockwise
:   cmp #4
    bcc :+
    and #$03                   ; phases 4-7: same tile, 180 deg via flips
    sta OAM,x
    inx
    lda #$C0                   ; H+V flip, palette 0, front
    bne :++
:   sta OAM,x
    inx
    lda #$00                   ; palette 0, front priority
:   sta OAM,x
    inx
    lda ball_x,y
    sta OAM,x
    inx
    stx t0
    iny
    cpy ball_n
    bcc :+
    ldy #0
:   inc t2
    bne next
done:
    rts
.endproc
