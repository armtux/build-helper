build-helper
============

Gentoo Linux crossdev installation builder
------------------------------------------

# usage

until more tests are run and code is improved, please run this
as root, on a gentoo admincd, after launching tmux, preferably
in a virtual machine with kvm hardware acceleration working.

this will ensure that your work flow can include resuming the
process when there are errors, depending on when while building.

i.e. - tmux is a hard requirement for the script's resume mode.

## for one of the included targets

edit build-helper/scripts/example-starter.sh to your liking.

## for more than one target in parallel

edit build-helper/scripts/example-starter-parallel.sh to your liking.

## editing

this can include different environment variables which will be
checked for by build-helper/scripts/build-helper.sh when launched
by the starter script. note that a good idea would be to globally
set your gentoo mirrors, either before running the starter script
or in the edited script.

```console
export GENTOO_MIRRORS="your_preferred_mirrors"
```

## run either of these commands depending on desired target(s)

```console
/path/to/build-helper/scripts/example-starter.sh
```

```console
/path/to/build-helper/scripts/example-starter-parallel.sh
```

# work flow (what to expect)

note: this will likely produce errors, after which is launched
a rescue shell inside the chroot for the target with an error,
for errors during the chroot script launched at the end of (2):
once the error is presumably fixed, run exit 0.

3 options will appear after exiting the rescue shell:

- resume (to try resuming at the line number resulting in an error)

- retry (to try running the chroot script again from the beginning)

- abort (exit script while leaving tmux window open)

firstly, it will be wise to read the code and understand it before
choosing what to do while trying to fix the build. in some cases,
it would be wise to retry rather than resume. in others, you may want
to simply abort and restart the entire process (CTRL+C in the tmux
window for build-helper/scripts/build-helper.sh).

on another note, once the build is either completed or aborted,
you will want to check that your build history is saved in
build-helper/history and then can optionally remove the contents
of build-helper/work/name-date to save space for the next build,
but in the case of abort, only once /mnt/name-date is recursively
unmounted.

```console
umount -R /mnt/name-date
rmdir /mnt/name-date
rm -r /path/to/build-helper/work/name-date
```

## first run (complete build)

1. prepare work directories for primary build at /mnt/name-date/m

2. download latest musl stage3 tarball for the host architecture,
verify its integrity, extract it, chroot and run build-helper/scripts/build-helper-chroot.sh

3. if there is more than one build, wait until (4) is complete,
then mount an overlay of /mnt/name-date/m in /mnt/name-date/othername-date/m
for each additional build, chroot and run build-helper/scripts/build-helper-chroot.sh

4. prepare the common build environment: emerge --sync; emerge -e @world (to match
the latest toolchain/package versions available in crossdev); crossdev -t each-target;
emerge rust (to build rust toolchains for each desired crossdev target)

5. emerge --sync for selected target configuration(s)

6. prepare target configuration kernel files

7. build target configuration(s) with emerge command for crossdev target

8. install generated binary packages in the final build directories

9. build target configuration kernel(s) and install modules in the "base" final build directory

10. create squashfs images from the "base" and "extra" final build directories

11. optionally build squashfs images into the kernel initramfs

12. copy final build kernel/images/bootloader files, where applicable,
to build-helper/builds

13. create squashfs image of (or, optionally, copy) the combined build environment overlays
into build-helper/history for use during the next (update) runs

## update runs (using saved history files)

1. prepare work directories for primary build at /mnt/name-date/m

2. mount saved history files at /mnt/name-date/m,
chroot and run build-helper/scripts/build-helper-chroot.sh

3. if there is more than one build, wait until (4) is complete,
then mount an overlay of /mnt/name-date/m in /mnt/name-date/othername-date/m
for each additional build, chroot and run build-helper/scripts/build-helper-chroot.sh

4. update the common build environment: emerge --sync; emerge -uDNqv @world; crossdev -t each-new-target;
emerge rust (if there are new rust toolchains for each desired new crossdev target)

5. emerge --sync for selected target configuration(s)

6. prepare target configuration kernel files

7. update target configuration(s) with emerge command for crossdev target

8. update generated binary packages in the final build directories

9. build target configuration kernel(s) and install modules in the "base" final build directory

10. create squashfs images from the "base" and "extra" final build directories

11. optionally build squashfs images into the kernel initramfs

12. copy final build kernel/images/bootloader files, where applicable,
to build-helper/builds

13. create squashfs image of (or, optionally, copy) the combined build environment overlays
into build-helper/history for use during the next (update) runs

## "config" squashfs image for each finished build

to truly complete the builds, it is important to create a persistent configuration image for them.
this can be done with squashfs-tools' mksquashfs.

examples of persistent customized configuration include iptables rules, runlevel/init script selection,
users/passwords, or any other file which you prefer to keep after powering off or rebooting.

this is done by stacking a few squashfs images using an overlay filesystem in the initramfs init script.

# description of relevant environment variables (testing)

the following are environment variables which can be passed to build-helper/scripts/build-helper.sh
via your starter script:

- check if user disabled tmux support

```console
TMUX_MODE="${TMUX_MODE:-on}"
```

- gentoo mirror to use for fetching initial chroot tarball

```console
TARBALL_MIRROR="${TARBALL_MIRROR:-https://gentoo.osuosl.org}"
```

- path to build-helper directory structure

```console
BUILD_HELPER_TREE="${BUILD_HELPER_TREE:-$(dirname "${SCRIPT_PATH}")/..}"
```

- base chroot structure mount type (options: tmpfs or bind)

```console
MNT_TYPE="${MNT_TYPE:-bind}"
```

- base chroot structure mount options (for tmpfs)

```console
MNT_OPTS="${MNT_OPTS:-size=30G}"
```

- chroot /tmp /var/tmp type (options: none or tmpfs)

```console
TMP_TYPE="${TMP_TYPE:-none}"
```

- chroot /var/tmp/portage tmpfs mount size

```console
TMP_SIZE="${TMP_SIZE:-24G}"
```

- make -jN for kernel build, ideally reflecting contents of host chroot /etc/portage

```console
BUILD_JOBS="${BUILD_JOBS:-`nproc`}"
```

- path to finished work's saved history backup

```console
BUILD_HIST="${BUILD_HIST:-`[ -d ${BUILD_HELPER_TREE}/history ] && [ "$(ls -1 ${BUILD_HELPER_TREE}/history | wc -l)" -gt "0" ] && ls -1 ${BUILD_HELPER_TREE}/history/* | tail -n 1`}"
```

- saved history backup format (options: squashfs or files)

```console
HIST_TYPE="${HIST_TYPE:-squashfs}"
```

- path to gentoo distfiles

```console
DISTFILES="${DISTFILES:-${BUILD_HELPER_TREE}/distfiles}"
```

- whether to ask before unmounting chroot mounts at the end of the script

```console
UMOUNT_ASK="${UMOUNT_ASK-yes}"
```
