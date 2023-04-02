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

cd
source /etc/profile
REBUILD_RUST="no"
if [ ${PRIMARY_BUILD} = "yes" ]
then
	if [ "${FIRST_BUILD}" = "yes" ]
	then
		mkdir -p /var/db/repos/crossdev/profiles /var/db/repos/crossdev/metadata
		chown -R portage:portage /var/db/repos/crossdev
		echo "crossdev" > /var/db/repos/crossdev/profiles/repo_name
		echo "masters = gentoo" > /var/db/repos/crossdev/metadata/layout.conf
		echo "thin-manifests = true" >> /var/db/repos/crossdev/metadata/layout.conf
		mv /etc/portage/repos.conf/gentoo.conf /etc/portage/gentoo.conf.backup
		emerge-webrsync
		sed -i -e 's/USE="libressl"/USE="-libressl"/' /etc/portage/make.conf
		emerge -kq dev-vcs/git
		mv /etc/portage/gentoo.conf.backup /etc/portage/repos.conf/gentoo.conf
		mkdir /var/db/repos/gentoo.webrsync
		mv /var/db/repos/gentoo/* /var/db/repos/gentoo.webrsync/
		emerge --sync
	else
		emerge --sync || (rm -rf /var/db/repos/gentoo && emerge --sync)
	fi
	emerge -1kq portage
	if [ "${FIRST_BUILD}" = "yes" ]
	then
		sed -i -e 's/-libressl/libressl/' /etc/portage/make.conf
		sed -i -e 's/^cross-.*$//' /var/lib/portage/world
		emerge -1kq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/musl
		eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-gentoo-linux-musl | tail -n 1`
		eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-gentoo-linux-musl/binutils-bin | grep -v lib | tail -n 1`
		source /etc/profile
		emerge -1kq perl dev-perl/Locale-gettext dev-perl/Pod-Parser
		perl-cleaner --all -- -q
		emerge -ekq --with-bdeps=y @world
	else
		emerge -1ukq sys-kernel/linux-headers sys-devel/binutils sys-devel/gcc sys-libs/musl
		eselect gcc set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/lib/gcc/x86_64-gentoo-linux-musl | tail -n 1`
		eselect binutils set `grep -e '^CHOST' /etc/portage/make.conf | sed -e 's/CHOST="//' -e 's/"//'`-`ls -1v /usr/x86_64-gentoo-linux-musl/binutils-bin | grep -v lib | tail -n 1`
		source /etc/profile
		emerge -1kq perl dev-perl/Locale-gettext dev-perl/Pod-Parser
		perl-cleaner --all -- -q
		for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
		do
			if [ -h /usr/${unique_target} ]
			then
				rm /usr/${unique_target}
			fi
			ln -s `ls -1v /usr/${unique_target}.* | grep "/usr/" | grep -v skeleton | sed -e 's/://' | tail -n 1` /usr/${unique_target}
		done
		emerge -uDNkq --with-bdeps=y @world
		eselect rust update
	fi
	source /etc/profile

	for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
	do
		if [ ! -e /usr/${unique_target}.skeleton ]
		then
			mkdir -p /usr/${unique_target}/usr/lib /usr/${unique_target}/lib
			ln -s lib /usr/${unique_target}/lib64
			ln -s lib /usr/${unique_target}/usr/lib64
			crossdev -P -k -t ${unique_target}
			mv /usr/${unique_target} /usr/${unique_target}.skeleton
		fi
		if [ ! -e /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang ]
		then
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang++
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang-cl
			ln -s x86_64-gentoo-linux-musl-clang /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-clang-cpp
			ln -s x86_64-gentoo-linux-musl-llvm-config /usr/lib/llvm/`ls -1v /usr/lib/llvm | tail -n 1`/bin/${unique_target}-llvm-config
			#ln -s x86_64-gentoo-linux-musl-clang /usr/bin/${unique_target}-clang
			#ln -s x86_64-gentoo-linux-musl-llvm-config /usr/bin/${unique_target}-llvm-config
		fi
		if [ "`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`" = "glibc" ]
		then
			if [ ! -e /usr/sbin/locale-gen ]
			then
				ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/sbin/locale-gen /usr/sbin/locale-gen
			fi
		fi

		eselect gcc set ${unique_target}-`ls -1v /usr/lib/gcc/x86_64-gentoo-linux-musl | tail -n 1`
		eselect binutils set ${unique_target}-`ls -1v /usr/x86_64-gentoo-linux-musl/binutils-bin | grep -v lib | tail -n 1`

		if [ ! -e /usr/lib/rust/lib/rustlib/`cat /etc/portage/env/dev-lang/rust | grep ":${unique_target}\"" | cut -d ':' -f2` ]
		then
			REBUILD_RUST="yes"
		else
			touch /tmp/cross_ready.${unique_target}
		fi
	done

	if [ "${REBUILD_RUST}" = "yes" ]
	then
		source /etc/profile
		emerge -1 rust
		for unique_target in `echo ${1} | sed -e 's/:/\n/g' | sort -u`
		do
			touch /tmp/cross_ready.${unique_target}
		done
	fi

	source /etc/profile
	# BUG: due to emerge --sync for each target clashing
	if [ `echo ${1} | sed -e 's/:/\n/g' | wc -l` -gt 1 ]
	then
		sleep 300
	fi
else
	until [ -e /tmp/cross_ready.${CROSSDEV_TARGET} ]
	do
		sleep 5
	done
	source /etc/profile
fi

if [ -h /usr/${CROSSDEV_TARGET} ]
then
	rm /usr/${CROSSDEV_TARGET}
fi

if [ ! -e /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr ]
then
	cp -a /usr/${CROSSDEV_TARGET}.skeleton/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/
	rm -rf /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
	ln -s ${BUILD_CONF}/target-portage /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage
fi

ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME} /usr/${CROSSDEV_TARGET}
if [ -e /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages ]
then
	rm -rf /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages
fi
ln -s ${BUILD_PKGS} /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --sync || \
(rm -rf /var/db/repos/gentoo && ${CROSSDEV_TARGET}-emerge \
	--root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} --sync)

if [ "`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`" = "glibc" ]
then
	# TODO: allow user-defined locales
	echo "en_US.UTF-8 UTF-8" > /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/locale.gen
fi

sed -i -e 's/^INSTALL_MASK/#INSTALL_MASK/' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf
sed -i -e 's@^sys-devel/gcc@#sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -uDNkq \
	sys-libs/`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`
${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -kq --with-bdeps=y `cat ${BUILD_CONF}/worlds/kernel`

if [ ! -e /usr/lib64 ]
then
	ln -s lib /usr/lib64
fi

set +e
rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
set -e
ln -s /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/`ls -1v /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src | grep linux- | tail -n 1` \
	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux

cp ${BUILD_CONF}/linux.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux/.config
sed -i -e "s#CONFIG_INITRAMFS_SOURCE=\"\"#CONFIG_INITRAMFS_SOURCE=\"/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs\"#" \
	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux/.config

cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
yes "" | ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make oldconfig
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make modules_prepare

if [ ! -d /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps ]
then
	mkdir -p /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps
fi
cp ${BUILD_CONF}/busybox.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox

#sed -i -e 's@^sys-kernel/linux-headers@#sys-kernel/linux-headers@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided
#sed -i -e 's@^dev-libs/gmp@#dev-libs/gmp@' -e 's@^dev-libs/mpfr@#dev-libs/mpfr@' -e 's@^dev-libs/mpc@#dev-libs/mpc@' \
#	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided

#TODO: Conditional avoiding this when not needed
#ln -s libOpenGL.so.0.0.0 /usr/${CROSSDEV_TARGET}/usr/lib/libGL.so.0.0.0
#ln -s libGL.so.0.0.0 /usr/${CROSSDEV_TARGET}/usr/lib/libGL.so.0
#ln -s libGL.so.0 /usr/${CROSSDEV_TARGET}/usr/lib/libGL.so
#ln -s opengl.pc /usr/${CROSSDEV_TARGET}/usr/lib/pkgconfig/gl.pc

sed -i -e 's@^#sys-libs/pam@sys-libs/pam@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.use/pam

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1kq pam

sed -i -e 's@^sys-libs/pam@#sys-libs/pam@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.use/pam

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -uDNkq --with-bdeps=y `cat ${BUILD_CONF}/worlds/{base,extra}`

CHOST=${CROSSDEV_TARGET} PORTAGE_CONFIGROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
ROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} SYSROOT=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} smart-live-rebuild

ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make modules_prepare

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q --depclean

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q @preserved-rebuild

${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -q @module-rebuild

PATCH_SQUASHFS="no"
if [ ! -e ../squashfs ]
then
	PATCH_SQUASHFS="yes"
	mkdir ../squashfs
fi

sed -i -e 's/^#INSTALL_MASK/INSTALL_MASK/' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/make.conf
sed -i -e 's@^#sys-devel/gcc@sys-devel/gcc@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/package.env/gcc
#sed -i -e 's@^#sys-kernel/linux-headers@sys-kernel/linux-headers@' /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided
#sed -i -e 's@^#dev-libs/gmp@dev-libs/gmp@' -e 's@^#dev-libs/mpfr@dev-libs/mpfr@' -e 's@^#dev-libs/mpc@dev-libs/mpc@' \
#	/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/profile/package.provided

if [ ! -e ../squashfs.exclude ]
then
	mkdir -p ../squashfs.exclude
else
	set +e
	rmdir ../squashfs/var/db/pkg
	set -e
	mv ../squashfs.exclude/pkg.base ../squashfs/var/db/pkg
fi

if [ "`grep ELIBC ${BUILD_CONF}/target-portage/profile/make.defaults | sed -e 's/ELIBC="//' -e 's/"//'`" = "glibc" ]
then
	if [ ! -e ../squashfs/etc ]
	then
		mkdir -p ../squashfs/etc
	fi
	cp -a /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/locale.gen ../squashfs/etc/locale.gen
fi

FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs -uDNKq --with-bdeps=y `cat ${BUILD_CONF}/worlds/base`
${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs -q --depclean

if [ ! -e ../squashfs/root ]
then
	mkdir ../squashfs/{dev,home,media,mnt,opt,proc,root,sys}
	chmod 700 ../squashfs/root
	cp -a /dev/null /dev/console /dev/tty /dev/loop0 /dev/random /dev/urandom ../squashfs/dev/
fi

cd ../squashfs/lib
set +e
for i in `ls -1 ../usr/lib/gcc/*/*/*so*`
do
	rm `echo ${i} | sed -e 's#\.\./usr/lib/gcc/.*/.*/##'`
done
ln -s ../usr/lib/gcc/*/*/*so* ./
set -e
cd ..

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

if [ -h lib ]
then
	rm lib
fi
if [ -d lib64 ]
then
	cd lib64
	for i in `find . -type f,l`
	do
		if [ ! -d ../lib/`dirname ${i}` ]
		then
			mkdir -p ../lib/`dirname ${i}`
		fi
		mv ${i} ../lib/${i}
	done
	cd ..
	rm -rf lib64
	#ln -s lib64 lib
fi

if [ -h usr/lib ]
then
	rm usr/lib
fi
if [ -d usr/lib64 ]
then
	cd usr/lib64
	for i in `find . -type f,l`
	do
		if [ ! -d ../lib/`dirname ${i}` ]
		then
			mkdir -p ../lib/`dirname ${i}`
		fi
		mv ${i} ../lib/${i}
	done
	cd ../..
	rm -rf usr/lib64
	#ln -s lib64 usr/lib
fi

mkdir -p "../squashfs.exclude/${BUILD_DATE}/modules"
set +e
mv ../squashfs/usr/include "../squashfs.exclude/${BUILD_DATE}/include.base"
for kmodules in `ls -1v ../squashfs/lib/modules`
do
	if [ "${kmodules}" != "`ls -1v ../squashfs/lib/modules | tail -n1`" ]
	then
		mv ../squashfs/lib/modules/${kmodules} "../squashfs.exclude/${BUILD_DATE}/modules"
	fi
done
set -e

#${CROSSDEV_TARGET}-emerge --root=../squashfs --sysroot=../squashfs -Kq @module-rebuild

mv ../squashfs/var/db/pkg ../squashfs.exclude/pkg.base

if [ ! -e ../squashfs.extra ]
then
	mkdir -p ../squashfs.extra/var/db
	cp -a ../squashfs.exclude/pkg.base ../squashfs.extra/var/db/pkg
else
	mkdir ../squashfs.exclude/pkg.tmp
	mount -t tmpfs tmpfs ../squashfs.exclude/pkg.tmp
	mkdir ../squashfs.exclude/pkg.tmp/{b,e,w,u,m}
	cd ../squashfs.exclude/pkg.tmp
	#mount -o bind ../pkg.base b
	#mount -o bind ../pkg.extra e
	cp -a ../pkg.base/* b/
	set +e
	cp -a ../pkg.extra/* e/
	set -e
	mount -t overlay overlay -olowerdir=b:e,workdir=w,upperdir=u m
	set +e
	rmdir ../squashfs.extra/var/db/pkg
	set -e
	cp -r m ../../squashfs.extra/var/db/pkg
	cd ..
	#umount pkg.tmp/m pkg.tmp/e pkg.tmp/b pkg.tmp
	umount pkg.tmp/m pkg.tmp
	rm -rf pkg.tmp
	mv pkg.extra "${BUILD_DATE}/pkg.extra.old"
fi

FEATURES="-collision-protect" ${CROSSDEV_TARGET}-emerge --root=../squashfs.extra \
--sysroot=../squashfs.extra -uDNKq --with-bdeps=y `cat ${BUILD_CONF}/worlds/extra`

${CROSSDEV_TARGET}-emerge --root=../squashfs.extra --sysroot=../squashfs.extra -q --depclean

cd ../squashfs.extra
if [ ! -e lib/udev/rules.d ]
then
	mkdir -p lib/udev/rules.d
fi

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

if [ -h lib ]
then
	rm lib
fi
if [ -d lib64 ]
then
	cd lib64
	for i in `find . -type f,l`
	do
		if [ ! -d ../lib/`dirname ${i}` ]
		then
			mkdir -p ../lib/`dirname ${i}`
		fi
		mv ${i} ../lib/${i}
	done
	cd ..
	rm -rf lib64
	#ln -s lib64 lib
fi

if [ -h usr/lib ]
then
	rm usr/lib
fi
if [ -d usr/lib64 ]
then
	cd usr/lib64
	for i in `find . -type f,l`
	do
		if [ ! -d ../lib/`dirname ${i}` ]
		then
			mkdir -p ../lib/`dirname ${i}`
		fi
		mv ${i} ../lib/${i}
	done
	cd ../..
	rm -rf usr/lib64
	#ln -s lib64 usr/lib
fi

if [ ! -e usr/lib/libGL.so.1 && ! -h usr/lib/libGL.so.1 ]
then
	ln -s libOpenGL.so usr/lib/libGL.so.1
fi

set +e
#mv usr/${CROSSDEV_TARGET}/lib/udev/rules.d/* lib/udev/rules.d/
#mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/rules.d/* lib/udev/rules.d/
#mv usr/${CROSSDEV_TARGET}/lib/udev/net.sh lib/udev/rules.d/
#mv usr/${CROSSDEV_TARGET}.${BUILD_NAME}/lib/udev/net.sh lib/udev/rules.d/

mv ../squashfs.extra/usr/include  "../squashfs.exclude/${BUILD_DATE}/include.extra"
mv ../squashfs.extra/var/db/pkg ../squashfs.exclude/pkg.extra
mv ../squashfs.extra/usr/share/gtk-doc ../squashfs.exclude/gtk-doc
mv ../squashfs.extra/usr/share/qemu/edk2-a* ../squashfs.exclude/
set -e

if [ -e ../initramfs ]
then
	rm -rf ../initramfs
fi
cp -a ${BUILD_CONF}/initramfs ../initramfs

mkdir /tmp/busybox /tmp/busybox-mini
set +e
mv /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/busybox*.tbz2 /tmp/busybox/
rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox-*
set -e
cp ${BUILD_CONF}/busybox-mini.config /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox
USE="-make-symlinks -syslog" ${CROSSDEV_TARGET}-emerge --root=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} \
	--sysroot=/usr/${CROSSDEV_TARGET}.${BUILD_NAME} -1Bq busybox
mv /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/busybox*.tbz2 /tmp/busybox-mini/
set +e
mv /tmp/busybox/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/packages/sys-apps/
rm /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/etc/portage/savedconfig/sys-apps/busybox-*
set -e
cd /tmp/busybox-mini
tar xjpf busybox*.tbz2
cp -a bin/* /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/initramfs/bin/
rm -rf /tmp/busybox*

# TODO: remove old kernel modules
cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/linux
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make -j${BUILD_JOBS}
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- INSTALL_MOD_PATH=../squashfs make modules_install



cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/squashfs

if [ "${PATCH_SQUASHFS}" = "yes" ]
then
	patch -p0 < "${BUILD_CONF}/base.patch"
fi

cd etc/runlevels/boot
set +e
rm fsck keymaps localmount root save-keymaps save-termencoding swap
ln -s /etc/init.d/busybox-klogd ./
ln -s /etc/init.d/busybox-syslogd ./
ln -s /etc/init.d/iptables ./
ln -s /etc/init.d/ip6tables ./
ln -s /etc/init.d/pwgen ./
cd ../default
rm netmount
ln -s /etc/init.d/chronyd ./
set -e

cd /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/squashfs
#mksquashfs . ../initramfs/base -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ} -Xdict-size 1048576
mksquashfs . ../initramfs/base -comp xz -b 1048576 -Xdict-size 1048576

cd ../squashfs.extra
#mksquashfs . ../initramfs/extra -comp xz -b 1048576 -Xbcj ${SQUASH_BCJ} -Xdict-size 1048576
mksquashfs . ../initramfs/extra -comp xz -b 1048576 -Xdict-size 1048576

cd ../linux
rm usr/initramfs_data.cpio
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make -j${BUILD_JOBS}

#TODO: Implement for non-uefi and other architectures
mkdir -p "../${BUILD_NAME}-${BUILD_DATE}/EFI/boot"

if [ "`grep 'sys-kernel/raspberrypi-sources' /build-helper/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
then
	if [ ! -e ../${BUILD_NAME}-${BUILD_DATE}/boot/overlays ]
	then
		mkdir -p ../${BUILD_NAME}-${BUILD_DATE}/boot/overlays
	fi
	cp arch/${BUILD_ARCH}/boot/dts/overlays/*.dtbo ../${BUILD_NAME}-${BUILD_DATE}/boot/overlays/
	cp arch/${BUILD_ARCH}/boot/dts/broadcom/*.dtb ../${BUILD_NAME}-${BUILD_DATE}/boot/
	cp "arch/${BUILD_ARCH}/boot/Image" "../${BUILD_NAME}-${BUILD_DATE}/boot/kernel.img"
else
	cp "arch/${BUILD_ARCH}/boot/bzImage" "../${BUILD_NAME}-${BUILD_DATE}/EFI/boot/bootx64.efi"
fi
cp .config ../config
ARCH=${BUILD_ARCH} CROSS_COMPILE=${CROSSDEV_TARGET}- make mrproper
mv ../config .config

#TODO: Implement config squashfs

#TODO: Implement for non-uefi and other architectures
mkdir -p "${BUILD_DEST}"
if [ "`grep 'sys-kernel/raspberrypi-sources' /build-helper/configs/${CROSSDEV_TARGET}.${BUILD_NAME}/worlds/kernel | wc -l`" = "1" ]
then
	cp -r ../${BUILD_NAME}-${BUILD_DATE}/boot ${BUILD_DEST}/boot
	cp -r /usr/${CROSSDEV_TARGET}.${BUILD_NAME}/boot/* ${BUILD_DEST}/boot/
	mkdir -p ${BUILD_DEST}/EFI/boot
	ln -s ../../boot/kernel8.img ${BUILD_DEST}/EFI/boot/bootx64.efi
else
	cp -r "/usr/${CROSSDEV_TARGET}.${BUILD_NAME}/usr/src/${BUILD_NAME}-${BUILD_DATE}/EFI" "${BUILD_DEST}/EFI"
fi
