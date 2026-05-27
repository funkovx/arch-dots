#!/bin/bash
set -e

DOTFILES_DIR="$HOME/.dotfiles"
CONFIG_DIR="$HOME/.config"

log()  { echo "  $*"; }
info() { echo; echo "▸ $*"; }

safe_link() {
    local src=$1 dest=$2
    mkdir -p "$(dirname "$dest")"
    if [[ -d "$src" ]]; then
        rm -rf "$dest"
        ln -sfn "$src" "$dest"
    else
        rm -f "$dest"
        ln -sf "$src" "$dest"
    fi
    log "$dest → $src"
}

info "Pulling from GitHub..."
cd "$DOTFILES_DIR"
git pull origin main

info "Relinking configs..."
find "$DOTFILES_DIR/.config" -maxdepth 1 -mindepth 1 -type d | while read -r dir; do
    safe_link "$dir" "$CONFIG_DIR/$(basename "$dir")"
done

find "$DOTFILES_DIR/.config" -maxdepth 1 -type f | while read -r file; do
    safe_link "$file" "$CONFIG_DIR/$(basename "$file")"
done

if [[ -f "$DOTFILES_DIR/.zshrc" ]]; then
    safe_link "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
fi

info "Reloading Hyprland..."
hyprctl reload

echo
echo "Sync complete."
