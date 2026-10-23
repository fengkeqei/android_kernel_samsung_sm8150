#!/bin/bash
# Build the official US SM-G973U Android 12 kernel (4.14.190, beyond1qlte)
# with the Snapdragon LLVM (clang 10.0.6) + NDK r16b binutils toolchain.
#
# Usage: ./build_usa190.sh [--clean]
#   TOOLCHAIN_DIR  base dir holding llvm-arm-toolchain-ship-10.0/,
#                  ndk-r16b/, tools/make-4.3/   (default: /home/dev/Projects/toolchain)
#   OUT_DIR        out-of-tree build dir        (default: $TOOLCHAIN_DIR/out-usa190)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLCHAIN_DIR=${TOOLCHAIN_DIR:-/home/dev/Projects/toolchain}
T=$TOOLCHAIN_DIR
MAKE=$T/tools/make-4.3/bin/make
CLANG_BIN=$T/llvm-arm-toolchain-ship-10.0/llvm-arm-toolchain-ship/10.0/bin
NDK_BIN=$T/ndk-r16b/android-ndk-r16b/toolchains/aarch64-linux-android-4.9/prebuilt/linux-x86_64/bin
OUT=${OUT_DIR:-$T/out-usa190}
LOG=$OUT/build.log
DEFCONFIG=beyond1qlte_usa_single_defconfig

if [[ ${1:-} == --clean ]]; then rm -rf "$OUT"; fi
mkdir -p "$OUT"

export ARCH=arm64
export CROSS_COMPILE="$NDK_BIN/aarch64-linux-android-"
export REAL_CC="$CLANG_BIN/clang"
export CFP_CC="$CLANG_BIN/clang"
export CLANG_TRIPLE=aarch64-linux-gnu-
export PYTHON=python2
export LD_LIBRARY_PATH="$T/llvm-arm-toolchain-ship-10.0/llvm-arm-toolchain-ship/10.0/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# scripts/link-vmlinux.sh calls plain `python` for CFP instrumentation and the
# FIPS check; that code is python2-only. Map python -> python2.7 via a shim dir.
PY2SHIM=$T/py2bin
mkdir -p "$PY2SHIM"
ln -sf "$(command -v python2.7 || command -v python2)" "$PY2SHIM/python"
export PATH="$PY2SHIM:$CLANG_BIN:$NDK_BIN:$PATH"
# Match the stock OS12 banner (dpi@21DN2A11, #2).
export KBUILD_BUILD_USER=dpi
export KBUILD_BUILD_HOST=21DN2A11
export KBUILD_BUILD_VERSION=2

args=(
  -C "$ROOT" -j8 "O=$OUT" "ARCH=$ARCH"
  "CROSS_COMPILE=$CROSS_COMPILE" "REAL_CC=$REAL_CC" "CFP_CC=$CFP_CC"
  "CLANG_TRIPLE=$CLANG_TRIPLE" "PYTHON=$PYTHON"
  "KBUILD_BUILD_USER=$KBUILD_BUILD_USER" "KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST"
  "KBUILD_BUILD_VERSION=$KBUILD_BUILD_VERSION"
  "DTC_EXT=$ROOT/tools/dtc" "CONFIG_BUILD_ARM64_DT_OVERLAY=y"
  "GIT_BIN=false" "CURL_BIN=false"
)

{
  echo "[+] configure $DEFCONFIG"
  "$MAKE" "${args[@]}" "$DEFCONFIG"
  echo "[+] build Image"
  "$MAKE" "${args[@]}"
  img=$OUT/arch/arm64/boot/Image
  ls -l "$img"
  md5sum "$img"
  echo "[+] done: $img"
} 2>&1 | tee "$LOG"
