#!/usr/bin/env bash
set -euo pipefail

theme_source=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

detect_logo() {
    local identity="${1,,}"
    if [[ "$identity" == *thinkpad* ]]; then
        echo thinkpad
    elif [[ "$identity" == *asus* ]]; then
        echo asus
    else
        echo none
    fi
}

prepare_theme() {
    local target=$1 logo=${2:-auto} identity="" file
    if [[ "$logo" == auto ]]; then
        for file in sys_vendor product_name product_version; do
            [[ ! -r /sys/class/dmi/id/$file ]] || identity+=" $(cat "/sys/class/dmi/id/$file")"
        done
        logo=$(detect_logo "$identity")
    fi
    case "$logo" in thinkpad|asus|none) ;; *) echo "Unknown logo: $logo" >&2; return 1 ;; esac
    mkdir -p "$target"
    cp -R --no-preserve=all "$theme_source/theme/." "$target/"
    if [[ "$logo" == none ]]; then
        sed '/^# LOGO_BEGIN$/,/^# LOGO_END$/d' "$target/theme.txt" > "$target/theme.txt.new"
        mv "$target/theme.txt.new" "$target/theme.txt"
        rm -f "$target/logo.png"
    else
        cp --no-preserve=all "$theme_source/logos/$logo.png" "$target/logo.png"
        if [[ "$logo" == thinkpad ]]; then
            sed -i '/^# LOGO_BEGIN$/,/^# LOGO_END$/ { s/50%-160/50%-108/; s/50%-310/50%-280/; s/width = 320/width = 216/; s/height = 107/height = 78/; }' "$target/theme.txt"
        fi
    fi
    echo "ThinkGRUB logo: $logo"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    prepare_theme "${1:?Usage: prepare.sh OUTPUT [auto|thinkpad|asus|none]}" "${2:-auto}"
fi
