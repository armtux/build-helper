#!/bin/sh

set -e

STARTER_TIME="$(date -u +%Y%m%dT%H%M%SZ)"
STARTER_PATH=$(readlink -f "$0")
cd $(dirname "${STARTER_PATH}")
[ ! -e ../logs ] && mkdir -p ../logs

export MAKEOPTS="${MAKEOPTS} -j$(nproc)"
# change VIDEO_CARDS_NATIVE for your native target's hardware
#export VIDEO_CARDS_NATIVE="intel amdgpu nouveau radeonsi radeon virgl"
export MNT_TYPE="bind"
export HIST_TYPE="files"
export TMP_TYPE="tmpfs"
export MOUNT_HIST="${MOUNT_HIST:-no}"
export GENTOO_MIRRORS="${GENTOO_MIRRORS}"
export TARBALL_MIRROR="${TARBALL_MIRROR:-}"

if [ "${BUILD_HIST}" = "no" ]
then
	export BUILD_HIST='no'
fi

HELPER_CMD="./build-helper.sh m68k-unknown-linux-musl marchintosh"

if [ "${TERM_PROGRAM}" = "tmux" ]
then
	${HELPER_CMD} 2>&1
else
	${HELPER_CMD} 2>&1 | tee ../logs/marchintosh-${STARTER_TIME}.log
fi
