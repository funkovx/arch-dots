#!/bin/bash

# Прерывать скрипт при критических ошибках
set -e

DOTFILES_DIR="$HOME/dotfiles"
CONFIG_DIR="$HOME/.config"

# --- Списки пакетов ---
PKG_MINIMAL=("git" "curl" "htop" "zsh" "networkmanager" "base-devel" "fastfetch")
PKG_EXTENDED=("firefox" "dolphin" "hyprland" "waybar" "kitty" "hyprlock" "greetd" "greetd-tuigreet" "python" "rofi" "ttf-jetbrains-mono-nerd")
PKG_AUR_EXTENDED=("hyprshot")

CONFIG_FOLDERS=("hypr" "hyprland" "kitty" "waybar" "gtk-3.0" "Kvantum" "autostart" "dconf" "yay" "rofi")
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
        sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
    else
        echo "  Все необходимые пакеты уже установлены."
    fi
}

# 1. Выбор типа установки
echo "Выберите тип установки:"
echo "1) Минимальная (база + Zsh + NetworkManager + Fastfetch)"
echo "2) Расширенная (база + GUI, Rofi, Greetd, Шрифты)"
read -p "Ваш выбор (1 или 2): " install_type

if [[ "$install_type" == "1" ]]; then
    PACKAGES=("${PKG_MINIMAL[@]}")
elif [[ "$install_type" == "2" ]]; then
    PACKAGES=("${PKG_MINIMAL[@]}" "${PKG_EXTENDED[@]}")
else
    echo "Ошибка ввода. Отмена."
    exit 1
fi

# 2. Обновление системы и установка пакетов pacman
echo "Обновление системы..."
sudo pacman -Syu --noconfirm
install_packages "${PACKAGES[@]}"

sudo systemctl enable NetworkManager.service

# 3. Настройка расширенных компонентов
if [[ "$install_type" == "2" ]]; then
    
    # Установка yay (AUR helper)
    if ! command -v yay &> /dev/null; then
        echo "Установка yay..."
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        (cd /tmp/yay && makepkg -si --noconfirm)
        rm -rf /tmp/yay
    fi

    # Установка AUR пакетов
    echo "Установка пакетов из AUR..."
    yay -S --needed --noconfirm "${PKG_AUR_EXTENDED[@]}"

    # Замена SDDM на Greetd
    if pacman -Qq sddm &> /dev/null; then
        echo "Удаление SDDM..."
        sudo systemctl disable sddm.service 2>/dev/null || true
        sudo pacman -Rns --noconfirm sddm
    fi

    if [ -f "$DOTFILES_DIR/etc/greetd/config.toml" ]; then
        echo "Настройка Greetd..."
        sudo mkdir -p /etc/greetd
        sudo cp "$DOTFILES_DIR/etc/greetd/config.toml" /etc/greetd/config.toml
    fi
    sudo systemctl enable greetd.service

    # Создание Python VENV
    if [ ! -d "$HOME/.venv" ]; then
        echo "Создание виртуального окружения Python в ~/.venv..."
        python -m venv "$HOME/.venv"
    fi

    # Заглушка для hyprlock
    mkdir -p "$CONFIG_DIR/hypr"
    if [ ! -f "$DOTFILES_DIR/.config/hypr/hyprlock.conf" ]; then
        touch "$CONFIG_DIR/hypr/hyprlock.conf"
    fi
fi

# 4. Установка Oh My Zsh и Powerlevel10k (ДО симлинков)
# Отключаем смену shell и автозапуск в установщике OMZ
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Установка Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Явно указываем путь установки без зависимости от $ZSH_CUSTOM
P10K_DIR="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    echo "Клонирование Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# 5. Создание симлинков
echo "Линковка дотфайлов..."
mkdir -p "$CONFIG_DIR"

for folder in "${CONFIG_FOLDERS[@]}"; do
    if [ -d "$DOTFILES_DIR/.config/$folder" ]; then
        rm -rf "$CONFIG_DIR/$folder"
        ln -sfn "$DOTFILES_DIR/.config/$folder" "$CONFIG_DIR/$folder"
    fi
done

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$DOTFILES_DIR/.config/$file" ]; then
        rm -f "$CONFIG_DIR/$file"
        ln -sf "$DOTFILES_DIR/.config/$file" "$CONFIG_DIR/$file"
    fi
done

# Принудительно удаляем дефолтные файлы от установщика OMZ и ставим свои симлинки
echo "Настройка конфигурации Zsh..."
rm -f "$HOME/.zshrc" "$HOME/.p10k.zsh"
[ -f "$DOTFILES_DIR/.zshrc" ] && ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
[ -f "$DOTFILES_DIR/.p10k.zsh" ] && ln -sf "$DOTFILES_DIR/.p10k.zsh" "$HOME/.p10k.zsh"

# 6. Смена оболочки на Zsh
if [ "$SHELL" != "/usr/bin/zsh" ]; then
    echo "Смена оболочки по умолчанию на Zsh..."
    # Проверка наличия Zsh в /etc/shells перед сменой
    if grep -q "^/usr/bin/zsh$" /etc/shells; then
        chsh -s /usr/bin/zsh
    else
        echo "Внимание: /usr/bin/zsh не найден в /etc/shells. Смена оболочки пропущена."
    fi
fi

echo "Установка завершена. Перезагрузите систему."