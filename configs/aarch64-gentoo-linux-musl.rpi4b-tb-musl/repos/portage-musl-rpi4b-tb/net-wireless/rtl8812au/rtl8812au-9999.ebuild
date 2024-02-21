# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1 git-r3

MY_PN="8812au-20210629"
DESCRIPTION="Realtek 8812AU module for Linux kernel"
HOMEPAGE="https://github.com/morrownr/8812au-20210629"
#SRC_URI="https://github.com/morrownr/${MY_PN}/archive/${COMMIT}.tar.gz -> ${P}.tar.gz"
#S="${WORKDIR}/${MY_PN}-${COMMIT}"
EGIT_REPO_URI="https://github.com/morrownr/8812au-20210629"
EGIT_CLONE_TYPE="shallow"

SLOT=0
LICENSE="GPL-2"
KEYWORDS="~amd64 ~x86 ~arm ~arm64"

src_compile() {
	linux-mod-r1_pkg_setup

	local modlist=( 8812au=net/wireless )
	local modargs=( KSRC="${KV_OUT_DIR}" )
	linux-mod-r1_src_compile
}
