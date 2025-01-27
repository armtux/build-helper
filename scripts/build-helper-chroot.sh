#!/bin/sh

# Build Helper - Gentoo Linux crossdev installation builder.
# Copyright (C) 2021-2023 Alexis Boulva

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


# To contact the author, please contact the gentoo community:
# https://www.gentoo.org/get-involved/

# wait 2 seconds while tmux pipe-pane command kicks in
sleep 2

# output each running line of code
set -x
# exit on error
set -e

# always set this to $LINENO below when entering main loops
# also, set it back to '0' below when exiting said loops
CHROOT_RESUME_LINENO="0"

# increment this below when entering main conditions, recursively
# also, substract by 1 when exiting each of these condition
CHROOT_RESUME_DEPTH="0"

# initially set for first resume_mode run
CHROOT_ERROR="no"

# initially set to empty
BUILD_HELPER_CHROOT_SOURCE="$(readlink -f $0)"

# EXIT trap triggering rescue shell and resume dialog
resume_mode() {
	if [ "${TMUX_MODE}" = "on" ]
	then
		[ $4 -eq 0 ] && [ "${CHROOT_ERROR}" = "no" ] && exit
		CHROOT_ERROR="yes"
		set +x
		echo "chroot script exited due to error. rescue shell launched inside chroot to manually fix error. once fixed, \`exit 0\` from rescue shell"
		/bin/bash
		echo 'rescue shell exited. enter a choice of "resume" to continue the script nearest'
		echo 'possible to the previous error, "retry" to restart the chroot script from the beginning,'
		echo '"abort" to exit the chroot script, or anything else to re-enter the chroot rescue shell.'
		read resume_choice
		set -x
		case "${resume_choice}" in
			retry)
				$3 $1
			;;
			abort)
				exit
			;;
			resume)
				if [ "${CHROOT_RESUME_LINENO}" != "0" ]
				then
					CHROOT_RESUME_LASTNO="${CHROOT_RESUME_LINENO}"
				else
					CHROOT_RESUME_LASTNO="$2"
				fi

				#CHROOT_RESUME_DATE="$(date -Iseconds)"
				CHROOT_RESUME_DATE="$(date -u +%Y%m%dT%H%M%SZ)"
				BUILD_HELPER_CHROOT_SOURCE="/tmp/build-helper-chroot-resume-${CHROOT_RESUME_DATE}.sh"

				sed -n "1,${CHROOT_RESUME_TOP_END}p" $3 >> ${BUILD_HELPER_CHROOT_SOURCE}

				echo "CHROOT_RESUME_DEPTH=\"${CHROOT_RESUME_DEPTH}\"" >> ${BUILD_HELPER_CHROOT_SOURCE}

				if [ "${CHROOT_RESUME_DEPTH}" -gt "0" ]
				then
					for resume_depth in $(seq $CHROOT_RESUME_DEPTH)
					do
						echo "${CHROOT_RESUME_ADD}if true; then" >> ${BUILD_HELPER_CHROOT_SOURCE}
					done
				fi

				sed -n "${CHROOT_RESUME_LASTNO},\$p" $3 >> ${BUILD_HELPER_CHROOT_SOURCE}

				chmod 700 "${BUILD_HELPER_CHROOT_SOURCE}"
				${BUILD_HELPER_CHROOT_SOURCE} $1
			;;
			*)
				resume_mode $1 $2 $3 1
			;;
		esac
	fi
}

trap 'CHROOT_ERROR_OLDNO=$CHROOT_ERROR_LASTNO; CHROOT_ERROR_LASTNO=$LINENO' DEBUG
trap 'resume_mode $1 $CHROOT_ERROR_OLDNO $BUILD_HELPER_CHROOT_SOURCE $?' EXIT

# for resume_mode: start cutting at whatever LINENO this is. above also needs to be run upon resuming
CHROOT_RESUME_TOP_END="$LINENO"

# step out of chroot's / into /root
cd
# re-add spaces from transferred environment variables
for env_var in $(env | grep '##space##')
do
	export "${env_var//##space##/' '}"
done
# source chroot profile, as per gentoo handbook
source /etc/profile
# don't rebuild rust by default unless triggered by conditions below
REBUILD_RUST="no"
# initial chroot steps before cross-compiling, runs/logged with the first crossdev target
if [ ${PRIMARY_BUILD} = "yes" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	# initial chroot setup if no build history available
	if [ "${FIRST_BUILD}" = "yes" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		# create overlay containing only crossdev target toolchain ebuilds
		mkdir -p /var/db/repos/crossdev/profiles /var/db/repos/crossdev/metadata
		chown -R portage:portage /var/db/repos/crossdev
		echo "crossdev" > /var/db/repos/crossdev/profiles/repo_name
		echo "masters = gentoo" > /var/db/repos/crossdev/metadata/layout.conf
		echo "thin-manifests = true" >> /var/db/repos/crossdev/metadata/layout.conf
		# start with a ::gentoo mirror snapshot and make sure we have git
		mv /etc/portage/repos.conf/gentoo.conf /etc/portage/gentoo.conf.backup
		emerge-webrsync
		# old, libressl unsupported
		#sed -i -e 's/USE="libressl"/USE="-libressl"/' /etc/portage/make.conf
		emerge -kq dev-vcs/git
		mv /etc/portage/gentoo.conf.backup /etc/portage/repos.conf/gentoo.conf
		# backup ::gentoo mirror snapshot, then sync with git
		mkdir /var/db/repos/gentoo.webrsync
		mv /var/db/repos/gentoo/* /var/db/repos/gentoo.webrsync/
		emerge --sync
	# sync build history repositories using git
	else
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		emerge --sync || (rm -rf /var/db/repos/gentoo && emerge --sync)
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	# set CPU_FLAGS_* for native host target
	emerge -ukq app-portage/cpuid2cpuflags
	if [ -e "${HOST_CONF}/cpuflags" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags-native
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	fi
	export VIDEO_CARDS="${VIDEO_CARDS_NATIVE}"
	# make sure portage is up-to-date before continuing
	# TODO: skip portage update if new python needed? (done?)
	#set +e
	if [ "$(emerge -uDNp --with-bdeps=y @world | grep 'dev-lang/python-' | wc -l)" -lt "1" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		emerge -1kq portage
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	fi
	#set -e
	# prepare host environment if no history available
	if [ "${FIRST_BUILD}" = "yes" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		# old, libressl unsupported
		#sed -i -e 's/-libressl/libressl/' /etc/portage/make.conf
		# make sure we don't have crossdev targets in world before they exist
		sed -i -e 's/^cross-.*$//' /var/lib/portage/world
		# set locale in case the build system is glibc
		echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
		# build host toolchain
		emerge -1kq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/musl
		#emerge -1kq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/glibc
		# choose latest toolchain versions
		eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-pc-linux-musl | tail -n 1`
		eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-pc-linux-musl/binutils-bin | grep -v lib | tail -n 1`
		#eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-pc-linux-gnu | tail -n 1`
		#eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-pc-linux-gnu/binutils-bin | grep -v lib | tail -n 1`
		# re-source to apply eselect changes to current shell
		source /etc/profile
		# build perl and modules before the rest, to avoid build failures
		emerge -1kq perl
		#emerge -1kq perl dev-perl/Locale-gettext dev-perl/Pod-Parser
		perl-cleaner --all -- -q
		# temporarily avoid trying to build rust cross-toolchains for first build as crossdev is missing
		sed -i -e 's/^I_KNOW_WHAT_I_AM_DOING_CROSS/#I_KNOW_WHAT_I_AM_DOING_CROSS/' /etc/portage/make.conf
		# build the rest of world, some of which is not yet installed
		emerge -ekq --with-bdeps=y @world
		# revert avoiding rust cross-toolchains for rebuilding rust after crossdev targets are built
		sed -i -e 's/^#I_KNOW_WHAT_I_AM_DOING_CROSS/I_KNOW_WHAT_I_AM_DOING_CROSS/' /etc/portage/make.conf
	# update host environment from build history
	else
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		# update host toolchain
		emerge -1ukq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/musl
		#emerge -1ukq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/glibc
		# choose latest toolchain versions
		eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-pc-linux-musl | tail -n 1`
		eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-pc-linux-musl/binutils-bin | grep -v lib | tail -n 1`
		#eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-pc-linux-gnu | tail -n 1`
		#eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-pc-linux-gnu/binutils-bin | grep -v lib | tail -n 1`
		# re-source to apply eselect changes to current shell
		source /etc/profile
		# build perl and modules before the rest, to avoid build failures
		emerge -1kq perl
		#emerge -1kq perl dev-perl/Locale-gettext dev-perl/Pod-Parser
		perl-cleaner --all -- -q
		CHROOT_RESUME_LINENO="$LINENO"
		# initially point to first listed target for each unique crossdev target toolchain being built
		for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
		do
			if [ -h /usr/${unique_target} ]
			then
				rm /usr/${unique_target}
			fi
			ln -s `ls -1v /usr/${unique_target}.*/usr | grep "/usr/" | grep -v skeleton | sed -e 's/://' -e 's#/usr$##' | tail -n 1` /usr/${unique_target}
		done
		CHROOT_RESUME_LINENO="0"
		CHROOT_RESUME_LINENO="$LINENO"
		# check if new rust cross-targets need to be built later, avoid building them for now to avoid crash from missing new crossdev targets
		for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
		do
			if [ ! -e /usr/lib/rust/lib/rustlib/`cat /etc/portage/env/dev-lang/rust | grep ":${unique_target}\"" | cut -d ':' -f2` ]
			then
				sed -i -e 's/^I_KNOW_WHAT_I_AM_DOING_CROSS/#I_KNOW_WHAT_I_AM_DOING_CROSS/' /etc/portage/make.conf
			fi
		done
		CHROOT_RESUME_LINENO="0"
		# update world, including crossdev toolchains and rust
		emerge -uDNkq --with-bdeps=y @world
		# revert avoiding rust cross-toolchains for rebuilding rust after crossdev targets are built
		sed -i -e 's/^#I_KNOW_WHAT_I_AM_DOING_CROSS/I_KNOW_WHAT_I_AM_DOING_CROSS/' /etc/portage/make.conf
		# choose latest rust version if rust is in world file
		if [ "$(grep 'dev-lang/rust' ${HOST_CONF}/worlds/base)" = "dev-lang/rust" ]
		then
			eselect rust update
		fi
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	# re-source to apply eselect changes to current shell
	source /etc/profile

	CHROOT_RESUME_LINENO="$LINENO"
	# prepare and/or update each unique crossdev target toolchain
	for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
	do
		# run crossdev if target doesn't exist yet
		if [ ! -e /usr/${unique_target}.skeleton ]
		then
			# make sure all packages place their files in same directories
			# TODO: make compatible with merged-usr
			# may no longer be needed/appropriate since 17.1 / merged-usr, commenting for now
			#mkdir -p /usr/${unique_target}/usr/lib /usr/${unique_target}/lib
			#ln -s lib /usr/${unique_target}/lib64
			#ln -s lib /usr/${unique_target}/usr/lib64
			mkdir -p /usr/${unique_target}/usr/lib
			ln -s lib /usr/${unique_target}/usr/lib64
			ln -s usr/lib /usr/${unique_target}/lib
			ln -s usr/lib /usr/${unique_target}/lib64
			mkdir /usr/${unique_target}/usr/bin
			ln -s bin /usr/${unique_target}/usr/sbin
			ln -s usr/bin /usr/${unique_target}/bin
			ln -s usr/bin /usr/${unique_target}/sbin
			# run crossdev and save result as a skeleton for all targets using the same toolchain
			crossdev -P -k -t ${unique_target}
			# recompile crossdev's gcc to enable openmp support
			if ${unique_target}-gcc -v 2>&1 | grep -q disable-libgomp
			then
				emerge -1q --getbinpkg=n cross-${unique_target}/gcc
			fi
			mv /usr/${unique_target} /usr/${unique_target}.skeleton
			# symlink skeleton directory to crossdev target toolchain location for the time being
			ln -s /usr/${unique_target}.skeleton /usr/${unique_target}
		fi
		# make sure equivalent target toolchain symlinks to clang/llvm binaries are present
		if [ -e /usr/lib/llvm ] && [ ! -e /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang ]
		then
			# TODO: replace symlink creation with solution using upstream tools
			LLVM_HOST_VER="`ls -1v /usr/lib/llvm | tail -n 1`"
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang++
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cl
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cpp
			ln -s x86_64-pc-linux-musl-llvm-config /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-llvm-config
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-${LLVM_HOST_VER}
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang++-${LLVM_HOST_VER}
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cl-${LLVM_HOST_VER}
			ln -s x86_64-pc-linux-musl-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cpp-${LLVM_HOST_VER}
			#ln -s x86_64-pc-linux-musl-clang /usr/bin/${unique_target}-clang
			#ln -s x86_64-pc-linux-musl-llvm-config /usr/bin/${unique_target}-llvm-config

			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang++
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cl
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cpp
			#ln -s x86_64-pc-linux-gnu-llvm-config /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-llvm-config
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-${LLVM_HOST_VER}
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang++-${LLVM_HOST_VER}
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cl-${LLVM_HOST_VER}
			#ln -s x86_64-pc-linux-gnu-clang /usr/lib/llvm/${LLVM_HOST_VER}/bin/${unique_target}-clang-cpp-${LLVM_HOST_VER}
			##ln -s x86_64-pc-linux-gnu-clang /usr/bin/${unique_target}-clang
			##ln -s x86_64-pc-linux-gnu-llvm-config /usr/bin/${unique_target}-llvm-config
		fi
		# locale-gen is usually not present for musl (host environment), but is needed if target toolchain is glibc
		if [ "`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`" = "glibc" ]
		then
			if [ ! -e /usr/sbin/locale-gen ]
			then
				ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/sbin/locale-gen /usr/sbin/locale-gen
			fi
		fi

		# choose latest crossdev toolchain versions
		eselect gcc set ${unique_target}-`ls -1v /usr/lib/gcc/${unique_target} | tail -n 1`
		eselect binutils set ${unique_target}-`ls -1v /usr/x86_64-pc-linux-musl/${unique_target}/binutils-bin | grep -v lib | tail -n 1`
		#eselect binutils set ${unique_target}-`ls -1v /usr/x86_64-pc-linux-gnu/${unique_target}/binutils-bin | grep -v lib | tail -n 1`

		# use clang target --gcc-install-dir autodetection, don't rely on gentoo defaults
		if [ -e /etc/clang ]
		then
			echo > /etc/clang/gentoo-gcc-install.cfg
		fi

		# trigger rust rebuild below if rust cross-toolchain is currently missing for new crossdev targets
		if [ "$(grep 'dev-lang/rust' ${HOST_CONF}/worlds/base)" = "dev-lang/rust" ] && \
			[ ! -e /usr/lib/rust/lib/rustlib/`cat /etc/portage/env/dev-lang/rust | grep ":${unique_target}\"" | cut -d ':' -f2` ]
		then
			REBUILD_RUST="yes"
			# install rust dependencies into crossdev target skeleton
			if [ -h /usr/${unique_target}.skeleton/etc/portage ]
			then
				rm /usr/${unique_target}.skeleton/etc/portage
			elif [ -e /usr/${unique_target}.skeleton/etc/portage ]
			then
				rm -rf /usr/${unique_target}.skeleton/etc/portage
			fi
			if [ -h /usr/${unique_target}.skeleton/packages ]
			then
				rm /usr/${unique_target}.skeleton/packages
			elif [ -e /usr/${unique_target}.skeleton/packages ]
			then
				rm -rf /usr/${unique_target}.skeleton/packages
			fi
			TEMP_TARGET="$(ls -1 ${BUILD_CONF}/.. | grep ${unique_target} | head -n 1)"
			if [ "${unique_target}" = "${CROSSDEV_TARGET}" ]
			then
				ln -s ${BUILD_CONF}/target-portage /usr/${unique_target}.skeleton/etc/portage
				ln -s ${BUILD_PKGS} /usr/${unique_target}.skeleton/packages
			else
				ln -s ${BUILD_CONF}/../${TEMP_TARGET}/target-portage /usr/${unique_target}.skeleton/etc/portage
				if [ ! -e ${BUILD_CONF}/../../packages/${TEMP_TARGET} ]
				then
					mkdir -p ${BUILD_CONF}/../../packages/${TEMP_TARGET}
				fi
				ln -s ${BUILD_CONF}/../../packages/${TEMP_TARGET} /usr/${unique_target}.skeleton/packages
			fi
			if [ -L /usr/${unique_target} ]
			then
				rm /usr/${unique_target}
				ln -s /usr/${unique_target}.skeleton /usr/${unique_target}
			fi
			unset VIDEO_CARDS
			${unique_target}-emerge -1kq sys-devel/gcc \
				sys-libs/$(grep ELIBC ${BUILD_CONF}/../${TEMP_TARGET}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//')
			${unique_target}-emerge -1kq dev-libs/openssl
			#mv ${BUILD_CONF}/../../packages/${TEMP_TARGET} /tmp/packages-${TEMP_TARGET}
		# signal to non-chroot script that crossdev target environments are ready for next targets in line for chroot
		# TODO: replace with flock
		else
			touch /tmp/cross_ready.${unique_target}
		fi
	done
	CHROOT_RESUME_LINENO="0"

	# rebuild rust if needed
	if [ "${REBUILD_RUST}" = "yes" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		# re-source to apply eselect changes to current shell
		source /etc/profile
		emerge -1q rust
		# signal to non-chroot script that crossdev target environments are ready for next targets in line for chroot
		# TODO: replace with flock
		for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
		do
			# remove rust dependencies to rebuild later with correct custom target cflags
			TEMP_TARGET="$(ls -1 ${BUILD_CONF}/.. | grep ${unique_target} | head -n 1)"
			${unique_target}-emerge -qC $(cat ${BUILD_CONF}/../${TEMP_TARGET}/worlds/rust.clean)
			touch /tmp/cross_ready.${unique_target}
		done
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	fi

	# re-source to apply eselect changes to current shell
	source /etc/profile
	# BUG: due to emerge --sync for each target clashing
	# TODO: replace with proper sync management to avoid delay
	# note: testing detecting non-primary build sync completion before continuing primary build
	CROSS_BUILD_COUNT="$(echo ${1} | sed -e 's/:/\n/g' | wc -l)"
	if [ "${CROSS_BUILD_COUNT}" -gt 1 ]
	then
		until [ "$(($(ls -1 /tmp | grep cross_sync_ready | wc -l) + 1))" = "${CROSS_BUILD_COUNT}" ]
		do
			sleep 5
		done
		#sleep 300
	fi
# wait until crossdev target ready signal is received for next crossdev targets
else
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	until [ -e /tmp/cross_ready.${CROSSDEV_TARGET} ]
	do
		sleep 5
	done
	source /etc/profile
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# remove initial crossdev target symlink
if [ -h /usr/${CROSSDEV_TARGET} ]
then
	rm /usr/${CROSSDEV_TARGET}
fi

# create crossdev target environment for this build from skeleton if missing
if [ ! -e /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp -a /usr/${CROSSDEV_TARGET}.skeleton/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/
	if [ -h /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage ]
	then
		rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
	else
		rm -rf /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
	fi
	ln -s ${BUILD_CONF}/target-portage /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# check if crossdev target is a native build, apply CPU_FLAGS_*, VIDEO_CARDS and LLVM_TARGETS for user hardware if applicable
if [ "$(grep CHOST= /etc/portage/make.conf | sed -e 's/\"//g' -e 's/-.*$//')" = \
	"$(grep CHOST= /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf | sed -e 's/\"//g' -e 's/-.*$//')" ] \
	&& echo "${BUILD_NAME}" | grep -q native
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	echo "*/* $(cpuid2cpuflags)" > /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.use/00cpu-flags-native
	export VIDEO_CARDS="${VIDEO_CARDS_NATIVE}"
	if echo "${VIDEO_CARDS}" | grep -q amdgpu
	then
		export LLVM_TARGETS="AMDGPU"
	fi
else
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	unset VIDEO_CARDS
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# symlink crossdev target environment for this build to generic crossdev toolchain location
ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME} /usr/${CROSSDEV_TARGET}
# store crossdev target binpkg files in build-helper directory
if [ -h /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages ]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages
elif [ -e /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages ]
then
	rm -rf /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages
fi
if [ -e /tmp/packages-${CROSSDEV_TARGET}.${BUILD_NAME} ]
then
	mv /tmp/packages-${CROSSDEV_TARGET}.${BUILD_NAME}/* ${BUILD_PKGS}/
	rmdir /tmp/packages-${CROSSDEV_TARGET}.${BUILD_NAME}
fi
ln -s ${BUILD_PKGS} /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages

# sync this crossdev target's repositories (may differ from host environment repositories)
# TODO: make sure parallel sync doesn't clash (done?)
# note: set auto-sync = no for all repos which are shared with host configuration (like ::gentoo) to avoid excess syncing
CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --sync
CHROOT_RESUME_LINENO="0"
# note: ::gentoo should have auto-sync = no in crossdev target configurations, so this is no longer needed
#|| \
#	(rm -rf /var/db/repos/gentoo && ${CROSSDEV_TARGET}-emerge \
#		--root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
#		--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --sync)
touch /tmp/cross_sync_ready.${CROSSDEV_TARGET}.${BUILD_NAME}

# set locale before building crossdev target world if crossdev toolchain is glibc
if [ "`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`" = "glibc" ]
then
	# TODO: allow user-defined locales
	echo "en_US.UTF-8 UTF-8" > /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/locale.gen
fi

# comment crossdev target INSTALL_MASK (needed for embedded gentoo)
# TODO: ensure compatibility with full stage3 cross-emerge
# note: testing check for @system in crossdev target configuration's base world file
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	sed -i -e 's/^INSTALL_MASK/#INSTALL_MASK/' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf
	#sed -i -e 's@^sys-devel/gcc@#sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc
	sed -i -e 's@^INSTALL_MASK@#INSTALL_MASK@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/env/sys-devel/gcc
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# build libc, baselayout, ncurses and binutils-libs before other packages
CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1kq \
	sys-libs/`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'` \
	sys-apps/baselayout sys-libs/binutils-libs sys-libs/ncurses
CHROOT_RESUME_LINENO="0"
# include .config customizations if gentoo-kernel ebuild is being used
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" = "1" ]
then
	if [ ! -e /etc/kernel/config.d ]
	then
		mkdir -p /etc/kernel/config.d
	fi
	if [ -e ${BUILD_CONF}/linux.config ]
	then
		cp ${BUILD_CONF}/linux.config /etc/kernel/config.d/
	elif [ -e /etc/kernel/config.d/linux.config ]
	then
		rm /etc/kernel/config.d/linux.config
	fi
fi
# build kernel and dependencies before other packages
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -gt "0" ] && [ -e "${BUILD_CONF}/target-portage/profile/package.provided.kernel" ]
then
	mv "${BUILD_CONF}/target-portage/profile/package.provided.kernel" "${BUILD_CONF}/target-portage/profile/package.provided"
fi
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" = "1" ] && \
	[ ! -e "/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs" ]
then
	mkdir -p "/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs"
	touch "/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs/initramfs_list"
fi
CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -ukq --with-bdeps=y `cat ${BUILD_CONF}/worlds/kernel`
CHROOT_RESUME_LINENO="0"
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -gt "0" ] && [ -e "${BUILD_CONF}/target-portage/profile/package.provided" ]
then
	mv "${BUILD_CONF}/target-portage/profile/package.provided" "${BUILD_CONF}/target-portage/profile/package.provided.kernel"
fi

# ensure presence of /usr/lib64 to avoid potential bugs later
# TODO: make compatible with merged-usr
# note: upon further thought, this logic should not affect the musl stage3 seed chroot and may be needed when building glibc targets from it
# note: refactored because a symlink breaks glibs builds, while a missing lib64 breaks many target packages' pkgconfig
if [ ! -e /usr/lib64/pkgconfig ]
then
	if [ ! -e /usr/lib64 ]
	then
		mkdir -p /usr/lib64
	fi
	ln -s ../lib/pkgconfig /usr/lib64/pkgconfig
fi

# symlink to latest available kernel sources
if [ -h /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux ]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
fi
CHROOT_RESUME_LINENO="$LINENO"
ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/`ls -1v /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src | grep linux- | tail -n 1` \
	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
CHROOT_RESUME_LINENO="0"

cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" != "1" ] && [ ! -e ${BUILD_CONF}/split.initramfs ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	# use target kernel .config
	cp ${BUILD_CONF}/linux.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux/.config
	CHROOT_RESUME_LINENO="$LINENO"
	sed -i -e "s#CONFIG_INITRAMFS_SOURCE=\"\"#CONFIG_INITRAMFS_SOURCE=\"/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs\"#" \
		/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux/.config
	CHROOT_RESUME_LINENO="0"

	# update target kernel .config for current kernel version and prepare sources for emerge checks
	# TODO: support sys-kernel/gentoo-kernel[-bin] and dracut
	yes "" | ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make oldconfig
	ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make modules_prepare
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# make sure ld-musl-${ARCH}.path exists
cat /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/ld.so.conf.d/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/ld.so.conf | grep -v include \
	> /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/ld-musl-${BUILD_ARCH}.path

# copy system busybox configuration to crossdev target
# TODO: only do this for embedded gentoo (done?)
# TODO: support toybox in embedded gentoo
if [ -e ${BUILD_CONF}/busybox-mini.config ]
then
		export BOX_CHOICE="busybox"
elif [ -e ${BUILD_CONF}/toybox-mini.config ]
then
		export BOX_CHOICE="toybox"
fi
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	if [ ! -d /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps ]
	then
		mkdir -p /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps
	fi

	if [ -e ${BUILD_CONF}/busybox.config ]
	then
		cp ${BUILD_CONF}/busybox.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox
	elif [ -e ${BUILD_CONF}/toybox.config ]
	then
		cp ${BUILD_CONF}/toybox.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/toybox
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

#sed -i -e 's@^sys-kernel/linux-headers@#sys-kernel/linux-headers@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided
#sed -i -e 's@^dev-libs/gmp@#dev-libs/gmp@' -e 's@^dev-libs/mpfr@#dev-libs/mpfr@' -e 's@^dev-libs/mpc@#dev-libs/mpc@' \
#	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided

#TODO: Conditional avoiding this when not needed
#ln -s libOpenGL.so.0.0.0 /usr/${CROSSDEV_TARGET}/usr/lib/libGL.so.0.0.0
#ln -s libGL.so.0.0.0 /usr/${CROSSDEV_TARGET}/usr/lib/libGL.so.0
#ln -s libGL.so.0 /usr/${CROSSDEV_TARGET}/usr/lib/libGL.so
#ln -s opengl.pc /usr/${CROSSDEV_TARGET}/usr/lib/pkgconfig/gl.pc

# build pam with different USE flags to avoid circular dependency
sed -i -e 's@^#sys-libs/pam@sys-libs/pam@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.use/pam

CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1kq pam
CHROOT_RESUME_LINENO="0"

sed -i -e 's@^sys-libs/pam@#sys-libs/pam@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.use/pam

# order/sort extra package containers by dependency on one another
WORLD_TREE=""
if [ -d ${BUILD_CONF}/worlds/tree ]
then
	for world_dep in ${BUILD_CONF}/worlds/tree/*
	do
		WORLD_KEY="$(echo ${world_dep} | sed -e 's#.*tree/##')"
		WORLD_VAL="$(cat ${world_dep})"
		if [ "${WORLD_TREE}" != "" ]
		then
			for dep_dep in $(echo ${WORLD_TREE})
			do
				DEP_VAL="$(cat ${BUILD_CONF}/worlds/tree/${dep_dep})"
				if [ "${DEP_VAL}" = "${WORLD_KEY}" ]
				then
					WORLD_TREE="$(echo ${WORLD_TREE} | sed -E "s/${WORLD_KEY} ?//")"
					WORLD_TREE="$(echo ${WORLD_TREE} | sed -e "s/${dep_dep}/${WORLD_KEY} ${dep_dep}/")"
					break
				elif $(echo ${WORLD_TREE} | grep -qv "${WORLD_KEY}")
				then
					WORLD_TREE="${WORLD_TREE} ${WORLD_KEY}"
				fi
			done
		else
			WORLD_TREE="${WORLD_KEY}"
		fi
		if [ "${WORLD_VAL}" != "base" ] && $(echo ${WORLD_TREE} | grep -qv "${WORLD_VAL}")
		then
			WORLD_TREE="$(echo ${WORLD_TREE} | sed -e "s/${WORLD_KEY}/${WORLD_VAL} ${WORLD_KEY}/")"
		elif [ "${WORLD_VAL}" != "base" ] && $(echo ${WORLD_TREE} | grep -q "${WORLD_VAL}")
		then
			for dep_dep in $(echo ${WORLD_TREE})
			do
				DEP_VAL="$(cat ${BUILD_CONF}/worlds/tree/${dep_dep})"
				if [ "${DEP_VAL}" != "base" ] && [ "${DEP_VAL}" = "${WORLD_VAL}" ]
				then
					WORLD_TREE="$(echo ${WORLD_TREE} | sed -E "s/${DEP_VAL} ?//")"
					WORLD_TREE="$(echo ${WORLD_TREE} | sed -e "s/${dep_dep}/${WORLD_VAL} ${dep_dep}/")"
					break
				fi
			done
		fi
	done
fi
export WORLD_TREE="${WORLD_TREE}"

# build / update crossdev target world
CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -uDNkq --with-bdeps=y \
	$(for world in base ${WORLD_TREE}; do cat ${BUILD_CONF}/worlds/${world}; done)
CHROOT_RESUME_LINENO="0"

# build crossdev target live ebuilds with updates
CHROOT_RESUME_LINENO="$LINENO"
CHOST=${CROSSDEV_TARGET} PORTAGE_CONFIGROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
ROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} SYSROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} smart-live-rebuild -- -k
CHROOT_RESUME_LINENO="0"

# prepare sources for emerge checks (again?)
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" != "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make modules_prepare
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# crossdev target depclean
CHROOT_RESUME_LINENO="$LINENO"
UNINSTALL_IGNORE="/lib/modules/* /etc/portage" \
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q --depclean
CHROOT_RESUME_LINENO="0"

# crossdev target preserved-rebuild
CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q @preserved-rebuild
CHROOT_RESUME_LINENO="0"

# crossdev target out-of-tree kernel module rebuild
CHROOT_RESUME_LINENO="$LINENO"
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q @module-rebuild
CHROOT_RESUME_LINENO="0"

# only patch default configuration files if triggered by no build history being available
# TODO: check if patch even exists, skip if not (done?)
PATCH_SQUASHFS="no"
# create crossdev target final base build directory
if [ ! -e ../squashfs ]
then
	if [ -e "${BUILD_CONF}/base.patch" ]
	then
		PATCH_SQUASHFS="yes"
	fi
	mkdir -p ../squashfs/etc
	mkdir -p ../squashfs/usr/lib
	ln -s lib ../squashfs/usr/lib64
	ln -s usr/lib ../squashfs/lib
	ln -s usr/lib ../squashfs/lib64
	mkdir ../squashfs/usr/bin
	ln -s bin ../squashfs/usr/sbin
	ln -s usr/bin ../squashfs/bin
	ln -s usr/bin ../squashfs/sbin
	#touch ../squashfs/etc/{group,passwd,shadow}
fi

# uncomment crossdev target INSTALL_MASK (needed for embedded gentoo)
# TODO: ensure compatibility with full stage3 cross-emerge (done?)
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	sed -i -e 's/^#INSTALL_MASK/INSTALL_MASK/' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf
	#sed -i -e 's@^#sys-devel/gcc@sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc
	sed -i -e 's@^#INSTALL_MASK@INSTALL_MASK@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/env/sys-devel/gcc
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi
#sed -i -e 's@^#sys-kernel/linux-headers@sys-kernel/linux-headers@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided
#sed -i -e 's@^#dev-libs/gmp@dev-libs/gmp@' -e 's@^#dev-libs/mpfr@dev-libs/mpfr@' -e 's@^#dev-libs/mpc@dev-libs/mpc@' \
#	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided

# create directory to backup files excluded from final build (for old modules and embedded gentoo)
if [ ! -e ../squashfs.exclude ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mkdir -p ../squashfs.exclude
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
# if excluded file backup directory already exists, use its /var/db/pkg (for embedded gentoo)
elif [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	# TODO: check if directory exists instead of allowing an error (done? why is rmdir ever needed?)
	#set +e
	if [ -d ../squashfs/var/db/pkg ]
	then
		rmdir ../squashfs/var/db/pkg
	fi
	#set -e
	mv ../squashfs.exclude/pkg.base ../squashfs/var/db/pkg
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
elif [ -e ../squashfs.exclude/pkg.base ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mkdir -p "../squashfs.exclude/${BUILD_DATE}"
	mv ../squashfs.exclude/pkg.base "../squashfs.exclude/${BUILD_DATE}/pkg.base.old"
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# copy target portage configuration from cross-build environment to final build directory
if [ ! -e ../squashfs/etc ]
then
	mkdir -p ../squashfs/etc
elif [ -d ../squashfs/etc/portage ]
then
	rm -rf ../squashfs/etc/portage
fi
mkdir -p ../squashfs/etc/portage
cp -a /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/* ../squashfs/etc/portage

# copy locale.gen in final build
if [ "`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`" = "glibc" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp -a /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/locale.gen ../squashfs/etc/locale.gen
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# install baselayout binpkg files in final build directory first
ROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} SYSROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
PORTAGE_CONFIGROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} emaint binhost -f
FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs --config-root=../squashfs \
	-1uDNKq --with-bdeps=y sys-apps/baselayout

# install binpkg files in final build directory
FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs --config-root=../squashfs \
	-uDNKq --with-bdeps=y `cat ${BUILD_CONF}/worlds/base`
# final build depclean
${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs --config-root=../squashfs -q --depclean

# create missing system files/directories in final build
if [ ! -e ../squashfs/dev ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mkdir ../squashfs/{dev,home,media,mnt,opt,proc,sys}
	#cp -a /dev/null /dev/console /dev/tty /dev/tty1 /dev/loop0 /dev/loop1 /dev/loop2 /dev/random /dev/urandom ../squashfs/dev/
	cp -a /dev/null /dev/console /dev/tty /dev/tty1 /dev/random /dev/urandom ../squashfs/dev/
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# symlink gcc libaries in /lib and clean up old symlinks first if present
# TODO: make compatible with merged-usr
# TODO: instead of this, properly set crossdev target final build ld.so.conf et al
# note: testing setting --config-root for ${CROSSDEV_TARGET}-emerge and copying its /etc/portage to final build directory
cd ../squashfs
#cd ../squashfs/lib
#set +e
#for i in `ls -1 ../usr/lib/gcc/*/*/*so*`
#do
#	rm `echo ${i} | sed -e 's#\.\./usr/lib/gcc/.*/.*/##'`
#done
#ln -s ../usr/lib/gcc/*/*/*so* ./
#set -e
#cd ..

# BUG: some packages install files in wrong location; move them to where they can be found
# note: is this mkdir required, considering the code below?
if [ ! -e lib/udev/hwdb.d ]
then
	mkdir -p lib/udev/hwdb.d
fi
#set +e
#mv usr/${CROSSDEV_TARGET}/lib/udev/hwdb.d/* lib/udev/hwdb.d/
#mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/hwdb.d/* lib/udev/hwdb.d/
#mv usr/${CROSSDEV_TARGET}/lib/udev/rules.d/* lib/udev/rules.d/
#mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/rules.d/* lib/udev/rules.d/
#mv usr/${CROSSDEV_TARGET}/lib/udev/net.sh lib/udev/rules.d/
#mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/net.sh lib/udev/rules.d/
#set -e
if [ -e usr/${CROSSDEV_TARGET}.${BUILD_NAME} ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cd usr/${CROSSDEV_TARGET}.${BUILD_NAME}
	for i in `find . -type f,l`
	do
		if [ ! -d ../../`dirname ${i}` ]
		then
			mkdir -p ../../`dirname ${i}`
		fi
		mv "${i}" "../../${i}"
	done
	cd ../..
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# make sure all packages place their files in same directories
# TODO: make compatible with merged-usr
# note: testing this no longer being needed
#if [ -h lib ]
#then
#	rm lib
#fi
#if [ -d lib64 ]
#then
#	cd lib64
#	for i in `find . -type f,l`
#	do
#		if [ ! -d ../lib/`dirname ${i}` ]
#		then
#			mkdir -p ../lib/`dirname ${i}`
#		fi
#		mv ${i} ../lib/${i}
#	done
#	cd ..
#	rm -rf lib64
#	#ln -s lib64 lib
#fi

#if [ -h usr/lib ]
#then
#	rm usr/lib
#fi
#if [ -d usr/lib64 ]
#then
#	cd usr/lib64
#	for i in `find . -type f,l`
#	do
#		if [ ! -d ../lib/`dirname ${i}` ]
#		then
#			mkdir -p ../lib/`dirname ${i}`
#		fi
#		mv ${i} ../lib/${i}
#	done
#	cd ../..
#	rm -rf usr/lib64
#	#ln -s lib64 usr/lib
#fi

# back up old kernel modules outside of final build
# TODO: check if needed before doing, avoid letting errors pass (done?)
mkdir -p "../squashfs.exclude/${BUILD_DATE}/modules"
#set +e
# also back up embedded target headers outside of final build to save space
# note: commenting, use INSTALL_MASK trick instead
#if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ] && [ -e ../squashfs/usr/include ]
#then
#	mv ../squashfs/usr/include "../squashfs.exclude/${BUILD_DATE}/include.base"
#fi
if [ -e ../squashfs/lib/modules ] && [ "$(ls -1 ../squashfs/lib/modules | wc -l)" -gt "0" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	# note: will be rebuilding the kernel and out-of-tree modules later, therefore moving all old modules to avoid orphaned files from .config changes
	# keeping old code in case needed later.
	#CHROOT_RESUME_LINENO="$LINENO"
	#for kmodules in `ls -1v ../squashfs/lib/modules`
	#do
		#if [ "${kmodules}" != "`ls -1v ../squashfs/lib/modules | tail -n1`" ]
		#then
			#mv ../squashfs/lib/modules/${kmodules} "../squashfs.exclude/${BUILD_DATE}/modules"
		#fi
	#done
	#CHROOT_RESUME_LINENO="0"
	mv ../squashfs/lib/modules/* ../squashfs.exclude/${BUILD_DATE}/modules
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi
#set -e

#${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs -Kq @module-rebuild

# backup final build /var/db/pkg
# TODO: only do this for embedded gentoo (done?)
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mv ../squashfs/var/db/pkg ../squashfs.exclude/pkg.base
	rm -rf ../squashfs/var/cache/edb
else
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp -a ../squashfs/var/db/pkg ../squashfs.exclude/pkg.base
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# loop through sorted extra package container list and create each image
for world_img in ${WORLD_TREE}
do
	# determine which image is overlaid directly beneath this one, set to base if unspecified
	if [ ! -e ${BUILD_CONF}/worlds/tree/${world_img} ]
	then
		WORLD_BASE="base"
	else
		WORLD_BASE="$(cat ${BUILD_CONF}/worlds/tree/${world_img})"
	fi

	# create final build extra packages directory if missing, reuse base /var/db/pkg
	# TODO: refactor for crossdev stage3 build compatibility (done?)
	if [ ! -e ../squashfs.${world_img} ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		mkdir -p ../squashfs.${world_img}/var/db
		cp -a ../squashfs.exclude/pkg.${WORLD_BASE} ../squashfs.${world_img}/var/db/pkg
		mkdir -p ../squashfs.${world_img}/var/lib/portage
		cp -a ../squashfs$([ "${WORLD_BASE}" != "base" ] && echo -n ".${WORLD_BASE}")/var/lib/portage/world \
			../squashfs.${world_img}/var/lib/portage/world
		mkdir -p ../squashfs.${world_img}/usr/lib
		ln -s lib ../squashfs.${world_img}/usr/lib64
		ln -s usr/lib ../squashfs.${world_img}/lib
		ln -s usr/lib ../squashfs.${world_img}/lib64
		mkdir ../squashfs.${world_img}/usr/bin
		ln -s bin ../squashfs.${world_img}/usr/sbin
		ln -s usr/bin ../squashfs.${world_img}/bin
		ln -s usr/bin ../squashfs.${world_img}/sbin
	# prepare final build extra packages directory if present from build history
	# TODO: avoid letting errors pass (done?)
	else
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		mkdir ../squashfs.exclude/pkg.tmp
		mount -t tmpfs tmpfs ../squashfs.exclude/pkg.tmp
		mkdir ../squashfs.exclude/pkg.tmp/{b,e,w,u,m}
		cd ../squashfs.exclude/pkg.tmp
		#mount -o bind ../pkg.base b
		#mount -o bind ../pkg.extra e
		cp -a ../pkg.${WORLD_BASE}/* b/
		#set +e
		if [ -e ../pkg.${world_img} ] && [ "$(ls -1 ../pkg.${world_img} | wc -l)" -gt "0" ]
		then
			cp -a ../pkg.${world_img}/* e/
		fi
		#set -e
		mount -t overlay overlay -olowerdir=b:e,workdir=w,upperdir=u m
		#set +e
		if [ -e ../../squashfs.${world_img}/var/db/pkg ]
		then
			rm -rf ../../squashfs.${world_img}/var/db/pkg
		fi
		#set -e
		cp -r m ../../squashfs.${world_img}/var/db/pkg
		cd ..
		#umount pkg.tmp/m pkg.tmp/e pkg.tmp/b pkg.tmp
		umount pkg.tmp/m pkg.tmp
		rm -rf pkg.tmp
		mv pkg.${world_img} "${BUILD_DATE}/pkg.${world_img}.old"
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

	# copy target portage configuration from cross-build environment to final build extra packages directory
	if [ ! -e ../squashfs.${world_img}/etc ]
	then
		mkdir -p ../squashfs.${world_img}/etc
	elif [ -d ../squashfs.${world_img}/etc/portage ]
	then
		rm -rf ../squashfs.${world_img}/etc/portage
	fi
	mkdir -p ../squashfs.${world_img}/etc/portage
	cp -a /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/* ../squashfs.${world_img}/etc/portage

	# bind mount base /etc to extra to avoid configuration clobbering
	mount -o bind ../squashfs/etc ../squashfs.${world_img}/etc

	# install binpkg files in final build extra packages directory
	CHROOT_RESUME_LINENO="$LINENO"
	FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs.${world_img} --config-root=../squashfs.${world_img} \
		--sysroot=../squashfs.${world_img} -uDNKq --with-bdeps=y `cat ${BUILD_CONF}/worlds/${world_img}`
	CHROOT_RESUME_LINENO="0"

	# unmount base /etc from extra before depclean to avoid configuration file loss
	umount ../squashfs.${world_img}/etc

	# final build extra packages depclean
	${CROSSDEV_TARGET}-emerge --root=../squashfs.${world_img} --sysroot=../squashfs.${world_img} --config-root=../squashfs.${world_img} -q --depclean

	# BUG: some packages install files in wrong location; move them to where they can be found
	# note: is this mkdir required, considering the code below?
	cd ../squashfs.${world_img}
	if [ ! -e lib/udev/rules.d ]
	then
		mkdir -p lib/udev/rules.d
	fi

	# make sure all packages place their files in same directories
	# TODO: make compatible with merged-usr (done?)
	if [ -e usr/${CROSSDEV_TARGET}.${BUILD_NAME} ]
	then
		cd usr/${CROSSDEV_TARGET}.${BUILD_NAME}
		for i in `find . -type f,l`
		do
			if [ ! -d ../../`dirname ${i}` ]
			then
				mkdir -p ../../`dirname ${i}`
			fi
			mv "${i}" "../../${i}"
		done
		cd ../..
	fi

	# note: testing this no longer being needed
	#if [ -h lib ]
	#then
	#	rm lib
	#fi
	#if [ -d lib64 ]
	#then
	#	cd lib64
	#	for i in `find . -type f,l`
	#	do
	#		if [ ! -d ../lib/`dirname ${i}` ]
	#		then
	#			mkdir -p ../lib/`dirname ${i}`
	#		fi
	#		mv ${i} ../lib/${i}
	#	done
	#	cd ..
	#	rm -rf lib64
	#	#ln -s lib64 lib
	#fi

	#if [ -h usr/lib ]
	#then
	#	rm usr/lib
	#fi
	#if [ -d usr/lib64 ]
	#then
	#	cd usr/lib64
	#	for i in `find . -type f,l`
	#	do
	#		if [ ! -d ../lib/`dirname ${i}` ]
	#		then
	#			mkdir -p ../lib/`dirname ${i}`
	#		fi
	#		mv ${i} ../lib/${i}
	#	done
	#	cd ../..
	#	rm -rf usr/lib64
	#	#ln -s lib64 usr/lib
	#fi

	# symlink libOpenGL,so to libGL.so.1 if missing
	# TODO: uncomment or remove depending on purpose
	#if [ ! -e usr/lib/libGL.so.1 && ! -h usr/lib/libGL.so.1 ]
	#then
	#	ln -s libOpenGL.so usr/lib/libGL.so.1
	#fi

	# exclude files from final build extra packages directory
	# TODO: remove this, replace with longer INSTALL_MASK in target configuration
	#set +e
	##mv usr/${CROSSDEV_TARGET}/lib/udev/rules.d/* lib/udev/rules.d/
	##mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/rules.d/* lib/udev/rules.d/
	##mv usr/${CROSSDEV_TARGET}/lib/udev/net.sh lib/udev/rules.d/
	##mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/net.sh lib/udev/rules.d/

	#mv ../squashfs.extra/usr/include  "../squashfs.exclude/${BUILD_DATE}/include.extra"
	if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
	then
		mv ../squashfs.${world_img}/var/db/pkg ../squashfs.exclude/pkg.${world_img}
		rm -rf ../squashfs.${world_img}/var/cache/edb
	else
		cp -a ../squashfs.${world_img}/var/db/pkg ../squashfs.exclude/pkg.${world_img}
	fi
done
#mv ../squashfs.extra/usr/share/gtk-doc ../squashfs.exclude/gtk-doc
#mv ../squashfs.extra/usr/share/qemu/edk2-a* ../squashfs.exclude/
#set -e

# replace old initramfs files with configuration contents if present
# TODO: replace device nodes in configuration initramfs files with mounting a devtmpfs in the initramfs init script
if [ -e ../initramfs ]
then
	rm -rf ../initramfs
fi
cp -r ${BUILD_CONF}/initramfs ../initramfs
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" != "1" ]
then
	chown -R 0:0 ../initramfs
	chmod 700 ../initramfs/init
fi

# backup system busybox binpkg to build minimal initramfs busybox
mkdir /tmp/busybox /tmp/busybox-mini
# TODO: avoid letting errors pass (done?)
#set +e
if [ "$(ls -1 /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/${BOX_CHOICE}/${BOX_CHOICE}*.gpkg.tar | wc -l)" -gt "0" ]
then
	mv /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/${BOX_CHOICE}/${BOX_CHOICE}*.gpkg.tar /tmp/busybox/
fi
if [ "$(ls -1 /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps | grep ${BOX_CHOICE} | wc -l)" -gt "1" ]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/${BOX_CHOICE}-*
fi
#set -e
# use minimal busybox configuration to build initramfs busybox
cp ${BUILD_CONF}/${BOX_CHOICE}-mini.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/${BOX_CHOICE}
CHROOT_RESUME_LINENO="$LINENO"
#BINPKG_COMPRESS="bzip2" \
USE="-make-symlinks -syslog -pam static savedconfig static-libs" ${CROSSDEV_TARGET}-emerge \
	--root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1q --getbinpkg=n ${BOX_CHOICE}
CHROOT_RESUME_LINENO="0"
# move minimal busybox binpkg to temporary work directory
mv /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/${BOX_CHOICE}/${BOX_CHOICE}*.gpkg.tar /tmp/busybox-mini/
ROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} SYSROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
PORTAGE_CONFIGROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} emaint binhost -f
# restore system busybox binpkg
# TODO: avoid letting errors pass (done?)
#set +e
if [ "$(ls -1 /tmp/busybox | wc -l)" -gt "0" ]
then
	mv /tmp/busybox/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/${BOX_CHOICE}/
fi
if [ "$(ls -1 /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps | grep ${BOX_CHOICE} | wc -l)" -gt "0" ]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/${BOX_CHOICE}*
fi
#set -e
# extract minimal busybox binpkg and place static binary in initramfs
cd /tmp/busybox-mini
mkdir tmp
cd tmp
tar xpf ../${BOX_CHOICE}*.gpkg.tar
cd ${BOX_CHOICE}*
tar xpf image.tar.zst
if [ "${BOX_CHOICE}" = "busybox" ]
then
	cp -a image/bin/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs/bin/
elif [ "${BOX_CHOICE}" = "toybox" ]
then
	cp -a image/usr/bin/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs/bin/
fi
rm -rf /tmp/busybox*

# TODO: use initramfs_list
#cp -a /dev/null /dev/console /dev/tty /dev/tty1 /dev/loop0 /dev/loop1 /dev/loop2 /dev/random /dev/urandom \
cp -a /dev/null /dev/console /dev/tty /dev/tty1 /dev/random /dev/urandom \
	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs/dev/

# build crossdev target kernel and install modules in final build directory
# TODO: remove old kernel modules (done?)
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" != "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make -j${BUILD_JOBS}
	ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- INSTALL_MOD_PATH=../squashfs INSTALL_MOD_STRIP="--strip-unneeded" make modules_install
else
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	if [ ! -e ../squashfs/lib/modules ]
	then
		mkdir -p ../squashfs/lib/modules
	fi
	cp -a /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/modules/$(ls -1v /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/modules | tail -n 1) \
		../squashfs/lib/modules/
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# work in final build directory
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/squashfs

# patch final build directory if triggered on target's first build
# TODO: check if patch even exists, skip if not (done?)
if [ "${PATCH_SQUASHFS}" = "yes" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	patch -p0 < "${BUILD_CONF}/base.patch"
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# edit embedded gentoo init script runlevels
# TODO: remove this, should be done by users after build
# note: commenting to test if ever needed
#cd etc/runlevels/boot
#set +e
#rm fsck keymaps localmount root save-keymaps save-termencoding swap
#ln -s /etc/init.d/busybox-klogd ./
#ln -s /etc/init.d/busybox-syslogd ./
#ln -s /etc/init.d/iptables ./
#ln -s /etc/init.d/ip6tables ./
#ln -s /etc/init.d/pwgen ./
#cd ../default
#rm netmount
#ln -s /etc/init.d/chronyd ./
#set -e

# return to final build directory and compress it
# TODO: use sys-fs/squashfs-tools-ng instead
# TODO: additionally support tarballs
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/squashfs
#mksquashfs . ../initramfs/base -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ} -Xdict-size 1048576
if [ -e ../initramfs/base ]
then
	rm ../initramfs/base
fi
mksquashfs . ../initramfs/base -comp xz -b 1048576 -Xdict-size 1048576

# separate userland base packages from kernel binary if triggered by target configuration
if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.base ]
then
	mv ../initramfs/base ../base-${BUILD_DATE}
fi

for world_img in ${WORLD_TREE}
do
	# go to final build extra packages directory and compress it
	# TODO: use sys-fs/squashfs-tools-ng instead
	# TODO: additionally support tarballs
	cd ../squashfs.${world_img}
	#mksquashfs . ../initramfs/extra -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ} -Xdict-size 1048576
	if [ -e ../initramfs/${world_img} ]
	then
		rm ../initramfs/${world_img}
	fi
	mksquashfs . ../initramfs/${world_img} -comp xz -b 1048576 -Xdict-size 1048576

	# separate userland extra packages from kernel binary if triggered by target configuration
	if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.extra ]
	then
		mv ../initramfs/${world_img} ../${world_img}-${BUILD_DATE}
	fi
done

cd ../linux
# rebuild kernel with updated initramfs including userland if triggered by target configuration
if [ -e ${BUILD_CONF}/split.initramfs ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	BUILD_KERNEL_VER="$(ls -1 ../squashfs/lib/modules)"
	cd ../initramfs
	mkdir -p lib/modules/${BUILD_KERNEL_VER}/kernel/drivers/block \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/netfs \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/9p \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/fat \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/squashfs \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/overlayfs \
		lib/modules/${BUILD_KERNEL_VER}/kernel/net/9p
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/drivers/block/{loop,virtio_blk}* \
		lib/modules/${BUILD_KERNEL_VER}/kernel/drivers/block/
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/fs/netfs/* \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/netfs/
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/fs/9p/* \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/9p/
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/fs/fat/* \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/fat/
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/fs/squashfs/* \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/squashfs/
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/fs/overlayfs/* \
		lib/modules/${BUILD_KERNEL_VER}/kernel/fs/overlayfs/
	cp -a ../squashfs/lib/modules/${BUILD_KERNEL_VER}/kernel/net/9p/9pnet{,_virtio}.ko \
		lib/modules/${BUILD_KERNEL_VER}/kernel/net/9p/
	depmod -a -b . ${BUILD_KERNEL_VER}
	cp -a ../squashfs/lib/{ld-,libc.so,libcrypt.so}* lib/
	cp -a ../squashfs/lib/{libcrypto.so,libssl.so}* lib/
	if [ -e ../squashfs.extra/bin/wrmsr ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		cp -a ../squashfs.extra/bin/{rd,wr}msr bin/
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	fi
	find . -print0 | cpio -0 -H newc -v -o | gzip --best > ../initramfs-${BUILD_DATE}
	cd ../linux
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
elif [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" = "1" ] && \
	[ "`grep 'sys-kernel/gentoo-kernel-bin' ${BUILD_CONF}/worlds/kernel | wc -l`" != "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	CHROOT_RESUME_LINENO="$LINENO"
	${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
		--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q gentoo-kernel
	CHROOT_RESUME_LINENO="0"
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
elif [ ! -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.base ] && \
	[ ! -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.extra ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	rm usr/initramfs_data.cpio
	ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make -j${BUILD_JOBS}
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# comment crossdev target INSTALL_MASK (needed for embedded gentoo)
# TODO: ensure compatibility with full stage3 cross-emerge
# note: testing check for @system in crossdev target configuration's base world file
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	sed -i -e 's/^INSTALL_MASK/#INSTALL_MASK/' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf
	#sed -i -e 's@^sys-devel/gcc@#sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc
	sed -i -e 's@^INSTALL_MASK@#INSTALL_MASK@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/env/sys-devel/gcc
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

#TODO: Implement for non-uefi and other architectures
mkdir -p "../${BUILD_NAME}-${BUILD_DATE}/EFI/boot"

# copy final build kernel and boot files to output directory (raspberry pi arm / arm64)
if [ "`grep 'sys-kernel/raspberrypi-sources' ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	if [ ! -e ../${BUILD_NAME}-${BUILD_DATE}/boot/overlays ]
	then
		mkdir -p ../${BUILD_NAME}-${BUILD_DATE}/boot/overlays
	fi
	cp arch/${BUILD_ARCH}/boot/dts/overlays/*.dtbo ../${BUILD_NAME}-${BUILD_DATE}/boot/overlays/
	if [ "${BUILD_ARCH}" = "arm64" ]
	then
		cp arch/${BUILD_ARCH}/boot/dts/broadcom/*.dtb ../${BUILD_NAME}-${BUILD_DATE}/boot/
		cp "arch/${BUILD_ARCH}/boot/Image.gz" "../${BUILD_NAME}-${BUILD_DATE}/boot/kernel8.img"
	else
		cp arch/${BUILD_ARCH}/boot/dts/*.dtb ../${BUILD_NAME}-${BUILD_DATE}/boot/
		cp "arch/${BUILD_ARCH}/boot/zImage" "../${BUILD_NAME}-${BUILD_DATE}/boot/kernel.img"
	fi
# copy final build kernel to output directory (x86_64 uefi)
else
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp "arch/${BUILD_ARCH//_64/}/boot/bzImage" "../${BUILD_NAME}-${BUILD_DATE}/EFI/boot/bootx64.efi"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# copy userland base packages to output directory if separate from kernel
if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.base ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	# raspberry pi location
	if [ "`grep 'sys-kernel/raspberrypi-sources' ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
	then
		cp ../base-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/boot/base
	# x86_64 uefi location
	else
		cp ../base-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/base
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

for world_img in ${WORLD_TREE}
do
	# copy userland extra packages to output directory if separate from kernel
	if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.extra ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		# raspberry pi location
		if [ "`grep 'sys-kernel/raspberrypi-sources' ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
		then
			cp ../${world_img}-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/boot/${world_img}
		# x86_64 uefi location
		else
			cp ../${world_img}-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/${world_img}
		fi
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	fi
done

if [ -e ${BUILD_CONF}/split.initramfs ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp ../initramfs-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/initramfs
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# fully clean kernel source directory (required for some kernel security features)
# TODO: add option to skip cleanup (done?)
if [ "`grep 'sys-kernel/gentoo-kernel' ${BUILD_CONF}/worlds/kernel | wc -l`" != "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	if [ ! -e ${BUILD_CONF}/skip.mrproper ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		cp .config ../config
		ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make mrproper
		mv ../config .config
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
fi

# TODO: Implement config squashfs

# final build output to build-helper defined location
# TODO: Implement for non-uefi and other architectures
mkdir -p "${BUILD_DEST}"
# raspberry pi support
if [ "`grep 'sys-kernel/raspberrypi-sources' ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp -r ../${BUILD_NAME}-${BUILD_DATE}/boot ${BUILD_DEST}/boot
	cp -r /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/boot/* ${BUILD_DEST}/boot/
	# workaround for build completion detection in parent (non-chroot) script
	mkdir -p ${BUILD_DEST}/EFI/boot
	if [ "${BUILD_ARCH}" = "arm64" ]
	then
		ln -s ../../boot/kernel8.img ${BUILD_DEST}/EFI/boot/bootx64.efi
	else
		ln -s ../../boot/kernel.img ${BUILD_DEST}/EFI/boot/bootx64.efi
	fi
# x86_64 uefi support
else
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	cp -r "/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/${BUILD_NAME}-${BUILD_DATE}"/* "${BUILD_DEST}/"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
