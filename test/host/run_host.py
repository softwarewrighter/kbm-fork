#!/usr/bin/env python3
"""Run a k script through k-host on a pseudo-terminal; print the transcript.

Usage: run_host.py K_COMMAND SCRIPT.k   (K_COMMAND may include a runner,
       e.g. "qemu-aarch64 -cpu cortex-a72 ./k-aarch64")

k reads its input with read(fd = <result of writing the ' ' prompt> = 1),
so stdout must be a readable terminal -- a pipe makes it spin. A pty
satisfies that, exactly as an interactive session does.
"""
import os, pty, select, shlex, sys, time

kbin, script = sys.argv[1], sys.argv[2]
lines = [l.rstrip("\n") for l in open(script) if l.strip() and not l.startswith("#")]

pid, fd = pty.fork()
if pid == 0:
    argv = shlex.split(kbin)
    os.execvp(argv[0], argv)

# Raw-ish: no echo from the line discipline, so the transcript shows only
# what k itself writes plus the inputs we record explicitly.
import termios, tty
attrs = termios.tcgetattr(fd); attrs[3] &= ~termios.ECHO; termios.tcsetattr(fd, termios.TCSANOW, attrs)

out = bytearray()
def pump(t):
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return False
            if not d: return False
            out.extend(d)
    return True

def until_prompt(cap):
    """Read until k is waiting for input: output ends with its ' ' prompt and
    has been quiet for a moment. Pacing by k, not by a fixed delay, keeps slow
    emulators from shifting answers onto the wrong input line."""
    end, quiet = time.time() + cap, 0.0
    while time.time() < end:
        n = len(out)
        if not pump(0.1): return False
        quiet = quiet + 0.1 if len(out) == n else 0.0
        if quiet >= 0.3 and out.endswith(b" "): return True
    return True

CAP = float(os.environ.get("K_STEP_MAX", "30"))
until_prompt(CAP)
for line in lines:
    os.write(fd, line.encode() + b"\n")
    out.extend(b"<<" + line.encode() + b"\n")   # mark input in the transcript
    if not until_prompt(CAP): break
pump(0.2)
try: os.kill(pid, 9)
except ProcessLookupError: pass
sys.stdout.write(out.decode("latin1").replace("\r", ""))
