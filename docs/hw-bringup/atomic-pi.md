# Bring-up plan: Atomic Pi (Intel Atom x5-Z8350, x86-64)

The Atomic Pi is the one board here that can run kbm's own runtime,
BareMetal-OS, which is x86-64 only. Its Atom (Cherry Trail) has SSE4.2 but no
AVX of any kind, so the original AVX-512 kbm cannot run on it; the portable
build (`make PORTABLE=1`, x86-64-v2) can. 2 GB RAM, eMMC, UEFI firmware.

Two paths, in order of risk:

| Path | Console | Status in emulation |
|---|---|---|
| A. Linux + static k | ssh / any terminal | goldens pass (`qemu-x86_64 -cpu Westmere`, no AVX) |
| B. BareMetal from a UEFI USB stick | HDMI + keyboard (via PS/2 emulation), or serial | goldens pass over serial; HDMI + PS/2 keyboard works (screenshot-verified) |

## Path A: Linux

1. Install a Linux the board supports on the eMMC (or boot one from USB).
2. `boards/linux/build.sh --test`, then copy
   `boards/linux/dist/k-atomicpi-x86v2` to the board (`scp`), `chmod +x`.
3. Smoke test: run it from a terminal, `1+2` -> `3`, `\\` exits.
4. Acceptance: `boards/linux/test-on-board.sh user@atomicpi /path/to/k-atomicpi-x86v2`.
5. Optional: before copying, `grep -o -w 'avx\|avx2\|sse4_2' /proc/cpuinfo | sort -u`
   on the board; the build needs only `sse4_2` (plus popcnt).

## Path B: BareMetal, booted from a USB stick (kbm proper)

### Build the stick image

```sh
cd ../BareMetal-OS && ./baremetal.sh setup && cd ../kbm-fork   # current BareMetal
B=../BareMetal-OS boards/x86-baremetal/make-usb-image.sh screen   # HDMI + keyboard
B=../BareMetal-OS boards/x86-baremetal/make-usb-image.sh serial   # COM1 console
boards/x86-baremetal/test-uefi.sh                                 # goldens in QEMU (serial)
```

Output: `boards/x86-baremetal/dist/k-usb-{screen,serial}.img` (64 MB FAT32,
`EFI/BOOT/BOOTX64.EFI`). k's heap defaults to 256 MiB (`KHEAP=22`); set
`KHEAP=` (empty) for k's original 1 GiB.

Why it is built this way:
- Current BareMetal's only disk driver is virtio-blk, so on real hardware it
  cannot read the stick or the eMMC. The UEFI firmware loads `BOOTX64.EFI`,
  which carries a 1 MiB RAM drive holding `k.app`; nothing else is read.
- The Monitor auto-runs programs only from a disk filesystem, so at its `>`
  prompt type: `loadr`, then `1`, then `exec`.

### Write the stick (destructive)

1. Insert the stick; identify it with `lsblk` (Linux) or `diskutil list`
   (macOS). Confirm the size matches. Never pick a disk you have not
   identified that way.
2. `sudo dd if=boards/x86-baremetal/dist/k-usb-screen.img of=/dev/sdX bs=4M conv=fsync status=progress`
   (macOS: `/dev/rdiskN` after `diskutil unmountDisk`).

### Boot

1. HDMI monitor, USB keyboard, stick in a USB port.
2. Enter the firmware setup (usually Del or Esc at power-on). Note the
   firmware version. Find **Legacy USB Support** (or "USB keyboard legacy
   emulation") and **enable** it. Disable Secure Boot (BareMetal is not signed).
3. Boot the stick from the boot menu (UEFI entry).
4. Expect BareMetal's boot screen (a row of progress blocks), then the
   Monitor: a status line and a `>` prompt. Type `loadr`, `1`, `exec`; k
   prints its banner. Try `1+2`, `3^!10`.

### The one real risk: the keyboard

BareMetal's only input driver is PS/2 (`src/drivers/ps2.asm`); it has no USB
keyboard driver. The Atom SoC has no physical PS/2 controller, so a USB
keyboard works only if the firmware emulates PS/2 for it (Legacy USB
Support). Verified in QEMU: with a PS/2 controller, k on the HDMI console
works; with no PS/2 controller at all, **BareMetal hangs during boot at its
`hid` step** (the progress blocks stop advancing).

If that happens on the Atomic Pi:
1. Recheck Legacy USB Support; try the firmware's legacy/CSM boot mode if it
   offers one (then the image would need BareMetal's BIOS boot files instead;
   record that it is needed and stop there).
2. Try the `serial` image only if the board exposes a legacy COM1
   (I/O port 0x3F8). The Atom's on-chip UARTs are memory-mapped (LPSS), not
   COM1, so BareMetal's serial driver will most likely not see them.
3. Otherwise use Path A, and record what the firmware offered. Getting past
   this would need a USB keyboard or LPSS UART driver in BareMetal, which is
   out of scope.

### Acceptance (Path B)

- `test/golden/basic.k` typed (or pasted, slowly) at k's prompt produces
  `test/golden/basic.expected`. With only HDMI, compare by eye or photograph
  the screen; with a working COM1, use `test/drive_serial.py --attached`.
- `\\` shuts the machine down (k's exit is BareMetal's SHUTDOWN).

## Bonus: GPIO

BareMetal runs k in ring 0, so a `k_sys` call that reads or writes the Atom's
GPIO controller registers (memory-mapped) would give k direct pin access
with no driver stack. Not started; the register map is in Intel's Cherry
Trail datasheets.

## Results

(date, board revision, firmware version and settings, path, image, heap,
what the screen showed, acceptance pass/fail, notes)
