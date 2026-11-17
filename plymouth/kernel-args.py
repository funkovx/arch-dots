#!/usr/bin/env python3
"""Add splash parameters without replacing existing kernel arguments."""

import re
import shlex
import sys
from pathlib import Path


def configure(text):
    pattern = r"(?m)^GRUB_CMDLINE_LINUX_DEFAULT=(.*)$"
    matches = list(re.finditer(pattern, text))
    value = ""
    if matches:
        parts = shlex.split(matches[-1].group(1), comments=True)
        if len(parts) > 1 or (parts and ("$" in parts[0] or "`" in parts[0])):
            raise ValueError("Dynamic GRUB arguments require manual configuration")
        value = parts[0] if parts else ""
    args = value.split()
    remove = ("systemd.show_status=", "vt.global_cursor_default=")
    args = [arg for arg in args if arg not in ("quiet", "splash") and not arg.startswith(remove)]
    args += ["quiet", "splash", "systemd.show_status=false", "vt.global_cursor_default=0"]
    line = "GRUB_CMDLINE_LINUX_DEFAULT=" + shlex.quote(" ".join(args))
    return re.sub(pattern, "", text).rstrip() + "\n" + line + "\n"


if __name__ == "__main__":
    path = Path(sys.argv[1])
    path.write_text(configure(path.read_text()))
