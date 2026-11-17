# Arch boot splash

Static Arch Linux logo on black. Logo size follows the display width.

## Install

```sh
sudo ~/.dotfiles/plymouth/install.sh
```

Requires Arch Linux, GRUB and standard mkinitcpio presets. For GRUB and
Plymouth together, run `sudo ~/.dotfiles/bin/configure-boot`.

## Operation

- Preserve kernel arguments and existing hooks.
- Add the Plymouth hook and select `arch-minimal`.
- Rebuild initramfs and validate the generated boot configuration.
- Restore saved files if setup fails.

Backups: `/var/lib/dotfiles/boot-backups/`.
Press **Esc** during the splash to display boot diagnostics.
Arch's greetd service already waits for Plymouth to finish.
Custom presets that bypass the normal mkinitcpio configuration need review.

## Attribution

The logo comes from `/usr/share/pixmaps/archlinux-logo-text-dark.svg` in
Arch's `filesystem` package. Arch branding belongs to its respective owners.
