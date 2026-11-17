#!/bin/bash
set -e

DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR="$HOME/.config"
source "$DOTFILES_DIR/lib/install-common.sh"

log()  { echo "  $*"; }
info() { echo; echo "▸ $*"; }

info "Pulling from GitHub..."
cd "$DOTFILES_DIR"
git pull --ff-only origin main

info "Relinking configs..."
profile_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/profile"
profile=2
[[ ! -r "$profile_file" ]] || profile=$(cat "$profile_file")
[[ "$profile" == 1 ]] || link_configs

if [[ -f "$DOTFILES_DIR/.zshrc" ]]; then
    safe_link "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
fi

info "Reloading Hyprland..."
if command -v hyprctl >/dev/null && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload config-only
fi

echo
echo "Sync complete."
