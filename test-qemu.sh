#!/usr/bin/env bash
# Headless boot test. Usage: ./test-qemu.sh [bios|uefi] [seconds]
set -uo pipefail
cd "$(dirname "$0")"
MODE=${1:-bios}; SECS=${2:-240}
ISO=$(ls -t out/*.iso | head -1)
LOG=out/serial-$MODE.log
FW=()
if [ "$MODE" = uefi ]; then
  CODE=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null | head -1)
  VARS=$(ls /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS.fd 2>/dev/null | head -1)
  cp "$VARS" out/ovmf_vars.fd
  FW=(-drive if=pflash,format=raw,readonly=on,file="$CODE" -drive if=pflash,format=raw,file=out/ovmf_vars.fd)
fi
ACCEL=(); [ -w /dev/kvm ] && ACCEL=(-enable-kvm -cpu host)
timeout "$SECS" qemu-system-x86_64 "${ACCEL[@]}" -m 4096 -smp 4 "${FW[@]}" \
  -cdrom "$ISO" -boot d -display none -vga virtio -serial file:"$LOG" \
  -monitor unix:out/mon-$MODE.sock,server,nowait -nic user,model=virtio-net-pci &
PID=$!
sleep $((SECS-15)); echo "screendump out/screen-$MODE.ppm" | socat - UNIX-CONNECT:out/mon-$MODE.sock >/dev/null 2>&1 || true
wait $PID
grep -E "Reached target|login:|sddm|Welcome to" "$LOG" | tail -20
