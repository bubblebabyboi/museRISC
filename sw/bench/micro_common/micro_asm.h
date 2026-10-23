/* Assembler helpers for the micro_* kernels (README.md here).
 *
 * Kernel convention: a leaf function, a0 = loop trips (>= 1), further
 * arguments in a1.. / fa0.., result in a0 / fa0; only caller-saved
 * registers, no stack, no memory other than the data it measures.
 * Every kernel starts on a 64-byte (I$ line) boundary, and a file is
 * assembled with 32-bit encodings (.option norvc) unless a kernel says
 * otherwise, so every instruction starts on a fetch word. */
#ifndef MICRO_ASM_H
#define MICRO_ASM_H

#define MICRO_FUNC(name) \
  .text;                 \
  .balign 64;            \
  .globl name;           \
  .type name, @function; \
  name:

#define MICRO_ENDF(name) .size name, . - name

#endif /* MICRO_ASM_H */
