// Mock of the aws-fpga SDK fpga_mgmt.h (v2.3.5 signatures), only what
// sigil_host.c uses; implemented by ../sigil_host_mock.c.
#ifndef SIGIL_MOCK_FPGA_MGMT_H_
#define SIGIL_MOCK_FPGA_MGMT_H_
#include <stdint.h>
enum { FPGA_STATUS_LOADED = 0 };
struct fpga_meta_ids { char afi_id[64]; };
struct fpga_mgmt_image_info {
  int status;
  int status_q;
  int slot_id;
  struct fpga_meta_ids ids;
  uint32_t sh_version;
};
int fpga_mgmt_init(void);
int fpga_mgmt_describe_local_image(int slot_id, struct fpga_mgmt_image_info *info, uint32_t flags);
int fpga_mgmt_load_local_image_sync(int slot_id, char *afi_id, uint32_t timeout, uint32_t delay_msec,
                                    struct fpga_mgmt_image_info *info);
#endif
