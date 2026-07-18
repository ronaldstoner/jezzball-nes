; Title screen: RLE background, blinking PRESS START, three demo atoms
; bouncing behind the logo, and the title theme.

.proc title_init
    jsr sound_silence
    jsr render_off

    lda #<pal_title
    sta ptr0
    lda #>pal_title
    sta ptr0+1
    jsr load_palette

    lda #$20                   ; unpack nametable + attributes
    sta t0
    lda #$00
    sta t1
    jsr ppu_addr
    lda #<title_rle
    sta ptr0
    lda #>title_rle
    sta ptr0+1
@blk:
    ldy #0
    lda (ptr0),y
    beq @end
    tax
    iny
    lda (ptr0),y
:   sta PPUDATA
    dex
    bne :-
    lda ptr0
    clc
    adc #2
    sta ptr0
    bcc @blk
    inc ptr0+1
    jmp @blk
@end:

    lda #>TITLE_TOP_ADDR       ; session best score
    sta t0
    lda #<TITLE_TOP_ADDR
    sta t1
    jsr ppu_addr
    ldx #0
:   lda hi_digits,x
    ora #FONT_DIGIT_BASE
    sta PPUDATA
    inx
    cpx #9
    bne :-

    lda #3                     ; demo atoms
    sta ball_n
    lda #60
    sta ball_x+0
    lda #96
    sta ball_y+0
    lda #150
    sta ball_x+1
    lda #48
    sta ball_y+1
    lda #100
    sta ball_x+2
    lda #180
    sta ball_y+2
    lda #$01
    sta ball_dx+0
    sta ball_dy+0
    sta ball_dx+1
    sta ball_dy+2
    lda #$FF
    sta ball_dy+1
    sta ball_dx+2
    lda #0
    sta oam_rot
    sta blink_timer
    sta state_timer            ; start-press countdown idle

    jsr music_start
    lda #STATE_TITLE
    sta game_state
    jsr oam_clear              ; no stale sprites on the first frame
    jmp render_on
.endproc

.proc title_update
    inc blink_timer
    lda blink_timer
    and #$1F
    bne :+
    lda PAL_SHADOW+13          ; BG palette 3 color 1: PRESS START blink
    eor #$30^$0F
    sta PAL_SHADOW+13
    lda #1
    sta pal_dirty
:
    ldx #2                     ; bounce atoms inside the full screen
@ball:
    lda ball_x,x
    clc
    adc ball_dx,x
    sta ball_x,x
    cmp #9
    bcs :+
    lda #$01
    sta ball_dx,x
:   lda ball_x,x
    cmp #240
    bcc :+
    lda #$FF
    sta ball_dx,x
:   lda ball_y,x
    clc
    adc ball_dy,x
    sta ball_y,x
    cmp #25
    bcs :+
    lda #$01
    sta ball_dy,x
:   lda ball_y,x
    cmp #208
    bcc :+
    lda #$FF
    sta ball_dy,x
:   dex
    bpl @ball

    lda state_timer            ; started? let the confirm blip play out
    beq @input
    dec state_timer
    bne @draw
    lda #2
    sta init_request
    bne @draw
@input:
    lda pad_new
    and #PAD_START
    beq @draw
    jsr sfx_menu
    lda nmi_count              ; player timing is the entropy source
    eor rng_lo
    ora #$01
    sta rng_lo
    lda blink_timer
    eor #$5A
    sta rng_hi
    jsr run_begin              ; seed committed to the run code, stats zeroed
    ldx #8
    lda #0
:   sta score_digits,x
    dex
    bpl :-
    lda #1
    sta level
    lda #10                    ; frames before the level actually loads
    sta state_timer
@draw:
    jsr oam_clear
    ldx #0
    jmp balls_to_oam
.endproc
