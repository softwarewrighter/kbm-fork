/* boards/mcu/m33-an505/start.c -- vector table and reset for k on QEMU
 * mps2-an505 (Cortex-M33 + FPU). Stand-in for the RP2350's Arm cores; on the
 * real chip the Pico SDK provides this. The essential step is the same:
 * enable the FPU (CPACR CP10/CP11) before any floating-point code runs. */
#include <stdint.h>
extern uint32_t __stack_top, __bss_start, __bss_end;
void kmain(void);

__attribute__((naked, noreturn)) void Reset_Handler(void) {
  __asm__ volatile("ldr sp, =__stack_top\n b reset_c\n");
}
__attribute__((noreturn, used)) void reset_c(void) {
  *(volatile uint32_t *)0xE000ED88 |= 0xFu << 20;   /* CPACR: CP10, CP11 full */
  __asm__ volatile("dsb\n isb" ::: "memory");
  for (uint32_t *p = &__bss_start; p < &__bss_end; p++) *p = 0;
  kmain();
  for (;;) {}
}
static void Fault_Handler(void) { for (;;) {} }

__attribute__((section(".vectors"), used))
const void *const vectors[16] = {
  &__stack_top, (void *)Reset_Handler, (void *)Fault_Handler, (void *)Fault_Handler,
  (void *)Fault_Handler, (void *)Fault_Handler, (void *)Fault_Handler,
};
