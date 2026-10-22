/* Sigil SDK link script: one image in the 128 MiB RAM window at
 * 0x8000_0000 (where the boot ROM jumps). The flat binary
 * (objcopy -O binary) holds .text through .data; .bss, the stack and
 * the heap are not in the file and are zeroed / used at run time.
 * Stack size: -Wl,--defsym=__stack_size=N (default 64 KiB). The bump
 * allocator (sigil_alloc) hands out [_end, end of RAM). */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

__stack_size = DEFINED(__stack_size) ? __stack_size : 64K;

SECTIONS {
  .text : {
    KEEP(*(.text.init))
    *(.text.trap)
    *(.text .text.*)
  } > RAM
  .rodata : ALIGN(8) {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > RAM
  .data : ALIGN(8) {
    *(.data .data.*)
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
    . = ALIGN(8);
  } > RAM
  .bss (NOLOAD) : ALIGN(8) {
    _bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(8);
    _bss_end = .;
  } > RAM
  .stack (NOLOAD) : ALIGN(16) {
    . += __stack_size;
    _stack_top = .;
  } > RAM
  _end = .;
  _ram_end = ORIGIN(RAM) + LENGTH(RAM);
  /DISCARD/ : { *(.comment) *(.note .note.*) }
}
