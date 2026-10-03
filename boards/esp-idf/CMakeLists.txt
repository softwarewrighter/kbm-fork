# boards/esp-idf -- k on ESP32-S3 / ESP32-P4 with ESP-IDF.
# k's own sources (ksrc/) are compiled by ESP-IDF's GCC in components/k.
# See README.md here, and docs/hw-bringup/esp32-s3.md / esp32-p4.md.
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(k_esp)
