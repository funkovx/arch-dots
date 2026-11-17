#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
    echo "Run: sudo $0 [auto|thinkpad|asus|none]" >&2
    exit 1
fi
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$source_dir/prepare.sh"
logo=${1:-auto}
case "$logo" in auto|thinkpad|asus|none) ;; *) echo "Unknown logo: $logo" >&2; exit 1 ;; esac

if [[ ! -f /boot/grub/grub.cfg || ! -f /etc/default/grub ]]; then
    echo "No existing GRUB installation found; leaving the current bootloader unchanged."
    exit 0
fi
command -v grub-mkconfig >/dev/null
command -v grub-script-check >/dev/null
destination=/boot/grub/themes/thinkgrub
backup_dir=$(mktemp -d /etc/default/grub-backup-thinkgrub.XXXXXX)
cp -a /etc/default/grub "$backup_dir/default-grub"
cp /boot/grub/grub.cfg "$backup_dir/grub.cfg"
if [[ -d "$destination" ]]; then
    cp -R --no-preserve=all "$destination" "$backup_dir/theme"
fi
temporary_config=$(mktemp /boot/grub/grub.cfg.thinkgrub.XXXXXX)

restore_on_error() {
    local failure_status=$1
    trap - ERR
    cp -a "$backup_dir/default-grub" /etc/default/grub
    rm -rf -- "$destination"
    if [[ -d "$backup_dir/theme" ]]; then
        mkdir -p "$destination"
        cp -R --no-preserve=all "$backup_dir/theme/." "$destination/"
    fi
    rm -f -- "$temporary_config" "${temporary_config}.new"
    echo "Installation failed; restored GRUB defaults and theme. Backup: $backup_dir" >&2
    exit "$failure_status"
}
trap 'restore_on_error "$?"' ERR
prepare_theme "$destination" "$logo"

# Keep the current ASUS appearance, with a mode for smaller firmware displays.
# GRUB_TERMINAL overrides GRUB_TERMINAL_OUTPUT in grub-mkconfig.
sed -Ei '/^[[:blank:]]*(export[[:blank:]]+)?GRUB_(THEME|GFXMODE|TERMINAL|TERMINAL_OUTPUT|BACKGROUND)=/d' /etc/default/grub
cat >> /etc/default/grub <<'SETTINGS'
GRUB_THEME="/boot/grub/themes/thinkgrub/theme.txt"
GRUB_GFXMODE="1920x1080,1600x900,1280x720,1024x768,auto"
GRUB_TERMINAL_OUTPUT="gfxterm"
SETTINGS
grub-mkconfig -o "$temporary_config"
grub-script-check "$temporary_config"
grep -Fq '/themes/thinkgrub/theme.txt' "$temporary_config"
mv -f -- "$temporary_config" /boot/grub/grub.cfg
trap - ERR
echo "ThinkGRUB installed. Backup: $backup_dir"
echo "Visible on the next boot; no reboot has been requested."
