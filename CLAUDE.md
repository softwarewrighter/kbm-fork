# kbm-fork: notes for coding agents

k (Arthur Whitney's k edu, `ksrc/`) on BareMetal-OS, extended on branch
`spike/portable-k` to run on other OSes and CPUs.

- Start with `test/README.md` (what exists and how it is tested) and
  `docs/hw-bringup/README.md` (plans for real boards: LicheeRV Nano,
  Luckfox RV1103, Milk-V Duo, ESP32-S3, ESP32-P4, RP2350, CH582F, Atomic Pi).
  CH582F firmware: `boards/ch582/build.sh` (WCH EVT SDK, 32 KB RAM budget).
  ESP32 builds: `boards/esp-idf/README.md` (ESP-IDF v5.4.x). `docs/k-on-sw-os-ml.md` is the
  design for running k on sw-os-ml.
- Every build must reproduce `test/golden/basic.expected` (and `big.expected`
  when its heap is >= 256 KiB). Run
  `test/host/run-golden.sh`, `boards/linux/build.sh --test` and
  `boards/mcu/build.sh --test` before and after changes.
- k compiles with clang or GCC (GCC flags and caveats: `ksrc/README.md`).
  SDK projects can compile it or link `boards/mcu/dist/libk-*.a`.
- The original BareMetal build must stay byte-identical:
  `test/check-kapp-hash.sh <Dec-2024 BareMetal from test/pin-baremetal-2024.sh>`
  (it pins the build date: k's banner embeds `__DATE__`).
- k's macros use most one- and two-letter names (`b`, `f`, `nr`, `x`...):
  avoid them as identifiers or macro arguments in code that includes
  ksrc headers, and never put a bare comma inside a k macro argument.
- Work on a branch, push regularly, and treat SD-card writes and flash
  erases as destructive (see docs/hw-bringup/README.md).
