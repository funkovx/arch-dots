# arch-dots

My Arch Linux laptop dotfiles.

## Requirements

- Arch Linux, x86-64.
- A working graphics driver and network connection.
- An existing GRUB + mkinitcpio setup for boot styling.

## Installation

```sh
git clone https://github.com/funkovx/arch-dots.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

| Profile | Configuration |
| --- | --- |
| Minimal | Base tools, Zsh, NetworkManager, fastfetch, Plymouth |
| Extended | Minimal profile plus Hyprland, Waybar, Rofi, greetd/tuigreet, desktop applications and KVM tools |

Existing configuration is backed up before linking. Boot files are validated
before replacement. The installer does not reboot automatically.

## Synchronization

```sh
./sync.sh
```

## Screenshots

Rofi

![Rofi](docs/images/launcher.png)

| Quick settings | Sound |
| --- | --- |
| ![Quick settings](docs/images/quick-settings.png) | ![Sound](docs/images/sound.png) |

| Wi-Fi | Power |
| --- | --- |
| ![Wi-Fi](docs/images/wifi.png) | ![Power](docs/images/power.png) |

GRUB

![GRUB](docs/images/grub.png)

Plymouth

![Plymouth](docs/images/boot-splash.png)

Tuigreet

![Tuigreet](docs/images/login.png)

## References

- [ThinkGRUB](https://github.com/mschiller890/ThinkGRUB) — MIT; license included with the theme.
