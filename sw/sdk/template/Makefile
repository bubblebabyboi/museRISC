# Template for your own Sigil program. Copy this folder (e.g. to
# sw/myprog/), put your .c/.S files in it, and run `make` (ELF + flat
# .bin in build/) or `make run` (RTL SoC simulation). See
# docs/PROGRAMMING.md and sw/sdk/sdk.mk for the variables.

# Program / test name (default: the folder name).
PROG ?= $(notdir $(CURDIR))

# Path to sw/sdk: found automatically for a folder next to sw/sdk, in
# sw/, or at the repository root; set it explicitly anywhere else.
SIGIL_SDK ?= $(patsubst %/sdk.mk,%,$(firstword $(wildcard \
  ../sdk/sdk.mk ../../sdk/sdk.mk ../sw/sdk/sdk.mk ../../sw/sdk/sdk.mk)))
ifeq ($(SIGIL_SDK),)
$(error cannot find sw/sdk: run make SIGIL_SDK=/path/to/sigil/sw/sdk)
endif

include $(SIGIL_SDK)/sdk.mk
