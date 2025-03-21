build-helper
============

# table of contents

1. [description](#description)

    1.1 [supported flavours](#supported-flavours)

    1.2 [stacked/split overlay filesystem support](#stackedsplit-overlay-filesystem-support)

    1.3 [unified single-file installation](#unified-single-file-installation)

    1.4 [build history](#build-history)

2. [usage](#usage)

    2.1 [for one of the included targets](#for-one-of-the-included-targets)

    2.2 [for more than one target in parallel](#for-more-than-one-target-in-parallel)

    2.3 [editing](#editing)

    2.4 [run either of these commands depending on desired target(s)](#run-either-of-these-commands-depending-on-desired-targets)

3. [work flow (what to expect)](#work-flow-what-to-expect)

    3.1 [first run (complete build)](#first-run-complete-build)

    3.2 [update runs (using saved history files)](#update-runs-using-saved-history-files)

    3.3 ["config" squashfs image for each finished build](#config-squashfs-image-for-each-finished-build)

4. [description of relevant global environment variables](#description-of-relevant-global-environment-variables)

5. [description of specific target configuration files and customization options](#description-of-specific-target-configuration-files-and-customization-options)

    5.1 [build-arch (file; required)](#build-arch-file-required)

    5.2 [initramfs (directory; required)](#initramfs-directory-required)

    5.3 [linux.config (file; optional)](#linuxconfig-file-optional)

    5.4 [repos (directory; required, but optionally without ebuilds or eclasses)](#repos-directory-required-but-optionally-without-ebuilds-or-eclasses)

    5.5 [skip.mrproper (empty file; optional)](#skipmrproper-empty-file-optional)

    5.6 [split.base (empty file; optional)](#splitbase-empty-file-optional)

    5.7 [split.extra (empty file; optional)](#splitextra-empty-file-optional)

    5.8 [split.initramfs (empty file; optional)](#splitinitramfs-empty-file-optional)

    5.9 [target-portage (directory; required)](#target-portage-directory-required)

    5.10 [toybox-mini.config OR busybox-mini.config (file; required)](#toybox-miniconfig-or-busybox-miniconfig-file-required)

    5.11 [toybox.config OR busybox.config (file; optional)](#toyboxconfig-or-busyboxconfig-file-optional)

    5.12 [worlds and worlds/tree (directory tree; required)](#worlds-and-worldstree-directory-tree-required)

6. [reduced LLVM_TARGETS flags per supported architecture](#reduced-llvm_targets-flags-per-supported-architecture)

7. [configuring the rust cross-compiler](#configuring-the-rust-cross-compiler)

8. [note on circular dependencies](#note-on-circular-dependencies)

9. [final installation structure](#final-installation-structure)

Gentoo Linux crossdev installation builder
------------------------------------------

# description 

an automated/scripted method accompanied by various system target
configurations to cross-compile different flavours of gentoo.

it should support any CPU architecture supported by crossdev.
(testing is required for currently absent target configurations)

it can optionally build many targets in parallel, regardless of CPU
architectures, either outputting to the same screen or to different
tmux panes, by running one starter script for the "build-helper"
unified build environment preparation script (meant to only be used
internally), which will launch the "build-helper-chroot" script for
each target declared in the starter script.

when tmux is optionally used, once there is an error in the workflow,
the options of either aborting, retrying from the beginning of the
individual target chroot script, or resuming from the point where the
target's chroot script failed after having attempted to fix the cause,
are offered.

## supported flavours 

- regular complete gentoo stage3 or stage4 (i.e. the whole software
stack desired in the installation) build, including portage/toolchain

- embedded busybox based stage0 (i.e. without portage/toolchain),
which is solely maintained by running build-helper, to which can be
added up to stage4 level software stacks

- embedded toybox based stage0 (i.e. without portage/toolchain),
which is solely maintained by running build-helper, to which can be
added up to stage4 level software stacks

## stacked/split overlay filesystem support 

optionally, various sets of software can be installed in separate
directories, which are intended to be mounted as the stacked lowerdir
of an overlayfs mount point.

## unified single-file installation 

optionally, the entirety of the chosen software stack can be included
in the initramfs, which in turn can be built into the kernel, which
results in a single file to be booted into system memory.

this option is best suited for more compact/lightweight embedded
installations, however, for target systems with large amounts of
memory, it can also be used for a complete gentoo stage3 or stage4
build. stage0 up to stage4 builds can wildly vary in final size.

## build history 

files used/generated by the build process are saved in the history
directory, and by default are used again when the starter script is
run again. this allows updates to be performed, without the need to
begin the whole build process from scratch every time the tool is run.

# usage 

until more tests are run and code is improved, please run this
as root, on a gentoo admincd, after launching tmux, preferably
in a virtual machine with kvm hardware acceleration working.

this will ensure that the work flow can include resuming the
process when there are errors, depending on when while building.

i.e. - tmux is a hard requirement for the script's resume mode.

note: using 50GB up to >1TB of hard drive space, as well as 32GB
(ideally at least 48GB) up to 1TB of memory are to be be expected,
depending on the amount of targets being built in parallel, and
especially if the entire build process is run in memory (i.e. storing
all work in a tmpfs).

## for one of the included targets 

edit a non-parallel example starter script in build-helper/scripts/
as needed/preferred.

## for more than one target in parallel 

edit a parallel example starter script in build-helper/scripts/
as needed/preferred.

## editing 

this can include different environment variables which will be
checked for by build-helper/scripts/build-helper.sh when launched
by the starter script. note that a good idea would be to globally
set some gentoo mirrors, either before running the starter script
or in the edited script.

```console
export GENTOO_MIRRORS="preferred_mirrors"
```

## run either of these commands depending on desired target(s) 

```console
/path/to/build-helper/scripts/example-starter-zen2-tb-stack.sh
```

```console
/path/to/build-helper/scripts/example-starter-zen2-mbp-tb-stack-parallel.sh
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
it would be wise to retry rather than resume. in others, one may want
to simply abort and restart the entire process (CTRL+C in the tmux
window for build-helper/scripts/build-helper.sh).

on another note, once the build is either completed or aborted,
one will want to check that the build history is saved in
build-helper/history and then can optionally remove the contents
of build-helper/work/name-date to save space for the next build,
but in the case of abort, only once /mnt/name-date is recursively
unmounted.

thankfully, build-helper makes use of binary package generation.
this means that if abort is chosen when there is an error, less
compiling is required each time the starter script is run from scratch.

also, support for gentoo's binary hosts is implemented, potentially
reducing the need for compiling when more standard USE flags are kept.

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

7. order lists of packages to build/install (in configs/target/worlds) based on the indicator
of what previous list each one depends on in configs/target/worlds/tree

8. build target configuration(s) with emerge command for crossdev target

9. install generated binary packages in the final build directories per package list

10. build target configuration kernel(s) and install modules in the "base" final build directory

11. create squashfs images from the final build directories for each package list

12. optionally build squashfs images into the kernel initramfs

13. copy final build kernel/images/bootloader files, where applicable,
to build-helper/builds

14. create squashfs image of (or, optionally, copy) the combined build environment overlays
into build-helper/history for use during the next (update) runs

## update runs (using saved history files) 

1. prepare work directories for primary build at /mnt/name-date/m

2. mount saved history files at /mnt/name-date/m,
chroot and run build-helper/scripts/build-helper-chroot.sh

3. if there is more than one build, wait until (4) is complete,
then mount an overlay of /mnt/name-date/m in /mnt/name-date/othername-date/m
for each additional build, chroot and run build-helper/scripts/build-helper-chroot.sh

4. update the common build environment: emerge --sync; emerge -uDNkq @world; crossdev -t each-new-target;
emerge rust (if there are new rust toolchains needed for each desired new crossdev target)

5. emerge --sync for selected target configuration(s)

6. prepare target configuration kernel files

7. order lists of packages to build/install (in configs/target/worlds) based on the indicator
of what previous list each one depends on in configs/target/worlds/tree

8. update target configuration(s) with emerge command for crossdev target

9. update generated binary packages in the final build directories per package list

10. build target configuration kernel(s) and install modules in the "base" final build directory

11. create squashfs images from the final build directories for each package list

12. optionally build squashfs images into the kernel initramfs

13. copy final build kernel/images/bootloader files, where applicable,
to build-helper/builds

14. create squashfs image of (or, optionally, copy) the combined build environment overlays
into build-helper/history for use during the next (update) runs

## "config" squashfs image for each finished build 

to truly complete the builds, it is important to create a persistent configuration image for them.
this can be done with squashfs-tools' mksquashfs or squashfs-tools-ng's gensquashfs.

examples of persistent customized configuration include iptables rules, runlevel/init script selection,
users/passwords, or any other file which is preferred to be kept after powering off or rebooting.

this is done by stacking a each squashfs image chosen at boot time using a colon-separated "squash_stack"
boot parameter in an overlay filesystem in the initramfs init script.

note that the same squashfs images (and whichever additional images one might want to later load in a
virtual machine) must also be included in a colon-separated "squash_load" boot parameter, especially when
using the "docache" boot parameter, which loads the images in a tmpfs, similarly to the gentoo live media
boot parameter of the same name, allowing one to eject the storage device containing these files after
having booted. (for builds using other initramfs generation such as dracut, this feature is not available)

# description of relevant global environment variables 

the following are environment variables which can be passed to build-helper/scripts/build-helper.sh
via a starter script.

- check if user disabled tmux support (default: "on")

```console
TMUX_MODE="${TMUX_MODE:-on}"
```

- gentoo mirror to use for fetching initial chroot tarball (default: Ohio State University mirror)

```console
TARBALL_MIRROR="${TARBALL_MIRROR:-https://gentoo.osuosl.org}"
```

- path to build-helper directory structure (default: auto-detected; currently must remain in the same
location as the first time the script was run for subsequent updates)

```console
BUILD_HELPER_TREE="${BUILD_HELPER_TREE:-$(dirname "${SCRIPT_PATH}")/..}"
```

- base chroot structure mount type (options: "tmpfs" to build everything in memory, or "bind" to use a mounted
filesystem; default: "bind")

```console
MNT_TYPE="${MNT_TYPE:-bind}"
```

- base chroot structure mount options (for tmpfs; default: "30G")

```console
MNT_OPTS="${MNT_OPTS:-size=30G}"
```

- chroot /tmp and /var/tmp type (options: "none" or "tmpfs")

```console
TMP_TYPE="${TMP_TYPE:-none}"
```

- chroot /var/tmp/portage tmpfs mount size (default: "30G")

```console
TMP_SIZE="${TMP_SIZE:-30G}"
```

- make -jN for kernel build, ideally reflecting contents of host chroot /etc/portage (default: detect number of CPU threads)

```console
BUILD_JOBS="${BUILD_JOBS:-`nproc`}"
```

- path to finished work's saved history backup (default: last/latest listed directory in build-helper/history if present)

```console
BUILD_HIST="${BUILD_HIST:-`[ -d ${BUILD_HELPER_TREE}/history ] && [ "$(ls -1 ${BUILD_HELPER_TREE}/history | wc -l)" -gt "0" ] && ls -1 ${BUILD_HELPER_TREE}/history/* | tail -n 1`}"
```

- saved history backup format (options: "squashfs" to compress into an image, or "files" for uncompressed copying; default: "squashfs")

```console
HIST_TYPE="${HIST_TYPE:-squashfs}"
```

- path to gentoo distfiles (default: build-helper/distfiles)

```console
DISTFILES="${DISTFILES:-${BUILD_HELPER_TREE}/distfiles}"
```

- whether to ask before unmounting chroot mounts at the end of the script (default: "yes")

```console
UMOUNT_ASK="${UMOUNT_ASK-yes}"
```

- run the script only to re-mount saved build history in /mnt/name-date/m and then exit; for exploring/maintaining work without building (default: "no")

```console
MOUNT_HIST="${MOUNT_HIST:-no}"
```

# description of specific target configuration files and customization options 

the following aspects of a target configuration are used to specify various
customizations to the resulting flavour of a target's installation through
conditional checks in the build-helper/scripts/build-helper-chroot.sh script.

note: the "host" symbolic link leading to a host configuration for the build
machine, such as the host-amd64 directory, is a simpler and different case.
it contains fewer aspects of the customizations described below, and is used
for setting up a global build environment with all of the build dependencies
required for cross-compiling targets.

## build-arch (file; required) 

used to specify the target architecture outside of portage/emerge, such as when
the kernel is being cross-compiled.

## initramfs (directory; required) 

the contents of this directory is a template used to generate the target
installation's initramfs. files and directories within it tend to be a base,
completed by build-helper to generate something bootable, using either toybox
or busybox depending on user choice.

## linux.config (file; optional) 

the custom linux kernel .config file provided by the user; formats supported
are either a full .config file, where the kernel is entirely built using a
sources based kernel ebuild like sys-kernel/gentoo-sources, or an abbreviated
.config contents placed in the /etc/kernel/config.d directory for customizing
the kernel configuration for a dist-kernel based ebuild such as
sys-kernel/gentoo-kernel.

this file is only optional when the chosen kernel is a kernel distributed in
binary form, such as for the sys-kernel/gentoo-kernel-bin or sys-kernel/raspberrypi-image
ebuilds.

## repos (directory; required, but optionally without ebuilds or eclasses) 

the local portage overlay(s) used by the system target for temporary ebuilds
and eclasses for testing changes to the ::gentoo ebuild repository. each
overlay must be placed in a different directory inside of repos.

## skip.mrproper (empty file; optional) 

when compiling sources based kernel ebuilds, some kernel .config options will
recommend erasing the work files for security reasons; this is therefore done
by default, but for users not requiring such, as well as to reduce duration of
the build process while testing a new target configuration, the presence of
this file will skip deletion of work files after compiling the kernel.

## split.base (empty file; optional) 

the presence of this file will result in a base squashfs image outside of the
initramfs, useful for mounting/accessing files from a physical storage device
rather than loading the software stack into memory.

## split.extra (empty file; optional) 

same function as split.base, but for the optional stacked squashfs images used
as the lowerdir in an overlayfs mount point.

## split.initramfs (empty file; optional) 

the presence of this file will result in generating an initramfs file, separate
from the kernel. without it, the initramfs will be built into the kernel binary.

## target-portage (directory; required) 

the target configuration /etc/portage used by crossdev and located with the
work files' directory tree pointed to when running target emerge commands.

example location during building: /usr/x86_64-unknown-linux-musl.zen2-tb-stack/etc/portage

below are important customizations notes/caveats.

- make.conf contains a commented INSTALL_MASK variable to exclude files when
installing to the final build directories, which gets uncommented during final
stages to reduce resulting installation size. if the script is not run until
fully completed, there is a chance that this variable will need manual commenting
out to avoid build failure. this may be fixed in the future

- certain files in the package.use directory are required for setting up the
target work files' directory tree before cross-compiling the installation's packages.
example: pam

- for embedded toybox/busybox installations, it is important to override the
default packages file in the ::gentoo ebuild repository profiles to reduce the
number of installed packages typically providing the commands that are instead
included as toybox/busybox applets using the profile/packages file

- similarly, it is wise for such embedded installations to further reduce the
packages being installed when unneeded for runtime in profile/package.provided

- taking a closer look at the profile directory, notable less common profile
modifications can be included and even necessary for crossdev targets. a good idea
would be to manually run crossdev and look at what defaults may be found in the
crossdev target work files directory, such as the example path provided above

- the repositories located in the repos directory must be properly described in the 
repos.conf directory

- the savedconfig directory must ideally contain saved configurations for desired
customizations, such as for the sys-kernel/linux-firmware ebuild

## toybox-mini.config OR busybox-mini.config (file; required) 

depending on user choice, selects whether to build toybox or busybox for the
initramfs; also contains the custom minimal configuration used when compiling
the binary used as a basis for the initramfs.

this file also determines which between toybox or busybox is used in stage0
embedded installations.

## toybox.config OR busybox.config (file; optional) 

if the base world file (described below) does not contain the @system set, the
presence of one of these files selects whether to build toybox or busybox as
a base for the installation's software stack; if neither file is present,
build-helper will typically compile a complete stage3 or stage4 installation.

## worlds and worlds/tree (directory tree; required) 

as explained earlier in this document, sets of packages to be installed in
split / stacked directories as the lowerdir of an overlayfs mount are to be
described in separate files in the worlds directory.

furthermore, the worlds/tree directory must contain filenames identical to the
filenames in the worlds directory, in turn containing the filename of another
file in the worlds directory describing the packages that each set depends on,
for build-helper to properly order the installation of packages and avoid
duplicate package installation in each resulting split / stacked directory.

base is the minimum required world file, followed by the required presence of
a worlds/tree directory even if it is empty in the case of users not wanting
a split / stacked filesystem tree. in other words, base can simply contain all
package names to be installed by build-helper in a single final directory.

finally, there are two special cases excluded from the worlds and worlds/tree
ecosystem: kernel (describing the dependencies needed to build/prepare the
kernel as well as the name of the chosen kernel for the installation, which all
typically live outside of the installation for stage0 embedded flavours),
and rust.clean (describing dependencies built early on when setting up the rust
cross-toolchain in the build machine's environment, later cleaned, and excluded
from final stage0 embedded installations).

# reduced LLVM_TARGETS flags per supported architecture 

currently, in order to reduce the final build size, default LLVM_TARGETS flags
from gentoo have been overridden for both the host target configuration and
each target configuration being built for.

to ensure that a build will succeed, one must edit the following files:

- host/target-portage/profile/package.use.force/llvm_targets

- target/target-portage/profile/package.use.force/llvm_targets

# configuring the rust cross-compiler 

for the rust ebuild to generate a cross-compiler for a target configuration,
details for the target must be included in the host target configuration.
the file in question is located in target-portage/env/dev-lang/rust and how
to properly detail the target is documented in the rust ebuild.

an important note is that when a target configuration is for the same CPU
architecture as the build machine, customizations to the rust ebuild create
a custom rust target, for example x86_64-crossdev-linux-musl, to avoid any
errors further into the work flow.

when more than the x86_64 CPU architecture is supported as a build machine,
other custom rust targets will be added.

finally, one must ensure that the target CPU architecture is added to the
LLVM_TARGETS flags, detailed above.

# note on circular dependencies 

a caveat of the script is that it doesn't yet take circular build dependencies
into consideration. therefore, on the first run, some will be encountered upon
setting up the build system's environment before crossdev is run, particularly
one for freetype/harfbuzz. the current solution is to let it fail, and follow
emerge's resolution instructions, then resume the script. this will be solved
eventually.

# final installation structure 

the build-helper/builds directory will contain one directory per built target,
and per build date.

in some cases, the kernel will be in EFI/boot/bootx64.efi because build-helper
looks for the presence of this file to determine that the work is done and that
it can proceed to backing up the work into the history directory. this may be
changed to a better topology later, mirroring more common topologies for other
CPU architectures than x86_64 with EFI support.

for raspberry pi installations, EFI/boot/bootx64.efi will be a symbolic link
to kernel.img (for arm), or kernel8.img (for arm64), located immediately in
the target's builds directory.

other installation files generated by build-helper, typically squashfs images,
as well as the initramfs file, are located immediately in the target's builds
directory.
