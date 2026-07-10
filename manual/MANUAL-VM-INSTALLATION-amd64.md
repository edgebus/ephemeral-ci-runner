# Manual amd64 VM installation

## Bootstrap

### Prepare Kernel

TODO: Disable IPv6. (like `ipv6.disable=1` kernel arg)

See Docker image [gentoo-sources-bundle](https://hub.docker.com/r/theanurin/gentoo-sources-bundle)

```shell
#
# On Mac
#
mkdir ~/w-osfordev
git clone git@github.com:osfordev/gentoo-overlay.git ~/w-osfordev/gentoo-overlay
(cd ~/w-osfordev/gentoo-overlay && git pull)
mkdir -p releases/amd64/next
docker run --rm --interactive --tty \
  --platform linux/amd64 \
  --env KCONFIG_OVERWRITECONFIG=y \
  --env KCONFIG_CONFIG=/gentoo-overlay/profiles/qemuguest/builder/amd64/config-6.18.18-gentoo-qemuguestbuilder \
  --env KBUILD_OUTPUT="/cache/amd64" \
  --volume cache:/cache \
  --mount type=bind,source="$(pwd)/releases/amd64/next",target=/data \
  --mount type=bind,source="${HOME}/w-osfordev/gentoo-overlay",target=/gentoo-overlay \
  theanurin/gentoo-sources-bundle:6.18.18

# Inside Container
make -j$(nproc)
cp "${KCONFIG_CONFIG}"                    /data/amd64.config
cp /cache/amd64/arch/x86_64/boot/bzImage  /data/amd64.bzImage
cp /cache/arm32v7/System.map              /data/amd64.System.map
exit
```

See for kernel at `releases/amd64/next/amd64.bzImage`

### Prepare Disk Image

NOTE: On Mac we may use Docker to prepare disk image

```shell
#
# On Mac
#
mkdir -p releases/amd64/next
docker run --rm --interactive --tty \
  --platform linux/amd64 \
  --privileged \
  --mount type=bind,source="$(pwd)/releases/amd64/next",target=/data \
  gentoo/stage3

#
# Inside Container
#
# init image file for 4Gb
dd if=/dev/zero of=/data/amd64.raw bs=1M count=$((4 * 1024))
# make file system (262144 inodes will be increased to 2359296 after resize disk to 36GB)
mkfs.ext4 -L system -N 262144 /data/amd64.raw
# mount
(mkdir /mnt/gentoo && mount /data/amd64.raw /mnt/gentoo)
# unpack stage3 (on fly)
wget --quiet --content-disposition --output-document=- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt \
  | tee latest-stage3-amd64-openrc.txt
STAGE3_BUILD_PATH=$(cat latest-stage3-amd64-openrc.txt | grep -e '^202[0-9].\+Z.tar.xz' | cut -f1 -d' ')
wget --quiet --content-disposition --output-document=- "https://distfiles.gentoo.org/releases/amd64/autobuilds/${STAGE3_BUILD_PATH}" | tar -xJvpC /mnt/gentoo
# configure password `root` for user `root`
mv /mnt/gentoo/etc/shadow /mnt/gentoo/etc/shadow.bak
echo 'root:$6$oJ4/9UGjWU3xugSV$LYRzOuvq1FlghJa2GfSytZfG3o/I/kW3qJgZj4zLAasXuT9sFfbx6ljyLiQoQBP8wQ6SF15x.h31uxl7.dAtD/:19503:0:::::' >> /mnt/gentoo/etc/shadow
grep -v "^root" /mnt/gentoo/etc/shadow.bak >> /mnt/gentoo/etc/shadow
chmod 640 /mnt/gentoo/etc/shadow
rm /mnt/gentoo/etc/shadow.bak
# add `sshd` daemon to auto start `default`
ln --symbolic /etc/init.d/sshd /mnt/gentoo/etc/runlevels/default/sshd
# add `dhcpcd` daemon to auto start `boot`
ln --symbolic /etc/init.d/dhcpcd /mnt/gentoo/etc/runlevels/boot/dhcpcd
# remove `modules` from auto start `boot` (due kernel non-modular)
rm /mnt/gentoo/etc/runlevels/boot/modules
rm /mnt/gentoo/etc/runlevels/sysinit/kmod-static-nodes
# update `/etc/inittab` to prevent hangs agetty after launch
sed --in-place 's~#s0:12345:respawn:/sbin/agetty -L 115200 ttyS0 vt100~s0:12345:respawn:/sbin/agetty -L 115200 ttyS0 vt100~g' /mnt/gentoo/etc/inittab
# configure `/mnt/gentoo/etc/fstab`
cat <<EOF > /mnt/gentoo/etc/fstab
LABEL=system /    ext4 noatime 0 1
/swapfile    none swap auto    0 0
EOF
# permit login as root in `/mnt/gentoo/etc/ssh/sshd_config`
sed --in-place 's/#PermitRootLogin .*/PermitRootLogin yes/g' /mnt/gentoo/etc/ssh/sshd_config
# provide hostname to DHCP server (unmask hostname)
sed --in-place 's~#hostname~hostname~g' /mnt/gentoo/etc/dhcpcd.conf
# copy kernel (these files are not really used, just for convenience/integrity)
cp /data/amd64.config  /mnt/gentoo/boot/config
cp /data/amd64.bzImage  /mnt/gentoo/boot/bzImage
# setup welcome message
mv /mnt/gentoo/etc/issue /mnt/gentoo/etc/issue.bak
cat <<EOF > /mnt/gentoo/etc/issue

Follow us at https://github.com/edgebus/ephemeral-ci-runner

Default "root" password is "root".
EOF
cat /mnt/gentoo/etc/issue.bak >> /mnt/gentoo/etc/issue
rm /mnt/gentoo/etc/issue.bak
# setup Bash history
cat <<EOF > /mnt/gentoo/root/.bash_history
shutdown -hP now
poweroff -f
EOF
chmod 600 /mnt/gentoo/root/.bash_history
# exit container
umount /mnt/gentoo
exit

#
# On Mac
#
# Convert image to qcow2 format
qemu-img convert --target-format=qcow2 releases/amd64/next/amd64.raw releases/amd64/next/amd64.qcow2
rm releases/amd64/next/amd64.raw
qemu-img resize releases/amd64/next/amd64.qcow2 36G
```

## Install/Configure Software

```shell
#
# On Mac
#
cp misc/qemu-launch-amd64.sh  releases/amd64/next/amd64.sh
./releases/amd64/next/amd64.sh --no-snapshot

#
# Inside Virtual Machine (login as root/root)
#
# resize FS to maximum size
resize2fs /dev/vda
# make swapfile
dd if=/dev/zero of=/swapfile bs=1M count=4096 && mkswap -L swap /swapfile && chmod 600 /swapfile && swapon --all
# setup locales
cat <<'EOF' > /etc/locale.gen
en_US ISO-8859-1
en_US.UTF-8 UTF-8
EOF
locale-gen
cat <<'EOF' > /etc/env.d/02locale
LANG="en_US.utf8"
EOF
env-update && source /etc/profile
# cleanup /etc/portage
rm -r /etc/portage/binrepos.conf
rm -r /etc/portage/package.accept_keywords
rm -r /etc/portage/package.mask
rm -r /etc/portage/package.use
# register OS For Developers repo
mkdir -p /etc/portage/repos.conf
cat <<EOF > /etc/portage/repos.conf/default.conf
[gentoo]
location = /var/db/repos/gentoo
priority = 0 
eclass-overrides = osfordev
sync-type = webrsync
EOF
cat <<EOF > /etc/portage/repos.conf/osfordev.conf
[osfordev]
location = /var/db/repos/osfordev
# Higher priority (default gentoo is -1000) ensures that our ebuilds take precedence in case of version collisions.
priority = 50
auto-sync = yes
sync-type = zipfile
sync-uri = https://osfordev.github.io/gentoo-overlay/latest.zip
#sync-type = git
#sync-uri = https://github.com/osfordev/gentoo-overlay.git
#sync-git-clone-extra-opts = --single-branch --branch dev
EOF
emerge --sync
# select base profile
eselect profile set osfordev:qemuguest/amd64
# install base software
MAKEOPTS="-j$(nproc)" emerge --ask --verbose --newuse --deep --update @world
# Configure kernel configuration linkage
cat <<EOF | tee /etc/env.d/99kernel
# https://www.kernel.org/doc/html/v6.18/kbuild/kconfig.html#environment-variables
# If you set KCONFIG_OVERWRITECONFIG in the environment, Kconfig will not break symlinks when .config is a symlink to somewhere else.
#
# Symlink is: /etc/portage/make.profile/config-X.Y.Z-gentoo-XXXXXXXXX
#
KCONFIG_OVERWRITECONFIG=y
EOF
cat <<'EOF' | tee /etc/profile.d/99kernel.sh
#
# Resolve path to kernel configuration
#
export KCONFIG_CONFIG="/etc/portage/make.profile/config-$(uname --kernel-release)"
EOF
env-update && source /etc/profile
# select target profile
eselect profile set osfordev:qemuguest/builder/amd64
# install target software
MAKEOPTS="-j$(nproc)" emerge --ask --verbose --newuse --deep --update @world

# install Drone Exec Runner
curl -L https://github.com/theanurin/drone-runner-exec/releases/download/v1.0.0-single-stage-mode-02/drone_runner_exec_linux_amd64.tar.gz | tar -xzC /opt
mkdir /etc/drone-runner-exec
cat <<'EOF' > /etc/drone-runner-exec/default
#DRONE_DEBUG="true"
#DRONE_TRACE="true"

DRONE_RPC_SECRET="SET_SECRET"
DRONE_RPC_HOST="drone.infra.example.org"
DRONE_RPC_PROTO="https"
DRONE_RUNNER_CAPACITY="0" # Turn-on single stage mode
DRONE_HTTP_BIND="false"
DRONE_UI_DISABLE="true"
DRONE_RUNNER_LABELS="role:builder,builder.type:default"
# Additional labels will be added on setup instance phase
#DRONE_RUNNER_LABELS="${DRONE_RUNNER_LABELS},???"
EOF

cat <<'EOF' > /etc/local.d/drone-runner-exec.start-
#!/bin/bash
#

# Reboot VM after Drone runner exit
(/opt/drone-runner-exec daemon /etc/drone-runner-exec/default 1>>/var/log/drone-runner-exec.log 2>>/var/log/drone-runner-exec.err ; sleep 60; /usr/bin/poweroff -f) &>/dev/null &
EOF
chmod +x /etc/local.d/drone-runner-exec.start-


# cleanup inside VM
emerge --depclean
rm -rf /tmp/*
rm -rf /var/cache/*
rm -rf /var/db/repos/*
rm -rf /var/log/*
rm -rf /var/tmp/*
rm /etc/ssh/*key*
swapoff -a
dd if=/dev/zero of=/swapfile bs=32M status=progress # to cleanup all disk and future compact on host
truncate --size 4G /swapfile && mkswap -L swap /swapfile && chmod 600 /swapfile
/usr/bin/shutdown -hP now; history -c; exit

#
# On Mac
#
mv releases/amd64/next/amd64.qcow2 releases/amd64/next/amd64.qcow2-bak
qemu-img convert --target-format=qcow2 releases/amd64/next/amd64.qcow2-bak releases/amd64/next/amd64.qcow2
ls -lh releases/amd64/next/
rm releases/amd64/next/amd64.qcow2-bak
chmod 640 releases/amd64/next/amd64.qcow2
cp manual/MANUAL-VM-INSTALLATION-arm.md releases/amd64/next/amd64.BUILD_LOG.md
NOW=$(date '+%Y%m%d')
mv releases/amd64/next/ releases/amd64/$(date '+%Y%m%d')/
```

## References
