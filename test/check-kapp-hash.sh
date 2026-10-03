#!/usr/bin/env bash
# test/check-kapp-hash.sh -- prove the original kbm build is unchanged.
#
#   test/check-kapp-hash.sh [path/to/BareMetal-OS-2024]
#
# Builds kbm exactly as shipped (clang, AVX-512, `make` with no options)
# against the Dec-2024 BareMetal set (test/pin-baremetal-2024.sh) and
# compares k.app with the reference hash. k's banner embeds __DATE__, so the
# build date is pinned with SOURCE_DATE_EPOCH (clang honours it); without
# that, the hash changes every day.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
B=$(cd -- "${1:-$ROOT/../BareMetal-OS-2024}" && pwd)
WANT=c1d8062886cdb222d710105a26c97e6e68bbd82f0b7674e65d74eb8fa5c63d03
export SOURCE_DATE_EPOCH=1790942400   # 2026-10-02 12:00 UTC, the reference build's date
cd "$ROOT"
make -s clean B="$B" >/dev/null 2>&1 || true
make -s B="$B" >/dev/null
GOT=$(sha256sum "$B/sys/k.app" | cut -d' ' -f1)
if [[ $GOT == "$WANT" ]]; then echo "PASS k.app byte-identical ($GOT)"
else echo "FAIL k.app $GOT, expected $WANT"; exit 1; fi
