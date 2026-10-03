#!/usr/bin/env python3
"""Feed a k script to k-on-BareMetal over QEMU's serial stdio.

Usage: drive_qemu.py SCRIPT.k QEMU_ARGV...
Prints the transcript normalized to the golden format: k's ' ' prompt
followed by its own echo of the input becomes ' <<input', and the boot log
and k's banner line are dropped.
"""
import os, select, subprocess, sys, time

script, argv = sys.argv[1], sys.argv[2:]
lines = [l.rstrip("\n") for l in open(script) if l.strip() and not l.startswith("#")]
p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
buf = bytearray()

def pump(t):
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.1)
        if r:
            d = os.read(p.stdout.fileno(), 65536)
            if not d: return
            buf.extend(d)

def wait_for(pat, t, since=0):
    """Wait until pat appears in output received at or after index `since`."""
    end = time.time() + t
    while time.time() < end and buf.find(pat, since) < 0:
        pump(0.05)
    return buf.find(pat, since) >= 0

# K_PRE="loadr;1;exec": Monitor commands to type before k starts (BareMetal
# booted via UEFI keeps k in its RAM drive and does not auto-run it).
pre = [c for c in os.environ.get("K_PRE", "").split(";") if c]
if pre:
    if not wait_for(b"> ", 300):
        p.kill(); sys.exit("Monitor prompt not seen:\n" + buf.decode("latin1"))
    for cmd in pre:
        for ch in cmd.encode() + b"\r":
            p.stdin.write(bytes([ch])); p.stdin.flush(); pump(0.2)
        pump(1)
if not wait_for(b"whitney", 300):
    p.kill(); sys.exit("k banner not seen:\n" + buf.decode("latin1"))
start = buf.index(b"whitney")
for line in lines:
    for ch in line.encode() + b"\r":   # serial Enter is CR; BareMetal maps it
        mark = len(buf)
        p.stdin.write(bytes([ch])); p.stdin.flush()
        # BareMetal latches one key at a time: wait for k's echo before the next.
        if ch >= 0x20 and not wait_for(bytes([ch]), 30, mark):
            print(f"no echo for {chr(ch)!r}", file=sys.stderr)
    pump(float(os.environ.get("K_STEP", "1.5")))
pump(1)
p.kill()

text = buf[start:].decode("latin1").replace("\r", "")
text = text.split("\n", 1)[1] if "\n" in text else ""   # drop banner line
out, pos = [], 0
for line in lines:                                         # mark inputs
    key = " " + line + "\n"
    i = text.find(key, pos)
    if i < 0: break
    out.append(text[pos:i]); out.append(" <<" + line + "\n"); pos = i + len(key)
out.append(text[pos:])
sys.stdout.write("".join(out) + "\n")   # same shape as run-golden.sh
