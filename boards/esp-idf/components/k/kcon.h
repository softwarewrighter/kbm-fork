// kcon.h -- k's console and entry point for the ESP-IDF app.
#pragma once
void con_init(void);       // install the console driver (call once, before kmain)
int  con_getc(void);
void con_putc(int c);
void con_exit(int code);
void kmain(void);          // ksys-bare.c: runs k's REPL; returns only via con_exit
