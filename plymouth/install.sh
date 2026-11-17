#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
    echo "Run: sudo $0" >&2
    exit 1
fi
if [[ ! -f /boot/grub/grub.cfg || ! -f /etc/mkinitcpio.conf ]]; then
    echo "Plymouth setup requires an existing GRUB + mkinitcpio installation; skipped."
    exit 0
fi
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Let pacman verify signatures and use the machine's configured repositories.
pacman -S --needed --noconfirm plymouth
mkdir -p /var/lib/dotfiles/boot-backups
backup_dir=$(mktemp -d /var/lib/dotfiles/boot-backups/plymouth.XXXXXX)
backed_up=()
created=()
save_file() {
    local path=$1
    if [[ -e "$path" ]]; then
        mkdir -p "$backup_dir$(dirname -- "$path")"
        cp -- "$path" "$backup_dir$path"
        backed_up+=("$path")
    else
        created+=("$path")
    fi
}

save_file /etc/default/grub
save_file /etc/plymouth/plymouthd.conf
save_file /etc/mkinitcpio.conf.d/99-dotfiles-plymouth.conf
save_file /boot/grub/grub.cfg

# Back up each image that mkinitcpio -P can replace, including LTS/custom kernels.
shopt -s nullglob
for preset_file in /etc/mkinitcpio.d/*.preset; do
    while IFS= read -r image; do
        [[ -z "$image" ]] || save_file "$image"
    done < <(bash -c '
        source "$1"
        for preset in "${PRESETS[@]}"; do
            for suffix in image uki; do
                key="${preset}_${suffix}"
                [[ -z "${!key:-}" ]] || printf "%s\n" "${!key}"
            done
        done
    ' _ "$preset_file")
done
temporary_config=$(mktemp /boot/grub/grub.cfg.plymouth.XXXXXX)

restore_on_error() {
    local failure_status=$1
    trap - ERR
    set +e
    local path
    for path in "${backed_up[@]}"; do
        cp --no-preserve=all -- "$backup_dir$path" "$path"
    done
    for path in "${created[@]}"; do rm -f -- "$path"; done
    rm -f -- "$temporary_config" "${temporary_config}.new"
    echo "Setup failed. Restored boot files and settings. Backup: $backup_dir" >&2
    exit "$failure_status"
}
trap 'restore_on_error "$?"' ERR

mkdir -p /usr/share/plymouth/themes/arch-minimal /etc/mkinitcpio.conf.d
cp -R --no-preserve=all "$source_dir/arch-minimal/." /usr/share/plymouth/themes/arch-minimal/
plymouth-set-default-theme arch-minimal

# Derive the hook list from the existing configuration and local overrides.
source /etc/mkinitcpio.conf
for fragment in /etc/mkinitcpio.conf.d/*.conf; do
    [[ "$fragment" == /etc/mkinitcpio.conf.d/99-dotfiles-plymouth.conf ]] || source "$fragment"
done
new_hooks=()
inserted=false
for hook in "${HOOKS[@]}"; do
    [[ "$hook" == plymouth ]] && continue
    new_hooks+=("$hook")
    if [[ "$hook" == kms ]]; then new_hooks+=(plymouth); inserted=true; fi
done
if ! "$inserted"; then
    new_hooks=()
    for hook in "${HOOKS[@]}"; do
        [[ "$hook" == plymouth ]] && continue
        new_hooks+=("$hook")
        if [[ "$hook" == udev || "$hook" == systemd ]]; then
            new_hooks+=(plymouth); inserted=true
        fi
    done
fi
if ! "$inserted"; then echo "No udev/systemd hook found; refusing to alter initramfs." >&2; false; fi
printf 'HOOKS=(%s)\n' "${new_hooks[*]}" > /etc/mkinitcpio.conf.d/99-dotfiles-plymouth.conf

python "$source_dir/kernel-args.py" /etc/default/grub
mkinitcpio -P

# Verify that the default image contains the selected theme, not just Plymouth.
if [[ -f /boot/initramfs-linux.img ]]; then
    lsinitcpio /boot/initramfs-linux.img > "$backup_dir/initramfs-contents.txt"
    grep -Fq 'usr/share/plymouth/themes/arch-minimal/logo.png' "$backup_dir/initramfs-contents.txt"
fi
grub-mkconfig -o "$temporary_config"
grub-script-check "$temporary_config"
grep -q 'quiet.*splash\|splash.*quiet' "$temporary_config"
mv -f -- "$temporary_config" /boot/grub/grub.cfg
trap - ERR
systemctl daemon-reload
echo "Arch boot splash configured. Backup: $backup_dir"
echo "Reboot when ready. Press Esc during the splash to view boot messages."
