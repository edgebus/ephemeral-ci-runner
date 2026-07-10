# Installation for amd64

## Setup Base VM

### Bootstrap

#### Prepare Kernel

TODO: Disable IPv6. (like `ipv6.disable=1` kernel arg)

See Docker image [gentoo-sources-bundle](https://hub.docker.com/r/theanurin/gentoo-sources-bundle)

```shell
# On Mac
git clone git@github.com:osfordev/gentoo-overlay.git ~/w-osfordev/gentoo-overlay
(cd ~/w-osfordev/gentoo-overlay && git pull)
mkdir .build
docker run --rm --interactive --tty --platform linux/amd64 \
  --env KCONFIG_OVERWRITECONFIG=y \
  --env KBUILD_OUTPUT="/cache/amd64" \
  --volume cache:/cache \
  --mount type=bind,source="$(pwd)/.build",target=/data \
  --mount type=bind,source="${HOME}/w-osfordev/gentoo-overlay",target=/gentoo-overlay \
  theanurin/gentoo-sources-bundle:6.12.21

# Inside Container
mkdir --parents "${KBUILD_OUTPUT}"
ln --symbolic /gentoo-overlay/profiles/qemu-guest/builder/amd64/kernel.config "${KBUILD_OUTPUT}/.config"
make -j$(nproc)
cp /cache/amd64/arch/x86_64/boot/bzImage /data/qemu-builder-vm-amd64.vmlinuz
exit
```

Copy `.build/qemu-builder-vm-amd64.vmlinuz` to VM Host `/tmp/qemu-builder-vm-amd64.vmlinuz`

#### Prepare Disk Image

NOTE: On Mac we may use Docker to prepare disk image

```shell
mkdir .build
docker run --rm --interactive --tty --platform linux/amd64 --privileged \
  --mount type=bind,source="$(pwd)/.build",target=/tmp \
  gentoo/stage3
```

1. Create image
   ```shell
   dd if=/dev/zero of=/tmp/qemu-builder-vm-amd64.raw bs=1M count=$((4 * 1024))
   mkfs.ext4 -L system -N 2359296 /tmp/qemu-builder-vm-amd64.raw
   mkdir /mnt/gentoo
   mount /tmp/qemu-builder-vm-amd64.raw /mnt/gentoo
   ```
1. Use Gentoo installation guide to unpack
   ```shell
   (cd /mnt/gentoo && wget --no-hsts -qO- https://mirror.bytemark.co.uk/gentoo/releases/amd64/autobuilds/20240616T153408Z/stage3-amd64-openrc-20240616T153408Z.tar.xz | tar -xJvp)
   ```
1. Make minimal settings of stage3
   - [ ] set password `root` for user `root`
     ```shell
     mv /mnt/gentoo/etc/shadow /mnt/gentoo/etc/shadow.bak
     echo 'root:$6$oJ4/9UGjWU3xugSV$LYRzOuvq1FlghJa2GfSytZfG3o/I/kW3qJgZj4zLAasXuT9sFfbx6ljyLiQoQBP8wQ6SF15x.h31uxl7.dAtD/:19503:0:::::' >> /mnt/gentoo/etc/shadow
     grep -v "^root" /mnt/gentoo/etc/shadow.bak >> /mnt/gentoo/etc/shadow
     chmod 640 /mnt/gentoo/etc/shadow
     rm /mnt/gentoo/etc/shadow.bak
     ```
   - [ ] add `sshd` daemon to auto start `default`
     ```shell
     ln --symbolic /etc/init.d/sshd /mnt/gentoo/etc/runlevels/default/sshd
     ```
   - [ ] add `dhcpcd` daemon to auto start `boot`
     ```shell
     ln --symbolic /etc/init.d/dhcpcd /mnt/gentoo/etc/runlevels/boot/dhcpcd
     ```
   - [ ] remove `modules` from auto start `boot` (due kernel non-modular)
     ```shell
     rm /mnt/gentoo/etc/runlevels/boot/modules
     rm /mnt/gentoo/etc/runlevels/sysinit/kmod-static-nodes
     ```
1. Configure `/mnt/gentoo/etc/fstab`
   ```shell
   echo "LABEL=system / ext4 noatime 0 1" >> /mnt/gentoo/etc/fstab
   echo "/swapfile none swap auto 0 0" >> /mnt/gentoo/etc/fstab
   ```
1. Permit login as root in `/mnt/gentoo/etc/ssh/sshd_config`
   ```shell
   sed --in-place 's/#PermitRootLogin .*/PermitRootLogin yes/g' /mnt/gentoo/etc/ssh/sshd_config
   ```
1. Provide hostname to DHCP server (unmask hostname)
   ```shell
   sed --in-place 's~#hostname~hostname~g' /mnt/gentoo/etc/dhcpcd.conf
   ```
1. Copy kernel (this file is not really used, just for convenience/integrity)
   ```shell
   cp /tmp/qemu-builder-vm-amd64.vmlinuz /mnt/gentoo/boot/vmlinuz
   ```
1. Umount
   ```shell
   cd /
   umount /mnt/gentoo
   ```
1. Convert image to qcow2 format
   ```shell
   qemu-img convert -O qcow2 /tmp/qemu-builder-vm-amd64.raw /tmp/qemu-builder-vm-amd64.qcow2
   rm /tmp/qemu-builder-vm-amd64.raw
   qemu-img resize /tmp/qemu-builder-vm-amd64.qcow2 48G
   ```
1. Move image to `/var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64.qcow2`
   ```shell
   mv /tmp/qemu-builder-vm-amd64.qcow2 /var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64.qcow2
   ```

### Install/Configure Software

#### Launch VM (setup mode)

1. Run qemu VM

   ```shell
   cp /tmp/qemu-builder-vm-amd64.vmlinuz /var/lib/qemu-vms/qemu-builder-vm/

   export DRIVE_FILE=/var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64.qcow2
   export KERNEL_PATH=/var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64.vmlinuz

   qemu-system-x86_64 \
       -enable-kvm \
       -machine pc \
       -cpu max \
       -smp 6 \
       -m 8G \
       -kernel "${KERNEL_PATH}" \
       -append 'root=/dev/vda' \
       -device virtio-blk,drive=disk0 \
       -drive if=none,file=${DRIVE_FILE},id=disk0 \
       -device virtio-net,netdev=vm_eth0 \
       -netdev "user,id=vm_eth0,hostname=qemu-builder-vm-setup,hostfwd=tcp:0.0.0.0:65425-:22" \
       -device virtio-rng-pci \
       -device virtio-keyboard-pci \
       -display vnc=0.0.0.0:0,password=on \
       -monitor stdio
   ```

2. Allow VNC Access (by set VNC password)
   ```text
   QEMU 10.0.5 monitor - type 'help' for more information
   (qemu) change vnc password
   Password: **
   (qemu)
   ```

#### Connect

Note: A following alias `cssh` looks like

```shell
alias cssh='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```

#### Connect into terminal via SSH

- Locally
  ```shell
  cssh -p 65425 root@127.0.0.1
  ```
- Remotely
  ```shell
  cssh -J tw00 -p 65425 root@127.0.0.1
  ```

##### Connect via VNC

```shell
cssh -L5900:127.0.0.1:5900 tw00
```

```shell
open vnc://127.0.0.1:5900
```

#### Prepare

1. Set some strong password for user `root`
   ```shell
   passwd
   ```
1. Resize FS to maximum size
   ```shell
   resize2fs /dev/vda
   ```
1. Make swapfile
   ```shell
   dd if=/dev/zero of=/swapfile bs=1M count=4096 && mkswap -L swap /swapfile && chmod 600 /swapfile && swapon --all
   ```
1. Fetch Portage repository `gentoo`
   ```shell
   emerge-webrsync
   ```
1. Install `git` (to be able to fetch `osfordev` repo)
   ```shell
   emerge --ask --verbose --oneshot dev-vcs/git
   ```
1. Register OS For Developers repo
   ```shell
   mkdir -p /etc/portage/repos.conf
   cat <<EOF > /etc/portage/repos.conf/osfordev-repo.conf
   [osfordev]
   location = /var/db/repos/osfordev
   sync-type = git
   sync-uri = https://github.com/osfordev/gentoo-overlay.git
   sync-git-clone-extra-opts = --single-branch --branch dev
   auto-sync = yes
   EOF
   ```
1. Fetch Portage repository `osfordev`
   ```shell
   emerge --sync osfordev
   ```
1. Select profile `osfordev:qemu-guest/builder/amd64`
   ```shell
   eselect profile set osfordev:qemu-guest/builder/amd64
   ```
1. Accept Keywords
1. Apply patches
1. Install software
   ```shell
   emerge --ask --verbose --newuse --deep --update --job=3 @world
   ```
1. Install Woodpecker Agent (see https://gitea.zxteam.net/orgs/zxteam/src/branch/docs/woodpecker.md)

   ```shell
   useradd \
       --user-group \
       --home-dir /var/lib/woodpecker-agent \
       --create-home \
       woodpecker-agent

   wget --no-hsts --quiet --output-document=- https://github.com/theanurin/woodpecker/releases/download/v2.7.0-single-workflow-2/woodpecker-agent_linux_amd64.tar.gz | tar -xzv -C /opt

   mkdir /opt/bin
   wget --no-hsts --output-document=/opt/bin/plugin-git https://github.com/woodpecker-ci/plugin-git/releases/download/2.5.2/linux-amd64_plugin-git
   chmod +x /opt/bin/plugin-git
   plugin-git --help

   cat <<'EOF' > /etc/init.d/woodpecker-agent
   #!/sbin/openrc-run

   command="/opt/woodpecker-agent"
   command_args="
           --connect-retry-delay 30s
           --connect-retry-count 86400
           ${AGENT_OPTS}"
   command_background=true
   extra_started_commands="reload"
   name="${name:-Woodpecker Agent}"
   pidfile="/run/${RC_SVCNAME}.pid"
   output_log="/var/log/woodpecker-agent/woodpecker-agent.log"
   error_log="/var/log/woodpecker-agent/woodpecker-agent.err"

   retry="QUIT/60/TERM/60"
   start_stop_daemon_args="--user \"root\" --name \"${RC_SVCNAME}\" --chdir \"/var/lib/woodpecker-agent\""

   depend() {
       need localmount
       after net.lo loopback
   }

   start_pre() {
       checkpath -d -m 0750 -o "root" "/var/log/woodpecker-agent"
   }

   reload() {
       ebegin "Reloading ${name} configuration"
       start-stop-daemon --signal HUP --pidfile "${pidfile}"
       eend $? "Failed to reload ${name}"
   }
   EOF

   chmod +x /etc/init.d/woodpecker-agent

   cat <<'EOF' > /etc/local.d/woodpecker-agent.start-
   #!/bin/bash
   #

   set -e

   source /etc/conf.d/woodpecker-agent

   set +e

   # Reboot VM after Woodpecker Agent exit
   (/opt/woodpecker-agent ${AGENT_OPTS} 1>>/var/log/woodpecker-agent/woodpecker-agent.log 2>>/var/log/woodpecker-agent/woodpecker-agent.err ; sleep 60; /usr/bin/poweroff -f) &>/dev/null &
   EOF

   chmod +x /etc/local.d/woodpecker-agent.start-

   cat <<'EOF' > /etc/conf.d/woodpecker-agent
   AGENT_OPTS="--log-level info"
   AGENT_OPTS="${AGENT_OPTS} --backend-engine local"
   AGENT_OPTS="${AGENT_OPTS} --server 164.92.248.198:22284"
   #AGENT_OPTS="${AGENT_OPTS} --server woodpecker.zxteam.net:22284"
   AGENT_OPTS="${AGENT_OPTS} --grpc-token ????"
   AGENT_OPTS="${AGENT_OPTS} --single-workflow"
   AGENT_OPTS="${AGENT_OPTS} --healthcheck=false"
   AGENT_OPTS="${AGENT_OPTS} --log-level debug"
   AGENT_OPTS="${AGENT_OPTS} --filter role=builder --filter builder.type=osfordev"
   # Additional filters will be added on setup instance phase
   #AGENT_OPTS="${AGENT_OPTS} ???"
   EOF

   mkdir /etc/woodpecker
   echo -n '{"agent_id":9999}' > /etc/woodpecker/agent.conf

   mkdir --parents /var/log/woodpecker-agent
   ```

1. Install Drone Exec Runner (see https://gitea.zxteam.net/zxteam/zxteam/src/branch/docs/drone-ci.md)

   ```shell
   curl -L https://github.com/theanurin/drone-runner-exec/releases/download/v1.0.0-single-stage-mode-02/drone_runner_exec_linux_amd64.tar.gz | tar -xzC /opt
   /opt/drone-runner-exec --help

   mkdir /etc/drone-runner-exec

   cat <<'EOF' > /etc/drone-runner-exec/osfordev
   #DRONE_DEBUG="true"
   #DRONE_TRACE="true"

   DRONE_RPC_SECRET="SET_SECRET"

   DRONE_RPC_HOST="drone.infra.zxteam.net"
   DRONE_RPC_PROTO="https"
   DRONE_RUNNER_CAPACITY="0" # Turn-on single stage mode
   DRONE_HTTP_BIND="false"
   DRONE_UI_DISABLE="true"
   DRONE_RUNNER_LABELS="role:builder,builder.type:osfordev"
   # Additional labels will be added on setup instance phase
   #DRONE_RUNNER_LABELS="${DRONE_RUNNER_LABELS},???"
   EOF

   cat <<'EOF' > /etc/local.d/drone-runner-exec.start-
   #!/bin/bash
   #

   # Reboot VM after Drone runner exit
   (/opt/drone-runner-exec daemon /etc/drone-runner-exec/osfordev 1>>/var/log/drone-runner-exec.log 2>>/var/log/drone-runner-exec.err ; sleep 60; /usr/bin/poweroff -f) &>/dev/null &
   EOF

   chmod +x /etc/local.d/drone-runner-exec.start-
   ```

1. Auto-start
   ```shell
   rc-update add docker default
   ```
1. Cleanup inside VM
   ```shell
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
   rm /root/.bash_history; /usr/bin/shutdown -hP now; history -c; exit
   ```
1. Cleanup on host
   ```shell
   mv "${DRIVE_FILE}" "${DRIVE_FILE}-bak"
   qemu-img convert -O qcow2 "${DRIVE_FILE}-bak" "${DRIVE_FILE}"
   rm "${DRIVE_FILE}-bak"
   chmod 640 "${DRIVE_FILE}"
   ```

## Setup Instance VM

### Create Disk Image

[!] Make sure base VM is power off

```shell
export INSTANCE_ID="25"
export DRIVE_BACKING_FILE=/var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64.qcow2
export DRIVE_INSTANCE_FILE="/var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64-${INSTANCE_ID}.qcow2"
qemu-img create -F qcow2 -b "${DRIVE_BACKING_FILE}" -f qcow2 "${DRIVE_INSTANCE_FILE}"
```

### Create configuration

```shell
export INSTANCE_ID="25"
cat <<EOF > /var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64-${INSTANCE_ID}.conf
USE_KVM=yes
CPU=6
#CPU_FLAGS=max
MEM=12
# Choose "bridge" or "nat". Use "bridge" only in good network infrastructure. Is works badly in a home network (home router may provide bad DHCP experience that case broken builds)
#NETWORK=bridge
NETWORK=nat
SSH_FORWARD_PORT=654${INSTANCE_ID}
EOF
```

### Prepare Instance VM

1. Make first (manual) launch
   ```shell
   INSTANCE_ID="25"
   ln --symbolic /var/lib/qemu-vms/qemu-builder-vm/qemu-builder-vm-amd64 /etc/local.d/qemu-builder-vm-amd64.${INSTANCE_ID}.start
   DEBUG=yes VNC_DISPLAY=0 NO_SNAPSHOT=yes /etc/local.d/qemu-builder-vm-amd64.${INSTANCE_ID}.start
   ```
   Note: `NO_SNAPSHOT` say launcher to do not use `-snapshot` qemu option, to make permanent changes on VM's disk.
1. Connect into terminal via SSH (see SSH_FORWARD_PORT value in conf file)
   ```shell
   cssh -p 65425 root@127.0.0.1
   ```
1. Set hostname
   ```shell
   export INSTANCE_ID="25"
   echo "hostname=\"qemu-builder-vm-amd64-${INSTANCE_ID}\"" >  /etc/conf.d/hostname
   echo "127.0.0.1 qemu-builder-vm-amd64-${INSTANCE_ID}"    >> /etc/hosts
   echo "::1       qemu-builder-vm-amd64-${INSTANCE_ID}"    >> /etc/hosts
   ```
1. Reboot VM and reconnect terminal via SSH
   ```shell
   reboot
   ```

#### Configure One Of CI Runner/Agent

##### ~~Configure GitLab Runner Instance (Obsolete)~~

1. collect runner tags
   ```shell
   TAGS="platform:amd64,osfordev"
   for CPU_FLAG in $(cat /proc/cpuinfo | grep --extended-regexp '^flags' | head -n 1 | cut -d: -f2 | xargs | tr ' ' '\n' | sort | tr '\n' ' '); do
       TAGS="${TAGS},osfordev:cpuflag:${CPU_FLAG}"
   done
   echo $TAGS
   ```
1. setup `gitlab-runner` using tags: `qemu,osfordev-builder,platform:amd64` and executor: `custom` by run `gitlab-runner register`
1. fullfil `/etc/gitlab-runner/config.toml`
   ```toml
   concurrent = 1
   check_interval = 0
   shutdown_timeout = 0
   [session_server]
     session_timeout = 1800
   [[runners]]
     name = "qemu-builder-vm-amd64-25"
     url = "https://dev.zxteam.net/"
     id = XX
     token = "xxxxxxxx"
     token_obtained_at = 2024-05-15T06:36:58Z
     token_expires_at = 0001-01-01T00:00:00Z
     executor = "custom"
     builds_dir = "/builds"
     cache_dir = "/cache"
     output_limit = 10240
     [runners.custom_build_dir]
     [runners.cache]
       MaxUploadedArchiveSize = 0
       [runners.cache.s3]
       [runners.cache.gcs]
       [runners.cache.azure]
     [runners.custom]
       run_exec = "/bin/bash"
       cleanup_exec = "/usr/bin/shutdown"
       cleanup_args = [ "-hP", "now" ]
   ```
1. add daemon to auto start `rc-update add gitlab-runner default`
1. cleanup and halt VM `rm /root/.bash_history; /usr/bin/shutdown -hP now; history -c; exit`

##### ~~Configure Woodpecker Agent Instance (Obsolete)~~

1. In _[Woodpecker Admin UI](https://woodpecker.zxteam.net/admin#agents)_ create an agent in **Disabled State** (to prevent start any pipelines)
   - name(sample): osfordev-${INSTANCE} on lo00
   - grab Agent **ID**
   - grab grpc **Token**
1. setup agent CPU filters labels
   ```shell
   for CPU_FLAG in $(cat /proc/cpuinfo | grep --extended-regexp '^flags' | head -n 1 | cut -d: -f2 | xargs | tr ' ' '\n' | sort | tr '\n' ' '); do
       echo "AGENT_OPTS=\"\${AGENT_OPTS} --filter builder.cpuflag.${CPU_FLAG}=yes\""
   done >> /etc/conf.d/woodpecker-agent
   ```
1. fill `/etc/woodpecker/agent.conf` file contains `{"agent_id":XXXXX}` (replace `XXXXX` to Agent **ID**)
1. edit `/etc/conf.d/woodpecker-agent` to
   - uncomment AGENT_OPTS option
     - set `--grpc-token=????` (replace `????`)
     - add FILTER_LABELS
     - check `--server` value
1. add to auto start `mv /etc/local.d/woodpecker-agent.start- /etc/local.d/woodpecker-agent.start`
1. cleanup and halt VM `rm /root/.bash_history; /usr/bin/shutdown -hP now; history -c; exit`
1. In _Woodpecker Admin UI_ enable the agent
1. To troubleshoot problems, begin from `tail --follow /var/log/woodpecker-agent.*` inside Instance VM

##### Configure Drone Runner Instance

1. obtain Drone RPC password (from Drone Server configuration)
1. edit `/etc/drone-runner-exec/osfordev` to
   - set value of `DRONE_RPC_SECRET`
   - add labels `DRONE_RUNNER_LABELS`, for example `hostname:qemu-builder-vm-amd64-24`
1. add to auto start `mv /etc/local.d/drone-runner-exec.start- /etc/local.d/drone-runner-exec.start`
1. cleanup and halt VM `rm /root/.bash_history; /usr/bin/shutdown -hP now; history -c; exit`
1. To troubleshoot problems, begin from `tail --follow /var/log/drone-runner-exec.*` inside Instance VM

qemu-builder-vm-amd64-25 ~ # cat /etc/drone-runner-exec/osfordev
#DRONE_DEBUG="true"
#DRONE_TRACE="true"

DRONE_RPC_SECRET="240d5068c4e6d8bd37ec7c601af99651"

DRONE_RPC_HOST="drone.infra.zxteam.net"
DRONE_RPC_PROTO="https"
DRONE_RUNNER_CAPACITY="0" # Turn-on single stage mode
DRONE_HTTP_BIND="false"
DRONE_UI_DISABLE="true"
DRONE_RUNNER_LABELS="role:builder,builder.type:osfordev"

# Additional labels will be added on setup instance phase

#DRONE_RUNNER_LABELS="${DRONE_RUNNER_LABELS},???"

DEBUG=yes VNC_DISPLAY=0 NO_SNAPSHOT=yes /etc/local.d/qemu-docker-swarm-demo-01.start

export INSTANCE_ID=x
echo "hostname=\"docker-swarm-node-0${INSTANCE_ID}\""                                                         >  /etc/conf.d/hostname
echo "127.0.0.1       node0${INSTANCE_ID} docker-swarm-node-0${INSTANCE_ID}.sandbox.docker-swarm.example.org" >> /etc/hosts
echo "::1             node0${INSTANCE_ID} docker-swarm-node-0${INSTANCE_ID}.sandbox.docker-swarm.example.org" >> /etc/hosts

cat <<EOF > /etc/conf.d/net
dns_servers="8.8.8.8 8.8.4.4"
dns_domain_lo="sandbox.docker-swarm.example.org"

config_eth0="172.16.0.${INSTANCE_ID}/24"
routes_eth0="default via 172.16.0.254"
EOF

ln -s net.lo /etc/init.d/net.eth0

rc-update add net.eth0
rc-update del dhcpcd boot

mkdir ~/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXoq5VchuGwfyLcEyGNMes9+fUv3N7FlXvSKH1Fx1+ceaiqKTUU3PiUjr99kx8x2otcQt2uHzUqWRvt1640bkv2vnosKlisq9FYfi8nWd+KrbcUmZLhUrijn5M5kOTRKgncD4uFlxnc165XMwuVYEJZe9GFxGMtf7iYvOiIYJ2G0BHp6OS7xrjIV4I/v8yMJVz9kxlwoe3HM4XKotqDbM/D6pNA9fWCTE5+//SympDGfgSKRcpi9dI4sLSqwXmhw5S1MA1bCnwMfzrcm5vS2GJpPoPddcV+4LtRgfGT+e/zg6Og01cADIo6JXWhg5F2edlbOKWwfysClBXZ5yCBtj32XXXC4Fhq7w9OWF2z5fpxfRIbVw+FZQpbzKQgvSyfaBBRVWGiZnaSy57xeF1RWadb1bcARLq04a7c5WijBK02EgVnFDV7Z5qsgT6E7/wHSF7ZQYlpYpFdXuAcGohmyrZAKoxxK8qrTlUyiYEet0l+XBDKyG42aq1pU/vxzjr/+s= maxim.anurin@zxlaptop0a" > ~/.ssh/authorized_keys

reboot

rm /root/.bash_history; /usr/bin/shutdown -hP now; history -c; exit

docker swarm init --advertise-addr 172.16.0.1

# Manager

docker swarm join --token SWMTKN-1-11avqo1i7d97vrweicv9fmud0o2nnoa3c6nalfh9gqhtg9vcnr-6hcysq32qaz33efzxpgjlbc0b 172.16.0.1:2377

# Worker

docker swarm join --token SWMTKN-1-11avqo1i7d97vrweicv9fmud0o2nnoa3c6nalfh9gqhtg9vcnr-3hud13xlxja3q56pdmsuvr45x 172.16.0.1:2377

/etc/init.d/docker stop; sleep 3; rm -r /var/log/docker.log; rm -r /var/log/containerd/containerd.log; rm /root/.bash_history; /usr/bin/shutdown -hP now; history -c; exit

# On node 01

```shell
emerge-webrsync; emerge --sync osfordev; emerge --oneshot --verbose app-misc/screen
ssh-keygen
cat ~/.ssh/id_ed25519.pub # set key to dg04 /root/.ssh/authorized_keys

screen /bin/bash -c "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -R 80:127.0.0.1:80 -R 443:127.0.0.1:443 -N root@dg05.zxteam.net"
```

# On node 04 and 05

```shell
chmod o+rw /var/run/docker.sock
```
