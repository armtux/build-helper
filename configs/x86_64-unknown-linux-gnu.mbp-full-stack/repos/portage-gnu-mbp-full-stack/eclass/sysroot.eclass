# Copyright 2025-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: sysroot.eclass
# @MAINTAINER:
# cross@gentoo.org
# @AUTHOR:
# James Le Cuirot <chewi@gentoo.org>
# @SUPPORTED_EAPIS: 7 8 9
# @BLURB: Common functions for using a different (sys)root
# @DESCRIPTION:
# This eclass provides common functions to run executables within a different
# root or sysroot, with or without emulation by QEMU. Despite the name, these
# functions can be used in src_* or pkg_* phase functions.

case ${EAPI} in
	7|8|9) ;;
	*) die "${ECLASS}: EAPI ${EAPI:-0} not supported" ;;
esac

# @FUNCTION: qemu_arch
# @DESCRIPTION:
# Return the QEMU architecture name for the given target or CHOST. This name is
# used in qemu-user binary filenames, e.g. qemu-ppc64le.
qemu_arch() {
	local target=${1:-${CHOST}}
	case ${target} in
		armeb*) echo armeb ;;
		arm*) echo arm ;;
		hppa*) echo hppa ;;
		i?86*) echo i386 ;;
		m68*) echo m68k ;;
		mips64el*-gnuabi64) echo mips64el ;;
		mips64el*-gnuabin32) echo mipsn32el ;;
		mips64*-gnuabi64) echo mips64 ;;
		mips64*-gnuabin32) echo mipsn32 ;;
		powerpc64le*) echo ppc64le ;;
		powerpc64*) echo ppc64 ;;
		powerpc*) echo ppc ;;
		*) echo "${target%%-*}" ;;
	esac
}

# @FUNCTION: qemu_arch_if_needed
# @DESCRIPTION:
# If QEMU is needed to run binaries for the given target or CHOST on the build
# system, return the QEMU architecture, otherwise return status code 1.
qemu_arch_if_needed() {
	local target=${1:-${CHOST}}
	local qemu_arch=$(qemu_arch "${target}")

	# We ideally compare CHOST against CBUILD, but binary packages cache the
	# CBUILD value from the system that originally built them.
	if [[ ${MERGE_TYPE} != binary ]]; then
		if [[ ${qemu_arch} == $(qemu_arch "${CBUILD}") ]]; then
			return 1
		else
			echo "${qemu_arch}"
			return 0
		fi
	fi

	# So for binary packages, compare against the machine hardware name instead.
	# Don't use uname because that may lie. /proc knows the real value.
	case "${qemu_arch}/$(< /proc/sys/kernel/arch)" in
		"${qemu_arch}/${qemu_arch}") return 1 ;;
		arm/armv*) return 1 ;;
		hppa/parisc*) return 1 ;;
		i386/i?86) return 1 ;;
		mips64*/mips64) return 1 ;;
		mipsn32*/mips64) return 1 ;;
		mips*/mips) return 1 ;;
	esac

	echo "${qemu_arch}"
	return 0
}


# @FUNCTION: _sysroot_compile_and_link_test_exe
# @USAGE: <output-path-name>
# @INTERNAL
# @DESCRIPTION:
# Compile and link a test executable that does nothing except to return success.
# The executable is built for the *host* machine using $(tc-getCC), *not* for
# the build machine using $(tc-getBUILD_CC).
_sysroot_compile_and_link_test_exe() {
	[[ -n "${1}" ]] || die 'Must specify test executable path name.'
	local test="${1}"
	echo 'int main(void) { return 0; }' > "${test}.c" || die "failed to write ${test##*/}.c"
	$(tc-getCC) ${CFLAGS} ${CPPFLAGS} ${LDFLAGS} -o "${test}" "${test}.c" || die "failed to build ${test##*/}"
}


# @FUNCTION: sysroot_make_run_prefixed
# @DESCRIPTION:
# Create a wrapper script for directly running executables within a (sys)root
# without changing the root directory. The path to that script is returned. If
# no (sys)root has been set, then return status code 1. If the wrapper cannot be
# created for a permissible reason like QEMU being missing or broken, then
# return status code 2.
#
# The script explicitly uses QEMU if this is necessary and it is available in
# this environment. It may otherwise implicitly use a QEMU outside this
# environment if binfmt_misc has been used with the F flag. It is not feasible
# to add a conditional dependency on QEMU.
sysroot_make_run_prefixed() {
	local QEMU_ARCH SCRIPT MYROOT MYEROOT LIBGCC

	if [[ ${EBUILD_PHASE_FUNC} == src_* ]]; then
		[[ -z ${SYSROOT} ]] && return 1
		SCRIPT="${T}"/sysroot-run-prefixed
		MYROOT=${SYSROOT}
		MYEROOT=${ESYSROOT}

		# Both methods below might need help to find GCC's libs. GCC might not
		# be installed in the SYSROOT. Note that Clang supports this flag too.
		LIBGCC=$($(tc-getCC) ${CPPFLAGS} ${CFLAGS} ${LDFLAGS} -print-libgcc-file-name)
		LIBGCC=${LIBGCC%/*}
	else
		[[ -z ${ROOT} ]] && return 1
		SCRIPT="${T}"/root-run-prefixed
		MYROOT=${ROOT}
		MYEROOT=${EROOT}

		# Both methods below might need help to find GCC's libs. libc++ systems
		# won't have this file, but it's not needed in that case.
		if [[ -f ${EROOT}/etc/ld.so.conf.d/05gcc-${CHOST}.conf ]]; then
			local LIBGCC_A
			mapfile -t LIBGCC_A < "${EROOT}/etc/ld.so.conf.d/05gcc-${CHOST}.conf"
			LIBGCC=$(printf "%s:" "${LIBGCC_A[@]/#/${ROOT}}")
			LIBGCC=${LIBGCC%:}
		fi
	fi

	if [[ ${CHOST} = *-mingw32 || ${CHOST} = *-cygwin ]]; then
		if ! type -P wine >/dev/null; then
			einfo "Wine not found. Continuing without ${SCRIPT##*/} wrapper."
			return 2
		fi

		# UNIX paths can work, but programs will not expect this in %PATH%.
		local winepath="Z:${LIBGCC};Z:${MYEROOT}/bin;Z:${MYEROOT}/usr/bin;Z:${MYEROOT}/$(get_libdir);Z:${MYEROOT}/usr/$(get_libdir)"

		# Assume that Wine can do its own CPU emulation.
		install -m0755 /dev/stdin "${SCRIPT}" <<-EOF || die
			#!/bin/sh
			SANDBOX_ON=0 LD_PRELOAD= WINEPATH="\${WINEPATH}\${WINEPATH+;};${winepath//\//\\}" exec wine "\${@}"
		EOF
	elif [[ ${CHOST} != *-linux-* ]]; then
		einfo "Target is not Linux. Continuing without ${SCRIPT##*/} wrapper."
		return 2
	elif ! QEMU_ARCH=$(qemu_arch_if_needed); then
		local DLINKER
		if [[ "${ABI-${DEFAULT_ABI}}" == "${DEFAULT_ABI}" ]]; then
			# glibc: ld.so is a symlink, ldd is a binary.
			# musl: ld.so doesn't exist, ldd is a symlink.
			local candidate
			for candidate in "${MYEROOT}"/usr/bin/{ld.so,ldd}; do
				if [[ -L ${candidate} ]]; then
					DLINKER=${candidate}
					break
				fi
			done
		else
			# non-default ABI needs a non-default dynamic linker
			SCRIPT+="-${ABI}"
			local test="${SCRIPT}-test"
			_sysroot_compile_and_link_test_exe "${test}"
			read -d '' -r DLINKER < <($(tc-getOBJCOPY) -O binary -j .interp -- "${test}" /dev/stdout)
			DLINKER="${DLINKER:+${MYEROOT}${DLINKER}}"
			[[ -f ${DLINKER} && -x ${DLINKER} ]] || DLINKER=
		fi
		[[ -n ${DLINKER} ]] || die "failed to find dynamic linker"

		# musl symlinks ldd to ld-musl.so to libc.so. We want the ld-musl.so
		# path, not the libc.so path, so don't resolve the symlinks entirely.
		DLINKER=$(readlink -ev "${DLINKER}" || die "failed to find dynamic linker")

		# Using LD_LIBRARY_PATH to set the prefix is not perfect, as it doesn't
		# adjust RUNPATHs, but it is probably good enough.
		install -m0755 /dev/stdin "${SCRIPT}" <<-EOF || die
			#!/bin/sh
			LD_LIBRARY_PATH="\${LD_LIBRARY_PATH}\${LD_LIBRARY_PATH+:}${LIBGCC}:${MYEROOT}/$(get_libdir):${MYEROOT}/usr/$(get_libdir)" exec "${DLINKER}" "\${@}"
		EOF
	else
		# Override MYROOT/SYSROOT value for glib, which requires SYSROOT="/".
		#if [ "${SYSROOT}" = "/" ] ; then
		#	MYROOT="${ROOT}"
		#fi

		# Use QEMU's environment variables rather than its command line
		# arguments to cover both explicit and implicit QEMU usage.
		install -m0755 /dev/stdin "${SCRIPT}" <<-EOF || die
			#!/bin/sh

			# Point to ROOT libdir when executing temporary gobject-introspection binaries.
			if echo "\${@}" | grep -Eq "(introspect-dump)" ; then
				export LD_LIBRARY_PATH="/usr/$(get_libdir)"
			fi

			QEMU_SET_ENV="\${QEMU_SET_ENV}\${QEMU_SET_ENV+,}LD_LIBRARY_PATH=\${LD_LIBRARY_PATH}\${LD_LIBRARY_PATH+:}${LIBGCC}" QEMU_LD_PREFIX="${MYROOT}" exec $(type -P "qemu-${QEMU_ARCH}") "\${@}"
		EOF

		# Meson will fail if the given exe_wrapper does not work, regardless of
		# whether one is actually needed. This is bad if QEMU is not installed
		# and worse if QEMU does not support the architecture. We therefore need
		# to perform our own test up front.
		local test="${SCRIPT}-test"
		_sysroot_compile_and_link_test_exe "${test}"

		if ! "${SCRIPT}" "${test}" &>/dev/null; then
			einfo "Failed to run ${test##*/}. Continuing without ${SCRIPT##*/} wrapper."
			return 2
		fi
	fi

	echo "${SCRIPT}"
}

# @FUNCTION: sysroot_run_prefixed
# @DESCRIPTION:
# Create a wrapper script with sysroot_make_run_prefixed if necessary, and use
# it to execute the given command, otherwise just execute the command directly.
# Return unsuccessfully if the wrapper cannot be created.
sysroot_run_prefixed() {
	local script
	script=$(sysroot_make_run_prefixed)

	case $? in
		0) "${script}" "${@}" ;;
		1) "${@}" ;;
		*) return $? ;;
	esac
}

# @FUNCTION: sysroot_try_run_prefixed
# @DESCRIPTION:
# Create a wrapper script with sysroot_make_run_prefixed if necessary, and use
# it to execute the given command, otherwise just execute the command directly.
# Print a warning and return successfully if the wrapper cannot be created.
sysroot_try_run_prefixed() {
	local script
	script=$(sysroot_make_run_prefixed)

	case $? in
		0) "${script}" "${@}" ;;
		1) "${@}" ;;
		*) ewarn "Unable to run command under prefix: $*" ;;
	esac
}

# @FUNCTION: sysroot_make_cross_introspection_lddwrapper
# @DESCRIPTION:
# Create a gobject-introspection ldd wrapper script with sysroot_make_run_prefixed
# for cross-compiling, and use it in tandem with g-ir-scanner.
# The path to that script is returned.
sysroot_make_cross_introspection_lddwrapper() {
	local LDDWRAPPER="${T}/g-ir-scanner-lddwrapper"
	# The glibc ldd bash script needs to point to ROOT when cross-compiling, so customizing it.
	if use elibc_glibc ; then
		install -m0755 "${ROOT}/bin/ldd" "${T}/custom-ldd"
		sed -i -E 's/\$\{?rtld\}?/${ROOT}${rtld}/' "${T}/custom-ldd"
	fi
	install -m0755 /dev/stdin "${LDDWRAPPER}" <<-EOF || die
		#!/bin/bash

		# Avoid PATH confusion when pointing to binaries.
		FULLCOMMAND="\$(echo "\$@" | sed -E "s#^(/usr)?(/s?bin/)#\${ROOT}/bin/#" | sed -E "s#^([a-z])#\${ROOT}/bin/\\1#")"

		# Avoid loading libraries from anywhere except intended locations.
		unset LD_LIBRARY_PATH
		unset LD_PRELOAD
		export QEMU_SET_ENV="LD_PRELOAD=,LD_LIBRARY_PATH="

		# The glibc ldd is a bash script, while the musl ldd is a binary.
		$(sysroot_make_run_prefixed) \
		\$(echo \${CHOST} | cut -d '-' -f 4 | grep -qv musl && echo -n "\${ROOT}/bin/bash \${T}/custom-ldd" || echo -n "\${ROOT}/bin/ldd") "\${FULLCOMMAND}"
	EOF

	echo "${LDDWRAPPER}"
}

# @FUNCTION: sysroot_make_cross_introspection_qemuwrapper
# @DESCRIPTION:
# Create a gobject-introspection ldd wrapper script with sysroot_make_run_prefixed
# for cross-compiling, and use it in tandem with g-ir-scanner.
# The path to that script is returned.
sysroot_make_cross_introspection_qemuwrapper() {
	local QEMUWRAPPER="${T}/g-ir-scanner-qemuwrapper"
	install -m0755 /dev/stdin "${QEMUWRAPPER}" <<-EOF || die
		#!/bin/sh

		# Avoid PATH confusion when pointing to binaries.
		FULLCOMMAND="\$(echo "\$@" | sed -E "s#^(/usr)?(/s?bin/)#\${ROOT}/bin/#" | sed -E "s#^([a-z])#\${ROOT}/bin/\\1#")"
		# Find file path of binary or script we intend to run from command.
		FILEPATH="\$(echo \${FULLCOMMAND} | cut -d ' ' -f 1)"

		# Set an interpreter for the file we intend to run if it is a script.
		file \${FILEPATH} | grep -q script && INTERPRETER="\${ROOT}/\$(head -n 1 \${FILEPATH} | sed -e 's/^#!//') "

		# Avoid loading libraries from anywhere except intended locations.
		unset LD_PRELOAD
		unset GIO_MODULE_DIR
		# Search for libraries in package presently being installed.
		export LD_LIBRARY_PATH="../../src/.libs:../src/.libs:src/.libs:.libs:\${LD_LIBRARY_PATH}"

		$(sysroot_make_run_prefixed) \${INTERPRETER}\${FULLCOMMAND}
	EOF

	echo "${QEMUWRAPPER}"
}

# @FUNCTION: sysroot_make_cross_introspection_scanner
# @DESCRIPTION:
# Create a gobject-introspection scanner wrapper script with sysroot_make_run_prefixed
# for cross-compiling, and use it instead of g-ir-scanner.
# The path to that script is returned.
sysroot_make_cross_introspection_scanner() {
	local SCANNERWRAPPER="${T}/g-ir-scanner-wrapper"
	install -m0755 /dev/stdin "${SCANNERWRAPPER}" <<-EOF || die
		#!/bin/sh

		# Disable gobject-introspection cache to avoid sandbox violations.
		export GI_SCANNER_DISABLE_CACHE=1
		# Set CBUILD LD_LIBRARY_PATH for native tools separately from CHOST's.
		export GI_SCANNER_EXTRA_LD_LIBRARY_PATH="/usr/lib:/usr/lib64:/usr/lib32"
		# TODO: find out why setting these flags is required to avoid a compilation error when g-ir-scanner launches a compiler.
		export COMMON_FLAGS="\${COMMON_FLAGS} -L\${ROOT}/$(get_libdir) -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -pthread -lglib-2.0"
		export CFLAGS="\${COMMON_FLAGS}"
		export CXXFLAGS="\${COMMON_FLAGS}"
		export FCFLAGS="\${COMMON_FLAGS}"
		export FFLAGS="\${COMMON_FLAGS}"

		# Only set LD_LIBRARY_PATH when compiling dev-libs/glib if gobject-introspection bootstrapping is required.
		echo \${LD_LIBRARY_PATH} | grep -q bootstrap-gi-prefix && export LD_LIBRARY_PATH="/usr/lib:/usr/$(get_libdir):\${LD_LIBRARY_PATH}"

		# Make g-ir-scanner use wrappers and ROOT files for its work.
		/usr/bin/g-ir-scanner \
			--lib-dirs-envvar=NOTHING \
			--use-ldd-wrapper=$(sysroot_make_cross_introspection_lddwrapper) \
			--use-binary-wrapper=$(sysroot_make_cross_introspection_qemuwrapper) \
			--add-include-path=\${ROOT}/usr/share/gir-1.0 \
			--add-include-path=\${ROOT}/usr/lib/girepository-1.0 \
			"\${@//-I\/usr\/include/-I\${ROOT}\/usr\/include}"
	EOF

	echo "${SCANNERWRAPPER}"
}

# @FUNCTION: sysroot_make_cross_introspection_compiler
# @DESCRIPTION:
# Create a gobject-introspection compiler wrapper script with sysroot_make_run_prefixed
# for cross-compiling, and use it in tandem with g-ir-scanner.
# The path to that script is returned.
sysroot_make_cross_introspection_compiler() {
	local COMPILERWRAPPER="${T}/g-ir-compiler-wrapper"
	install -m0755 /dev/stdin "${COMPILERWRAPPER}" <<-EOF || die
		#!/bin/sh

		$(sysroot_make_run_prefixed) "\${ROOT}/usr/bin/g-ir-compiler" "\$@"
	EOF

	echo "${COMPILERWRAPPER}"
}
