#!/bin/sh
#

set -eo pipefail

# Normalize SCRIPT_DIR
SCRIPT_DIR=$(cd $(dirname "$0") && pwd -LP)

REVISION=$(basename "${SCRIPT_DIR}")

KERNEL_PATH="${SCRIPT_DIR}/linux-arm7a_hardfp.zImage"
DRIVE_FILE="${SCRIPT_DIR}/linux-arm7a_hardfp.qcow2"

SNAPSHOT="yes"
FORWARD_SSH_PORT=""
DISPLAY_VNC=""
NETWORK_BRIDGE_DEV=""

QEMU_ADDITIONAL_OPTS=""

while (( "$#" )); do
        case "${1}" in
                --headless)
                        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -nographic"
                        ;;
                --ssh-port=*)
                        FORWARD_SSH_PORT="$(echo "$1" | cut -d= -f2)"
                        ;;
                --no-snapshot)
                        SNAPSHOT="no"
                        ;;
                --display-vnc=*)
                        DISPLAY_VNC="$(echo "$1" | cut -d= -f2)"
                        ;;
                --net-bridge-dev=*)
                        NETWORK_BRIDGE_DEV="$(echo "$1" | cut -d= -f2)"
                        ;;
                --)
                        shift
                        break
                        ;;
                *)
                        echo "Bad argument: ${1}" >&2
                        exit 1
                        ;;
        esac
        shift
done


if [ "${SNAPSHOT}" == "yes" ]; then
        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -snapshot"
fi

if [ -n "${DISPLAY_VNC}" ]; then
        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -display vnc=:${DISPLAY_VNC},password=off"
fi

if [ -n "${NETWORK_BRIDGE_DEV}" ]; then
        # Bridge
        if [ -n "${FORWARD_SSH_PORT}" ]; then
                echo "Unable to use SSH forward port in bridge mode." >&2
                exit 22
        fi

        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev bridge,id=vm_eth0,br=${NETWORK_BRIDGE_DEV}"
else
        # NAT
        if [ -n "${FORWARD_SSH_PORT}" ]; then
                QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=linux-arm7a_hardfp-${REVISION},hostfwd=tcp:0.0.0.0:${FORWARD_SSH_PORT}-:22"
        else
                QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=linux-arm7a_hardfp-${REVISION}"
        fi
fi

case "$(uname -s)" in
    Linux*)     HOST_OS=Linux;;
    Darwin*)    HOST_OS=Mac;;
    *)          HOST_OS="UNKNOWN";;
esac
HOST_ARCH=$(uname -m)

set -x

qemu-system-arm \
  -machine virt \
  -cpu cortex-a7 \
  -smp 2 \
  -m 4G \
  -kernel "${KERNEL_PATH}" \
  -append 'root=/dev/vda' \
  -device virtio-blk-device,drive=disk0 \
  -device virtio-keyboard-pci \
  -device virtio-net-device,netdev=vm_eth0 \
  -device virtio-rng-pci \
  -drive if=none,id=disk0,file="${DRIVE_FILE}" \
  ${QEMU_ADDITIONAL_OPTS}

set +x
