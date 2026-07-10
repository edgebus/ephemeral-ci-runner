#!/bin/sh
#

set -eo pipefail

# Normalize SCRIPT_DIR
SCRIPT_DIR=$(cd $(dirname "$0") && pwd -LP)

REVISION=$(basename "${SCRIPT_DIR}")

KERNEL_PATH="${SCRIPT_DIR}/arm7a_hardfp.zImage"
DRIVE_FILE="${SCRIPT_DIR}/arm7a_hardfp.qcow2"

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
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=arm7a_hardfp-${REVISION},hostfwd=tcp:0.0.0.0:60022-:22"
else
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=arm7a_hardfp-${REVISION}"
fi

if [ "${SNAPSHOT}" == "yes" ]; then
  QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -snapshot"
fi

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
  -drive if=none,file=${DRIVE_FILE},id=disk0 \
  -nographic \
  ${QEMU_ADDITIONAL_OPTS}
