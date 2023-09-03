#!/bin/sh

set -e

STARTER_TIME="$(date -u +%Y%m%dT%H%M%SZ)"
STARTER_PATH=$(readlink -f "$0")
cd $(dirname "${STARTER_PATH}")
[ ! -e ../logs ] && mkdir -p ../logs

export MAKEOPTS="${MAKEOPTS} -j$(nproc)"
# change VIDEO_CARDS_NATIVE for your native target's hardware
export VIDEO_CARDS_NATIVE="amdgpu radeonsi radeon virgl"
export MNT_TYPE="bind"
export HIST_TYPE="squashfs"
export TMP_TYPE="tmpfs"

HELPER_CMD="./build-helper.sh aarch64-unknown-linux-musl:aarch64-unknown-linux-musl:armv6j-unknown-linux-musleabihf:x86_64-unknown-linux-musl rpi4b:rpi3b:rpi01:native"

[ "${TERM_PROGRAM}" = "tmux" ] && ${HELPER_CMD} 2>&1 || \
(${HELPER_CMD} 2>&1 | tee ../logs/rpi4b-${STARTER_TIME}.log)
