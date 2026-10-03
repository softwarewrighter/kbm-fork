// main.c -- start k in its own task.
// k recurses deeply, so it gets a 32 KB stack (the main task's default is
// ~3.5 KB). On dual-core chips it runs on core 1, so long computations do
// not starve core 0's idle task (the task watchdog stays quiet).
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "kcon.h"

static void k_task(void *arg) {
    (void)arg;
    kmain();
}

void app_main(void) {
    con_init();
#if CONFIG_FREERTOS_UNICORE
    xTaskCreate(k_task, "k", 32 * 1024, NULL, 5, NULL);
#else
    xTaskCreatePinnedToCore(k_task, "k", 32 * 1024, NULL, 5, NULL, 1);
#endif
}
