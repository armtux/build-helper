# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit autotools toolchain-funcs

DESCRIPTION="LibTomCrypt is a comprehensive, modular and portable cryptographic toolkit"
HOMEPAGE="https://www.libtom.net/LibTomCrypt/ https://github.com/libtom/libtomcrypt"
SRC_URI="
	https://github.com/libtom/${PN}/releases/download/v${PV}/crypt-${PV}.tar.xz
		-> ${P}.tar.xz"

LICENSE="|| ( WTFPL-2 public-domain )"
# Current SONAME is 1
# Please bump when the ABI changes upstream
# Helpful site:
# https://abi-laboratory.pro/index.php?view=timeline&l=libtomcrypt
SLOT="0/1"
KEYWORDS="~alpha amd64 arm arm64 hppa ~ia64 ~loong ~m68k ~mips ppc ppc64 ~riscv ~s390 sparc x86 ~amd64-linux ~x86-linux ~arm64-macos ~ppc-macos ~x64-macos ~x64-solaris"
IUSE="+gmp +libtommath tomsfastmath"

# Enforce at least one math provider
# bug #772935
REQUIRED_USE="|| ( gmp libtommath tomsfastmath )"

BDEPEND="
	sys-devel/libtool
	virtual/pkgconfig
"
DEPEND="
	gmp? ( dev-libs/gmp:= )
	libtommath? ( dev-libs/libtommath:= )
	tomsfastmath? ( dev-libs/tomsfastmath:= )
"
RDEPEND="${DEPEND}"

PATCHES=(
	"${FILESDIR}"/${P}-slibtool.patch
)

src_prepare() {
	default

	# need libtool for cross compilation, bug #376643
	cat <<-EOF > configure.ac
	AC_INIT(libtommath, 0)
	AM_INIT_AUTOMAKE
	LT_INIT
	AC_CONFIG_FILES(Makefile)
	AC_OUTPUT
	EOF

	touch NEWS README AUTHORS ChangeLog Makefile.am || die

	eautoreconf

	export LIBTOOL="${S}"/libtool
}

mymake() {
	# Standard boilerplate
	# Upstream use homebrewed makefiles
	# Best to use same args for all, for consistency,
	# in case behaviour changes (v possible).
	local enabled_features=()
	local extra_libs=()

	# Build support as appropriate for consumers (MPI)
	if use gmp; then
		enabled_features+=( -DGMP_DESC=1 )
		extra_libs+=( -lgmp )
	fi
	if use libtommath; then
		enabled_features+=( -DLTM_DESC=1 )
		extra_libs+=( -ltommath )
	fi
	if use tomsfastmath; then
		enabled_features+=( -DTFM_DESC=1 )
		extra_libs+=( -ltfm )
	fi

	# For the test and example binaries, we have to choose
	# which MPI we want to use.
	# For now (see src_test), arbitrarily choose:
	# gmp > libtommath > tomsfastmath > none
	if use gmp ; then
		enabled_features+=( -DUSE_GMP=1 )
	elif use libtommath ; then
		enabled_features+=( -DUSE_LTM=1 )
	elif use tomsfastmath ; then
		enabled_features+=( -DUSE_TFM=1 )
	fi

	# IGNORE_SPEED=1 is needed to respect CFLAGS
	EXTRALIBS="${extra_libs[*]}" emake \
		CFLAGS="${CFLAGS} ${enabled_features[*]}" \
		CC="$(tc-getCC)" \
		AR="$(tc-getAR)" \
		LTCC="$(tc-getCC)" \
		RANLIB="$(tc-getRANLIB)" \
		LIBPATH="${EPREFIX}/usr/$(get_libdir)" \
		INCPATH="${EPREFIX}/usr/include" \
		IGNORE_SPEED=1 \
		PREFIX="${EPREFIX}/usr" \
		"${@}"
}

src_compile() {
	# Replace hard-coded libdir=${exec_prefix}/lib.
	sed -i -e "/libdir=/s:/lib:/$(get_libdir):" libtomcrypt.pc.in || die

	mymake -f makefile.shared library
}

src_test() {
	# libtomcrypt can build with several MPI providers
	# but the tests can only be built with one at a time.
	# When the next release (> 1.18.2) containing
	# 1) https://github.com/libtom/libtomcrypt/commit/a65cfb8dbe4
	# 2) https://github.com/libtom/libtomcrypt/commit/fdc6cd20137
	# is made, we can run tests for each provider.
	mymake test
	./test || die "Running tests failed"
}

src_install() {
	mymake -f makefile.shared \
		DATAPATH="${EPREFIX}/usr/share/doc/${PF}" \
		DESTDIR="${D}" \
		install install_docs

	find "${ED}" '(' -name '*.la' -o -name '*.a' ')' -delete || die
}
