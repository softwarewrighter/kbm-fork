// con_esp.c -- the three console functions k's OS layer (ksys-bare.c) needs,
// on whichever console ESP-IDF is configured for (menuconfig:
// Component config > ESP System Settings > Channel for console output).
// Uses the console driver directly, blocking, with no stdio line buffering
// or CR/LF translation: ksys-bare.c does echo and line editing itself.
#include <stdint.h>
#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "esp_system.h"
#include "kcon.h"

#if CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG
#include "driver/usb_serial_jtag.h"
void con_init(void) {
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    usb_serial_jtag_driver_install(&cfg);
}
int con_getc(void) {
    uint8_t c;
    while (usb_serial_jtag_read_bytes(&c, 1, portMAX_DELAY) != 1) {}
    return c;
}
void con_putc(int c) {
    uint8_t b = (uint8_t)c;
    usb_serial_jtag_write_bytes(&b, 1, portMAX_DELAY);
}
#else  // UART console (the default: UART0, the dev board's USB-UART bridge port)
#include "driver/uart.h"
#ifdef CONFIG_ESP_CONSOLE_UART_NUM
#define K_UART CONFIG_ESP_CONSOLE_UART_NUM
#else
#define K_UART UART_NUM_0
#endif
void con_init(void) {
    uart_driver_install(K_UART, 512, 0, 0, NULL, 0);
}
int con_getc(void) {
    uint8_t c;
    while (uart_read_bytes(K_UART, &c, 1, portMAX_DELAY) != 1) {}
    return c;
}
void con_putc(int c) {
    char b = (char)c;
    uart_write_bytes(K_UART, &b, 1);
}
#endif

void con_exit(int code) {
    (void)code;
    esp_restart();   // `\\` in k reboots the board back into k
}
