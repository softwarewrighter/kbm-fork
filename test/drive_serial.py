#!/usr/bin/env python3
"""Run a k script against k on a real board over a serial port.

Usage: drive_serial.py SCRIPT.k PORT [--baud 115200] [--attached] [--boot-timeout 60]

PORT is e.g. /dev/ttyACM0 (USB CDC: RP2350, ESP32-P4 USB-Serial-JTAG) or
/dev/ttyUSB0 (USB-UART bridge). Without --attached, the driver waits for
k's banner ("...(c)arthur whitney(l)MIT"), so start it before resetting the
board (or let the board reset when the port opens). With --attached, k is
assumed to be at its prompt already.

Prints the transcript in the golden format (" <<input" lines, banner
dropped), so: drive_serial.py test/golden/basic.k /dev/ttyACM0 | diff
test/golden/basic.expected -
Requires pyserial (pip install pyserial).
"""
import argparse, os, sys, time
import serial  # pyserial

ap = argparse.ArgumentParser()
ap.add_argument("script"); ap.add_argument("port")
ap.add_argument("--baud", type=int, default=115200)
ap.add_argument("--attached", action="store_true")
ap.add_argument("--boot-timeout", type=float, default=60)
args = ap.parse_args()

lines = [l.rstrip("\n") for l in open(args.script) if l.strip() and not l.startswith("#")]
port = serial.Serial(args.port, args.baud, timeout=0.05)
buf = bytearray()

def pump(t):
    end = time.time() + t
    while time.time() < end:
        d = port.read(4096)
        if d: buf.extend(d)

def wait_for(pat, t, since=0):
    end = time.time() + t
    while time.time() < end and buf.find(pat, since) < 0:
        pump(0.05)
    return buf.find(pat, since) >= 0

if args.attached:
    port.write(b"\r"); pump(1.0)
    # Record from the start of the line holding k's fresh ' ' prompt.
    start = buf.rfind(b"\n") + 1; text_skip_banner = False
else:
    if not wait_for(b"whitney", args.boot_timeout):
        sys.exit("k banner not seen; reset the board after starting this, or use --attached:\n"
                 + buf.decode("latin1"))
    start = buf.index(b"whitney"); text_skip_banner = True

for line in lines:
    for ch in line.encode() + b"\r":
        mark = len(buf)
        port.write(bytes([ch])); port.flush()
        # k's console echoes each byte; wait for it so no keystroke is lost.
        if ch >= 0x20 and not wait_for(bytes([ch]), 10, mark):
            print(f"no echo for {chr(ch)!r}", file=sys.stderr)
    pump(float(os.environ.get("K_STEP", "1.0")))
pump(0.5)

text = buf[start:].decode("latin1").replace("\r", "")
if text_skip_banner:
    text = text.split("\n", 1)[1] if "\n" in text else ""
else:
    text = text.lstrip("\n")
out, pos = [], 0
for line in lines:
    key = " " + line + "\n"
    i = text.find(key, pos)
    if i < 0: break
    out.append(text[pos:i]); out.append(" <<" + line + "\n"); pos = i + len(key)
out.append(text[pos:])
sys.stdout.write("".join(out) + "\n")
