# Bring-up plan: Milk-V Duo family (Linux)

All Duo boards run Linux, so k needs no SDK and no drivers. It runs as one
static, libc-free binary that makes raw Linux syscalls
(`test/host/ksys-linux.c`). It does not care whether the image uses musl or
glibc. The Duo 256M uses the same SoC as the LicheeRV Nano (SG2002), so
`linux-boards.md` applies too.

## Which board, which binary

| Board | SoC | Linux core(s) | RAM | Binary (`boards/linux/dist/`) | Heap |
|---|---|---|---|---|---|
| Duo | CV1800B | C906 @ 1 GHz (RV64GC) | 64 MB | `k-milkv-duo-rv64` | KHEAP=17, 8 MiB |
| Duo 256M | SG2002 | C906 @ 1 GHz, **or** Cortex-A53 | 256 MB | `k-milkv-duo256m-rv64` / `k-milkv-arm64` | KHEAP=20, 64 MiB |
| Duo S | SG2000 | C906 @ 1 GHz, **or** Cortex-A53 | 512 MB | `k-milkv-duos-rv64` / `k-milkv-arm64` | KHEAP=21 / 20 |

Tell the boards apart by the SoC marking (CV1800B, SG2002 or SG2000), and by
their shape: the Duo S is larger and has an Ethernet jack and a USB-A port.
Every binary passes the goldens under qemu-user (`boards/linux/build.sh
--test`).

Heap: the image reserves part of RAM for the camera/multimedia (ION) pool,
so check `free -m` on the board. If the binary will not start ("cannot
allocate memory", or killed), rebuild with a smaller heap, e.g.
`KHEAP_milkv_duo_rv64=16 boards/linux/build.sh`.

Each SoC also has a second, small C906 core (700 MHz) that Milk-V's SDK
runs FreeRTOS on. Running k there (bare, next to Linux) is possible later
with `boards/mcu`-style glue. It is out of scope here.

## Prerequisites (bring-up machine)

- clang + lld and `qemu-user` (to build and pre-test: `boards/linux/build.sh --test`;
  `dist/` is not committed), Python 3, ssh/scp.
- A microSD card (the Duo S can also boot from eMMC; this plan uses SD).
- An SD writer: `dd` with `lsblk` checks, `bmaptool`, or balenaEtcher.
- Optional: a 3.3 V USB-serial adapter for the console. **Never connect a
  5 V adapter.** Settings are 115200 8N1.
  - Duo 256M: header pins 16 = TX, 17 = RX, 18 = GND. The Duo is
    pin-compatible, but check its pinout before connecting.
  - Duo S: header J3 pins 8 = TX, 10 = RX, 6 = GND.

## Steps

### 1. Image the SD card (destructive)

1. Download the newest image for the exact board from Milk-V's releases.
   Use `github.com/milkv-duo/duo-buildroot-sdk-v2/releases`, which
   covers Duo, Duo 256M and Duo S, including arm64 images for the 256M
   and Duo S. Asset names carry the board, libc and architecture, e.g.
   `milkv-duo256m-musl-riscv64-sd_<ver>.img.zip`.
   - Choose **riscv64** first.
   - Record the image name and version.
2. Identify the card:
   - Run `lsblk` before and after inserting it. The new device whose size
     matches the card is the target (e.g. `/dev/sdX`; on macOS use
     `diskutil list`).
   - Never write to a device you have not identified this way, or one with
     a mounted system partition.
   - Unmount its partitions.
3. Write the image:
   `unzip -p milkv-*.img.zip | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress`,
   then `sync` and eject.

### 2. Boot and get a shell

1. Insert the card and connect the board's USB-C port to the bring-up
   machine (this also powers it). The blue LED blinks once Linux is up.
2. The board appears as a USB network adapter (CDC-NCM on image V1.1.2 and
   later; RNDIS before that) and serves DHCP. Its address is
   **192.168.42.1**.
   - Check with `ping 192.168.42.1`.
   - On the Duo S, Ethernet works as well.
3. Log in with `ssh root@192.168.42.1`; the password is `milkv`.
   - Install a key for the test script (it uses `BatchMode=yes`):
     `ssh-copy-id root@192.168.42.1`.
   - If ssh warns about a changed host key after reflashing, remove the
     old one with `ssh-keygen -R 192.168.42.1`.
4. On the board, record `uname -m` (expect `riscv64`), `free -m`, and
   `cat /proc/cpuinfo`.
   - Boot-log note: on the Duo 256M and Duo S, the console's first boot
     line starts with `C` for the RISC-V core and `B` for the A53.

### 3. Copy k and smoke test

```sh
boards/linux/build.sh --test                   # builds dist/ and pre-tests under qemu-user
scp -O boards/linux/dist/k-milkv-duo-rv64 root@192.168.42.1:/root/k   # pick your board's binary
ssh -t root@192.168.42.1 /root/k               # type 1+2 (expect 3), then \\ to exit
```

`-O` makes scp use the old protocol. The image's ssh server (Dropbear) may
have no SFTP server, so plain `scp` can fail. Alternatively, copy the
binary onto the SD card's root filesystem from the bring-up machine.

k reads its input from its terminal (fd 1), so it needs a tty: use
`ssh -t`, the serial console, or the test script. Piping input into it
does not work.

### 4. Acceptance

```sh
boards/linux/test-on-board.sh root@192.168.42.1 /root/k
```

This runs `basic.k` and `big.k` through `ssh -tt` and diffs them against
the goldens.

Heap limit: copy a small-heap build and run `test/limits/heap.k`; expect
`wsfull`.
```sh
KHEAP_milkv_duo_rv64=12 boards/linux/build.sh
scp -O boards/linux/dist/k-milkv-duo-rv64 root@192.168.42.1:/root/k12
python3 test/host/run_host.py "ssh -tt -o BatchMode=yes root@192.168.42.1 /root/k12" test/limits/heap.k | tail -2
boards/linux/build.sh                          # restore the default heap
```

### 5. Optional: the Arm core (Duo 256M, Duo S)

1. Write an **arm64** image for the board (step 1).
2. Select the A53:
   - **Duo 256M:** short header pin 35 (Boot-Switch) to GND.
   - **Duo S:** set its RISC-V/ARM switch to ARM.
3. Boot; the first console line should start with `B`, and `uname -m` should
   report `aarch64`.
4. Repeat steps 3–4 with `k-milkv-arm64`.

Asking the human first is not required: this is a board switch plus an SD
image, and both are reversible.

## Known gaps / risks

- **Untested on silicon:** the binaries are proven only under qemu-user.
  The C906's RVV 0.7.1 is unused (the build is scalar rv64gc), so no
  vector instructions can fault.
- **Image names** and the Dropbear/SFTP behaviour come from Milk-V's
  docs and community reports. Fix this file if the board differs.
- **Timing:** `\t` timings use `rdcycle`/`rdtime` scaling written for x86.
  Treat them as relative only.

## Results

(date, board + SoC marking, image name/version, core (RISC-V/ARM),
`free -m`, binary + heap, basic.k / big.k / heap.k pass/fail, notes)
