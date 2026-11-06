#!/usr/bin/env python3
"""Toggle a distraction-free game session without losing prior settings."""

import fcntl
import json
import os
import signal
import subprocess
from pathlib import Path


RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
STATE_DIR = RUNTIME / "qfunk-game-mode"
STATE_FILE = STATE_DIR / "state.json"


def command(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def waybar_pids(visible_only=False):
    if visible_only:
        try:
            layers = json.loads(command("hyprctl", "layers", "-j").stdout)
            return {
                int(layer["pid"])
                for monitor in layers.values()
                for layer in monitor["levels"].get("2", [])
                if layer["namespace"] == "waybar"
            }
        except (ValueError, KeyError, TypeError):
            return set()
    return {int(pid) for pid in command("pgrep", "-x", "waybar").stdout.split()}


def animations_enabled():
    try:
        return json.loads(command("hyprctl", "getoption", "animations:enabled", "-j").stdout)["bool"]
    except (ValueError, KeyError):
        return True


def save(state):
    temporary = STATE_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state))
    temporary.replace(STATE_FILE)


def toggle():
    if STATE_FILE.exists():
        state = json.loads(STATE_FILE.read_text())
        pid = state.get("inhibitor_pid")
        if pid:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        command("hyprctl", "eval", "hl.config({ animations = { enabled = "
                + ("true" if state.get("animations", True) else "false") + " } })")
        if state.get("power_profile"):
            command("powerprofilesctl", "set", state["power_profile"])
        if state.get("bar_hidden") and not waybar_pids(visible_only=True):
            for bar_pid in waybar_pids():
                os.kill(bar_pid, signal.SIGUSR1)
        STATE_FILE.unlink()
        return

    visible_bars = waybar_pids(visible_only=True)
    profile = command("powerprofilesctl", "get").stdout.strip()
    inhibitor = subprocess.Popen(
        ["systemd-inhibit", "--what=idle", "--mode=block", "--who=Game mode",
         "--why=Keep the display awake while gaming", "sleep", "infinity"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    save({"bar_hidden": bool(visible_bars), "animations": animations_enabled(),
          "power_profile": profile, "inhibitor_pid": inhibitor.pid})
    for bar_pid in visible_bars:
        os.kill(bar_pid, signal.SIGUSR1)
    command("hyprctl", "eval", "hl.config({ animations = { enabled = false } })")
    if "performance:" in command("powerprofilesctl", "list").stdout:
        command("powerprofilesctl", "set", "performance")


if __name__ == "__main__":
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (STATE_DIR / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        toggle()
