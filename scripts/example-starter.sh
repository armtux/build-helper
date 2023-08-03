#!/bin/sh

cd $(readlink -f "$0")
TARBALL_MIRROR="https://mirror.csclub.uwaterloo.ca/gentoo-distfiles" \
MNT_TYPE="bind" HIST_TYPE="squashfs" TMP_TYPE="tmpfs" \
./build-helper.sh aarch64-unknown-linux-musl rpi4b
