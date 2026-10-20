#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="graphiteos"
iso_label="GRAPHITE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="GraphiteOS <https://github.com/Skeleten80/GraphiteOS>"
iso_application="GraphiteOS Live (Hyprland)"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="graphite"
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86,arm64' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/sudoers.d/g-wheel"]="0:0:440"
  ["/usr/local/bin/graphite-welcome"]="0:0:755"
  ["/usr/local/bin/graphite-wallpaper"]="0:0:755"
  ["/etc/skel/.config/hypr/scripts/gamemode-toggle.sh"]="0:0:755"
  ["/home/graphite"]="1000:1000:750"
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
)
