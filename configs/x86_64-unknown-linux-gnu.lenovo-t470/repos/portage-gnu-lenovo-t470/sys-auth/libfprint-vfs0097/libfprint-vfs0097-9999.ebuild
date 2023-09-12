# Copyright 2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 meson

DESCRIPTION="libfprint TOD driver for Validity Sensors 0097"
HOMEPAGE="https://gitlab.freedesktop.org/3v1n0/libfprint-tod-vfs0090"
EGIT_REPO_URI="https://gitlab.freedesktop.org/3v1n0/libfprint-tod-vfs0090.git"

LICENSE="LGPL-3+"
SLOT="0"
KEYWORDS="amd64"

DEPEND="sys-auth/libfprint"
RDEPEND="${DEPEND}"
