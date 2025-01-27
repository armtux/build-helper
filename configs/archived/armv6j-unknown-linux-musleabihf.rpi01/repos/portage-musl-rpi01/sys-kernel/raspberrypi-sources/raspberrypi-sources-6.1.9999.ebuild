# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ETYPE=sources
K_DEFCONFIG="bcmrpi_defconfig"
K_SECURITY_UNSUPPORTED=1
EXTRAVERSION="-${PN}/-*"

K_EXP_GENPATCHES_NOUSE=1
K_GENPATCHES_VER=58
K_DEBLOB_AVAILABLE=0
K_WANT_GENPATCHES="base extras"

inherit kernel-2 linux-info git-r3
detect_version
detect_arch

MY_P=$(ver_cut 4-)
MY_P="1.${MY_P/p/}"

DESCRIPTION="Raspberry Pi kernel sources"
HOMEPAGE="https://github.com/raspberrypi/linux"
EGIT_REPO_URI="https://github.com/raspberrypi/linux.git -> raspberrypi-linux.git"
EGIT_BRANCH="rpi-$(ver_cut 1-2).y"
EGIT_CHECKOUT_DIR="${WORKDIR}/linux-${PV}-raspberrypi"
EGIT_CLONE_TYPE="shallow"
#	https://github.com/raspberrypi/linux/archive/${MY_P}.tar.gz -> linux-${KV_FULL}.tar.gz
SRC_URI="
	${GENPATCHES_URI}
"

KEYWORDS="~arm ~arm64"

PATCHES=("${FILESDIR}"/${PN}-6.1.21-gentoo-kconfig.patch)

UNIPATCH_EXCLUDE="
	10*
	15*
	1700
	2000
	29*
	3000
	4567"

pkg_setup() {
	ewarn ""
	ewarn "${PN} is *not* supported by the Gentoo Kernel Project in any way."
	ewarn "If you need support, please contact the raspberrypi developers directly."
	ewarn "Do *not* open bugs in Gentoo's bugzilla unless you have issues with"
	ewarn "the ebuilds. Thank you."
	ewarn ""

	kernel-2_pkg_setup
}

universal_unpack() {
	#unpack linux-${KV_FULL}.tar.gz
	git-r3_src_unpack
	# We want to rename the unpacked directory to a nice normalised string
	# bug #762766
	#mv "${WORKDIR}"/linux-${MY_P} "${WORKDIR}"/linux-${KV_FULL} || die

	# remove all backup files
	find . -iname "*~" -exec rm {} \; 2>/dev/null
}

src_prepare() {
	default
	kernel-2_src_prepare
}

pkg_postinst() {
	kernel-2_pkg_postinst
}

pkg_postrm() {
	kernel-2_pkg_postrm
}
