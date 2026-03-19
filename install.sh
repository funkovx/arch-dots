#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
CONFIG_DIR="$HOME/.config"

# --- Списки пакетов ---
PKG_MINIMAL=("git" "curl" "htop" "zsh" "networkmanager")
PKG_EXTENDED=("firefox" "dolphin" "hyprland" "hyprshot" "waybar" "kitty" "hyprlock" "greetd" "greetd-tuigreet" "python")

CONFIG_FOLDERS=("hypr" "hyprland" "kitty" "waybar" "gtk-3.0" "Kvantum" "autostart" "dconf" "yay")
CONFIG_FILES=("arkrc" "dolphinrc" "kdeglobals" "kiorc" "ktrashrc" "QtProject.conf" "trashrc")

# --- Функция установки ---
install_packages() {
    local pkgs=("$@")
    local missing_pkgs=()

    echo "Проверка пакетов..."
    for pkg in "${pkgs[@]}"; do
        if pacman -Qq "$pkg" &> /dev/null; then
            echo "  [ПРОПУСК] $pkg уже установлен."
        else
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo "  [УСТАНОВКА] ${missing_pkgs[*]}"
        sudo pacman -S --noconfirm "${missing_pkgs[@]}"
    else
        echo "  Все необходимые пакеты уже установлены."
    fi
}

# 1. Выбор типа установки
echo "Выберите тип установки:"
echo "1) Минимальная (база + Zsh + NetworkManager)"
echo "2) Расширенная (база + Hyprland, Greetd, Hyprlock, VENV, GUI-утилиты)"
read -p "Ваш выбор (1 или 2): " install_type

if [[ "$install_type" == "1" ]]; then
    PACKAGES=("${PKG_MINIMAL[@]}")
elif [[ "$install_type" == "2" ]]; then
    PACKAGES=("${PKG_MINIMAL[@]}" "${PKG_EXTENDED[@]}")
else
    echo "Ошибка ввода. Отмена."
    exit 1
fi

# 2. Установка пакетов
sudo pacman -Syu --noconfirm
install_packages "${PACKAGES[@]}"

# Включение основных системных служб
sudo systemctl enable --now NetworkManager.service

# 3. Настройка расширенных компонентов (если выбран вариант 2)
if [[ "$install_type" == "2" ]]; then
    # Активация greetd
    sudo systemctl enable greetd.service

    # Создание Python VENV
    if [ ! -d "$HOME/.venv" ]; then
        echo "Создание виртуального окружения Python в ~/.venv..."
        python -m venv "$HOME/.venv"
    fi

    # Заглушка для hyprlock (если еще не добавлен в dotfiles)
    mkdir -p "$CONFIG_DIR/hypr"
    if [ ! -f "$DOTFILES_DIR/.config/hypr/hyprlock.conf" ]; then
        touch "$CONFIG_DIR/hypr/hyprlock.conf"
        echo "Создан пустой файл настроек: $CONFIG_DIR/hypr/hyprlock.conf"
    fi
fi

# 4. Установка Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Установка Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

if [ "$SHELL" != "/usr/bin/zsh" ]; then
    chsh -s /usr/bin/zsh
fi

# 5. Создание симлинков
echo "Линковка дотфайлов..."
mkdir -p "$CONFIG_DIR"

for folder in "${CONFIG_FOLDERS[@]}"; do
    if [ -d "$DOTFILES_DIR/.config/$folder" ]; then
        rm -rf "$CONFIG_DIR/$folder"
        ln -sfn "$DOTFILES_DIR/.config/$folder" "$CONFIG_DIR/$folder"
        echo "  Связана директория: $folder"
    fi
done

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$DOTFILES_DIR/.config/$file" ]; then
        rm -f "$CONFIG_DIR/$file"
        ln -sf "$DOTFILES_DIR/.config/$file" "$CONFIG_DIR/$file"
        echo "  Связан файл: $file"
    fi
done

rm -f "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

echo "Установка завершена. Рекомендуется перезагрузить систему."