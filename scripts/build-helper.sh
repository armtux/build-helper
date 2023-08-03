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

# output each running line of code
set -x
# exit on error
set -e

echo "	Build Helper version 0.1, Copyright (C) 2021-2023 Alexis Boulva
	Build Helper comes with ABSOLUTELY NO WARRANTY; for details
	read the included LICENSE file. This is free software, and you are welcome
	to redistribute it under certain conditions; read the LICENSE file
	for details.
"

# brief usage details
build_helper_usage() {
	echo "Welcome to the build helper. Automates a custom gentoo build recipe.

Usage: 
	sh /build-helper/scripts/build-helper.sh \\
	<primary-crossdev-target[:other-crossdev-target].*> \\
	<primary-build-name[:other-build-name].*>

NOTE:	Build name order corresponds to crossdev target order; number of each must be equal.

	Requirement: a complete config for each target in:
	/build-helper/configs/crossdev-target.build-name

	If needed, please refer to existing configs as a base.
	Sorry about the messiness."
	exit
}

# NOTE: For checks later on. DO NOT TOUCH
export PRIMARY_BUILD="yes"
export FIRST_BUILD="no"

# NOTE: If you choose to customize these, be sure to know what you are changing!
# check if user disabled tmux support
if [ "${TERM_PROGRAM}" = "tmux" ]
then
	export TMUX_MODE="${TMUX_MODE-on}"
else
	export TMUX_MODE="off"
fi
# gentoo mirror to use for fetching initial chroot tarball
export TARBALL_MIRROR="${TARBALL_MIRROR:-https://gentoo.osuosl.org}"
# path to this script
export SCRIPT_PATH="`readlink -f "$0"`"
# path to build-helper directory structure
export BUILD_HELPER_TREE="${BUILD_HELPER_TREE:-$(dirname "${SCRIPT_PATH}")/..}"
# path to build environment configuration files
export HOST_CONF="${BUILD_HELPER_TREE}/configs/host"
# path to build environment binpkg directory
export HOST_PKGS="${BUILD_HELPER_TREE}/packages/host"
# paths to build environment ebuild repositories in chroot
export SYS_REPOS="${SYS_REPOS:-/var/db/repos/gentoo}"
# base chroot structure mount type (options: tmpfs or bind)
export MNT_TYPE="${MNT_TYPE:-bind}"
#export MNT_TYPE="${MNT_TYPE:-tmpfs}"
# base chroot structure mount options (for tmpfs)
export MNT_OPTS="${MNT_OPTS:-size=30G}"
# chroot /tmp /var/tmp type (options: none or tmpfs)
export TMP_TYPE="${TMP_TYPE:-none}"
# chroot /var/tmp/portage tmpfs mount size
export TMP_SIZE="${TMP_SIZE:-24G}"
# old: "unreliable" option for mksquashfs
#export SQUASH_BCJ="${SQUASH_BCJ:-x86}"
#export SQUASH_BCJ_HIST="${SQUASH_BCJ_HIST:-x86}"
# make -jN for kernel build, ideally reflecting contents of host chroot /etc/portage
export BUILD_JOBS="${BUILD_JOBS:-`nproc`}"

# NOTE: These you should not touch.
# first target tuple from command input
export CROSSDEV_TARGET="`echo ${1} | cut -d ':' -f 1`"
# first target build name from command input
export BUILD_NAME="`echo ${2} | cut -d ':' -f 1`"

# path to first target configuration files
export BUILD_CONF="${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}"
# path to first target binpkg directory
export BUILD_PKGS="${BUILD_HELPER_TREE}/packages/${CROSSDEV_TARGET}.${BUILD_NAME}"
# first target cpu architecture
export BUILD_ARCH="`cat ${BUILD_CONF}/build-arch`"
# build timestamp
export BUILD_DATE="`date -Iseconds`"
# path to first target final build
export BUILD_DEST="${BUILD_HELPER_TREE}/builds/${CROSSDEV_TARGET}.${BUILD_NAME}.${BUILD_DATE}"
# path to finished work's squashfs backup
#export BUILD_HIST="${BUILD_HIST:-`ls -1 ${BUILD_HELPER_TREE}/builds/${CROSSDEV_TARGET}.${BUILD_NAME}*/dev.sqfs | tail -n 1`}"
export BUILD_HIST="${BUILD_HIST:-`[ -d ${BUILD_HELPER_TREE}/history ] && ls -1 ${BUILD_HELPER_TREE}/history | tail -n 1`}"
# history archive format
export HIST_TYPE="${HIST_TYPE:-squashfs}"
#export HIST_TYPE="${HIST_TYPE:-files}"
# path to gentoo distfiles
export DISTFILES="${DISTFILES:-${BUILD_HELPER_TREE}/distfiles}"
# path to build environment mount point
export MNT_PATH="/mnt/${BUILD_NAME}-${BUILD_DATE}"
# whether to ask before unmounting chroot mounts at the end of the script
export UMOUNT_ASK="${UMOUNT_ASK-yes}"

# minimally sanitize input and display usage if invalid
DISPLAY_USAGE="no"
# check for 2 input parameters
if [ "${#}" = "2" ]
then
	# compare target tuple and build name parameter counts, proceed if equal
	CROSSDEV_TARGET_NUM="`echo ${1} | sed -e 's/:/ /g' | wc -w`"
	BUILD_NAME_NUM="`echo ${2} | sed -e 's/:/ /g' | wc -w`"
	if [ "${CROSSDEV_TARGET_NUM}" = "${BUILD_NAME_NUM}" ]
	then
		# sanity checks for each target tuple
		TUPLE_COUNT="0"
		for i in `echo ${1} | sed -e 's/:/ /g'`
		do
			# check if target tuple/build name combination match a target configuration
			TUPLE_COUNT="`expr \"${TUPLE_COUNT}\" + \"1\"`"
			CONF_FOUND="no"
			if [ -e ${BUILD_HELPER_TREE}/configs/${i}.`echo ${2} | cut -d ':' -f ${TUPLE_COUNT}` ]
			then
				CONF_FOUND="yes"
			fi

			# proceed only if tuple consists of 4 words and matching configuration is found
			TUPLE_LEN="`echo ${i} | sed -e 's/-/ /g' | wc -w`"
			if [ "${TUPLE_LEN}" != "4" ] || [ "${CONF_FOUND}" = "no" ]
			then
				DISPLAY_USAGE="yes"
			fi
		done
	else
		DISPLAY_USAGE="yes"
	fi
else
	DISPLAY_USAGE="yes"
fi

# display command usage if triggered
if [ "${DISPLAY_USAGE}" = "yes" ]
then
	build_helper_usage
fi

# setup chroot directory/mount structure
build_helper_mounts() {

	# check if logs directory exists, otherwise create it
	if [ ! -e "${BUILD_HELPER_TREE}/logs"]
	then
		mkdir -p "${BUILD_HELPER_TREE}/logs"
	fi

	# bind mount for accessing distfiles in chroot
	if [ ! -e "${DISTFILES}" ]
	then
		mkdir -p "${DISTFILES}"
	fi
	mount -o bind ${DISTFILES} ./var/cache/distfiles

	# clear chroot of previous ebuild repository files for bring-up
	# TODO: find out why (possibly BUILD_HIST related), and avoid if possible
	#if [ "${PRIMARY_BUILD}" = "yes" ]
	#then
	#	for i in ${SYS_REPOS}
	#	do
	#		set +e
	#		rm -rf .${i}
	#		set -e
	#	done
	#fi

	# bind mount for accessing build environment configuration in chroot
	if [ ! -e .${HOST_CONF} ]
	then
		mkdir -p .${HOST_CONF}
	fi
	mount -o bind ${HOST_CONF} .${HOST_CONF}

	# bind mounts for target local configuration overlays
	for i in `ls -1 ${HOST_CONF}/repos`
	do
		if [ ! -e var/db/repos/${i} ]
		then
			mkdir var/db/repos/${i}
		fi
		mount -o bind ${HOST_CONF}/repos/${i} var/db/repos/${i}
	done

	# bind mount for completed build destination
	if [ ! -e ${BUILD_HELPER_TREE}/builds ]
	then
		mkdir -p ${BUILD_HELPER_TREE}/builds
	fi
	if [ ! -e .${BUILD_HELPER_TREE}/builds ]
	then
		mkdir -p .${BUILD_HELPER_TREE}/builds
	fi
	mount -o bind ${BUILD_HELPER_TREE}/builds .${BUILD_HELPER_TREE}/builds

	# bind mount for accessing build-helper script in chroot
	if [ ! -e .${BUILD_HELPER_TREE}/scripts ]
	then
		mkdir -p .${BUILD_HELPER_TREE}/scripts
	fi
	mount -o bind,ro ${BUILD_HELPER_TREE}/scripts .${BUILD_HELPER_TREE}/scripts

	# bind mount for accessing build environment binpkg directory in chroot
	if [ ! -e "${HOST_PKGS}" ]
	then
		mkdir -p "${HOST_PKGS}"
	fi
	mount -o bind ${HOST_PKGS} var/cache/binpkgs

	# tmpfs mounts for chroot /tmp and /var/tmp if enabled by TMP_TYPE
	if [ "${TMP_TYPE}" = "tmpfs" ]
	then
		mount -t tmpfs tmpfs \
			-o rw,nosuid,noatime,nodev,size=4G,mode=1777 \
			tmp

		mount -t tmpfs tmpfs \
			-o rw,nosuid,noatime,nodev,size=4G,mode=1777 \
			var/tmp

		# tmpfs mount for chroot /var/tmp/portage
		if [ ! -e var/tmp/portage ]
		then
			mkdir -p var/tmp/portage
			chown portage:portage var/tmp/portage
			chmod 775 var/tmp/portage
		fi

		#	-o rw,nosuid,noatime,nodev,size=${TMP_SIZE},mode=775,uid=portage,gid=portage,x-mount.mkdir=775 \
		mount -t tmpfs tmpfs \
			-o rw,nosuid,noatime,nodev,size=${TMP_SIZE},mode=775,uid=250,gid=250 \
			var/tmp/portage
	fi

	# tmpfs mount for chroot /run
	mount -t tmpfs tmpfs \
		-o rw,nodev,relatime,size=10G,mode=755 \
		run

	# mounts for chroot /proc, /sys and /dev, like the gentoo handbook
	mount -t proc proc proc
	mount --rbind /sys sys
	mount --rbind /dev dev

	# bind mount for build environment portage configuration
	mount -o bind .${HOST_CONF}/target-portage etc/portage
	# copy build environment world configuration to chroot
	cp -a .${HOST_CONF}/worlds/base var/lib/portage/world

}

# TODO: allow regular mount/filesystem rather than squashfs/tmpfs/overlayfs
# NOTE: done?
# mount build-helper directory structure at expected path with chosen mount type
mkdir "${MNT_PATH}"
if [ "${MNT_TYPE}" = "bind" ] && [ ! -e "${BUILD_HELPER_TREE}/work/${BUILD_DATE}" ]
then
	mkdir -p "${BUILD_HELPER_TREE}/work/${BUILD_DATE}"
	mount -o bind "${BUILD_HELPER_TREE}/work/${BUILD_DATE}" "${MNT_PATH}"
elif [ "${MNT_TYPE}" = "tmpfs" ]
then
	mount -t tmpfs ${BUILD_NAME} -o ${MNT_OPTS} "${MNT_PATH}"
fi
cd "${MNT_PATH}"
mkdir s w u m
# fetch and verify initial stage3 tarball if path to prior work to update not defined, otherwise mount prior work
#if [ "${HIST_TYPE}" = "files" ] && [ -e "${BUILD_HELPER_TREE}/history" ]
if [ "${HIST_TYPE}" = "files" ] && [ "${BUILD_HIST}" != "" ] && [ -d "${BUILD_HIST}" ]
then
	#mount -o ro,bind "${BUILD_HELPER_TREE}/history/`ls -1 ${BUILD_HELPER_TREE}/history | tail -n 1`" s
	mount -o ro,bind "${BUILD_HIST}" s
	mount -t overlay overlay -olowerdir=s,workdir=w,upperdir=u m
elif [ "${BUILD_HIST}" = "" ]
then
	export FIRST_BUILD="yes"
	TARBALL_LINK="${TARBALL_MIRROR}/releases/amd64/autobuilds/`curl -s ${TARBALL_MIRROR}/releases/amd64/autobuilds/latest-stage3-amd64-musl-hardened.txt | tail -n 1 | cut -d ' ' -f 1`"
	curl -O ${TARBALL_LINK}.asc -O ${TARBALL_LINK}.DIGESTS -O ${TARBALL_LINK}
	#curl -O ${TARBALL_MIRROR}/releases/amd64/autobuilds/`curl -s ${TARBALL_MIRROR}/releases/amd64/autobuilds/latest-stage3-amd64-musl-hardened.txt | tail -n 1 | cut -d ' ' -f 1` -O ${TARBALL_MIRROR}/releases/amd64/autobuilds/`curl -s ${TARBALL_MIRROR}/releases/amd64/autobuilds/latest-stage3-amd64-musl-hardened.txt | tail -n 1 | cut -d ' ' -f 1`.DIGESTS.asc
	if [ -e /usr/share/openpgp-keys/gentoo-release.asc ]
	then
		gpg --import /usr/share/openpgp-keys/gentoo-release.asc
	else
		gpg --keyserver hkps://keys.gentoo.org --recv-keys 13EBBDBEDE7A12775DFDB1BABB572E0E2D182910
	fi
	gpg --verify stage3*.asc && gpg --verify stage3*.DIGESTS && grep -A 1 SHA512 stage3*.DIGESTS | grep -e 'xz$' | sha512sum -c || (echo "stage3 integrity check failed." && exit)
	#gpg --verify stage3*.asc && grep -A 1 SHA512 stage3*.asc | grep -e 'bz2$' | sha512sum -c || (echo "stage3 integrity check failed." && exit)
else
	mount -t squashfs ${BUILD_HIST} s
	mount -t overlay overlay -olowerdir=s,workdir=w,upperdir=u m
fi
cd m

# extract initial stage3 tarball if this is the first time we're building
if [ "${FIRST_BUILD}" = "yes" ]
then
	#tar xjpf ../stage3*.bz2 --xattrs-include='*.*' --numeric-owner
	#tar xjpf ../stage3*.bz2
	tar xJpf ../stage3*.xz --xattrs-include='*.*' --numeric-owner
fi

# setup chroot directory/mount structure
build_helper_mounts

# copy DNS server information to chroot
cp -L /etc/resolv.conf etc/resolv.conf

# bind mount of build environment for clean archiving
mkdir -p "${MNT_PATH}/b"
mount -o bind "${MNT_PATH}/m" "${MNT_PATH}/b"

# this is where we begin the target foreach loop
TARGET_COUNT="0"
for target in `echo ${1} | sed -e 's/:/ /g'`
do
	# increment which input target to prepare
	TARGET_COUNT="`expr \"${TARGET_COUNT}\" + \"1\"`"

	# set unique target variables
	export CROSSDEV_TARGET="${target}"
	export BUILD_NAME="`echo ${2} | cut -d ':' -f ${TARGET_COUNT}`"
	export BUILD_CONF="${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}"
	export BUILD_PKGS="${BUILD_HELPER_TREE}/packages/${CROSSDEV_TARGET}.${BUILD_NAME}"
	export BUILD_ARCH="`cat ${BUILD_CONF}/build-arch`"
	export BUILD_DEST="${BUILD_HELPER_TREE}/builds/${CROSSDEV_TARGET}.${BUILD_NAME}.${BUILD_DATE}"

	# setup secondary target chroot when first target environment signals crossdev build environment is ready
	# TODO: use flock instead of cross_ready signal files
	if [ "${PRIMARY_BUILD}" = "no" ]
	then
		until [ -e ${MNT_PATH}/m/tmp/cross_ready.${CROSSDEV_TARGET} ]
		do
			sleep 5
		done
	
		mkdir -p ${MNT_PATH}/${BUILD_NAME}-${BUILD_DATE}/{l,w,u,m}
		cd ${MNT_PATH}/${BUILD_NAME}-${BUILD_DATE}
		mount -o bind ../m l
		mount -t overlay overlay -olowerdir=l,workdir=w,upperdir=u m
		cd m
		build_helper_mounts
		cp ../../m/tmp/cross_ready.${CROSSDEV_TARGET} tmp/
	fi

	# bind mount for target configuration files
	if [ ! -e .${BUILD_CONF} ]
	then
		mkdir -p .${BUILD_CONF}
	fi
	mount -o bind ${BUILD_CONF} .${BUILD_CONF}

	# bind mounts for target ebuild repositories
	for i in `ls -1 ${BUILD_CONF}/repos`
	do
		if [ ! -e var/db/repos/${i} ]
		then
			mkdir var/db/repos/${i}
		fi
		mount -o bind ${BUILD_CONF}/repos/${i} var/db/repos/${i}
	done

	# bind mount for accessing target binpkg directory in chroot
	if [ ! -e ${BUILD_PKGS} ]
	then
		mkdir -p ${BUILD_PKGS}
	fi
	if [ ! -e .${BUILD_PKGS} ]
	then
		mkdir -p .${BUILD_PKGS}
	fi
	mount -o bind ${BUILD_PKGS} .${BUILD_PKGS}

	# tmpfs mount for /usr/target/tmp/portage if enabled by TMP_TYPE
	if [ "${TMP_TYPE}" = "tmpfs" ]
	then
		if [ ! -e usr/${CROSSDEV_TARGET}.${BUILD_NAME}/tmp/portage ]
		then
			mkdir -p usr/${CROSSDEV_TARGET}.${BUILD_NAME}/tmp/portage
			chown portage:portage usr/${CROSSDEV_TARGET}.${BUILD_NAME}/tmp/portage
			chmod 775 usr/${CROSSDEV_TARGET}.${BUILD_NAME}/tmp/portage
		fi

		#	-o rw,nosuid,nodev,noatime,size=${TMP_SIZE},mode=775,uid=portage,gid=portage,x-mount.mkdir=775 \
		mount -t tmpfs tmpfs \
			-o rw,nosuid,nodev,noatime,size=${TMP_SIZE},mode=775,uid=250,gid=250 \
			usr/${CROSSDEV_TARGET}.${BUILD_NAME}/tmp/portage
	fi

	# TODO: add tmux support
	# NOTE: done?
	# enter target chroot and run target build script
	CHROOT_LOG="${BUILD_HELPER_TREE}/logs/${BUILD_NAME}-${BUILD_DATE}-chroot.log"
	$([ "${TMUX_MODE}" = "on" ] && echo -n "tmux new-window -n \"${CROSSDEV_TARGET}.${BUILD_NAME}\" \"tmux capture-pane -pS - > ${CHROOT_LOG} && ")\
		chroot . /bin/bash -x -e ${BUILD_HELPER_TREE}/scripts/build-helper-chroot.sh ${1} 2>&1 \
		$( ([ "${TMUX_MODE}" = "on" ] && echo -n \") || echo -n "| tee ${CHROOT_LOG} &")

	# bind mount for target inclusion for archiving
	if [ "${PRIMARY_BUILD}" = "no" ]
	then
		# wait for crossdev target directory to exist
		until [ -e "usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr" ]
		do
			sleep 5
		done

		if [ ! -e "${MNT_PATH}/b/usr/${CROSSDEV_TARGET}.${BUILD_NAME}" ]
		then
			mkdir "${MNT_PATH}/b/usr/${CROSSDEV_TARGET}.${BUILD_NAME}"
		fi
		mount -o bind "${MNT_PATH}/${BUILD_NAME}-${BUILD_DATE}/m/usr/${CROSSDEV_TARGET}.${BUILD_NAME}" \
		"${MNT_PATH}/b/usr/${CROSSDEV_TARGET}.${BUILD_NAME}"
	fi

	# indicate that we are no longer setting up the first target
	export PRIMARY_BUILD="no"
done

# wait until all target build chroot commands complete before continuing
BUILD_COUNT="0"
for build in `echo ${1} | sed -e 's/:/ /g'`
do
	BUILD_COUNT="`expr \"${BUILD_COUNT}\" + \"1\"`"
	until [ -e ${MNT_PATH}/m${BUILD_HELPER_TREE}/builds/${build}.`echo ${2} | cut -d ':' -f ${BUILD_COUNT}`.${BUILD_DATE}/EFI ]
	do
		sleep 5
	done
done

# NOTE: Keep this out of the foreach loops
cp -a ${MNT_PATH}/m/var/lib/portage/world ${HOST_CONF}/worlds/base

# unify mounted work into build history
[ ! -e "${BUILD_HELPER_TREE}/history" ] && mkdir -p "${BUILD_HELPER_TREE}/history"
cd "${MNT_PATH}/b"
if [ "${HIST_TYPE}" = "squashfs" ]
then
	if [ -e "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" ]
	then
		rm "${MNT_PATH}/m/var/tmp/portage/dev.sqfs"
	fi
	#mksquashfs . "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ_HIST} -Xdict-size 1048576
	#### TODO: change to gensquashfs from sys-fs/squashfs-tools-ng
	# TODO: make squashfs image compression settings adjustable
	#mksquashfs . "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" -comp xz -b 1048576 -Xdict-size 1048576
	#mv "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" "${BUILD_DEST}/dev.sqfs"
	# NOTE: new way of creating squashfs image due to lack of squashfs-tools in gentoo boot images
	mount --rbind . "${MNT_PATH}/m/mnt"
	chroot "${MNT_PATH}/m" /bin/bash -c "cd /mnt && mksquashfs . /var/tmp/portage/dev.sqfs -comp xz -b 1048576 -Xdict-size 1048576"
	mv "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" "${BUILD_HELPER_TREE}/history/${BUILD_DATE}.sqfs"
else
	mkdir -p "${BUILD_HELPER_TREE}/history/${BUILD_DATE}"
	rsync -HAaX . "${BUILD_HELPER_TREE}/history/${BUILD_DATE}"
fi
cd

# tear down build environment mounts
# TODO: ask user whether or not they want to unmount the work rather than automatically doing so (done?)
UMOUNT_CHOICE="yes"
if [ "${UMOUNT_ASK}" = "yes" ]
then
	echo "Work has been archived. Before finishing: enter 'no' to keep the work mounts for inspection, or press return/enter to unmount."
	read umount_choice
	if [ "${umount_choice}" = "no" ]
	then
		UMOUNT_CHOICE="no"
	fi
fi

if [ "${UMOUNT_CHOICE}" = "yes" ]
then
	for i in `cat /proc/mounts | grep ${MNT_PATH} | sed -e 's/^.* \//\//' -e 's/ .*$//' | tac`; do umount ${i}; done
fi

if [ "${HIST_TYPE}" = "squashfs" ]
then
	#echo "Finished... Backup squashfs image located at: ${BUILD_DEST}/dev.sqfs"
	echo "Finished... Backup squashfs image located at: ${BUILD_HELPER_TREE}/history/${BUILD_DATE}.sqfs"
else
	echo "Finished... Backup chroot located at: ${BUILD_HELPER_TREE}/history/${BUILD_DATE}"
fi
