#!/bin/bash
set -e

DOTFILES_DIR="$HOME/.dotfiles"
CONFIG_DIR="$HOME/.config"

PKG_MINIMAL=(git curl htop zsh networkmanager base-devel fastfetch)
PKG_EXTENDED=(
    firefox dolphin hyprland waybar kitty hyprlock
    greetd greetd-tuigreet python rofi ttf-jetbrains-mono-nerd
    code telegram-desktop qemu-full virt-manager libvirt dnsmasq
    kvantum qt5-wayland qt6-wayland hypridle xdg-utils
    kde-cli-tools archlinux-xdg-menu imv zathura zathura-pdf-mupdf copyq
    brightnessctl
)
PKG_AUR_EXTENDED=(hyprshot libinput-gestures)

CONFIG_FOLDERS=(hypr hyprland kitty waybar gtk-3.0 Kvantum autostart dconf yay rofi)
CONFIG_FILES=(arkrc dolphinrc kdeglobals kiorc ktrashrc QtProject.conf trashrc mimeapps.list libinput-gestures.conf)

# ── helpers ──────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
info() { echo; echo "▸ $*"; }

install_packages() {
    local pkgs=("$@")
    local missing=()

    for pkg in "${pkgs[@]}"; do
        pacman -Qq "$pkg" &>/dev/null && log "[skip] $pkg already installed" || missing+=("$pkg")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "[install] ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    else
        log "all packages already installed"
    fi
}

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

# ── 1. choose install type ───────────────────────────────────────────────────

echo "Select install type:"
echo "  1) Minimal  — base + Zsh + NetworkManager + fastfetch"
echo "  2) Extended — base + GUI, Rofi, Greetd, fonts, VSCode, KVM, Telegram"
read -rp "Choice (1 or 2): " install_type

case "$install_type" in
    1) PACKAGES=("${PKG_MINIMAL[@]}") ;;
    2) PACKAGES=("${PKG_MINIMAL[@]}" "${PKG_EXTENDED[@]}") ;;
    *) echo "Invalid choice. Aborting."; exit 1 ;;
esac

# ── 2. system update + pacman packages ──────────────────────────────────────

info "Updating system..."
sudo pacman -Syu --noconfirm
install_packages "${PACKAGES[@]}"
sudo systemctl enable NetworkManager.service

# ── 3. extended setup ───────────────────────────────────────────────────────

if [[ "$install_type" == "2" ]]; then

    info "Installing yay (AUR helper)..."
    if ! command -v yay &>/dev/null; then
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        (cd /tmp/yay && makepkg -si --noconfirm)
        rm -rf /tmp/yay
    else
        log "yay already installed"
    fi

    info "Installing AUR packages..."
    yay -S --needed --noconfirm "${PKG_AUR_EXTENDED[@]}"

    info "Configuring QEMU/KVM..."
    sudo systemctl enable libvirtd.service
    sudo usermod -aG libvirt "$USER"
    sudo usermod -aG input "$USER"

    info "Replacing SDDM with greetd..."
    if pacman -Qq sddm &>/dev/null; then
        sudo systemctl disable sddm.service 2>/dev/null || true
        sudo pacman -Rns --noconfirm sddm
    fi

    if [[ -f "$DOTFILES_DIR/etc/greetd/config.toml" ]]; then
        sudo mkdir -p /etc/greetd
        sudo cp "$DOTFILES_DIR/etc/greetd/config.toml" /etc/greetd/config.toml
        sudo chown -R greeter:greeter /etc/greetd
    fi
    sudo systemctl enable greetd.service

    info "Creating Python venv at ~/.venv..."
    [[ -d "$HOME/.venv" ]] || python -m venv "$HOME/.venv"

fi

# ── 4. oh-my-zsh + powerlevel10k ────────────────────────────────────────────

info "Installing Oh My Zsh..."
if [[ ! -d "$HOME/.oh-my-zsh/templates" ]]; then
    rm -rf "$HOME/.oh-my-zsh"
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    log "Oh My Zsh already installed"
fi

P10K_DIR="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
    info "Cloning Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
else
    log "Powerlevel10k already installed"
fi

# ── 5. symlinks ──────────────────────────────────────────────────────────────

info "Linking dotfiles..."
mkdir -p "$CONFIG_DIR"

for folder in "${CONFIG_FOLDERS[@]}"; do
    [[ -d "$DOTFILES_DIR/.config/$folder" ]] && safe_link "$DOTFILES_DIR/.config/$folder" "$CONFIG_DIR/$folder"
done

for file in "${CONFIG_FILES[@]}"; do
    [[ -f "$DOTFILES_DIR/.config/$file" ]] && safe_link "$DOTFILES_DIR/.config/$file" "$CONFIG_DIR/$file"
done

# ── 6. zsh config ───────────────────────────────────────────────────────────

info "Configuring Zsh..."
if [[ ! -f "$HOME/.zshrc" ]]; then
    if [[ -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" ]]; then
        cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
    else
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/templates/zshrc.zsh-template -o "$HOME/.zshrc"
    fi
fi
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

# ── 7. default shell ─────────────────────────────────────────────────────────

if [[ "$SHELL" != "/usr/bin/zsh" ]]; then
    info "Changing default shell to Zsh..."
    if grep -q "^/usr/bin/zsh$" /etc/shells; then
        chsh -s /usr/bin/zsh
    else
        log "WARNING: /usr/bin/zsh not in /etc/shells — skipping chsh"
    fi
fi

# ── 8. reboot ────────────────────────────────────────────────────────────────

echo
echo "Done. Rebooting in 5 seconds..."
sleep 5
sudo reboot
