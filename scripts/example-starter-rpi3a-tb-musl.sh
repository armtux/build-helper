#!/bin/sh

set -e

STARTER_TIME="$(date -u +%Y%m%dT%H%M%SZ)"
STARTER_PATH=$(readlink -f "$0")
cd $(dirname "${STARTER_PATH}")
[ ! -e ../logs ] && mkdir -p ../logs

export MAKEOPTS="${MAKEOPTS} -j$(nproc)"
# change VIDEO_CARDS_NATIVE for your native target's hardware
export VIDEO_CARDS_NATIVE="intel"
export MNT_TYPE="bind"
export HIST_TYPE="files"
export TMP_TYPE="tmpfs"

HELPER_CMD="./build-helper.sh aarch64-gentoo-linux-musl rpi3a-tb-musl"

if [ "${TERM_PROGRAM}" = "tmux" ]
then
	${HELPER_CMD} 2>&1
else
	${HELPER_CMD} 2>&1 | tee ../logs/rpi3a-tb-musl-${STARTER_TIME}.log
fi
