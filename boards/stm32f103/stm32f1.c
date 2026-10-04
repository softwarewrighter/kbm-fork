// boards/stm32f103/stm32f1.c -- the whole board port of k to the STM32F103:
// reset, clock, and a polled USART1 console (PA9 TX, PA10 RX, 115200 8N1).
// Register-level, no SDK. k plus boards/mcu/common/ksys-bare.c do the rest.
//
// -DKQEMU_F2: build for QEMU's netduino2 (STM32F205) as a stand-in. Its USART
// is the same register model at another address; the F1 clock and GPIO
// registers do not exist there, so that setup is skipped.
// -DKSTACK_REPORT: paint the stack at boot; k's exit (\\) prints the
// high-water mark before resetting. Use it once on the board to check the
// stack size.
#include <stdint.h>
#define R(a) (*(volatile uint32_t *)(a))

#ifdef KQEMU_F2
#define USART1 0x40011000u
#else
#define USART1 0x40013800u
#endif
#define USART_SR  R(USART1 + 0x00)
#define USART_DR  R(USART1 + 0x04)
#define USART_BRR R(USART1 + 0x08)
#define USART_CR1 R(USART1 + 0x0C)
#define SR_RXNE (1u << 5)
#define SR_TC   (1u << 6)
#define SR_TXE  (1u << 7)

#define RCC_CR      R(0x40021000u)
#define RCC_CFGR    R(0x40021004u)
#define RCC_APB2ENR R(0x40021018u)
#define GPIOA_CRH   R(0x40010804u)
#define FLASH_ACR   R(0x40022000u)
#define SCB_AIRCR   R(0xE000ED0Cu)

extern uint32_t __data_start, __data_end, __data_load, __bss_start, __bss_end, __stack_top;
void kmain(void);
static uint32_t pclk2 = 8000000;   // HSI after reset

// 72 MHz from the board's 8 MHz crystal (HSE x9). If the crystal does not
// start (missing on some boards), stay on the internal 8 MHz oscillator: k
// works the same, only slower. Every wait is bounded.
static void clock_init(void) {
#ifndef KQEMU_F2
  RCC_CR |= 1u << 16;                                         // HSEON
  for (uint32_t n = 0; n < 500000 && !(RCC_CR & (1u << 17)); n++) {}
  if (!(RCC_CR & (1u << 17))) return;                         // no HSERDY
  FLASH_ACR = 0x12;                                           // prefetch, 2 wait states
  RCC_CFGR = (7u << 18) | (1u << 16) | (4u << 8);             // PLL x9, src HSE, APB1 /2
  RCC_CR |= 1u << 24;                                         // PLLON
  for (uint32_t n = 0; n < 500000 && !(RCC_CR & (1u << 25)); n++) {}
  if (!(RCC_CR & (1u << 25))) return;                         // PLL did not lock
  RCC_CFGR |= 2u;                                             // SYSCLK = PLL
  for (uint32_t n = 0; n < 500000 && ((RCC_CFGR >> 2) & 3u) != 2u; n++) {}
  if (((RCC_CFGR >> 2) & 3u) == 2u) pclk2 = 72000000;
#endif
}

static void uart_init(void) {
#ifndef KQEMU_F2
  RCC_APB2ENR |= (1u << 2) | (1u << 14);                      // IOPAEN, USART1EN
  GPIOA_CRH = (GPIOA_CRH & ~0xFF0u) | (0xBu << 4) | (0x4u << 8); // PA9 AF push-pull, PA10 input
#endif
  USART_BRR = (pclk2 + 115200 / 2) / 115200;
  USART_CR1 = (1u << 13) | (1u << 3) | (1u << 2);             // UE, TE, RE
}

int con_getc(void) {
  while (!(USART_SR & SR_RXNE)) {}
  return (int)(USART_DR & 0xFF);                              // also clears an overrun
}

void con_putc(int c) {
  while (!(USART_SR & SR_TXE)) {}
  USART_DR = (uint32_t)(c & 0xFF);
}

#ifdef KSTACK_REPORT
#define PAINT 0xA5A5A5A5u
static void report_stack(void) {
  uint32_t *p = &__bss_end;
  while (p < &__stack_top && *p == PAINT) p++;
  uint32_t used = (uint32_t)((char *)&__stack_top - (char *)p);
  char b[12]; int i = 11; b[i] = 0;
  do b[--i] = (char)('0' + used % 10); while (used /= 10);
  for (const char *s = "\r\nstack high-water bytes: "; *s; s++) con_putc(*s);
  for (const char *s = b + i; *s; s++) con_putc(*s);
  con_putc('\r'); con_putc('\n');
}
#endif

void con_exit(int code) {   // like the other MCU ports: k's exit resets the chip
  (void)code;
#ifdef KSTACK_REPORT
  report_stack();
#endif
  while (!(USART_SR & SR_TC)) {}                              // drain the last byte
  SCB_AIRCR = 0x05FA0004u;                                    // SYSRESETREQ
  for (;;) {}
}

__attribute__((noreturn, used)) void reset_c(void) {
  for (uint32_t *s = &__data_load, *d = &__data_start; d < &__data_end;) *d++ = *s++;
  for (uint32_t *p = &__bss_start; p < &__bss_end; p++) *p = 0;
#ifdef KSTACK_REPORT
  { uint32_t *sp; __asm__ volatile("mov %0, sp" : "=r"(sp));
    for (uint32_t *p = &__bss_end; p < sp - 16; p++) *p = PAINT; }
#endif
  clock_init();
  uart_init();
  kmain();
  for (;;) {}
}

__attribute__((naked, noreturn)) void Reset_Handler(void) {
  __asm__ volatile("ldr sp, =__stack_top\n b reset_c\n");
}
static void Fault_Handler(void) { for (;;) {} }   // a debugger shows where it stopped

__attribute__((section(".vectors"), used))
const void *const vectors[16] = {
  &__stack_top, (void *)Reset_Handler, (void *)Fault_Handler /* NMI */,
  (void *)Fault_Handler /* HardFault */, (void *)Fault_Handler /* MemManage */,
  (void *)Fault_Handler /* BusFault */, (void *)Fault_Handler /* UsageFault */,
};
