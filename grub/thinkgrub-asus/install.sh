#!/usr/bin/env bash
# Compatibility entry point for the original ASUS installation command.
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$source_dir/../thinkgrub/install.sh" asus
