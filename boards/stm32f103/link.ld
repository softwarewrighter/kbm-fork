/* boards/stm32f103/link.ld -- k on an STM32F103C8 ("Blue Pill" class board).
 *
 * Flash: officially 64 KB on the C8, but k at -Os is ~85 KB. Most C8 parts
 * have 128 KB that programs and verifies fine (same die as the CB); build.sh
 * passes FLASH_KB (default 128) and docs/hw-bringup/stm32f103.md says how to
 * check the chip. RAM: 20 KB, enforced here, with __stack_size bytes kept free
 * at the top for the stack. */
ENTRY(Reset_Handler)
PROVIDE(__flash_size = 128K);
PROVIDE(__stack_size = 6K);
MEMORY {
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = __flash_size
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 20K
}
SECTIONS {
  .text : {
    KEEP(*(.vectors))
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
  } > FLASH
  .ARM.exidx : { *(.ARM.exidx*) } > FLASH
  .data : {
    . = ALIGN(4); __data_start = .;
    *(.data .data.*)
    . = ALIGN(4); __data_end = .;
  } > RAM AT > FLASH
  __data_load = LOADADDR(.data);
  .bss (NOLOAD) : {
    . = ALIGN(4); __bss_start = .;
    *(.bss .bss.* COMMON)
    . = ALIGN(4); __bss_end = .;
  } > RAM
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(__bss_end + __stack_size <= __stack_top, "k's statics + stack do not fit the 20 KB SRAM: lower KHEAP or STACK")
}
