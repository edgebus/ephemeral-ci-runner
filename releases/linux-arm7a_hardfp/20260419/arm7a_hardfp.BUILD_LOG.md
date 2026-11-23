# Manual ARM7l VM installation

## Bootstrap

### Prepare Kernel

See Docker image [gentoo-sources-bundle](https://hub.docker.com/r/theanurin/gentoo-sources-bundle)

```shell
#
# On Mac
#
mkdir ~/w-osfordev
git clone git@github.com:osfordev/gentoo-overlay.git ~/w-osfordev/gentoo-overlay
(cd ~/w-osfordev/gentoo-overlay && git pull && git log -1)
mkdir -p releases/arm7a_hardfp/next
docker run --rm --interactive --tty \
  --platform linux/arm/v7 \
  --env KCONFIG_OVERWRITECONFIG=y \
  --env KCONFIG_CONFIG=/gentoo-overlay/profiles/qemuguest/builder/arm32v7/config-6.18.18-gentoo-qemuguestbuilder \
  --env KBUILD_OUTPUT="/cache/arm32v7" \
  --volume cache:/cache \
  --mount type=bind,source="$(pwd)/releases/arm7a_hardfp/next",target=/data \
  --mount type=bind,source="${HOME}/w-osfordev/gentoo-overlay",target=/gentoo-overlay \
  theanurin/gentoo-sources-bundle:6.18.18

# Inside Container
make -j$(nproc)
cp "${KCONFIG_CONFIG}"                  /data/arm7a_hardfp.config
cp /cache/arm32v7/arch/arm/boot/zImage  /data/arm7a_hardfp.zImage
cp /cache/arm32v7/System.map            /data/arm7a_hardfp.System.map
exit
```

See for kernel at `releases/arm7a_hardfp/next/arm7a_hardfp.zImage`

### Prepare Disk Image

NOTE: On Mac we may use Docker to prepare disk image

```shell
#
# On Mac
#
mkdir -p releases/arm7a_hardfp/next
docker run --rm --interactive --tty \
  --platform linux/arm/v7 \
  --privileged \
  --mount type=bind,source="$(pwd)/releases/arm7a_hardfp/next",target=/data \
  gentoo/stage3

#
# Inside Container
#
# init image file for 4Gb
dd if=/dev/zero of=/data/arm7a_hardfp.raw bs=1M count=$((4 * 1024))
# make file system
mkfs.ext4 -L system -N 2359296 /data/arm7a_hardfp.raw
# mount
(mkdir /mnt/gentoo && mount /data/arm7a_hardfp.raw /mnt/gentoo)
# unpack stage3 (on fly)
wget --quiet --content-disposition --output-document=- https://distfiles.gentoo.org/releases/arm/autobuilds/latest-stage3-armv7a_hardfp-openrc.txt \
  | tee latest-stage3-armv7a_hardfp-openrc.txt
STAGE3_BUILD_PATH=$(cat latest-stage3-armv7a_hardfp-openrc.txt | grep -e '^202[0-9].\+Z.tar.xz' | cut -f1 -d' ')
wget --quiet --content-disposition --output-document=- "https://distfiles.gentoo.org/releases/arm/autobuilds/${STAGE3_BUILD_PATH}" | tar -xJvpC /mnt/gentoo
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
sed --in-place 's~s0:12345:respawn:/sbin/agetty -L 9600 ttyS0 vt100~s0:12345:respawn:/sbin/agetty -L 9600 ttyAMA0 vt100~g' /mnt/gentoo/etc/inittab
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
cp /data/arm7a_hardfp.config  /mnt/gentoo/boot/config
cp /data/arm7a_hardfp.zImage  /mnt/gentoo/boot/zImage
# setup welcome message
mv /etc/issue /etc/issue.bak
cat <<EOF > /etc/issue

Follow us at https://github.com/edgebus/ephemeral-ci-runner
Default "root" password is "root".
EOF
cat /etc/issue.bak >> /etc/issue
rm /etc/issue.bak
# setup Bash history
cat <<EOF > /root/.bash_history
shutdown -hP now
poweroff -f
EOF
chmod 600 /root/.bash_history
# exit container
umount /mnt/gentoo
exit

#
# On Mac
#
# Convert image to qcow2 format
qemu-img convert -O qcow2 releases/arm7a_hardfp/next/arm7a_hardfp.raw releases/arm7a_hardfp/next/arm7a_hardfp.qcow2
rm releases/arm7a_hardfp/next/arm7a_hardfp.raw
qemu-img resize releases/arm7a_hardfp/next/arm7a_hardfp.qcow2 36G
```

## Install/Configure Software

```shell
#
# On Mac
#
cp misc/qemu-launch-arm7a_hardfp.sh  releases/arm7a_hardfp/next/arm7a_hardfp.sh
./releases/arm7a_hardfp/next/arm7a_hardfp.sh --no-snapshot

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

rm -r /etc/portage/binrepos.conf
rm -r /etc/portage/package.accept_keywords
rm -r /etc/portage/package.mask
rm -r /etc/portage/package.use
rm -r /etc/portage/repos.conf

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
eselect profile set osfordev:qemuguest/arm32v7
# install base software
MAKEOPTS="-j$(nproc)" emerge --ask --verbose --newuse --deep --update @world
# select target profile
eselect profile set osfordev:qemuguest/builder/arm32v7
# install target software
MAKEOPTS="-j$(nproc)" emerge --ask --verbose --newuse --deep --update @world

# install Drone Exec Runner
curl -L https://github.com/theanurin/drone-runner-exec/releases/download/v1.0.0-single-stage-mode-02/drone_runner_exec_linux_arm.tar.gz | tar -xzC /opt
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
mv releases/arm7a_hardfp/next/arm7a_hardfp.qcow2 releases/arm7a_hardfp/next/arm7a_hardfp.qcow2-bak
qemu-img convert -O qcow2 releases/arm7a_hardfp/next/arm7a_hardfp.qcow2-bak releases/arm7a_hardfp/next/arm7a_hardfp.qcow2
ls -lh releases/arm7a_hardfp/next/
rm releases/arm7a_hardfp/next/arm7a_hardfp.qcow2-bak
chmod 640 releases/arm7a_hardfp/next/arm7a_hardfp.qcow2
cp manual/MANUAL-VM-INSTALLATION-arm.md releases/arm7a_hardfp/next/arm7a_hardfp.BUILD_LOG.md
NOW=$(date '+%Y%m%d')
mv releases/arm7a_hardfp/next/ releases/arm7a_hardfp/$(date '+%Y%m%d')/
```

## References

- https://translatedcode.wordpress.com/2016/11/03/installing-debian-on-qemus-32-bit-arm-virt-board/
