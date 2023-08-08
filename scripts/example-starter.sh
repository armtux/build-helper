#!/bin/sh

set -e

STARTER_TIME="$(date -Iseconds)"
STARTER_PATH=$(readlink -f "$0")
cd $(dirname "${STARTER_PATH}")
[ ! -e ../logs ] && mkdir -p ../logs

TARBALL_MIRROR="https://mirror.csclub.uwaterloo.ca/gentoo-distfiles" \
MNT_TYPE="bind" HIST_TYPE="squashfs" TMP_TYPE="tmpfs" \
./build-helper.sh aarch64-unknown-linux-musl rpi4b 2>&1 \
$([ "${TERM_PROGRAM}" != "tmux" ] && echo -n "| tee ../logs/rpi4b-${STARTER_TIME}.log")
