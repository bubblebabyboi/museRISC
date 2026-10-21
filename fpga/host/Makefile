# Sigil F2 host runtime (issue #54). On an F2 instance (or the Developer
# AMI): build the SDK library once (aws-fpga/sdk/userspace/
# mkall_fpga_mgmt_tools.sh, or source aws-fpga/sdk_setup.sh), then
# `make -C fpga/host SDK_DIR=<aws-fpga>/sdk`. Links libfpga_mgmt.a
# statically when present, so the binary runs without the SDK
# installed system-wide (the AFI management tools still need it).
SDK_DIR ?= $(HOME)/src/project_data/aws-fpga/sdk
CC      ?= gcc
CFLAGS  ?= -O2 -g -std=gnu11 -Wall -Wextra -Werror
CPPFLAGS += -I$(SDK_DIR)/userspace/include
LDFLAGS += -L$(SDK_DIR)/userspace/lib
LDLIBS  += -lfpga_mgmt -lrt -lpthread

sigil_host: sigil_host.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

clean:
	rm -f sigil_host
.PHONY: clean
