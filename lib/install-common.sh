#!/usr/bin/env bash
# Preserve existing local files and skip identical symlinks.

safe_link() {
    local src=$1 dest=$2 backup
    [[ -e "$src" ]] || return 0
    mkdir -p "$(dirname -- "$dest")"
    if [[ -L "$dest" && "$(readlink -f -- "$dest")" == "$(readlink -f -- "$src")" ]]; then
        return 0
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
        mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups"
        backup=$(mktemp -d "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/config.XXXXXX")
        mv -- "$dest" "$backup/$(basename -- "$dest")"
        echo "  Existing config saved: $backup"
    fi
    ln -s -- "$src" "$dest"
    echo "  $dest → $src"
}

link_configs() {
    local folder file
    for folder in hypr kitty waybar gtk-3.0 Kvantum autostart rofi; do
        safe_link "$DOTFILES_DIR/.config/$folder" "$CONFIG_DIR/$folder"
    done
    for file in arkrc dolphinrc kdeglobals kiorc trashrc mimeapps.list libinput-gestures.conf; do
        safe_link "$DOTFILES_DIR/.config/$file" "$CONFIG_DIR/$file"
    done
    safe_link "$DOTFILES_DIR/bin/lock-screen" "$HOME/.local/bin/lock-screen"
}
