# k on the WCH CH582F (bare metal)

The firmware is k (`ksrc/`, compiled by GCC), `boards/mcu/common/ksys-bare.c`,
and `con_ch58x.c`, which handles the UART1 console on PA9 (TX) and PA8 (RX)
at 115200 8N1. WCH's CH583 EVT SDK supplies the startup code, linker script
and drivers. `build.sh` fetches the SDK at a pinned commit.

```sh
boards/ch582/build.sh                          # -> build/k-ch582.{elf,bin,hex}
wchisp flash boards/ch582/build/k-ch582.bin    # board in ISP mode: hold BOOT, plug in USB
```

| Variable | Default | |
|---|---|---|
| `KHEAP` | 8 | heap = 64 << KHEAP bytes (16 KiB) |
| `KOBJ` | 8 | 256 handles, 2 KiB |
| `STACK` | 8192 | bytes, reserved at the top of RAM |
| `CC` | riscv64-unknown-elf-gcc | or riscv-none-elf-gcc (xPack) |
| `CH58X_EVT` | `.evt` (auto-cloned) | path to an existing openwch/ch583 checkout |

The full plan, with wiring, flashing safety and acceptance, is in
`docs/hw-bringup/ch582.md`.
