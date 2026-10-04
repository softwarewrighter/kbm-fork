// boards/ch582/con_ch58x.c -- k's console on a WCH CH582F (CH58x family).
//
// Polled UART1 on PA9 (TX) / PA8 (RX), 115200 8N1, through WCH's
// StdPeriphDriver from the CH583 EVT SDK (Apache-2.0, fetched by build.sh).
// k itself is portable C; this file is the whole board port: main() brings up
// the clock and UART, then hands over to ksys-bare.c's kmain(), which calls k.
// No interrupts, no BLE (k leaves no RAM for the BLE stack).
#include "CH58x_common.h"

void kmain(void);

int con_getc(void) {
  while (!R8_UART1_RFC) {}                  // RX FIFO count
  return R8_UART1_RBR;
}

void con_putc(int c) {
  while (R8_UART1_TFC >= UART_FIFO_SIZE) {} // TX FIFO full
  R8_UART1_THR = (uint8_t)c;
}

void con_exit(int code) {
  (void)code;                               // like ESP-IDF: k's exit (\\) restarts
  while (R8_UART1_TFC) {}                   // drain the TX FIFO first
  for (volatile int i = 0; i < 20000; i++) {}
  SYS_ResetExecute();
  for (;;) {}
}

int main(void) {
  SetSysClock(CLK_SOURCE_PLL_60MHz);
  GPIOA_SetBits(GPIO_Pin_9);
  GPIOA_ModeCfg(GPIO_Pin_8, GPIO_ModeIN_PU);       // RXD1: input, pull-up
  GPIOA_ModeCfg(GPIO_Pin_9, GPIO_ModeOut_PP_5mA);  // TXD1: push-pull, idle high
  UART1_DefInit();                                 // 115200 8N1, FIFO on
  kmain();
  return 0;
}
