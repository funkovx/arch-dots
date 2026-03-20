#!/bin/bash
set -e

DOTFILES_DIR="$HOME/.dotfiles"
CONFIG_DIR="$HOME/.config"

echo " Обновление из GitHub..."
cd "$DOTFILES_DIR"
git pull origin main

echo " Перелинковка..."

safe_link() {
    local src=$1
    local dest=$2

    mkdir -p "$(dirname "$dest")"
    
    ln -sfn "$src" "$dest"
    echo "   $dest -> $src"
}

find "$DOTFILES_DIR/.config" -maxdepth 1 -mindepth 1 -type d | while read -r folder; do
    folder_name=$(basename "$folder")
    safe_link "$folder" "$CONFIG_DIR/$folder_name"
done

find "$DOTFILES_DIR/.config" -maxdepth 1 -type f | while read -r file; do
    file_name=$(basename "$file")
    safe_link "$file" "$CONFIG_DIR/$file_name"
done

if [ -f "$DOTFILES_DIR/.zshrc" ]; then
    safe_link "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
fi

echo " Синхронизация завершена!"

hyprctl reload