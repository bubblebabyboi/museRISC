# Sigil Linux examples, built on the board (or in QEMU) with Debian's
# gcc:  make && make run
CC      ?= gcc
CFLAGS  ?= -O2 -Wall
PROGS   = hello malloc_test numa_hbm rvv_vadd

all: $(PROGS)

numa_hbm: LDLIBS += -lnuma
rvv_vadd: CFLAGS += -march=rv64gc_zve64d

run: all
	./hello
	./malloc_test
	./numa_hbm
	./rvv_vadd

clean:
	rm -f $(PROGS)

.PHONY: all run clean
