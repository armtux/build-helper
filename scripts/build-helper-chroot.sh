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

# find out and display $LINENO before running each line, for EXIT trap
PS4="$((CHROOT_ERROR_LASTNO=$LINENO)): "

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
BUILD_HELPER_CHROOT_SOURCE=""

# EXIT trap triggering rescue shell and resume dialog
resume_mode() {
	if [ "${TMUX_MODE}" = "on" ]
	then
		[ $? -eq 0 ] && [ "${CHROOT_ERROR}" = "no" ] && exit
		CHROOT_ERROR="yes"
		echo "chroot script exited due to error. rescue shell launched inside chroot to manually fix error."
		/bin/bash
		echo "rescue shell exited. enter a choice of 'resume' (or just press enter/return) to continue the script nearest \
			possible to the previous error, 'retry' to restart the chroot script from the beginning, \
			'abort' to exit the chroot scripti, or anything else to re-enter the chroot rescue shell."
		read resume_choice
		case "${resume_choice}" in
			retry)
				$0 $1
			;;
			abort)
				exit
			;;
			resume)
				if [ "${CHROOT_RESUME_LINENO}" != "0" ]
				then
					CHROOT_RESUME_LASTNO="${CHROOT_RESUME_LINENO}"
				else
					CHROOT_RESUME_LASTNO="${CHROOT_ERROR_LASTNO}"
				fi

				if [ "${BUILD_HELPER_CHROOT_SOURCE}" = "" ]
				then
					BUILD_HELPER_CHROOT_SOURCE=$(sed -n '2,$' $0)
				fi

				BUILD_HELPER_CHROOT_TOP=$(echo ${BUILD_HELPER_CHROOT_SOURCE} | \
								sed -n "1,${CHROOT_RESUME_TOP_END}p")
				BUILD_HELPER_CHROOT_NEW=$(echo ${BUILD_HELPER_CHROOT_SOURCE} | \
								sed -n "${CHROOT_RESUME_LASTNO},\$p")
				BUILD_HELPER_CHROOT_ADD="CHROOT_RESUME_DEPTH=\"${CHROOT_RESUME_DEPTH}\"\n"
				if [ "${CHROOT_RESUME_DEPTH}" -gt "0" ]
				then
					for resume_depth in $(seq $CHROOT_RESUME_DEPTH)
					do
						BUILD_HELPER_CHROOT_ADD="${CHROOT_RESUME_ADD}if true; then\n"
					done
				fi
				$(echo ${BUILD_HELPER_CHROOT_TOP}\n${BUILD_HELPER_CHROOT_ADD}\n${BUILD_HELPER_CHROOT_NEW}) $1
			;;
			*)
				resume_mode
			;;
		esac
	fi
}

trap resume_mode EXIT

# for resume_mode: start cutting at whatever LINENO this is. above also needs to be run upon resuming
CHROOT_RESUME_TOP_END="$LINENO"

# step out of chroot's / into /root
cd
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
		emerge --sync || (rm -rf /var/db/repos/gentoo && emerge --sync)
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	# make sure portage is up-to-date before continuing
	# TODO: skip portage update if new python needed? (done?)
	#set +e
	if [ "$(emerge -uDNp --with-bdeps=y @world | grep 'dev-lang/python-' | wc -l)" -lt "1" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		emerge -1kq portage
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
	#set -e
	# prepare host environment if no history available
	if [ "${FIRST_BUILD}" = "yes" ]
	then
		CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
		# old, libressl unsupported
		#sed -i -e 's/-libressl/libressl/' /etc/portage/make.conf
		# make sure we don't have crossdev targets in world before they exist
		sed -i -e 's/^cross-.*$//' /var/lib/portage/world
		# build host toolchain
		emerge -1kq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/musl
		# choose latest toolchain versions
		eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-gentoo-linux-musl | tail -n 1`
		eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-gentoo-linux-musl/binutils-bin | grep -v lib | tail -n 1`
		# re-source to apply eselect changes to current shell
		source /etc/profile
		# build perl and modules before the rest, to avoid build failures
		emerge -1kq perl
		#emerge -1kq perl dev-perl/Locale-gettext dev-perl/Pod-Parser
		perl-cleaner --all -- -q
		# build the rest of world, some of which is not yet installed
		emerge -ekq --with-bdeps=y @world
	# update host environment from build history
	else
		# update host toolchain
		emerge -1ukq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/musl
		# choose latest toolchain versions
		eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-gentoo-linux-musl | tail -n 1`
		eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-gentoo-linux-musl/binutils-bin | grep -v lib | tail -n 1`
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
		# update world, including crossdev toolchains and rust
		emerge -uDNkq --with-bdeps=y @world
		# choose latest rust version
		eselect rust update
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
			# run crossdev and save result as a skeleton for all targets using the same toolchain
			crossdev -P -k -t ${unique_target}
			mv /usr/${unique_target} /usr/${unique_target}.skeleton
		fi
		# make sure equivalent target toolchain symlinks to clang/llvm binaries are present
		if [ ! -e /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang ]
		then
			# TODO: replace symlink creation with solution using upstream tools
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang++
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang-cl
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang-cpp
			ln -s x86_64-gentoo-linux-musl-llvm-config /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-llvm-config
			#ln -s x86_64-gentoo-linux-musl-clang /usr/bin/${unique_target}-clang
			#ln -s x86_64-gentoo-linux-musl-llvm-config /usr/bin/${unique_target}-llvm-config
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
		eselect gcc set ${unique_target}-`ls -1v /usr/lib/gcc/x86_64-gentoo-linux-musl | tail -n 1`
		eselect binutils set ${unique_target}-`ls -1v /usr/x86_64-gentoo-linux-musl/binutils-bin | grep -v lib | tail -n 1`

		# trigger rust rebuild below if rust cross-toolchain is currently missing for new crossdev targets
		if [ ! -e /usr/lib/rust/lib/rustlib/`cat /etc/portage/env/dev-lang/rust | grep ":${unique_target}\"" | cut -d ':' -f2` ]
		then
			REBUILD_RUST="yes"
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
			touch /tmp/cross_ready.${unique_target}
		done
	fi
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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
	rm -rf /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
	ln -s ${BUILD_CONF}/target-portage /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# symlink crossdev target environment for this build to generic crossdev toolchain location
ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME} /usr/${CROSSDEV_TARGET}
# store crossdev target binpkg files in build-helper directory
if [ -e /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages ]
then
	rm -rf /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages
fi
ln -s ${BUILD_PKGS} /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages

# sync this crossdev target's repositories (may differ from host environment repositories)
# TODO: make sure parallel sync doesn't clash (done?)
# note: set auto-sync = no for all repos which are shared with host configuration (like ::gentoo) to avoid excess syncing
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --sync
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
	sed -i -e 's@^sys-devel/gcc@#sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# build libc before other packages
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -uDNkq \
	sys-libs/`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`
# build kernel and dependencies before other packages
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -kq --with-bdeps=y `cat ${BUILD_CONF}/worlds/kernel`

# ensure presence of /usr/lib64 to avoid potential bugs later
# TODO: make compatible with merged-usr
# note: upon further thought, this logic should not affect the musl stage3 seed chroot and may be needed when building glibc targets from it
if [ ! -e /usr/lib64 ]
then
	ln -s lib /usr/lib64
fi

# symlink to latest available kernel sources
if [ -h /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux ]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
fi
ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/`ls -1v /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src | grep linux- | tail -n 1` \
	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux

# use target kernel .config
cp ${BUILD_CONF}/linux.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux/.config
sed -i -e "s#CONFIG_INITRAMFS_SOURCE=\"\"#CONFIG_INITRAMFS_SOURCE=\"/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs\"#" \
	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux/.config

# update target kernel .config for current kernel version and prepare sources for emerge checks
# TODO: support sys-kernel/gentoo-kernel[-bin] and dracut
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
yes "" | ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make oldconfig
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make modules_prepare

# copy system busybox configuration to crossdev target
# TODO: only do this for embedded gentoo (done?)
# TODO: support toybox in embedded gentoo
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	if [ ! -d /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps ]
	then
		mkdir -p /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps
	fi
	cp ${BUILD_CONF}/busybox.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1kq pam

sed -i -e 's@^sys-libs/pam@#sys-libs/pam@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.use/pam

# build / update crossdev target world
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -uDNkq --with-bdeps=y `cat ${BUILD_CONF}/worlds/{base,extra}`

# build crossdev target live ebuilds with updates
CHOST=${CROSSDEV_TARGET} PORTAGE_CONFIGROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
ROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} SYSROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} smart-live-rebuild

# prepare sources for emerge checks (again?)
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make modules_prepare

# crossdev target depclean
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q --depclean

# crossdev target preserved-rebuild
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q @preserved-rebuild

# crossdev target out-of-tree kernel module rebuild
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q @module-rebuild

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
	mkdir ../squashfs
fi

# uncomment crossdev target INSTALL_MASK (needed for embedded gentoo)
# TODO: ensure compatibility with full stage3 cross-emerge (done?)
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	sed -i -e 's/^#INSTALL_MASK/INSTALL_MASK/' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf
	sed -i -e 's@^#sys-devel/gcc@sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
#sed -i -e 's@^#sys-kernel/linux-headers@sys-kernel/linux-headers@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided
#sed -i -e 's@^#dev-libs/gmp@dev-libs/gmp@' -e 's@^#dev-libs/mpfr@dev-libs/mpfr@' -e 's@^#dev-libs/mpc@dev-libs/mpc@' \
#	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided

# create directory to backup files excluded from final build (for old modules and embedded gentoo)
if [ ! -e ../squashfs.exclude ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mkdir -p ../squashfs.exclude
# if excluded file backup directory already exists, use its /var/db/pkg (for embedded gentoo)
elif [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	# TODO: check if directory exists instead of allowing an error (done? why is rmdir ever needed?)
	#set +e
	if [ -d ../squashfs/var/db/pkg ]
	then
		rmdir ../squashfs/var/db/pkg
	fi
	#set -e
	mv ../squashfs.exclude/pkg.base ../squashfs/var/db/pkg
elif [ -e ../squashfs.exclude/pkg.base ]
then
	mkdir -p "../squashfs.exclude/${BUILD_DATE}"
	mv ../squashfs.exclude/pkg.base "../squashfs.exclude/${BUILD_DATE}/pkg.base.old"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# install binpkg files in final build directory
FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs --config-root=../squashfs \
	-uDNKq --with-bdeps=y `cat ${BUILD_CONF}/worlds/base`
# final build depclean
${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs --config-root=../squashfs -q --depclean

# create missing system files/directories in final build
if [ ! -e ../squashfs/root ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mkdir ../squashfs/{dev,home,media,mnt,opt,proc,root,sys}
	chmod 700 ../squashfs/root
	cp -a /dev/null /dev/console /dev/tty /dev/loop0 /dev/random /dev/urandom ../squashfs/dev/
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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
	CHROOT_RESUME_LINENO="$LINENO"
	for kmodules in `ls -1v ../squashfs/lib/modules`
	do
		if [ "${kmodules}" != "`ls -1v ../squashfs/lib/modules | tail -n1`" ]
		then
			mv ../squashfs/lib/modules/${kmodules} "../squashfs.exclude/${BUILD_DATE}/modules"
		fi
	done
	CHROOT_RESUME_LINENO="0"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
#set -e

#${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs -Kq @module-rebuild

# backup final build /var/db/pkg
# TODO: only do this for embedded gentoo (done?)
if [ "$(grep '@system' ${BUILD_CONF}/worlds/base | wc -l)" -lt "1" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mv ../squashfs/var/db/pkg ../squashfs.exclude/pkg.base
else
	cp -a ../squashfs/var/db/pkg ../squashfs.exclude/pkg.base
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# create final build extra packages directory if missing, reuse base /var/db/pkg
# TODO: refactor for crossdev stage3 build compatibility (done?)
if [ ! -e ../squashfs.extra ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	mkdir -p ../squashfs.extra/var/db
	cp -a ../squashfs.exclude/pkg.base ../squashfs.extra/var/db/pkg
# prepare final build extra packages directory if present from build history
# TODO: avoid letting errors pass (done?)
else
	mkdir ../squashfs.exclude/pkg.tmp
	mount -t tmpfs tmpfs ../squashfs.exclude/pkg.tmp
	mkdir ../squashfs.exclude/pkg.tmp/{b,e,w,u,m}
	cd ../squashfs.exclude/pkg.tmp
	#mount -o bind ../pkg.base b
	#mount -o bind ../pkg.extra e
	cp -a ../pkg.base/* b/
	#set +e
	if [ -e ../pkg.extra ] && [ "$(ls -1 ../pkg.extra | wc -l)" -gt "0" ]
	then
		cp -a ../pkg.extra/* e/
	fi
	#set -e
	mount -t overlay overlay -olowerdir=b:e,workdir=w,upperdir=u m
	#set +e
	if [ -e ../squashfs.extra/var/db/pkg ]
	then
		rm -rf ../squashfs.extra/var/db/pkg
	fi
	#set -e
	cp -r m ../../squashfs.extra/var/db/pkg
	cd ..
	#umount pkg.tmp/m pkg.tmp/e pkg.tmp/b pkg.tmp
	umount pkg.tmp/m pkg.tmp
	rm -rf pkg.tmp
	mv pkg.extra "${BUILD_DATE}/pkg.extra.old"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# copy target portage configuration from cross-build environment to final build extra packages directory
if [ ! -e ../squashfs.extra/etc ]
then
	mkdir -p ../squashfs.extra/etc
elif [ -d ../squashfs.extra/etc/portage ]
then
	rm -rf ../squashfs.extra/etc/portage
fi
mkdir -p ../squashfs.extra/etc/portage
cp -a /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/* ../squashfs.extra/etc/portage

# install binpkg files in final build extra packages directory
FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs.extra --config-root=../squashfs.extra \
	--sysroot=../squashfs.extra -uDNKq --with-bdeps=y `cat ${BUILD_CONF}/worlds/extra`

# final build extra packages depclean
${CROSSDEV_TARGET}-emerge --root=../squashfs.extra --sysroot=../squashfs.extra --config-root=../squashfs.extra -q --depclean

# BUG: some packages install files in wrong location; move them to where they can be found
# note: is this mkdir required, considering the code below?
cd ../squashfs.extra
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
	mv ../squashfs.extra/var/db/pkg ../squashfs.exclude/pkg.extra
else
	cp -a ../squashfs.extra/var/db/pkg ../squashfs.exclude/pkg.extra
fi
#mv ../squashfs.extra/usr/share/gtk-doc ../squashfs.exclude/gtk-doc
#mv ../squashfs.extra/usr/share/qemu/edk2-a* ../squashfs.exclude/
#set -e

# replace old initramfs files with configuration contents if present
# TODO: replace device nodes in configuration initramfs files with mounting a devtmpfs in the initramfs init script
if [ -e ../initramfs ]
then
	rm -rf ../initramfs
fi
cp -a ${BUILD_CONF}/initramfs ../initramfs

# backup system busybox binpkg to build minimal initramfs busybox
mkdir /tmp/busybox /tmp/busybox-mini
# TODO: avoid letting errors pass (done?)
#set +e
if [ "$(ls -1 /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/busybox*.tbz2 | wc -l)" -gt "0" ]
then
	mv /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/busybox*.tbz2 /tmp/busybox/
fi
if [ "$(ls -1 /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps | grep busybox | wc -l)" -gt "0"]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox-*
fi
#set -e
# use minimal busybox configuration to build initramfs busybox
cp ${BUILD_CONF}/busybox-mini.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox
BINPKG_COMPRESS="bzip2" USE="-make-symlinks -syslog" ${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --config-root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1Bq busybox
# move minimal busybox binpkg to temporary work directory
mv /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/busybox*.tbz2 /tmp/busybox-mini/
# restore system busybox binpkg
# TODO: avoid letting errors pass (done?)
#set +e
if [ "$(ls -1 /tmp/busybox | wc -l)" -gt "0" ]
then
	mv /tmp/busybox/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/
fi
if [ "$(ls -1 /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps | grep busybox | wc -l)" -gt "0" ]
then
	rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox-*
fi
#set -e
# extract minimal busybox binpkg and place static binary in initramfs
cd /tmp/busybox-mini
tar xjpf busybox*.tbz2
cp -a bin/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs/bin/
rm -rf /tmp/busybox*

# build crossdev target kernel and install modules in final build directory
# TODO: remove old kernel modules (done?)
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make -j${BUILD_JOBS}
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- INSTALL_MOD_PATH=../squashfs make modules_install

# work in final build directory
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/squashfs

# patch final build directory if triggered on target's first build
# TODO: check if patch even exists, skip if not (done?)
if [ "${PATCH_SQUASHFS}" = "yes" ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	patch -p0 < "${BUILD_CONF}/base.patch"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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
mksquashfs . ../initramfs/base -comp xz -b 1048576 -Xdict-size 1048576

# separate userland base packages from kernel binary if triggered by target configuration
if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.base ]
then
	mv ../initramfs/base ../base-${BUILD_DATE}
fi

# go to final build extra packages directory and compress it
# TODO: use sys-fs/squashfs-tools-ng instead
# TODO: additionally support tarballs
cd ../squashfs.extra
#mksquashfs . ../initramfs/extra -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ} -Xdict-size 1048576
mksquashfs . ../initramfs/extra -comp xz -b 1048576 -Xdict-size 1048576

# separate userland extra packages from kernel binary if triggered by target configuration
if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.extra ]
then
	mv ../initramfs/extra ../extra-${BUILD_DATE}
fi

# rebuild kernel with updated initramfs including userland if triggered by target configuration
cd ../linux
if [ ! -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.base ] && [ ! -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.extra ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	rm usr/initramfs_data.cpio
	ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make -j${BUILD_JOBS}
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

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
	cp arch/${BUILD_ARCH}/boot/dts/broadcom/*.dtb ../${BUILD_NAME}-${BUILD_DATE}/boot/
	if [ "${BUILD_ARCH}" = "arm64" ]
	then
		cp "arch/${BUILD_ARCH}/boot/Image" "../${BUILD_NAME}-${BUILD_DATE}/boot/kernel8.img"
	else
		cp "arch/${BUILD_ARCH}/boot/zImage" "../${BUILD_NAME}-${BUILD_DATE}/boot/kernel.img"
	fi
# copy final build kernel to output directory (x86_64 uefi)
else
	cp "arch/${BUILD_ARCH}/boot/bzImage" "../${BUILD_NAME}-${BUILD_DATE}/EFI/boot/bootx64.efi"
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
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# copy userland extra packages to output directory if separate from kernel
if [ -e ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/split.extra ]
then
	CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} + 1))"
	# raspberry pi location
	if [ "`grep 'sys-kernel/raspberrypi-sources' ${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
	then
		cp ../extra-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/boot/extra
	# x86_64 uefi location
	else
		cp ../extra-${BUILD_DATE} ../${BUILD_NAME}-${BUILD_DATE}/extra
	fi
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"

# fully clean kernel source directory (required for some kernel security features)
# TODO: add option to skip cleanup
cp .config ../config
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make mrproper
mv ../config .config

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
	cp -r "/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/${BUILD_NAME}-${BUILD_DATE}/*" "${BUILD_DEST}/"
fi
CHROOT_RESUME_DEPTH="$((${CHROOT_RESUME_DEPTH} - 1))"
