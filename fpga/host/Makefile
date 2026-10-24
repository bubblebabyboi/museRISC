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

# Host-side test without an FPGA or the SDK (#75): sigil_host.c built
# against test/sigil_host_mock.c (a mock of the SDK and of the Sigil CL),
# then test/test_sigil_host.py runs the F2 Linux flow on it with
# relative and absolute image paths. Linux: the real host build (mmap,
# copy threads); other hosts: the co-simulation seam (-DSV_TEST).
TEST_BUILD ?= ../../build/host-test
TEST_CFLAGS := -O1 -g -std=gnu11 -Wall -Wextra -Werror $(if $(filter Linux,$(shell uname -s)),,-DSV_TEST)
$(TEST_BUILD)/sigil_host_mock: sigil_host.c test/sigil_host_mock.c $(wildcard test/mock/*.h) cosim/sigil_host_cosim.h
	mkdir -p $(TEST_BUILD)
	$(CC) -Itest/mock $(TEST_CFLAGS) -o $@ test/sigil_host_mock.c -lpthread

test: $(TEST_BUILD)/sigil_host_mock
	python3 test/test_sigil_host.py $(abspath $(TEST_BUILD)/sigil_host_mock)

clean:
	rm -f sigil_host
	rm -rf $(TEST_BUILD)
.PHONY: clean test
