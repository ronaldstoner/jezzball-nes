; JEZZBALL - an original NES fan tribute to the classic wall-builder.
; NROM (mapper 0), 16KB PRG + 8KB CHR, pure ca65.  Build: make

.include "gen/charmap.inc"     ; must precede any .byte "text"
.include "defs.inc"
.include "gen/tiles.inc"

.segment "HEADER"
.byte $4E, $45, $53, $1A       ; "NES\x1A" (literal: the charmap is active)
.byte 1                        ; 16KB PRG
.byte 1                        ; 8KB CHR
.byte $01                      ; flags 6: vertical mirroring, mapper 0
.byte $00                      ; flags 7
.res 8, $00

.segment "CODE"
.include "reset.s"
.include "nmi.s"
.include "ppu.s"
.include "title.s"
.include "game.s"
.include "balls.s"
.include "capture.s"
.include "hud.s"
.include "recap.s"
.include "sound.s"
.include "data.s"
.include "gen/title_rle.s"

.segment "CHR"
.incbin "../assets/chr/jezzball.chr"

.segment "VECTORS"
.addr nmi_handler, reset, irq_handler
