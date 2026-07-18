; reset, main loop, controller reading, RNG.

.proc reset
    sei
    cld
    ldx #$40
    stx $4017                  ; frame counter: 4-step, IRQ off
    ldx #$FF
    txs
    inx
    stx PPUCTRL                ; NMI off during warmup
    stx PPUMASK
    stx $4010
    bit PPUSTATUS
:   bit PPUSTATUS              ; first vblank
    bpl :-

    lda #0                     ; clear all RAM
    tax
:   sta $0000,x
    sta $0100,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne :-
    lda #$F0                   ; park all sprites offscreen
:   sta OAM,x
    inx
    bne :-

:   bit PPUSTATUS              ; second vblank: PPU is warm
    bpl :-

    lda #$0F                   ; APU: enable pulse1/2, triangle, noise
    sta $4015
    lda #$08                   ; sweep negate trick: low notes not muted
    sta $4001
    sta $4005
    lda #$30
    sta $4000
    sta $4004
    sta $400C
    lda #$80
    sta $4008

    lda #$C3                   ; RNG seed (re-seeded on title start press)
    sta rng_lo
    lda #$A5
    sta rng_hi

    lda #CTRL_BASE             ; NMI on from here; render still off
    sta PPUCTRL
    lda #1
    sta init_request           ; boot into the title screen
    ; fall through into the main loop
.endproc

.proc main_loop
forever:
    lda init_request
    beq @run
    cmp #1
    bne @lvl
    lda #0
    sta init_request
    jsr title_init
    jmp forever
@lvl:
    cmp #2
    bne @rcp
    lda #0
    sta init_request
    jsr level_init
    jmp forever
@rcp:
    lda #0
    sta init_request
    jsr recap_init
    jmp forever
@run:
    jsr build_frame
    lda #1
    sta frame_ready
    jsr wait_frame
    jmp forever
.endproc

; one game frame: reset queue, poll input, run the current state
.proc build_frame
    lda #0
    sta buf_idx
    sta PPUBUF                 ; empty, terminated queue
    lda #VRAM_BUDGET
    sta vram_budget
    jsr read_pad

    lda game_state                 ; bind every interactive input frame
    cmp #STATE_SPLASH              ; (splash/play/clear) into the run code
    bcc :+
    cmp #STATE_OVER
    bcs :+
    lda pad
    jsr crc_update
:
    lda game_state
    cmp #STATE_TITLE
    bne :+
    jmp title_update
:   cmp #STATE_SPLASH
    bne :+
    jmp splash_update
:   cmp #STATE_PLAY
    bne :+
    jmp play_update
:   cmp #STATE_CLEAR
    bne :+
    jmp clear_update
:   cmp #STATE_OVER
    bne :+
    jmp over_update
:   jmp recap_update
.endproc

.proc wait_frame
    lda nmi_count
:   cmp nmi_count
    beq :-
    rts
.endproc

.proc read_pad
    lda pad
    sta pad_prev
    lda #1
    sta $4016
    lda #0
    sta $4016
    ldx #8
:   lda $4016
    lsr
    rol pad
    dex
    bne :-
    lda pad_prev
    eor #$FF
    and pad
    sta pad_new
    rts
.endproc

; 8 steps of a Galois 16-bit LFSR (taps $B400); returns A = rng_lo.
; Preserves X (callers keep loop indices there).
.proc rand8
    ldy #8
:   lsr rng_hi
    ror rng_lo
    bcc :+
    lda rng_hi
    eor #$B4
    sta rng_hi
:   dey
    bne :--
    lda rng_lo
    rts
.endproc

irq_handler:
    rti
