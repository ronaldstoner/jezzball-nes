# JEZZBALL for the NES (NROM / mapper 0) -- ca65 + python3
CA65 = ca65
LD65 = ld65
PY   = python3
ROM  = build/jezzball.nes

GEN = src/gen/tiles.inc src/gen/charmap.inc src/gen/title_rle.s \
      src/gen/notes.inc src/gen/music.inc assets/chr/jezzball.chr

SRCS = src/jezzball.s src/defs.inc src/reset.s src/nmi.s src/ppu.s \
       src/title.s src/game.s src/balls.s src/capture.s src/hud.s \
       src/recap.s src/sound.s src/data.s

all: $(ROM)

$(GEN) &: tools/gen_chr.py tools/font8x8_basic.h
	$(PY) tools/gen_chr.py

build/jezzball.o: $(SRCS) $(GEN)
	@mkdir -p build
	$(CA65) src/jezzball.s -g -o $@

$(ROM): build/jezzball.o nes.cfg
	$(LD65) -C nes.cfg -o $@ build/jezzball.o \
	  -Ln build/labels.txt --dbgfile build/jezzball.dbg
	@ls -la $(ROM)
	@echo "iNES header:"; xxd -l 16 $(ROM)

run: $(ROM)
	fceux $(ROM) &

test: $(ROM)
	.venv/bin/python tools/test_rom.py

clean:
	rm -rf build src/gen assets/chr/jezzball.chr

.PHONY: all run test clean
