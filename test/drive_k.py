#!/usr/bin/env python3
"""Drive k-on-BareMetal inside Bochs over COM1 and capture a transcript.

Usage: drive_k.py HOST:PORT SCRIPT_FILE TRANSCRIPT_FILE

SCRIPT_FILE holds one k line per row; '#'-prefixed rows are skipped.
BareMetal keeps a single-byte input latch (`key`), so characters are sent one
at a time and we wait for k's echo of each before sending the next; otherwise
keystrokes get overwritten.
"""
import socket, sys, time

addr, script, out = sys.argv[1], sys.argv[2], sys.argv[3]
host, port = addr.split(":")
log = open(out, "wb")
buf = bytearray()

def connect():
    for _ in range(300):
        try:
            return socket.create_connection((host, int(port)), timeout=1)
        except OSError:
            time.sleep(0.2)
    sys.exit("could not connect to Bochs COM1")

s = connect()
s.settimeout(0.2)

def pump(secs):
    end = time.time() + secs
    while time.time() < end:
        try:
            d = s.recv(4096)
        except socket.timeout:
            continue
        if not d:
            break
        buf.extend(d); log.write(d); log.flush()

def wait_for(pat: bytes, secs: float, start: int) -> bool:
    end = time.time() + secs
    while time.time() < end:
        if pat in buf[start:]:
            return True
        pump(0.2)
    return False

def send_line(line: str, echo_timeout=20):
    for ch in line.encode() + b"\r":
        mark = len(buf)
        s.sendall(bytes([ch]))
        # Wait for echo of printable chars; newline echoes vary (\r or \n).
        if ch >= 0x20:
            if not wait_for(bytes([ch]), echo_timeout, mark):
                print(f"!! no echo for {chr(ch)!r}", file=sys.stderr)
        else:
            pump(0.5)

# Boot: the Monitor auto-runs k (sole file on BMFS); wait for k's banner,
# which ends with "(c)arthur whitney(l)MIT".
if not wait_for(b"whitney", 600, 0):
    sys.exit("!! k banner not seen (boot failed or k crashed; see transcript)")
pump(1)
for raw in open(script):
    line = raw.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    send_line(line)
    pump(3)
pump(5)
log.close()
