#!/usr/bin/env python3
"""Waybar custom module — shows Claude.ai session and weekly usage.

Setup:
  1. Get your sessionKey from claude.ai DevTools → Application → Cookies
  2. mkdir -p ~/.config/claude-limits-widget
  3. echo 'CLAUDE_SESSION_KEY=sk-ant-...' > ~/.config/claude-limits-widget/secret.env
  4. chmod 600 ~/.config/claude-limits-widget/secret.env
"""

import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone

CONFIG_DIR = os.path.expanduser("~/.config/claude-limits-widget")
SECRET_FILE = os.path.join(CONFIG_DIR, "secret.env")


def load_session_key():
    key = os.environ.get("CLAUDE_SESSION_KEY")
    if key:
        return key
    if os.path.exists(SECRET_FILE):
        with open(SECRET_FILE) as f:
            for line in f:
                line = line.strip()
                if line.startswith("CLAUDE_SESSION_KEY="):
                    return line.split("=", 1)[1].strip().strip("\"'")
    return None


def api_get(url, session_key):
    req = urllib.request.Request(url)
    req.add_header("Cookie", f"sessionKey={session_key}")
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36")
    req.add_header("anthropic-client-platform", "web_claude_ai")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def format_reset(ts_str):
    if not ts_str:
        return ""
    try:
        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        secs = int((ts - now).total_seconds())
        if secs <= 0:
            return "Resetting soon"
        h, rem = divmod(secs, 3600)
        m = rem // 60
        return f"Resets in {h}h {m}m" if h > 0 else f"Resets in {m}m"
    except Exception:
        return ""


def bar(p, width=16):
    filled = round(width * p / 100)
    return "█" * filled + "░" * (width - filled)


def output_error(msg, transient=False):
    print(json.dumps({"text": f"✦ {msg}", "tooltip": msg, "class": "error"}))
    sys.exit(0)


def main():
    session_key = load_session_key()
    if not session_key:
        output_error("set sessionKey")
        return

    try:
        orgs = api_get("https://claude.ai/api/organizations", session_key)
        org_uuid = orgs[0]["uuid"]
    except urllib.error.HTTPError as e:
        output_error("session expired" if e.code in (401, 403, 419) else f"HTTP {e.code}")
        return
    except Exception:
        output_error("offline")
        return

    try:
        data = api_get(f"https://claude.ai/api/organizations/{org_uuid}/usage", session_key)
    except Exception:
        output_error("bad response", transient=True)
        return

    five_hour = data.get("five_hour") or {}
    seven_day = data.get("seven_day") or {}

    session_pct = round(five_hour.get("utilization", 0))
    weekly_pct  = round(seven_day.get("utilization", 0))

    session_reset = format_reset(five_hour.get("resets_at", ""))
    weekly_reset  = format_reset(seven_day.get("resets_at", ""))

    tooltip_lines = [
        "✦ Claude Usage",
        "",
        f"Session (5h)  ·  {session_pct}%",
        bar(session_pct),
        session_reset,
        "",
        f"Weekly  ·  {weekly_pct}%",
        bar(weekly_pct),
        weekly_reset,
    ]

    # Extra buckets
    extras = {
        "seven_day_opus":       "Weekly Opus",
        "seven_day_sonnet":     "Weekly Sonnet",
        "seven_day_omelette":   "Weekly Design",
        "seven_day_cowork":     "Weekly Code",
        "seven_day_oauth_apps": "OAuth Apps",
    }
    for key, label in extras.items():
        bucket = data.get(key)
        if bucket and bucket.get("utilization") is not None:
            p = round(bucket["utilization"])
            tooltip_lines += ["", f"{label}  ·  {p}%", bar(p),
                              format_reset(bucket.get("resets_at", ""))]

    tooltip_lines.append(f"\nUpdated {datetime.now().strftime('%H:%M')}")

    max_pct = max(session_pct, weekly_pct)
    css_class = "critical" if max_pct >= 80 else "warning" if max_pct >= 50 else "normal"

    print(json.dumps({
        "text": f"✦ {session_pct}%",
        "tooltip": "\n".join(tooltip_lines),
        "class": css_class,
        "percentage": max_pct,
    }))


if __name__ == "__main__":
    main()
