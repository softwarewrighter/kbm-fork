#!/usr/bin/env bash
# boards/linux/test-on-board.sh -- run the golden transcripts against k on a
# real board, from the development machine.
#
#   boards/linux/test-on-board.sh user@board /root/k-licheerv-nano-rv64
#
# k reads its input from its terminal (fd 1), so it needs a tty: `ssh -tt`
# gives it one. Nothing beyond sshd and the k binary is needed on the board.
# For a serial-only board, see docs/hw-bringup/linux-boards.md.
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 user@host /path/to/k-on-board" >&2; exit 2; }
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
fail=0
for k in "$ROOT"/test/golden/*.k; do
    got=$(K_STEP=${K_STEP:-1.5} python3 "$ROOT/test/host/run_host.py" "ssh -tt -o BatchMode=yes $1 $2" "$k" | tail -n +2)
    if diff -u "${k%.k}.expected" <(printf '%s\n' "$got"); then
        echo "PASS on-board $(basename "$k")"
    else echo "FAIL on-board $(basename "$k")"; fail=1; fi
done
exit $fail
