# components/k: k's C sources (ksrc/, shared with every other target) plus
# its OS layer for ESP-IDF. Compiled by ESP-IDF's GCC with the flags k needs
# (ksrc/README.md).
set(KSRC ${CMAKE_CURRENT_LIST_DIR}/../../../../ksrc)
set(KBARE ${CMAKE_CURRENT_LIST_DIR}/../../../mcu/common)

idf_component_register(
    SRCS "${KSRC}/a.c" "${KSRC}/z.c" "${KBARE}/ksys-bare.c" "con_esp.c"
    INCLUDE_DIRS "."
    PRIV_INCLUDE_DIRS "${KSRC}"
    PRIV_REQUIRES esp_driver_uart esp_driver_usb_serial_jtag)

# Heap: in PSRAM when .bss may live there (16 MiB on boards with 8 MB PSRAM is
# too much with IDF's own PSRAM use, so 4 MiB), else 256 KiB of internal SRAM.
# Override: idf.py -DK_HEAP=n build   (heap = 64 << n bytes, see ksrc/kheap.h)
if(NOT DEFINED K_HEAP)
    if(CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY)
        set(K_HEAP 16)
    else()
        set(K_HEAP 12)
    endif()
endif()
set(K_DEFS KSYS main=k_main KHEAP=${K_HEAP} KOBJ=10)
if(CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY)
    list(APPEND K_DEFS "KHEAP_ATTR=__attribute__((section(\".ext_ram.bss\")))")
endif()
message(STATUS "k: heap 2^${K_HEAP} x 64 bytes")

set_source_files_properties("${KSRC}/a.c" "${KSRC}/z.c" PROPERTIES
    COMPILE_DEFINITIONS "${K_DEFS}"
    COMPILE_OPTIONS "-Ofast;-flax-vector-conversions;-fno-strict-aliasing;-fno-builtin;-funsigned-char;-Wno-incompatible-pointer-types;-Wno-attributes;-Wno-psabi;-Wno-pointer-to-int-cast;-Wno-int-to-pointer-cast;-Wno-parentheses;-Wno-unused-function;-Wno-unused-variable;-Wno-unused-value;-Wno-unused-but-set-variable;-Wno-return-type;-Wno-sign-compare;-Wno-implicit-fallthrough;-Wno-maybe-uninitialized;-Wno-int-conversion;-Wno-format;-Wno-char-subscripts;-Wno-array-bounds;-Wno-stringop-overflow;-Wno-stringop-overread;-Wno-error")
