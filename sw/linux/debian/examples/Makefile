# Sigil Linux examples, built on the board (or in QEMU) with Debian's
# gcc:  make && make run
CC      ?= gcc
CFLAGS  ?= -O2 -Wall
PROGS   = hello malloc_test numa_hbm memwhere rvv_vadd autovec

all: $(PROGS)

numa_hbm memwhere: LDLIBS += -lnuma
rvv_vadd: CFLAGS += -march=rv64gc_zve64d
autovec: CFLAGS += -O3 -march=rv64gc_zve64d_zvl512b

run: all
	./hello
	./malloc_test
	./numa_hbm
	./memwhere 256
	numactl --membind=1 ./memwhere 256
	./rvv_vadd
	./autovec

clean:
	rm -f $(PROGS)

.PHONY: all run clean
