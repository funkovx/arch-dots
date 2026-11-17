#!/bin/bash
set -e

DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR="$HOME/.config"
source "$DOTFILES_DIR/lib/install-common.sh"

PKG_MINIMAL=(git curl htop zsh networkmanager base-devel fastfetch python grub plymouth)
PKG_EXTENDED=(
    firefox dolphin hyprland waybar kitty hyprlock hyprpolkitagent
    greetd greetd-tuigreet python rofi ttf-jetbrains-mono-nerd
    code telegram-desktop qemu-full virt-manager libvirt dnsmasq
    kvantum qt5-wayland qt6-wayland hypridle xdg-utils
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    kde-cli-tools archlinux-xdg-menu imv zathura zathura-pdf-mupdf copyq
    brightnessctl playerctl
    bluez bluez-utils pipewire pipewire-pulse wireplumber libpulse
    gtk3 gtk-layer-shell python-gobject power-profiles-daemon libnotify
)
PKG_AUR_EXTENDED=(hyprshot libinput-gestures)

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

# Configure an existing GRUB installation in both profiles. Do not replace a
# different bootloader or install an EFI boot entry implicitly.
info "Configuring boot appearance..."
sudo "$DOTFILES_DIR/grub/thinkgrub/install.sh"
sudo "$DOTFILES_DIR/plymouth/install.sh"

# ── 3. extended setup ───────────────────────────────────────────────────────

if [[ "$install_type" == "2" ]]; then

    info "Enabling Bluetooth and power profiles..."
    sudo systemctl enable bluetooth.service power-profiles-daemon.service

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

    info "Configuring greetd..."
    current_dm=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
    if [[ -n "$current_dm" && "$(basename "$current_dm")" != greetd.service ]]; then
        sudo systemctl disable "$(basename "$current_dm")"
    fi

    if [[ -f "$DOTFILES_DIR/etc/greetd/config.toml" ]]; then
        sudo install -Dm644 "$DOTFILES_DIR/etc/greetd/config.toml" /etc/greetd/config.toml
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

if [[ "$install_type" == 2 ]]; then
    link_configs
fi
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
printf '%s\n' "$install_type" > "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/profile"

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
echo "Done. Reboot when ready to apply boot and login changes."
