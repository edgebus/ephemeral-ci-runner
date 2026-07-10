#!/bin/sh
#

set -eo pipefail

# Normalize SCRIPT_DIR
SCRIPT_DIR=$(cd $(dirname "$0") && pwd -LP)

REVISION=$(basename "${SCRIPT_DIR}")

KERNEL_PATH="${SCRIPT_DIR}/amd64.bzImage"
DRIVE_FILE="${SCRIPT_DIR}/amd64.qcow2"

SNAPSHOT="yes"
FORWARD_SSH_PORT=""

while (( "$#" )); do
	case "${1}" in
		--ssh-port=*)
			FORWARD_SSH_PORT="$(echo "$1" | cut -d= -f2)"
			;;
		--no-snapshot)
			SNAPSHOT="no"
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

if [ -n "${FORWARD_SSH_PORT}" ]; then
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=amd64-${REVISION},hostfwd=tcp:0.0.0.0:60022-:22"
else
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=amd64-${REVISION}"
fi

if [ "${SNAPSHOT}" == "yes" ]; then
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -snapshot"
fi

case "$(uname -s)" in
    Linux*)     HOST_OS=Linux;;
    Darwin*)    HOST_OS=Mac;;
    *)          HOST_OS="UNKNOWN";;
esac
HOST_ARCH=$(uname -m)

if [ "${HOST_OS}" == "Linux" -a "${HOST_ARCH}" == "x86_64" ]; then
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -accel kvm"
elif [ "${HOST_OS}" == "Mac" -a "${HOST_ARCH}" == "x86_64" ]; then
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -accel hvf"
fi

qemu-system-x86_64 \
  -machine pc \
  -cpu qemu64-v1 \
  -smp 2 \
  -m 4G \
  -kernel "${KERNEL_PATH}" \
  -append 'root=/dev/vda console=ttyS0' \
  -device virtio-blk,drive=disk0 \
  -device virtio-keyboard-pci \
  -device virtio-net,netdev=vm_eth0 \
  -device virtio-rng-pci \
  -drive if=none,file=${DRIVE_FILE},id=disk0 \
  -nographic \
  ${QEMU_ADDITIONAL_OPTS}
