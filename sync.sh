#!/bin/bash
set -e

DOTFILES_DIR="$HOME/.dotfiles"
CONFIG_DIR="$HOME/.config"

echo " Обновление из GitHub..."
cd "$DOTFILES_DIR"
git pull origin main

echo " Безопасная перелинковка..."

# Функция для безопасного создания ссылок
safe_link() {
    local src=$1
    local dest=$2
    
    # Создаем родительскую директорию, если её нет
    mkdir -p "$(dirname "$dest")"
    
    # ln -sfn: 
    # -s (symbolic)
    # -f (force): перезапишет, если файл уже есть
    # -n: если это ссылка на папку, заменит саму ссылку, а не создаст новую внутри
    ln -sfn "$src" "$dest"
    echo "   $dest -> $src"
}

# Линкуем папки из репозитория
# Находим все папки внутри dotfiles/.config и зеркалим их в ~/.config
find "$DOTFILES_DIR/.config" -maxdepth 1 -mindepth 1 -type d | while read -r folder; do
    folder_name=$(basename "$folder")
    safe_link "$folder" "$CONFIG_DIR/$folder_name"
done

# Линкуем отдельные файлы из .config (например, mimeapps.list)
find "$DOTFILES_DIR/.config" -maxdepth 1 -type f | while read -r file; do
    file_name=$(basename "$file")
    safe_link "$file" "$CONFIG_DIR/$file_name"
done

# Линкуем .zshrc
if [ -f "$DOTFILES_DIR/.zshrc" ]; then
    safe_link "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
fi

echo " Синхронизация завершена!"
# Мягко просим Hyprland перечитать конфиг без перезагрузки
hyprctl reload