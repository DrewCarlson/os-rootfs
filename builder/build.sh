#!/bin/bash
set -ex
source builder/gpgcheck.sh

# this script should be run inside of a Docker container only
if [ ! -f /.dockerenv ]; then
  echo "ERROR: script works in Docker only!"
  exit 1
fi

# Hypriot common settings
HYPRIOT_HOSTNAME="${HYPRIOT_HOSTNAME:-black-pearl}"

# build Debian rootfs for ARCH={armhf,arm64,mips,i386,amd64}
# - Debian armhf = ARMv6/ARMv7
# - Debian arm64 = ARMv8/Aarch64
# - Debian mips  = MIPS
# - Debian i386  = Intel/AMD 32-bit
# - Debian amd64 = Intel/AMD 64-bit
BUILD_ARCH="${BUILD_ARCH:-arm64}"
QEMU_ARCH="${QEMU_ARCH}"
VARIANT="${VARIANT:-debian}"
HYPRIOT_OS_VERSION="${HYPRIOT_OS_VERSION:-dirty}"
ROOTFS_DIR="/debian-${BUILD_ARCH}"
DEBOOTSTRAP_URL="http://ftp.debian.org/debian"
DEFAULT_PACKAGES_INCLUDE="apt-transport-https,avahi-daemon,bash-completion,binutils,ca-certificates,curl,git,htop,locales,net-tools,ntp,openssh-server,parted,sudo,usbutils,wget,libpam-systemd,gnupg"
DEFAULT_PACKAGES_EXCLUDE="debfoster"

if [[ "${VARIANT}" = "raspbian" ]]; then
  # for Raspbian we need an extra gpg key to be able to access the repository
  mkdir -p /builder/files/tmp
  wget -v -O "/builder/files/tmp/raspbian.public.key" http://archive.raspberrypi.org/debian/raspberrypi.gpg.key
  get_gpg CF8A1AF502A2AA2D763BAE7E82B129927FA3303E "/builder/files/tmp/raspbian.public.key"

fi

# show TRAVIS_TAG in travis builds
echo TRAVIS_TAG="${TRAVIS_TAG}"

# cleanup
mkdir -p /workspace
rm -fr "${ROOTFS_DIR}"

# define ARCH dependent settings
DEBOOTSTRAP_CMD="debootstrap"

# debootstrap a minimal Debian Bullseye rootfs
${DEBOOTSTRAP_CMD} \
  --arch="${BUILD_ARCH}" \
  --include="${DEFAULT_PACKAGES_INCLUDE}" \
  --exclude="${DEFAULT_PACKAGES_EXCLUDE}" \
  bullseye \
  "${ROOTFS_DIR}" \
  "${DEBOOTSTRAP_URL}"

# modify/add image files directly
cp -R /builder/files/* "$ROOTFS_DIR/"

# only keep apt/sources.list files that we need for the current build
if [[ "$VARIANT" == "debian" ]]; then
  rm -f "$ROOTFS_DIR/etc/apt/sources.list.raspbian"
elif [[ "$VARIANT" == "raspbian" ]]; then
  mv -f "$ROOTFS_DIR/etc/apt/sources.list.raspbian" "$ROOTFS_DIR/etc/apt/sources.list"
fi

# set up mount points for the pseudo filesystems
mkdir -p "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/dev/pts"

mount -o bind /dev "$ROOTFS_DIR/dev"
mount -o bind /dev/pts "$ROOTFS_DIR/dev/pts"
mount -t proc none "$ROOTFS_DIR/proc"
mount -t sysfs none "$ROOTFS_DIR/sys"

# make our build directory the current root
# and install the Rasberry Pi firmware, kernel packages,
# docker tools and some customizations
chroot "$ROOTFS_DIR" \
       /usr/bin/env \
       HYPRIOT_HOSTNAME="$HYPRIOT_HOSTNAME" \
       HYPRIOT_OS_VERSION="$HYPRIOT_OS_VERSION" \
       BUILD_ARCH="$BUILD_ARCH" \
       VARIANT="$VARIANT" \
       /bin/bash < /builder/chroot-script.sh

# unmount pseudo filesystems
umount -l "$ROOTFS_DIR/dev/pts"
umount -l "$ROOTFS_DIR/dev"
umount -l "$ROOTFS_DIR/proc"
umount -l "$ROOTFS_DIR/sys"

# ensure that there are no leftover artifacts in the pseudo filesystems
rm -rf "$ROOTFS_DIR/{dev,sys,proc}/*"

# package rootfs tarball
umask 0000

pushd /workspace
ARCHIVE_NAME="rootfs-${BUILD_ARCH}-${VARIANT}-${HYPRIOT_OS_VERSION}.tar.gz"
tar -czf "${ARCHIVE_NAME}" -C "${ROOTFS_DIR}/" .
sha256sum "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256"
popd

# test if rootfs is OK
HYPRIOT_HOSTNAME="${HYPRIOT_HOSTNAME}" VARIANT="${VARIANT}" /builder/test.sh
