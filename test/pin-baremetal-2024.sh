#!/usr/bin/env bash
# pin-baremetal-2024.sh -- reproduce the BareMetal-OS that kbm was written
# against (last kbm commit: 2024-12-10).
#
# Why: `baremetal.sh setup` clones every component at HEAD. Since then:
#   - the BareMetal kernel's history was squashed (Jan 2026),
#   - its ATA/AHCI/NVMe storage drivers were dropped (virtio-blk only),
# and Bochs -- the emulator kbm's README uses, because it emulates AVX-512 --
# has no virtio device. So HEAD BareMetal boots in Bochs but cannot read
# k.app from disk. The Dec-2024 kernel survives only as an ancestor of a
# GitHub pull-request ref, which this script fetches explicitly.
#
# Output: $DEST (default ../../BareMetal-OS-2024) with sys/ built, ready for
#         `make B=$DEST` in kbm-fork.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEST=${DEST:-$HERE/../../BareMetal-OS-2024}
GH=https://github.com/ReturnInfinity

# component  commit   date        note
PINS=(
  "BareMetal-OS      082cf8a  2024-12-10 build script"
  "BareMetal         05c5935  2024-12-07 kernel, still has ata.asm (via PR refs)"
  "Pure64            f6b6f49  2024-12-08 loader"
  "BareMetal-Monitor 880b926  2024-11-28 monitor"
  "BMFS              4ea1c23  2024-11-22 filesystem tools"
  "BareMetal-Demo    7f24592  2024-12-10 demo apps"
)

fetch_pin() { # repo dir commit
    local repo=$1 dir=$2 commit=$3
    if [[ ! -d "$dir/.git" ]]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$GH/$repo.git"
    fi
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$dir" fetch -q --shallow-since=2024-06-01 origin \
            '+refs/heads/*:refs/remotes/origin/*' '+refs/pull/*/head:refs/remotes/pr/*' || true
    fi
    git -C "$dir" -c advice.detachedHead=false checkout -q "$commit"
    echo "  $repo @ $(git -C "$dir" log -1 --format='%h %ad' --date=short)"
}

echo "Pinning BareMetal components into $DEST"
read -r _ c _ <<<"${PINS[0]}"
fetch_pin BareMetal-OS "$DEST" "$c"
mkdir -p "$DEST/src" "$DEST/sys"
for p in "${PINS[@]:1}"; do
    read -r repo c _ <<<"$p"
    fetch_pin "$repo" "$DEST/src/$repo" "$c"
done

cd "$DEST"
# The components' own setup.sh scripts curl libBareMetal.* from BareMetal
# *master*, which no longer matches a pinned kernel (b_storage_* was later
# renamed b_nvs_*). Do their work by hand with the pinned API instead.
API="$DEST/src/BareMetal/api"
(cd src/BareMetal-Monitor && ./clean.sh >/dev/null 2>&1 || true
 mkdir -p src/api bin && cp "$API/libBareMetal.asm" src/api/ && ./build.sh >/dev/null)
(cd src/BareMetal-Demo && ./clean.sh >/dev/null 2>&1 || true
 cp "$API"/libBareMetal.{asm,c,h} src/ && mkdir -p bin)
./baremetal.sh build >/dev/null
./baremetal.sh install >/dev/null
echo "Built: $DEST/sys/baremetal_os.img"
