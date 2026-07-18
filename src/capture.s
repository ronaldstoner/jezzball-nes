; Capture engine: alternating raster sweeps spread reachability marks from
; atom seed cells (fwd: left/up, bwd: right/down); two quiet passes means
; converged, and unmarked empty cells become captured.  Budgeted per frame
; so gameplay never hitches; a new anchor restarts the sweep (cap_req).

.proc capture_step
    lda cap_req
    beq :+
    lda #0                     ; note: cap_cnt survives a restart -- cells a
    sta cap_req                ; mid-finalize pass already captured get scored
    lda #1                     ; when the restarted sweep completes
    sta cap_state
    sta cap_row
:   lda cap_state
    bne :+
    rts
:   cmp #1
    beq clear_marks
    cmp #2
    beq sweep
    cmp #3
    beq jfin
    jmp settle                 ; state 4: scoring on its own (light) frame
jfin:
    jmp finalize

; ---- state 1: strip bit7 from the whole interior, SWEEP_ROWS rows/frame ----
clear_marks:
    lda sweep_rows
    sta t7
@row:
    ldy cap_row
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    ldy #INT_XMAX
@cell:
    lda (ptr0),y
    and #$7F
    sta (ptr0),y
    dey
    bne @cell
    inc cap_row
    lda cap_row
    cmp #INT_YMAX+1
    beq @done
    dec t7
    bne @row
    rts
@done:
    lda #2                     ; begin sweeping
    sta cap_state
    lda #0
    sta cap_dir
    sta cap_changed
    sta cap_quiet
    lda #INT_YMIN
    sta cap_row
    jmp mark_balls

; ---- state 2: one budget's worth of sweep rows -----------------------------
sweep:
    lda sweep_rows
    sta t7
@row:
    lda cap_dir
    bne @bwd
    jsr sweep_row_fwd
    inc cap_row
    lda cap_row
    cmp #INT_YMAX+1
    beq pass_end
    bne @cont
@bwd:
    jsr sweep_row_bwd
    dec cap_row
    beq pass_end
@cont:
    dec t7
    bne @row
    rts

pass_end:
    lda cap_changed
    bne @busy
    inc cap_quiet
    lda cap_quiet
    cmp #2
    bcc @flip
    lda #3                     ; converged: fill unmarked empties
    sta cap_state
    lda #INT_YMIN
    sta cap_row
    rts
@busy:
    lda #0
    sta cap_quiet
@flip:
    lda #0
    sta cap_changed
    lda cap_dir
    eor #1
    sta cap_dir
    bne @setbwd
    lda #INT_YMIN
    sta cap_row
    jmp mark_balls
@setbwd:
    lda #INT_YMAX
    sta cap_row
    jmp mark_balls

; ---- state 3: unmarked empty cells become captured, marks are stripped -----
finalize:
    lda sweep_rows
    sta t7
@row:
    ldy cap_row
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    ldy #INT_XMAX
@cell:
    lda (ptr0),y
    bmi @marked
    and #$0F
    bne @next                  ; occupied cell stays
    lda #CELL_CAP|DIRTY_BIT    ; sealed: capture it
    sta (ptr0),y
    inc cap_cnt_lo
    bne :+
    inc cap_cnt_hi
:   inc dirty_lo
    bne :+
    inc dirty_hi
:   inc filled_lo
    bne @next
    inc filled_hi
    bne @next
@marked:
    and #$7F
    sta (ptr0),y
@next:
    dey
    bne @cell
    inc cap_row
    lda cap_row
    cmp #INT_YMAX+1
    beq @done
    dec t7
    bne @row
    rts
@done:
    lda #4                     ; rows done; score next frame (the completion
    sta cap_state              ; frame already carries wipe + finalize work)
    rts

; ---- state 4: award the capture -------------------------------------------
settle:
    lda #0
    sta cap_state
    lda cap_cnt_lo
    ora cap_cnt_hi
    bne :+
    rts                        ; both sides still have balls: nothing sealed
:   jsr sfx_capture
    lda stat_caps_lo           ; saturating count
    and stat_caps_hi
    cmp #$FF
    beq :+
    inc stat_caps_lo
    bne :+
    inc stat_caps_hi
:   lda #1                     ; wipe animates top-down
    sta wipe_row
    lda cap_cnt_lo             ; score += captured cells * level
    sta t0
    lda cap_cnt_hi
    sta t1
    lda #0
    sta cap_cnt_lo
    sta cap_cnt_hi
    lda level
    jsr mul16x8
    lda t2
    sta t0
    lda t3
    sta t1
    jsr score_add
    jsr update_percent
    jmp check_win

; one forward sweep row: marks spread from left/up.  cap_row is the row.
sweep_row_fwd:
    ldy cap_row
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    dey
    lda grid_row_lo,y
    sta ptr1
    lda grid_row_hi,y
    sta ptr1+1                 ; ptr1 = row above
    ldy #INT_XMIN
@cell:
    lda (ptr0),y
    bmi @next                  ; already marked
    and #$0F
    beq @open
    cmp #CELL_GROWA
    bcc @next                  ; wall/captured: impassable
@open:
    lda (ptr1),y               ; up neighbor marked?
    bmi @mark
    dey
    lda (ptr0),y               ; left neighbor marked?
    iny
    tax                        ; iny trashed flags; refresh from A
    bmi @mark
    bpl @next
@mark:
    lda (ptr0),y
    ora #MARK_BIT
    sta (ptr0),y
    lda #1
    sta cap_changed
@next:
    iny
    cpy #INT_XMAX+1
    bne @cell
    rts

; one backward sweep row: marks spread from right/down
sweep_row_bwd:
    ldy cap_row
    lda grid_row_lo,y
    sta ptr0
    lda grid_row_hi,y
    sta ptr0+1
    iny
    lda grid_row_lo,y
    sta ptr1
    lda grid_row_hi,y
    sta ptr1+1                 ; ptr1 = row below
    ldy #INT_XMAX
@cell:
    lda (ptr0),y
    bmi @next
    and #$0F
    beq @open
    cmp #CELL_GROWA
    bcc @next
@open:
    lda (ptr1),y               ; down neighbor marked?
    bmi @mark
    iny
    lda (ptr0),y               ; right neighbor marked?
    dey
    tax
    bmi @mark
    bpl @next
@mark:
    lda (ptr0),y
    ora #MARK_BIT
    sta (ptr0),y
    lda #1
    sta cap_changed
@next:
    dey
    bne @cell
    rts

; seed marks: the four corner cells under every ball
mark_balls:
    ldx ball_n
    dex
@ball:
    lda ball_x,x
    sta t0
    lda ball_y,x
    sta t1
    jsr mark_px
    lda ball_x,x
    clc
    adc #7
    sta t0
    jsr mark_px
    lda ball_y,x
    clc
    adc #7
    sta t1
    jsr mark_px
    lda ball_x,x
    sta t0
    jsr mark_px
    dex
    bpl @ball
    rts

mark_px:
    jsr cell_at_px             ; leaves ptr0 = row, Y = col
    bmi @done                  ; already marked: no change
    and #$0F
    beq @ok
    cmp #CELL_GROWA
    bcc @done                  ; solid cells are never seeds
@ok:
    lda (ptr0),y
    ora #MARK_BIT
    sta (ptr0),y
    lda #1
    sta cap_changed
@done:
    rts
.endproc

; Wipe drawer: stream DIRTY cells to the nametable as horizontal runs,
; top-down, within whatever VRAM budget is left this frame.
.proc wipe_update
    lda dirty_lo
    ora dirty_hi
    bne :+
    rts
:   lda #INT_YMAX              ; at most one full lap over the field
    sta t7
wrow:
    ldy wipe_row
    lda grid_row_lo,y
    sta ptr1
    lda grid_row_hi,y
    sta ptr1+1
    ldy #INT_XMIN
wscan:
    lda (ptr1),y
    and #DIRTY_BIT
    bne wrun
wcont:
    iny
    cpy #INT_XMAX+1
    bne wscan
    ; row finished: advance (wrap) and maybe keep going
    lda wipe_row
    cmp #INT_YMAX
    bcc :+
    lda #0
:   clc
    adc #1
    sta wipe_row
    lda dirty_lo
    ora dirty_hi
    beq done
    dec t7
    bne wrow
done:
    rts

wrun:
    sty t5                     ; run start col
    lda (ptr1),y
    and #$0F
    sta t6                     ; run cell type
wext:
    iny
    cpy #INT_XMAX+1
    beq wflush
    lda (ptr1),y
    and #DIRTY_BIT
    beq wflush
    lda (ptr1),y
    and #$0F
    cmp t6
    beq wext
wflush:
    sty wipe_end               ; run end col, exclusive (t3/t4 die in queue)
    ; queue it: addr from (wipe_row, t5), len, tile by type
    lda wipe_row
    sta t1
    lda t5
    sta t0
    jsr cell_nt_addr
    lda #0
    sta t2
    lda wipe_end
    sec
    sbc t5
    tax
    ldy t6
    lda tile_for_type,y
    jsr ppu_queue_run
    bcs done                   ; no room this frame: resume next frame
    ; success: clear DIRTY bits and account for them
    ldy t5
wclr:
    lda (ptr1),y
    and #$FF^DIRTY_BIT
    sta (ptr1),y
    lda dirty_lo
    bne :+
    dec dirty_hi
:   dec dirty_lo
    iny
    cpy wipe_end
    bne wclr
    cpy #INT_XMAX+1
    beq wrowend
    jmp wscan
wrowend:
    jmp wcont
.endproc
