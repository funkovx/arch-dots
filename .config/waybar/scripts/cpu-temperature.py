#!/usr/bin/env python3
"""Discover CPU temperature sensors without assuming an Intel hwmon path."""

import json
from pathlib import Path


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def temperature(sysfs=Path("/sys")):
    names = ("coretemp", "k10temp", "zenpower", "cpu_thermal")
    sensors = []
    for hwmon in (sysfs / "class/hwmon").glob("hwmon*"):
        name = read(hwmon / "name")
        if name not in names:
            continue
        for path in hwmon.glob("temp*_input"):
            label = read(path.with_name(path.name.replace("_input", "_label")))
            priority = 0 if label in ("Package id 0", "Tctl", "Tdie") else 1
            sensors.append((priority, names.index(name), path))
    for _, _, path in sorted(sensors):
        try:
            return float(read(path)) / 1000
        except ValueError:
            pass
    for zone in (sysfs / "class/thermal").glob("thermal_zone*"):
        if read(zone / "type") in ("x86_pkg_temp", "cpu-thermal", "cpu_thermal"):
            try:
                return float(read(zone / "temp")) / 1000
            except ValueError:
                pass
    return None


if __name__ == "__main__":
    value = temperature()
    print(json.dumps({
        "text": "" if value is None else f"{value:.0f}°C",
        "tooltip": "CPU temperature unavailable" if value is None else f"CPU: {value:.0f}°C",
        "class": "unavailable" if value is None else "critical" if value >= 80 else "normal",
    }))
