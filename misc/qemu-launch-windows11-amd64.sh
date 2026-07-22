#!/bin/sh
#

set -eo pipefail

#
# TODO: Check for swtpm and swtpm_setup binaries. Propose `emerge --ask app-crypt/swtpm`.
#


# Normalize SCRIPT_DIR
SCRIPT_DIR=$(cd $(dirname "$0") && pwd -LP)

REVISION=$(basename "${SCRIPT_DIR}")

DRIVE_FILE="${SCRIPT_DIR}/windows11-amd64.qcow2"

SNAPSHOT="yes"
FORWARD_RDP_PORT=""
DISPLAY_VNC=""
INSTALL_ISO=""
NETWORK_BRIDGE_DEV=""

QEMU_ADDITIONAL_OPTS=""

while (( "$#" )); do
        case "${1}" in
                --headless)
                        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -nographic"
                        ;;
                --rdp-port=*)
                        FORWARD_RDP_PORT="$(echo "$1" | cut -d= -f2)"
                        ;;
                --no-snapshot)
                        SNAPSHOT="no"
                        ;;
                --display-vnc=*)
                        DISPLAY_VNC="$(echo "$1" | cut -d= -f2)"
                        ;;
                --install-iso=*)
                        INSTALL_ISO="$(echo "$1" | cut -d= -f2)"
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

if [ -n "${INSTALL_ISO}" ]; then
        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -device ide-cd,bus=ide.1,drive=cdrom0 -drive if=none,file=${INSTALL_ISO},media=cdrom,id=cdrom0"
fi

if [ -n "${NETWORK_BRIDGE_DEV}" ]; then
        # Bridge
        if [ -n "${FORWARD_RDP_PORT}" ]; then
                echo "Unable to use RDP forward port in bridge mode." >&2
                exit 22
        fi

        QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev bridge,id=vm_eth0,br=${NETWORK_BRIDGE_DEV}"
else
        # NAT
        if [ -n "${FORWARD_RDP_PORT}" ]; then
                QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=windows11-${REVISION},hostfwd=tcp:0.0.0.0:${FORWARD_RDP_PORT}-:3389"
        else
                QEMU_ADDITIONAL_OPTS="${QEMU_ADDITIONAL_OPTS} -netdev user,id=vm_eth0,hostname=windows11-${REVISION}"
        fi
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

if [ ! -d "${SCRIPT_DIR}/.state" ]; then
        mkdir "${SCRIPT_DIR}/.state"
fi

set -e

if [ ! -f "${SCRIPT_DIR}/.state/OVMF_VARS.fd" ]; then
        cp -aL /usr/share/edk2/OvmfX64/OVMF_VARS.secboot.fd "${SCRIPT_DIR}/.state/OVMF_VARS.fd"
fi

if [ ! -d "${SCRIPT_DIR}/.state/tpm" ]; then
        mkdir "${SCRIPT_DIR}/.state/tpm"
        swtpm_setup --tpm2 --tpmstate "${SCRIPT_DIR}/.state/tpm"
fi

TPM_SOCKET="/tmp/swtpm-$$.sock"
swtpm socket --tpm2 --daemon --terminate --tpmstate dir="${SCRIPT_DIR}/.state/tpm" --ctrl type=unixio,path="${TPM_SOCKET}"

sleep 1
while [ ! -S "${TPM_SOCKET}" ]; do
        echo "Wait for ${TPM_SOCKET} ..." >&2
        sleep 1
done

set -x

qemu-system-x86_64 \
  -machine q35 \
  -cpu IvyBridge-v1 \
  -smp 4 \
  -m 16G \
  -chardev socket,id=chrtpm,path="${TPM_SOCKET}" \
  -tpmdev emulator,id=tpm0,chardev=chrtpm \
  -device tpm-tis,tpmdev=tpm0 \
  -device nvme,drive=disk0,serial=1 \
  -device qemu-xhci \
  -device usb-tablet \
  -device e1000e,netdev=vm_eth0 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/OvmfX64/OVMF_CODE.secboot.fd \
  -drive if=pflash,format=raw,file="${SCRIPT_DIR}/.state/OVMF_VARS.fd" \
  -drive if=none,id=disk0,file="${DRIVE_FILE}" \
  ${QEMU_ADDITIONAL_OPTS}
qemu_exit=$?

swtpm_ioctl \
  --unix "${TPM_SOCKET}" \
  -s >/dev/null 2>&1

set +x
exit $qemu_exit
