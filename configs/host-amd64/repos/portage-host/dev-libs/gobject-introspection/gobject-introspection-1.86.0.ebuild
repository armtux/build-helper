# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
PYTHON_REQ_USE="xml(+)"
inherit gnome.org meson python-single-r1 xdg

DESCRIPTION="Introspection system for GObject-based libraries"
HOMEPAGE="https://gi.readthedocs.io/"

LICENSE="FSFUL GPL-2+ LGPL-2+"
SLOT="0"

KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~m68k ~mips ppc ppc64 ~riscv ~s390 ~sparc x86 ~x64-macos ~x64-solaris"

IUSE="doctool gtk-doc test"
RESTRICT="!test? ( test )"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

# virtual/pkgconfig needed at runtime, bug #505408
RDEPEND="
	>=dev-libs/gobject-introspection-common-${PV}
	>=dev-libs/glib-2.82.0:2[introspection]
	dev-libs/libffi:=
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
	')
	doctool? (
		$(python_gen_cond_dep '
			dev-python/mako[${PYTHON_USEDEP}]
			dev-python/markdown[${PYTHON_USEDEP}]
		')
	)
	virtual/pkgconfig
	${PYTHON_DEPS}
"
# Wants real bison, not app-alternatives/yacc
DEPEND="${RDEPEND}"
BDEPEND="
	gtk-doc? (
		>=dev-util/gtk-doc-1.19
		app-text/docbook-xml-dtd:4.3
		app-text/docbook-xml-dtd:4.5
	)
	>=dev-build/meson-1.4.0
	sys-devel/bison
	app-alternatives/lex
	test? (
		x11-libs/cairo[glib]
		$(python_gen_cond_dep '
			dev-python/mako[${PYTHON_USEDEP}]
			dev-python/markdown[${PYTHON_USEDEP}]
		')
	)
"

PATCHES=(
	"${FILESDIR}"/${PN}-1.86.0-tests-setuptools.patch
)

pkg_setup() {
	python-single-r1_pkg_setup
}

src_configure() {
	local emesonargs=(
		$(meson_feature test cairo)
		# Enable building the tests (and installing them) unconditionally
		# for now as a workaround for old gnome-extra/cjs and dev-libs/gjs,
		# see bug #952011.
		#$(meson_use test tests)
		-Dtests=true
		$(meson_feature doctool)
		#-Dglib_src_dir
		$(meson_use gtk-doc gtk_doc)
		#-Dcairo_libname
		-Dpython="${EPYTHON}"
		-Dbuild_introspection_data=true
		#-Dgir_dir_prefix
		# Point to custom wrappers for gobject-introspection tools when cross-compiling.
		$(tc-is-cross-compiler && echo -n "-Dgi_cross_use_prebuilt_gi=true -Dgi_cross_binary_wrapper=$(sysroot_make_run_prefixed) -Dgi_cross_ldd_wrapper=$(sysroot_make_cross_introspection_lddwrapper) -Dgi_cross_pkgconfig_sysroot_path=${ROOT}")
	)
	# Look for libraries in ROOT when cross-compiling to avoid confusion in wrapped
	# gobject-introspection tools when cross-compiling.
	if tc-is-cross-compiler ; then
		export CC="$(tc-getCC) -L${ROOT}/$(get_libdir)"
	fi
	meson_src_configure
}

src_install() {
	meson_src_install
	python_fix_shebang "${ED}"/usr/bin/
	python_optimize "${ED}"/usr/$(get_libdir)/gobject-introspection/giscanner

	# Prevent collision with gobject-introspection-common
	rm -v "${ED}"/usr/share/aclocal/introspection.m4 \
		"${ED}"/usr/share/gobject-introspection-1.0/Makefile.introspection || die
	rmdir "${ED}"/usr/share/aclocal || die
}
