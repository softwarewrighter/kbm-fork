/* boards/mcu/m33-an505/link.ld -- QEMU mps2-an505 boots the M33 in secure
 * state with VTOR at 0x10000000 (the secure alias of the 4 MB ZBT SRAM), so
 * the vector table goes first there. The RP2350 has 520 KB of SRAM; build.sh
 * reports the .data/.bss/stack budget against it. */
ENTRY(Reset_Handler)
MEMORY { RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 4M }
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.*) } > RAM
  .ARM.exidx : { *(.ARM.exidx*) } > RAM
  .data : { *(.data .data.*) } > RAM
  .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss .bss.* COMMON) . = ALIGN(4); __bss_end = .; } > RAM
  .stack (NOLOAD) : { . = ALIGN(8); . += 32K; __stack_top = .; } > RAM
}
