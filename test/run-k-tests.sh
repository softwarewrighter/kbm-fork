#!/usr/bin/env bash
# run-k-tests.sh -- boot k-on-BareMetal headlessly in Bochs and run k scripts.
#
# Usage: test/run-k-tests.sh [script.k ...]     (default: test/*.k)
# For each script.k, writes script.out (raw serial transcript) and, if
# script.expected exists, diffs the normalized transcript against it.
#
# Requires: bochs (2.7+, with debugger is fine), seabios, python3, and a
# test/out/k-serial.img from make-serial-image.sh (built automatically).
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"
PORT=14501
BOOT_TIMEOUT=${BOOT_TIMEOUT:-600}

[[ -f out/k-serial.img && out/k-serial.img -nt ../../BareMetal-OS-2024/sys/k.app ]] || ./make-serial-image.sh

scripts=("$@")
(( ${#scripts[@]} )) || scripts=(*.k)

stop_bochs() {
    local p; p=$(pgrep -x bochs-bin || true)
    [[ -n "$p" ]] && kill -9 $p 2>/dev/null || true
    sleep 1
    rm -f out/k-serial.img.lock
}
trap stop_bochs EXIT

fail=0
for k in "${scripts[@]}"; do
    name=${k%.k}
    stop_bochs
    rm -f bochslog.txt "$name.out"
    # Bochs's term display needs a tty; `script` provides a pty.
    # `-rc ../bochsrc` (contains "c") continues past the built-in debugger prompt.
    (TERM=xterm timeout "$BOOT_TIMEOUT" script -qfec \
        "bochs -q -f bochs-headless.rc -rc ../bochsrc" /dev/null >/dev/null 2>&1 &)
    if ! timeout "$BOOT_TIMEOUT" python3 drive_k.py "localhost:$PORT" "$k" "$name.out"; then
        echo "FAIL $k (driver error)"; fail=1; continue
    fi
    if grep -q '>>PANIC<<\|resetting' bochslog.txt; then
        echo "FAIL $k (emulator panic/triple fault, see bochslog.txt)"; fail=1; continue
    fi
    if [[ -f "$name.expected" ]]; then
        if diff -u "$name.expected" <(tr -d '\r' < "$name.out" | sed -n '/whitney/,$p'); then
            echo "PASS $k"
        else
            echo "FAIL $k (transcript differs)"; fail=1
        fi
    else
        echo "RAN  $k (no .expected; transcript in $name.out)"
    fi
done
exit $fail
