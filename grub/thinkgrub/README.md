# ThinkGRUB

Monochrome GRUB theme based on [ThinkGRUB](https://github.com/mschiller890/ThinkGRUB).
Requires an existing GRUB installation. Both main installer profiles offer
the theme as an optional step.

## Install

```sh
sudo ~/.dotfiles/grub/thinkgrub/install.sh
```

DMI identification selects the logo:

| Identity | Logo |
| --- | --- |
| ThinkPad | Original wordmark |
| ASUS / ASUSTeK | White ASUS |
| Other / unreadable | None |

Manual override: append `thinkpad`, `asus` or `none`.

## Display

- Logical mode: 1280×720.
- Fallbacks: 1024×768, then `auto`.
- Layout: centered, percentage-based width, 28 px menu text.

Firmware scales the logical mode to the panel. This keeps sizing consistent
across FHD/QHD/UHD displays; native-resolution sharpness may differ.
Unsupported firmware modes require a local adjustment.

## Recovery

The installer backs up GRUB defaults and configuration, preserves kernel
arguments and checks the generated config before replacement. FAT ESPs are
supported. It does not run `grub-install` or modify EFI boot entries.

## Attribution

ThinkGRUB: Copyright 2026 Michal Schiller, MIT; see [LICENSE](LICENSE).
ASUS branding belongs to ASUS. Font license: [FONT-LICENSE](FONT-LICENSE).
