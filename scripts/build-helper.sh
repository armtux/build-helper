#!/bin/sh

# Build Helper - Gentoo Linux crossdev installation builder.
# Copyright (C) 2021 Alexis Boulva

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

set -x
set -e

echo "	Build Helper version 0.1, Copyright (C) 2021 Alexis Boulva
	Build Helper comes with ABSOLUTELY NO WARRANTY; for details
	read the included LICENSE file. This is free software, and you are welcome
	to redistribute it under certain conditions; read the LICENSE file
	for details.
"

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

#NOTE: For checks later on. DO NOT TOUCH
export PRIMARY_BUILD="yes"
export FIRST_BUILD="no"

#NOTE: If you choose to customize these, be sure to know what you are changing!
export TARBALL_MIRROR="${TARBALL_MIRROR:-https://gentoo.osuosl.org}"
export BUILD_HELPER_TREE="${BUILD_HELPER_TREE:-/build-helper}"
export HOST_CONF="${BUILD_HELPER_TREE}/configs/host"
export HOST_PKGS="${BUILD_HELPER_TREE}/packages/host"
export SYS_REPOS="${SYS_REPOS:-/var/db/repos/gentoo /var/db/repos/musl}"
export MNT_TYPE="${MNT_TYPE:-tmpfs}"
export MNT_OPTS="${MNT_OPTS:-size=64G}"
export TMP_SIZE="${TMP_SIZE:-24G}"
#export SQUASH_BCJ="${SQUASH_BCJ:-x86}"
#export SQUASH_BCJ_HIST="${SQUASH_BCJ_HIST:-x86}"
export BUILD_JOBS="${BUILD_JOBS:-`nproc`}"

#NOTE: These you should not touch.
export CROSSDEV_TARGET="`echo ${1} | cut -d ':' -f 1`"
export BUILD_NAME="`echo ${2} | cut -d ':' -f 1`"

export BUILD_CONF="${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}"
export BUILD_PKGS="${BUILD_HELPER_TREE}/packages/${CROSSDEV_TARGET}.${BUILD_NAME}"
export BUILD_ARCH="`cat ${BUILD_CONF}/build-arch`"
export BUILD_DATE="`date -Iseconds`"
export BUILD_DEST="${BUILD_HELPER_TREE}/builds/${CROSSDEV_TARGET}.${BUILD_NAME}.${BUILD_DATE}"
export BUILD_HIST="${BUILD_HIST:-`ls -1 ${BUILD_HELPER_TREE}/builds/${CROSSDEV_TARGET}.${BUILD_NAME}*/dev.sqfs | tail -n 1`}"
export DISTFILES="${DISTFILES:-/build-helper/distfiles}"
export MNT_PATH="/mnt/${BUILD_NAME}-${BUILD_DATE}"

DISPLAY_USAGE="no"
if [ "${#}" = "2" ]
then
	CROSSDEV_TARGET_NUM="`echo ${1} | sed -e 's/:/ /g' | wc -w`"
	BUILD_NAME_NUM="`echo ${2} | sed -e 's/:/ /g' | wc -w`"
	if [ "${CROSSDEV_TARGET_NUM}" = "${BUILD_NAME_NUM}" ]
	then
		TUPLE_COUNT="0"
		for i in `echo ${1} | sed -e 's/:/ /g'`
		do
			TUPLE_COUNT="`expr \"${TUPLE_COUNT}\" + \"1\"`"
			CONF_FOUND="no"
			if [ -e ${BUILD_HELPER_TREE}/configs/${i}.`echo ${2} | cut -d ':' -f ${TUPLE_COUNT}` ]
			then
				CONF_FOUND="yes"
			fi

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

if [ "${DISPLAY_USAGE}" = "yes" ]
then
	build_helper_usage
fi

build_helper_mounts() {

	mount -o bind ${DISTFILES} ./var/cache/distfiles

	if [ "${PRIMARY_BUILD}" = "yes" ]
	then
		for i in ${SYS_REPOS}
		do
			set +e
			rm -rf .${i}
			set -e
		done
	fi

	if [ ! -e .${HOST_CONF} ]
	then
		mkdir -p .${HOST_CONF}
	fi
	mount -o bind ${HOST_CONF} .${HOST_CONF}

	for i in `ls -1 ${HOST_CONF}/repos`
	do
		if [ ! -e var/db/repos/${i} ]
		then
			mkdir var/db/repos/${i}
		fi
		mount -o bind ${HOST_CONF}/repos/${i} var/db/repos/${i}
	done

	if [ ! -e .${BUILD_HELPER_TREE}/builds ]
	then
		mkdir -p .${BUILD_HELPER_TREE}/builds
	fi
	mount -o bind ${BUILD_HELPER_TREE}/builds .${BUILD_HELPER_TREE}/builds

	if [ ! -e .${BUILD_HELPER_TREE}/scripts ]
	then
		mkdir -p .${BUILD_HELPER_TREE}/scripts
	fi
	mount -o bind,ro ${BUILD_HELPER_TREE}/scripts .${BUILD_HELPER_TREE}/scripts

	mount -o bind ${HOST_PKGS} var/cache/binpkgs

	mount -t tmpfs tmpfs \
		-o rw,nosuid,noatime,nodev,size=4G,mode=1777 \
		tmp

	mount -t tmpfs tmpfs \
		-o rw,nosuid,noatime,nodev,size=4G,mode=1777 \
		var/tmp

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

	mount -t tmpfs tmpfs \
		-o rw,nodev,relatime,size=10G,mode=755 \
		run

	mount -t proc proc proc
	mount --rbind /sys sys
	mount --rbind /dev dev

	mount -o bind .${HOST_CONF}/target-portage etc/portage
	cp -a .${HOST_CONF}/worlds/base var/lib/portage/world

}

mkdir "${MNT_PATH}"
mount -t tmpfs ${BUILD_NAME} -o ${MNT_OPTS} "${MNT_PATH}"
cd "${MNT_PATH}"
mkdir s w u m
if [ "${BUILD_HIST}" = "" ]
then
	export FIRST_BUILD="yes"
	curl -O ${TARBALL_MIRROR}/releases/amd64/autobuilds/`curl -s ${TARBALL_MIRROR}/releases/amd64/autobuilds/latest-stage3-amd64-musl-hardened.txt | tail -n 1 | cut -d ' ' -f 1` -O ${TARBALL_MIRROR}/releases/amd64/autobuilds/`curl -s ${TARBALL_MIRROR}/releases/amd64/autobuilds/latest-stage3-amd64-musl-hardened.txt | tail -n 1 | cut -d ' ' -f 1`.DIGESTS.asc
	gpg --keyserver hkps://keys.gentoo.org --recv-keys 13EBBDBEDE7A12775DFDB1BABB572E0E2D182910
	gpg --verify stage3*.asc && grep -A 1 SHA512 stage3*.asc | grep -e 'bz2$' | sha512sum -c || (echo "stage3 integrity check failed." && exit)
else
	mount -t squashfs ${BUILD_HIST} s
	mount -t overlay overlay -olowerdir=s,workdir=w,upperdir=u m
fi
cd m

if [ "${FIRST_BUILD}" = "yes" ]
then
	#tar xjpf ../stage3*.bz2 --xattrs-include='*.*' --numeric-owner
	tar xjpf ../stage3*.bz2
fi

build_helper_mounts

cp -L /etc/resolv.conf etc/resolv.conf

mkdir -p "${MNT_PATH}/b"
mount -o bind "${MNT_PATH}/m" "${MNT_PATH}/b"

#NOTE: Seems like this is where we begin the target foreach loop
TARGET_COUNT="0"
for target in `echo ${1} | sed -e 's/:/ /g'`
do
	TARGET_COUNT="`expr \"${TARGET_COUNT}\" + \"1\"`"

	export CROSSDEV_TARGET="${target}"
	export BUILD_NAME="`echo ${2} | cut -d ':' -f ${TARGET_COUNT}`"
	export BUILD_CONF="${BUILD_HELPER_TREE}/configs/${CROSSDEV_TARGET}.${BUILD_NAME}"
	export BUILD_PKGS="${BUILD_HELPER_TREE}/packages/${CROSSDEV_TARGET}.${BUILD_NAME}"
	export BUILD_ARCH="`cat ${BUILD_CONF}/build-arch`"
	export BUILD_DEST="${BUILD_HELPER_TREE}/builds/${CROSSDEV_TARGET}.${BUILD_NAME}.${BUILD_DATE}"

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

	if [ ! -e .${BUILD_CONF} ]
	then
		mkdir -p .${BUILD_CONF}
	fi
	mount -o bind ${BUILD_CONF} .${BUILD_CONF}

	for i in `ls -1 ${BUILD_CONF}/repos`
	do
		if [ ! -e var/db/repos/${i} ]
		then
			mkdir var/db/repos/${i}
		fi
		mount -o bind ${BUILD_CONF}/repos/${i} var/db/repos/${i}
	done

	if [ ! -e .${BUILD_PKGS} ]
	then
		mkdir -p .${BUILD_PKGS}
	fi
	mount -o bind ${BUILD_PKGS} .${BUILD_PKGS}

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

	chroot . /bin/bash -x -e ${BUILD_HELPER_TREE}/scripts/build-helper-chroot.sh ${1} 2>&1 \
		| tee ${BUILD_HELPER_TREE}/logs/${BUILD_NAME}-${BUILD_DATE}-chroot.log &

	if [ "${PRIMARY_BUILD}" = "no" ]
	then
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

	export PRIMARY_BUILD="no"
done

BUILD_COUNT="0"
for build in `echo ${1} | sed -e 's/:/ /g'`
do
	BUILD_COUNT="`expr \"${BUILD_COUNT}\" + \"1\"`"
	until [ -e ${MNT_PATH}/m${BUILD_HELPER_TREE}/builds/${build}.`echo ${2} | cut -d ':' -f ${BUILD_COUNT}`.${BUILD_DATE}/EFI ]
	do
		sleep 5
	done
done

#NOTE: Keep this out of the foreach loops
cp -a ${MNT_PATH}/m/var/lib/portage/world ${HOST_CONF}/worlds/base

cd "${MNT_PATH}/b"
if [ -e "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" ]
then
	rm "${MNT_PATH}/m/var/tmp/portage/dev.sqfs"
fi
#mksquashfs . "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ_HIST} -Xdict-size 1048576
mksquashfs . "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" -comp xz -b 1048576 -Xdict-size 1048576
mv "${MNT_PATH}/m/var/tmp/portage/dev.sqfs" "${BUILD_DEST}/dev.sqfs"
cd

for i in `cat /proc/mounts | grep ${MNT_PATH} | sed -e 's/^.* \//\//' -e 's/ .*$//' | tac`; do umount ${i}; done

echo "Finished... Backup squashfs image located at: ${BUILD_DEST}/dev.sqfs"
