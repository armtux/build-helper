# Copyright 2019-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# Autogenerated by pycargoebuild 0.12.1

EAPI=8

CRATES="
	autocfg@1.1.0
	bitflags@1.3.2
	bitvec@1.0.1
	cc@1.0.83
	cfg-if@1.0.0
	dlib@0.5.2
	downcast-rs@1.2.0
	evdev@0.12.1
	funty@2.0.0
	hermit-abi@0.3.3
	io-lifetimes@1.0.11
	libc@0.2.150
	libloading@0.8.1
	log@0.4.20
	memchr@2.6.4
	memoffset@0.6.5
	memoffset@0.7.1
	nix@0.23.2
	nix@0.26.4
	once_cell@1.18.0
	pkg-config@0.3.27
	proc-macro2@1.0.70
	quick-xml@0.28.2
	quote@1.0.33
	radium@0.7.0
	scoped-tls@1.0.1
	smallvec@1.11.2
	syn@2.0.39
	tap@1.0.1
	thiserror@1.0.50
	thiserror-impl@1.0.50
	unicode-ident@1.0.12
	wayland-backend@0.1.2
	wayland-client@0.30.2
	wayland-protocols@0.30.1
	wayland-scanner@0.30.1
	wayland-sys@0.30.1
	windows-sys@0.48.0
	windows-targets@0.48.5
	windows_aarch64_gnullvm@0.48.5
	windows_aarch64_msvc@0.48.5
	windows_i686_gnu@0.48.5
	windows_i686_msvc@0.48.5
	windows_x86_64_gnu@0.48.5
	windows_x86_64_gnullvm@0.48.5
	windows_x86_64_msvc@0.48.5
	wyz@0.5.1
"

#RUST_MULTILIB=1

inherit cargo multilib-minimal rust-toolchain

DESCRIPTION="X11 XTEST Reimplementation for Steam Controller on Wayland"
HOMEPAGE="https://github.com/Supreeeme/extest"
SRC_URI="
	${CARGO_CRATE_URIS}
	https://github.com/Supreeeme/extest/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
"

LICENSE="Apache-2.0 Apache-2.0-with-LLVM-exceptions ISC MIT Unicode-DFS-2016 Unlicense"
SLOT="0"
KEYWORDS="~amd64 ~x86"

RDEPEND="
	dev-libs/libevdev[${MULTILIB_USEDEP}]
	dev-libs/wayland[${MULTILIB_USEDEP}]
"

# rust does not use *FLAGS from make.conf, silence portage warning
# update with proper path to binaries this crate installs, omit leading /
QA_FLAGS_IGNORED="
	usr/lib/lib${PN}.so
	usr/lib64/lib${PN}.so
"

src_prepare() {
	default
	multilib_copy_sources
}

multilib_src_compile() {
	cargo_src_compile --target="$(rust_abi)"
}

multilib_src_test() {
	cargo_src_test --target="$(rust_abi)"
}

multilib_src_install() {
	dolib.so "${BUILD_DIR}/target/$(rust_abi)/$(usex debug "debug" "release")/libextest.so"
}

pkg_postinst() {
	elog "In order to create the required virtual device ${PN} requires"
	elog "that your users is added to the input group."
}
