#!/bin/bash
set -e

DOTFILES_DIR="$HOME/.dotfiles"
CONFIG_DIR="$HOME/.config"

# Список папок для синхронизации (должен совпадать с основным скриптом)
CONFIG_FOLDERS=("hypr" "hyprland" "kitty" "waybar" "rofi" "zathura")
CONFIG_FILES=("mimeapps.list")

echo "🔄 Обновление из GitHub..."
cd "$DOTFILES_DIR"
git pull origin main

echo "🔗 Восстановление симлинков..."
mkdir -p "$CONFIG_DIR"

# Линковка папок
for folder in "${CONFIG_FOLDERS[@]}"; do
    if [ -d "$DOTFILES_DIR/.config/$folder" ]; then
        rm -rf "$CONFIG_DIR/$folder"
        ln -sfn "$DOTFILES_DIR/.config/$folder" "$CONFIG_DIR/$folder"
        echo "  Папка $folder синхронизирована"
    fi
done

# Линковка отдельных файлов
for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$DOTFILES_DIR/.config/$file" ]; then
        ln -sf "$DOTFILES_DIR/.config/$file" "$CONFIG_DIR/$file"
        echo "  Файл $file синхронизирован"
    fi
done

# Обновление конфига Zsh (на случай правок в .zshrc)
if [ -f "$DOTFILES_DIR/.zshrc" ]; then
    ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
    echo "  .zshrc обновлен"
fi

echo " Конфигурация успешно восстановлена."