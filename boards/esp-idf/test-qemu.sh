#!/usr/bin/env bash
# boards/esp-idf/test-qemu.sh -- run the built ESP-IDF firmware in Espressif's
# QEMU and check it against test/golden/*.k over the emulated UART0.
#
#   . $IDF_PATH/export.sh
#   boards/esp-idf/test-qemu.sh
#
# It builds its own variant in build-qemu/: Espressif's QEMU does not bring up
# the S3's PSRAM, so sdkconfig.qemu turns PSRAM off and k's heap goes in
# internal SRAM, 128 KiB (QEMU_KHEAP=11; 12 leaves too little RAM for k's
# task stack). The board build in build/ is untouched.
# Needs Espressif's QEMU: python $IDF_PATH/tools/idf_tools.py install qemu-xtensa
# (ESP32-S3 machine; there is no ESP32-P4 machine). The flash and eFuse images
# are made the same way `idf.py qemu` makes them.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
BUILD="$HERE/build-qemu"
[[ -n ${IDF_PATH:-} ]] || { echo "source \$IDF_PATH/export.sh first" >&2; exit 2; }
(cd "$HERE" && idf.py -B build-qemu -DSDKCONFIG=build-qemu/sdkconfig -DIDF_TARGET=esp32s3 -DK_HEAP="${QEMU_KHEAP:-11}" \
    -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.esp32s3;sdkconfig.qemu" build >/dev/null)
FLASH_SIZE=$(sed -n 's/^CONFIG_ESPTOOLPY_FLASHSIZE="\(.*\)"/\1/p' "$BUILD/sdkconfig")

(cd "$BUILD" && python -m esptool --chip=esp32s3 merge_bin --output=qemu_flash.bin \
    --fill-flash-size="$FLASH_SIZE" @flash_args >/dev/null)
python - "$BUILD/qemu_efuse.bin" <<'EOF'
import sys, os
sys.path.insert(0, os.path.join(os.environ["IDF_PATH"], "tools"))
from idf_py_actions.qemu_ext import QEMU_TARGETS
open(sys.argv[1], "wb").write(QEMU_TARGETS["esp32s3"].default_efuse)
EOF

QEMU=(qemu-system-xtensa -M esp32s3
      -drive "file=$BUILD/qemu_flash.bin,if=mtd,format=raw"
      -drive "file=$BUILD/qemu_efuse.bin,if=none,format=raw,id=efuse"
      -global driver=nvram.esp32c3.efuse,property=drive,value=efuse
      -nic none -display none -monitor none -serial stdio -no-reboot)
fail=0
# 128 KiB heap: run the goldens that fit (big.k needs KHEAP>=12).
for k in "$ROOT"/test/golden/basic.k; do
    out="$BUILD/$(basename "$k" .k).qemu.out"
    if timeout 900 python3 "$ROOT/test/drive_qemu.py" "$k" "${QEMU[@]}" > "$out" &&
       diff -u "${k%.k}.expected" "$out"; then
        echo "PASS esp32s3-qemu $(basename "$k")"
    else echo "FAIL esp32s3-qemu $(basename "$k") (see $out)"; fail=1; fi
done
exit $fail
