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

The checked-in theme preserves the current ASUS appearance: a centered
900×340 panel, a 320×107 ASUS logo, and bundled 20/28 px fonts. ThinkPad uses
a 216×78 logo; other machines use the same menu without a logo. No local
files or font generation are needed to reproduce it after a fresh clone.

Display modes are tried in order: 1920×1080, 1600×900, 1280×720, 1024×768,
then `auto`. The fixed layout fits all four requested modes. Firmware must
support one of them for the intended appearance; an `auto` mode below
1024×720 may clip the layout. Physical sizing depends on the panel.

## Recovery

The installer backs up GRUB defaults, configuration and the previous theme,
preserves kernel arguments and checks the generated config before replacement.
On failure it restores defaults and theme and leaves the active config intact.
FAT ESPs are supported. It does not run `grub-install` or modify EFI boot entries.

## Attribution

ThinkGRUB: Copyright 2026 Michal Schiller, MIT; see [LICENSE](LICENSE).
ASUS branding belongs to ASUS. Font license: [FONT-LICENSE](FONT-LICENSE).
