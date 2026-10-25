# Hardware test checklist

Graphite is only QEMU-tested so far. Use this on real machines and file one
issue per machine with the **Hardware report** issue form (New issue → Hardware report),
which has the same fields; or copy this list into a blank issue.

## Machine
- [ ] Vendor / model:
- [ ] CPU (Intel/AMD, generation):
- [ ] GPU(s) (Intel / AMD / NVIDIA, hybrid?):
- [ ] RAM / disk (NVMe/SATA):
- [ ] Firmware: UEFI version, Secure Boot on/off
- [ ] ISO: file name + SHA-256 checked (`sha256sum -c SHA256SUMS`)
- [ ] `cat /opt/graphite/build-info.txt` (live) or `/var/lib/graphite/src/build-info.txt`

## Live ISO
- [ ] USB written with dd / Rufus "DD image" / balenaEtcher
- [ ] Boots in UEFI mode; also BIOS/legacy if available
- [ ] Display at native resolution, no flicker
- [ ] Keyboard, touchpad, mouse
- [ ] Wi-Fi (`nmtui`) and Ethernet

## Install
- [ ] Installer finishes without errors (note duration)
- [ ] LUKS passphrase prompt appears and works on first boot
- [ ] GRUB menu shows Graphite, LTS and the snapshots submenu
- [ ] Boot time to login (approx.)

## Desktop
- [ ] SDDM login works; Hyprland starts
- [ ] Bar shows workspaces, clock, network, audio, battery (laptops)
- [ ] `graphite theme pick` switches themes; bar comes back
- [ ] Multi-monitor: hotplug, external display, scaling (HiDPI)
- [ ] Lock (Super+L / idle) and unlock: hyprlock does not crash
- [ ] Suspend + resume (lid close on laptops); Wi-Fi back after resume
- [ ] Brightness and volume keys

## Hardware
- [ ] Audio out: speakers, headphones (jack), HDMI/DP audio, Bluetooth headset
- [ ] Microphone (internal, headset)
- [ ] Bluetooth pairing
- [ ] Webcam
- [ ] GPU acceleration: `glxinfo -B` / `vulkaninfo --summary` shows the real GPU
- [ ] NVIDIA: graphite-nvidia ISO, `nvidia-smi`
- [ ] Battery life estimate / `powerprofilesctl` modes switch
- [ ] Fingerprint reader / card reader / Thunderbolt dock (if present)
- [ ] Firmware updates: `fwupdmgr get-devices`

## System
- [ ] `graphite doctor` all green
- [ ] `graphite update` works and takes a pre-update snapshot
- [ ] `graphite rollback N` + reboot returns to the snapshot
- [ ] `systemctl --failed` empty
- [ ] Secure Boot (optional): `graphite secureboot setup`, enable in firmware, boots; status says enabled
- [ ] Steam installs and a Proton game starts (gaming profile)

## Result
- [ ] Works as daily driver / works with issues / does not work
- Issues (with `journalctl -b -p err` excerpts):
