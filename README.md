# arch-dots

Portable Arch Linux laptop configuration. Hyprland, a monochrome desktop,
ThinkGRUB and an Arch Linux boot splash.

## Requirements

- Arch Linux, x86-64.
- A working graphics driver and network connection.
- An existing GRUB + mkinitcpio setup for boot styling.

GPU drivers, Secure Boot and disk encryption remain machine-specific.
Other bootloaders are left unchanged.

## Installation

```sh
git clone https://github.com/funkovx/arch-dots.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

| Profile | Configuration |
| --- | --- |
| Minimal | Base tools, Zsh, NetworkManager, fastfetch, ThinkGRUB, Plymouth |
| Extended | Minimal profile plus Hyprland, Waybar, Rofi, greetd/tuigreet, desktop applications and KVM tools |

Existing configuration is backed up before linking. Boot files are validated
before replacement. The installer does not reboot automatically.

## Boot configuration

```sh
sudo ~/.dotfiles/bin/configure-boot
```

| Hardware | GRUB logo |
| --- | --- |
| ThinkPad | Original ThinkGRUB wordmark |
| ASUS | White ASUS wordmark |
| Other / unknown | None |

GRUB uses a shared logical display size. Plymouth displays the Arch logo on
black, then hands control to the existing login manager.

Details: [GRUB](grub/thinkgrub/README.md) · [Plymouth](plymouth/README.md)

## Synchronization

```sh
./sync.sh
```

Updates use fast-forward only. Configuration links follow the installed
profile. Boot changes require a separate `bin/configure-boot` run.

## Verification

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -v
```

Tests cover logo selection, local configuration preservation, sensor detection,
kernel arguments and boot-setup rollback.

## Screenshots

See the [capture list](docs/screenshots.md).

## References

- [Hyprland](https://hypr.land/)
- [ThinkGRUB](https://github.com/mschiller890/ThinkGRUB) — MIT; license included with the theme.
- [Plymouth](https://www.freedesktop.org/wiki/Software/Plymouth/)
