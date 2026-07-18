; Title music (pulse1 lead w/ envelope+tremolo+vibrato, triangle bass,
; pulse2 echo and noise hats that yield to sfx) + sfx streams.  Runs in NMI:
; nmi_t0 is the only scratch, never t0-t7.  Streams: sfx [dur,note,vol]
; triples (0=end); music [note,dur] pairs ($FF=loop, 0=rest); hats 1B/8th.

.proc sound_silence
    lda #0
    sta mus_on
    sta sfx_p_ptr+1
    sta sfx_n_ptr+1
    lda #$30
    sta $4000
    sta $4004
    sta $400C
    lda #$80
    sta $4008
    rts
.endproc

.proc music_start
    lda #0
    sta mus_on                 ; keep NMI out while pointers change
    lda #<music_melody
    sta mus_mel_ptr
    lda #>music_melody
    sta mus_mel_ptr+1
    lda #<music_bass
    sta mus_bas_ptr
    lda #>music_bass
    sta mus_bas_ptr+1
    lda #<music_echo
    sta mus_echo_ptr
    lda #>music_echo
    sta mus_echo_ptr+1
    lda #<music_hats
    sta mus_hat_ptr
    lda #>music_hats
    sta mus_hat_ptr+1
    lda #1
    sta mus_mel_tmr
    sta mus_bas_tmr
    sta mus_echo_tmr
    sta mus_hat_tmr
    lda #$FF
    sta mus_p1_bhi             ; melody silent until the first note
    sta mus_p1_lhi
    lda #0
    sta mus_p1_frame
    lda #1
    sta mus_on
    rts
.endproc

; start a pulse2 sfx stream at A(lo)/X(hi); NMI-safe ordering
.proc sfx_play_p
    ldy #0
    sty sfx_p_ptr+1
    sta sfx_p_ptr
    lda #1
    sta sfx_p_tmr
    stx sfx_p_ptr+1
    rts
.endproc

.proc sfx_play_n
    ldy #0
    sty sfx_n_ptr+1
    sta sfx_n_ptr
    lda #1
    sta sfx_n_tmr
    stx sfx_n_ptr+1
    rts
.endproc

; --- triggers ---------------------------------------------------------------

.proc sfx_wall_start
    lda #<sfx_d_start
    ldx #>sfx_d_start
    jmp sfx_play_p
.endproc

.proc sfx_blip
    lda #<sfx_d_blip
    ldx #>sfx_d_blip
    jmp sfx_play_p
.endproc

.proc sfx_anchor
    lda #<sfx_d_anchor
    ldx #>sfx_d_anchor
    jsr sfx_play_p
    lda #<sfx_d_anchor_n
    ldx #>sfx_d_anchor_n
    jmp sfx_play_n
.endproc

.proc sfx_death
    lda #<sfx_d_death
    ldx #>sfx_d_death
    jsr sfx_play_p
    lda #<sfx_d_death_n
    ldx #>sfx_d_death_n
    jmp sfx_play_n
.endproc

.proc sfx_capture
    lda #<sfx_d_capture
    ldx #>sfx_d_capture
    jmp sfx_play_p
.endproc

.proc sfx_clear
    lda #<sfx_d_clear
    ldx #>sfx_d_clear
    jmp sfx_play_p
.endproc

.proc sfx_gameover
    lda #<sfx_d_over
    ldx #>sfx_d_over
    jmp sfx_play_p
.endproc

.proc sfx_menu
    lda #<sfx_d_menu
    ldx #>sfx_d_menu
    jmp sfx_play_p
.endproc

.proc sfx_pause
    lda #<sfx_d_pause
    ldx #>sfx_d_pause
    jmp sfx_play_p
.endproc

.proc sfx_tick
    lda #<sfx_d_tick_n
    ldx #>sfx_d_tick_n
    jmp sfx_play_n
.endproc

; --- NMI driver -------------------------------------------------------------

.proc sound_update
    lda mus_on
    bne music
    jmp sfx
music:
    dec mus_mel_tmr            ; ---- melody stream / pulse 1 ----
    bne express
@next:
    ldy #0
    lda (mus_mel_ptr),y
    cmp #$FF
    bne @ev
    lda #<music_melody
    sta mus_mel_ptr
    lda #>music_melody
    sta mus_mel_ptr+1
    jmp @next
@ev:
    sta nmi_t0
    iny
    lda (mus_mel_ptr),y
    sta mus_mel_tmr
    lda mus_mel_ptr
    clc
    adc #2
    sta mus_mel_ptr
    bcc :+
    inc mus_mel_ptr+1
:   lda nmi_t0
    beq @rest
    tax
    lda note_period_lo,x
    sta mus_p1_blo
    sta $4002
    lda note_period_hi,x
    sta mus_p1_bhi
    sta mus_p1_lhi
    sta $4003                  ; note-on: phase + fresh envelope
    lda #0
    sta mus_p1_frame
    beq express
@rest:
    lda #$FF
    sta mus_p1_bhi

express:                       ; ---- per-frame melody expression ----
    lda mus_p1_bhi
    cmp #$FF
    bne @live
    lda #$B0                   ; rest: duty 50, constant volume 0
    sta $4000
    jmp bass
@live:
    ldx mus_p1_frame           ; envelope: pluck table then tremolo sustain
    cpx #12
    bcs @sus
    lda env_tab,x
    jmp @vol
@sus:
    txa
    lsr
    lsr
    lsr
    and #$01                   ; sustain 5 <-> 6 wobble = tremolo
    clc
    adc #5
@vol:
    ora #$B0
    sta $4000
    lda mus_p1_frame           ; vibrato after a short settle
    cmp #16
    bcc @novib
    lsr
    and #$0F
    tax
    lda vib_tab,x
    sta nmi_t0
    ldy #0
    lda nmi_t0
    bpl :+
    dey                        ; sign extend
:   lda mus_p1_blo
    clc
    adc nmi_t0
    sta $4002
    tya
    adc mus_p1_bhi
    cmp mus_p1_lhi
    beq @vibdone
    sta mus_p1_lhi
    sta $4003
@vibdone:
    jmp @adv
@novib:
    lda mus_p1_blo
    sta $4002
@adv:
    lda mus_p1_frame
    cmp #$FF
    beq bass
    inc mus_p1_frame

bass:
    dec mus_bas_tmr            ; ---- bass / triangle ----
    bne echo
@next:
    ldy #0
    lda (mus_bas_ptr),y
    cmp #$FF
    bne @ev
    lda #<music_bass
    sta mus_bas_ptr
    lda #>music_bass
    sta mus_bas_ptr+1
    jmp @next
@ev:
    sta nmi_t0
    iny
    lda (mus_bas_ptr),y
    sta mus_bas_tmr
    lda mus_bas_ptr
    clc
    adc #2
    sta mus_bas_ptr
    bcc :+
    inc mus_bas_ptr+1
:   lda nmi_t0
    beq @rest
    tax
    lda #$FF                   ; linear counter on
    sta $4008
    lda note_period_lo,x
    sta $400A
    lda note_period_hi,x
    sta $400B
    jmp echo
@rest:
    lda #$80
    sta $4008

echo:
    dec mus_echo_tmr           ; ---- echo voice / pulse 2 (yields to sfx) --
    bne hats
@next:
    ldy #0
    lda (mus_echo_ptr),y
    cmp #$FF
    bne @ev
    lda #<music_echo
    sta mus_echo_ptr
    lda #>music_echo
    sta mus_echo_ptr+1
    jmp @next
@ev:
    sta nmi_t0
    iny
    lda (mus_echo_ptr),y
    sta mus_echo_tmr
    lda mus_echo_ptr
    clc
    adc #2
    sta mus_echo_ptr
    bcc :+
    inc mus_echo_ptr+1
:   lda sfx_p_ptr+1            ; an active sfx owns the channel; the stream
    bne hats                   ; still advances so the echo stays in time
    lda nmi_t0
    beq @rest
    tax
    lda note_period_lo,x
    sta $4006
    lda #$34                   ; duty 12.5%, quiet -- a room behind the lead
    sta $4004
    lda note_period_hi,x
    sta $4007
    jmp hats
@rest:
    lda #$30
    sta $4004

hats:
    dec mus_hat_tmr            ; ---- hi-hats / noise (yields to sfx) ----
    bne sfx
@next:
    ldy #0
    lda (mus_hat_ptr),y
    cmp #$FF
    bne @ev
    lda #<music_hats
    sta mus_hat_ptr
    lda #>music_hats
    sta mus_hat_ptr+1
    jmp @next
@ev:
    sta nmi_t0
    inc mus_hat_ptr
    bne :+
    inc mus_hat_ptr+1
:   lda #12                    ; straight 8ths
    sta mus_hat_tmr
    lda sfx_n_ptr+1
    bne sfx
    lda nmi_t0
    beq @rest
    lsr
    lsr
    lsr
    lsr
    sta $400E
    lda nmi_t0
    and #$0F
    ora #$30
    sta $400C
    lda #$08
    sta $400F
    jmp sfx
@rest:
    lda #$30
    sta $400C

sfx:
    lda sfx_p_ptr+1            ; ---- pulse 2 sfx ----
    beq noise
    dec sfx_p_tmr
    bne noise
    ldy #0
    lda (sfx_p_ptr),y
    bne @ev
    lda #$30                   ; end of stream
    sta $4004
    lda #0
    sta sfx_p_ptr+1
    beq noise
@ev:
    sta sfx_p_tmr
    iny
    lda (sfx_p_ptr),y
    beq @rest
    tax
    lda note_period_lo,x
    sta $4006
    lda note_period_hi,x
    sta $4007
    iny
    lda (sfx_p_ptr),y
    sta $4004
    jmp @adv
@rest:
    lda #$30
    sta $4004
@adv:
    lda sfx_p_ptr
    clc
    adc #3
    sta sfx_p_ptr
    bcc noise
    inc sfx_p_ptr+1

noise:
    lda sfx_n_ptr+1            ; ---- noise sfx ----
    beq done
    dec sfx_n_tmr
    bne done
    ldy #0
    lda (sfx_n_ptr),y
    bne @ev
    lda #$30
    sta $400C
    lda #0
    sta sfx_n_ptr+1
    beq done
@ev:
    sta sfx_n_tmr
    iny
    lda (sfx_n_ptr),y
    sta $400E
    iny
    lda (sfx_n_ptr),y
    sta $400C
    lda #$08
    sta $400F                  ; load length counter (halted, so any value)
    lda sfx_n_ptr
    clc
    adc #3
    sta sfx_n_ptr
    bcc done
    inc sfx_n_ptr+1
done:
    rts
.endproc
