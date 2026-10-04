/* boards/mcu/rv32-virt/link.ld -- everything in RAM at 0x80000000 (QEMU
 * loads the ELF there). On the ESP32-P4 code runs from flash (XIP) and only
 * .data/.bss/stack use the 768 KB of SRAM; build.sh reports that budget. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
PROVIDE(__stack_size = 32K);  /* override: -Wl,--defsym=__stack_size=8192 */
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 8M }
SECTIONS {
  .text : { *(.text.init) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
  .data : { __global_pointer$ = . + 0x800; *(.data .data.* .sdata .sdata.*) } > RAM
  .bss (NOLOAD) : { __bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON) . = ALIGN(4); __bss_end = .; } > RAM
  .stack (NOLOAD) : { . = ALIGN(16); . += __stack_size; __stack_top = .; } > RAM
}
