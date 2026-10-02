# kbm-fork: notes for coding agents

k (Arthur Whitney's k edu, `ksrc/`) on BareMetal-OS, extended on branch
`spike/portable-k` to run on other OSes and CPUs.

- Start with `test/README.md` (what exists and how it is tested) and
  `docs/hw-bringup/README.md` (plans for real boards: LicheeRV Nano,
  Luckfox RV1103, ESP32-P4, RP2350). `docs/k-on-sw-os-ml.md` is the
  design for running k on sw-os-ml.
- Every build must reproduce `test/golden/basic.expected`. Run
  `test/host/run-golden.sh`, `boards/linux/build.sh --test` and
  `boards/mcu/build.sh --test` before and after changes.
- k only compiles with clang. SDKs (GCC) link `boards/mcu/dist/libk-*.a`.
- The original BareMetal build must stay byte-identical: `make
  B=<Dec-2024 BareMetal from test/pin-baremetal-2024.sh>` gives a `k.app`
  with sha256 `c1d8062886cdb222...`.
- k's macros use most one- and two-letter names (`b`, `f`, `nr`, `x`...):
  avoid them as identifiers or macro arguments in code that includes
  ksrc headers, and never put a bare comma inside a k macro argument.
- Work on a branch, push regularly, and treat SD-card writes and flash
  erases as destructive (see docs/hw-bringup/README.md).
