/* F2 test firmware (sw/fpga-tests/f2_*.c): as sw/soc-tests/link.ld,
 * with .bss 8-byte aligned (crt.S clears it with 64-bit stores). */
OUTPUT_FORMAT("elf64-littleriscv")
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text) *(.text.*) }
  . = ALIGN(8);
  .rodata : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) }
  . = ALIGN(8);
  .data : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) }
  . = ALIGN(8);
  _bss_start = .;
  .bss : { *(.bss) *(.bss.*) *(.sbss) *(.sbss.*) *(COMMON) }
  . = ALIGN(8);
  _bss_end = .;
}
