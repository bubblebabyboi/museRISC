// Mock of the aws-fpga SDK fpga_pci.h (v2.3.5 signatures), only what
// sigil_host.c uses; implemented by ../sigil_host_mock.c.
#ifndef SIGIL_MOCK_FPGA_PCI_H_
#define SIGIL_MOCK_FPGA_PCI_H_
#include <stdint.h>
typedef int pci_bar_handle_t;
#define PCI_BAR_HANDLE_INIT (-1)
enum { FPGA_APP_PF = 0 };
enum { APP_PF_BAR0 = 0, APP_PF_BAR4 = 4 };
enum { BURST_CAPABLE = 0x1 };
int fpga_pci_attach(int slot_id, int pf_id, int bar_id, uint32_t flags, pci_bar_handle_t *handle);
int fpga_pci_detach(pci_bar_handle_t handle);
int fpga_pci_poke(pci_bar_handle_t handle, uint64_t offset, uint32_t value);
int fpga_pci_poke64(pci_bar_handle_t handle, uint64_t offset, uint64_t value);
int fpga_pci_write_burst(pci_bar_handle_t handle, uint64_t offset, uint32_t *datap, uint64_t dword_len);
int fpga_pci_peek(pci_bar_handle_t handle, uint64_t offset, uint32_t *value);
int fpga_pci_peek64(pci_bar_handle_t handle, uint64_t offset, uint64_t *value);
int fpga_pci_get_address(pci_bar_handle_t handle, uint64_t offset, uint64_t dword_len, void **ptr);
#endif
