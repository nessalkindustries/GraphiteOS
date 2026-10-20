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
# KVM is opt-in (USE_KVM=1); nested KVM on some hosts hangs silently
ACCEL=(-accel tcg,thread=multi -cpu max); [ "${USE_KVM:-0}" = 1 ] && ACCEL=(-enable-kvm -cpu host)
timeout "$SECS" qemu-system-x86_64 "${ACCEL[@]}" -m 4096 -smp 4 "${FW[@]}" \
  -cdrom "$ISO" -boot d -display none -vga std -serial stdio \
  -monitor unix:out/mon-$MODE.sock,server,nowait -nic user,model=virtio-net-pci < /dev/null > "$LOG" 2>&1 &
PID=$!
sleep $((SECS-15)); python3 -c "import socket,time;s=socket.socket(socket.AF_UNIX);s.connect('out/mon-$MODE.sock');s.send(b'screendump out/screen-$MODE.ppm\\n');time.sleep(2)" || true
wait $PID
grep -E "Reached target|login:|sddm|Welcome to" "$LOG" | tail -20
