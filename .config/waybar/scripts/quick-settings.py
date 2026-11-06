#!/usr/bin/env python3
"""One quick settings panel for Hyprland and Waybar."""

import fcntl
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import gi

os.environ["GDK_BACKEND"] = "wayland"
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell


STYLE = Path(__file__).resolve().parent.parent / "quick-settings.css"
ROUTE_STATE = Path.home() / ".cache" / "waybar-quick-settings" / "routes.json"


def run(*args, timeout=15):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(args, 1, "", str(exc))


def split_nmcli(line):
    parts, part, escape = [], "", False
    for char in line:
        if escape:
            part += char
            escape = False
        elif char == "\\":
            escape = True
        elif char == ":":
            parts.append(part)
            part = ""
        else:
            part += char
    return parts + [part]


def wifi_on():
    return run("nmcli", "-t", "-f", "WIFI", "general").stdout.strip() == "enabled"


def bluetooth_on():
    return "Powered: yes" in run("bluetoothctl", "show").stdout


def volume_state():
    output = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@").stdout
    number = re.search(r"([0-9]+(?:\.[0-9]+)?)", output)
    return (round(float(number.group(1)) * 100) if number else 0, "MUTED" in output)


def brightness_value():
    output = run("brightnessctl", "-m").stdout
    number = re.search(r"(\d+)%", output)
    return int(number.group(1)) if number else 0


def pactl_items(kind):
    result = run("pactl", "-f", "json", "list", kind)
    if result.returncode:
        return []
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return []


def pactl_volume(item):
    channels = item.get("volume", {})
    first = next(iter(channels.values()), {})
    match = re.search(r"\d+", first.get("value_percent", ""))
    return int(match.group()) if match else 0


def active_network_profiles():
    output = run("nmcli", "-t", "-e", "yes", "-f", "UUID,TYPE,DEVICE",
                 "connection", "show", "--active").stdout
    profiles = {}
    for line in output.splitlines():
        parts = split_nmcli(line)
        if len(parts) < 3:
            continue
        uuid, kind, device = parts[:3]
        if kind == "802-11-wireless" and device:
            profiles["wifi"] = (uuid, device)
        elif kind == "802-3-ethernet" and device:
            profiles["ethernet"] = (uuid, device)
    return profiles


def route_metrics(uuid):
    output = run("nmcli", "-g", "ipv4.route-metric,ipv6.route-metric",
                 "connection", "show", uuid).stdout.splitlines()
    return (output + ["-1", "-1"])[:2]


def saved_route_metrics():
    try:
        return json.loads(ROUTE_STATE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def save_route_metrics(state):
    ROUTE_STATE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = ROUTE_STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state))
    temporary.replace(ROUTE_STATE)


def wifi_networks():
    output = run("nmcli", "-t", "-e", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
                 "device", "wifi", "list", "--rescan", "no").stdout
    networks = {}
    for line in output.splitlines():
        parts = split_nmcli(line)
        if len(parts) < 4 or not parts[1]:
            continue
        active, ssid, signal, security = parts[:4]
        if ssid not in networks or active == "*":
            networks[ssid] = (active == "*", signal, security)
    return sorted(networks.items(), key=lambda item: (not item[1][0], -int(item[1][1] or 0)))


def bluetooth_devices(include_unnamed=False):
    devices = []
    for line in run("bluetoothctl", "devices").stdout.splitlines():
        match = re.match(r"Device ([0-9A-F:]{17}) (.+)", line)
        if not match:
            continue
        address, name = match.groups()
        info = run("bluetoothctl", "info", address).stdout
        paired = "Paired: yes" in info
        connected = "Connected: yes" in info
        advertised = re.search(r"(?m)^\s*Name: (.+)$", info)
        if advertised:
            name = advertised.group(1).strip()
        unnamed = bool(re.fullmatch(r"[0-9A-Fa-f]{2}(?:[-:][0-9A-Fa-f]{2}){5}", name))
        if unnamed and not (paired or connected or include_unnamed):
            continue
        if unnamed:
            name = f"Unnamed · {address}"
        devices.append((name, address, paired, connected))
    return sorted(devices, key=lambda item: (not item[3], not item[2], item[0].lower()))


class QuickSettings(Gtk.Application):
    def __init__(self, initial_mode):
        super().__init__(application_id="com.qfunk.WaybarQuickSettings")
        self.window = None
        self.mode = None
        self.initial_mode = initial_mode
        self.updating = False
        self.wifi_expanded = False
        self.bluetooth_expanded = False
        self.show_unnamed_bluetooth = False
        self.wifi_scan_busy = False
        self.bluetooth_scan_busy = False

    def do_activate(self):
        self.open_mode(self.initial_mode)

    def open_mode(self, mode):
        if self.window is None:
            self.build()
        if self.window.get_visible() and self.mode == mode:
            self.window.hide()
        else:
            self.mode = mode
            self.refresh()
            self.window.show_all()
            self.wifi_card.set_visible(mode in ("all", "wifi"))
            self.bluetooth_card.set_visible(mode == "all")
            self.refresh_priority()
            self.quick_audio_card.set_visible(mode == "all")
            self.audio_card.set_visible(mode == "sound")
            self.light_card.set_visible(mode in ("all", "brightness"))
            self.power_card.set_visible(mode == "power")
            self.title.set_text({"all": "Quick settings", "wifi": "Wi-Fi networks",
                                 "sound": "Sound settings", "brightness": "Brightness",
                                 "power": "Power mode"}[mode])
            self.wifi_expanded = mode == "wifi"
            self.bluetooth_expanded = False
            self.wifi_revealer.set_reveal_child(self.wifi_expanded)
            self.bluetooth_revealer.set_reveal_child(self.bluetooth_expanded)
            if self.wifi_expanded:
                self.scan_wifi()
            if mode == "sound":
                self.refresh_audio()
            self.window.present()

    def build(self):
        css = Gtk.CssProvider()
        css.load_from_path(str(STYLE))
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_name("quick-settings")
        self.window.set_title("Quick settings")
        self.window.set_default_size(380, -1)
        self.window.set_resizable(False)
        self.window.set_decorated(False)
        visual = self.window.get_screen().get_rgba_visual()
        if visual is not None:
            self.window.set_visual(visual)
        self.window.set_app_paintable(True)
        self.window.connect("key-press-event", self.on_key)
        self.window.connect("delete-event", self.on_delete)
        GtkLayerShell.init_for_window(self.window)
        GtkLayerShell.set_namespace(self.window, "waybar-quick-settings")
        GtkLayerShell.set_layer(self.window, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.TOP, 2)
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.RIGHT, 8)
        GtkLayerShell.set_keyboard_mode(self.window, GtkLayerShell.KeyboardMode.ON_DEMAND)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.get_style_context().add_class("panel")
        outer.set_border_width(0)
        self.window.add(outer)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_top(16)
        content.set_margin_bottom(16)
        content.set_margin_start(16)
        content.set_margin_end(16)
        outer.pack_start(content, True, True, 0)
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.title = Gtk.Label(label="Quick settings", xalign=0)
        self.title.get_style_context().add_class("title")
        head.pack_start(self.title, True, True, 0)
        head.pack_end(self.button("✕", lambda *_: self.window.hide(), "close"), False, False, 0)
        content.pack_start(head, False, False, 0)

        self.wifi_card, self.wifi_switch, self.wifi_revealer, self.wifi_list = self.section(
            content, "Wi-Fi", self.toggle_wifi, self.toggle_wifi_list)
        self.bluetooth_card, self.bluetooth_switch, self.bluetooth_revealer, self.bluetooth_list = self.section(
            content, "Bluetooth", self.toggle_bluetooth, self.toggle_bluetooth_list)
        self.priority_card = self.card(content)
        self.priority_card.pack_start(Gtk.Label(label="Preferred internet route", xalign=0), False, False, 0)
        self.priority_card.pack_start(Gtk.Label(label="Ethernet and Wi-Fi both stay connected", xalign=0),
                                      False, False, 0)
        self.priority_options = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        self.priority_card.pack_start(self.priority_options, False, False, 0)

        quick_audio = self.quick_audio_card = self.card(content)
        quick_audio.pack_start(Gtk.Label(label="Sound", xalign=0), False, False, 0)
        quick_audio_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        quick_audio.pack_start(quick_audio_row, False, False, 0)
        self.quick_mute_button = self.button("Mute", self.toggle_quick_mute)
        quick_audio_row.pack_start(self.quick_mute_button, False, False, 0)
        self.quick_volume_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        self.quick_volume_scale.set_draw_value(False)
        self.quick_volume_scale.set_hexpand(True)
        self.quick_volume_scale.connect("value-changed", self.change_quick_volume)
        quick_audio_row.pack_start(self.quick_volume_scale, True, True, 0)
        self.quick_volume_label = Gtk.Label(label="0%")
        quick_audio_row.pack_start(self.quick_volume_label, False, False, 0)

        audio = self.audio_card = self.card(content)
        self.audio_notebook = Gtk.Notebook()
        self.audio_notebook.set_show_border(False)
        audio.pack_start(self.audio_notebook, False, False, 0)
        self.outputs_page = self.audio_page("Devices")
        self.mixer_page = self.audio_page("Mixer")

        light = self.light_card = self.card(content)
        light.pack_start(Gtk.Label(label="Brightness", xalign=0), False, False, 0)
        light_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        light.pack_start(light_row, False, False, 0)
        self.brightness_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 1, 100, 1)
        self.brightness_scale.set_draw_value(False)
        self.brightness_scale.set_hexpand(True)
        self.brightness_scale.connect("value-changed", self.change_brightness)
        light_row.pack_start(self.brightness_scale, True, True, 0)
        self.brightness_label = Gtk.Label(label="0%")
        light_row.pack_start(self.brightness_label, False, False, 0)
        self.power_card = self.card(content)
        self.power_card.pack_start(Gtk.Label(label="Performance mode", xalign=0), False, False, 0)
        self.power_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.power_card.pack_start(self.power_list, False, False, 0)
        GLib.timeout_add_seconds(5, self.periodic_refresh)
        GLib.timeout_add_seconds(15, self.periodic_discovery)

    def audio_page(self, title):
        scroll = Gtk.ScrolledWindow()
        scroll.get_style_context().add_class("audio-scroll")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_propagate_natural_height(True)
        scroll.set_max_content_height(390)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(4)
        box.set_margin_end(4)
        scroll.add(box)
        self.audio_notebook.append_page(scroll, Gtk.Label(label=title))
        return box

    def button(self, label, callback, style=None):
        button = Gtk.Button(label=label)
        if style:
            button.get_style_context().add_class(style)
        if style in ("expand", "list"):
            button.get_child().set_xalign(0.0)
        button.connect("clicked", callback)
        return button

    def card(self, parent):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.get_style_context().add_class("card")
        parent.pack_start(box, False, False, 0)
        return box

    def section(self, parent, title, on_switch, on_expand):
        card = self.card(parent)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        card.pack_start(row, False, False, 0)
        expand = self.button(f"{title}  ▾", on_expand, "expand")
        expand.set_hexpand(True)
        row.pack_start(expand, True, True, 0)
        toggle = Gtk.Switch()
        toggle.set_valign(Gtk.Align.CENTER)
        toggle.connect("notify::active", on_switch)
        row.pack_end(toggle, False, False, 0)
        revealer = Gtk.Revealer()
        revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        card.pack_start(revealer, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.get_style_context().add_class("network-scroll")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_propagate_natural_height(True)
        scroll.set_max_content_height(280)
        revealer.add(scroll)
        listbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        scroll.add(listbox)
        return card, toggle, revealer, listbox

    def clear(self, box):
        for child in box.get_children():
            box.remove(child)

    def refresh(self):
        self.updating = True
        self.wifi_switch.set_active(wifi_on())
        self.bluetooth_switch.set_active(bluetooth_on())
        volume, muted = volume_state()
        self.quick_volume_scale.set_value(min(volume, 150))
        self.quick_volume_label.set_text(f"{volume}%")
        self.quick_mute_button.set_label("Unmute" if muted else "Mute")
        light = brightness_value()
        self.brightness_scale.set_value(max(1, light))
        self.brightness_label.set_text(f"{light}%")
        self.updating = False
        if self.mode == "power":
            self.refresh_power()
        if self.mode == "sound":
            self.refresh_audio()
        self.refresh_priority()

    def refresh_priority(self):
        profiles = active_network_profiles()
        available = "wifi" in profiles and "ethernet" in profiles
        self.priority_card.set_visible(available and self.mode in ("all", "wifi"))
        if not available:
            return
        wifi_metric = route_metrics(profiles["wifi"][0])[0]
        ethernet_metric = route_metrics(profiles["ethernet"][0])[0]
        selected = ("ethernet" if ethernet_metric == "100" and wifi_metric == "600" else
                    "wifi" if wifi_metric == "100" and ethernet_metric == "600" else "auto")
        self.clear(self.priority_options)
        for key, name in (("auto", "Auto"), ("ethernet", "Ethernet"), ("wifi", "Wi-Fi")):
            button = self.button(f"{'●' if key == selected else '○'} {name}",
                                 lambda _, choice=key: self.set_priority(choice))
            self.priority_options.pack_start(button, True, True, 0)
        self.priority_options.show_all()

    def set_priority(self, choice):
        profiles = active_network_profiles()
        if not ("wifi" in profiles and "ethernet" in profiles):
            return
        saved = saved_route_metrics()
        if choice != "auto":
            for uuid, _device in profiles.values():
                saved.setdefault(uuid, list(route_metrics(uuid)))
            save_route_metrics(saved)
        for kind in ("wifi", "ethernet"):
            uuid, _device = profiles[kind]
            if choice == "auto":
                ipv4, ipv6 = saved.get(uuid, ["-1", "-1"])
            else:
                ipv4 = ipv6 = "100" if kind == choice else "600"
            result = run("nmcli", "connection", "modify", uuid,
                         "ipv4.route-metric", ipv4, "ipv6.route-metric", ipv6)
            if result.returncode:
                self.report(result)
                return
        for uuid, device in profiles.values():
            self.report(run("nmcli", "device", "reapply", device))
            if choice == "auto":
                saved.pop(uuid, None)
        save_route_metrics(saved)
        self.refresh_priority()

    def toggle_quick_mute(self, *_):
        self.report(run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"))
        self.refresh()

    def change_quick_volume(self, scale):
        if not self.updating:
            value = round(scale.get_value())
            self.quick_volume_label.set_text(f"{value}%")
            run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value}%")

    def audio_heading(self, parent, title):
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("audio-heading")
        parent.pack_start(label, False, False, 0)

    def audio_control(self, parent, kind, item, default=False):
        target = kind.removesuffix("s")
        if kind == "sink-inputs":
            target = "sink-input"
        elif kind == "source-outputs":
            target = "source-output"
        index = str(item["index"])
        name = item.get("description") or item.get("properties", {}).get("application.name") or item.get("name") or target
        if kind in ("sink-inputs", "source-outputs"):
            media = item.get("properties", {}).get("media.name", "")
            if media and media != name:
                name += f" · {media}"
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        card.get_style_context().add_class("audio-device")
        parent.pack_start(card, False, False, 0)
        if kind in ("sinks", "sources"):
            selector = self.button(f"{'●' if default else '○'}  {name}",
                                   lambda *_: self.select_audio(target, item["name"]), "list")
            card.pack_start(selector, False, False, 0)
        else:
            label = Gtk.Label(label=name, xalign=0)
            label.set_ellipsize(3)
            label.set_max_width_chars(42)
            label.set_tooltip_text(name)
            card.pack_start(label, False, False, 0)
        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        card.pack_start(controls, False, False, 0)
        mute = self.button("Unmute" if item.get("mute") else "Mute",
                           lambda *_: self.mute_audio(target, index))
        controls.pack_start(mute, False, False, 0)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        scale.set_draw_value(False)
        scale.set_hexpand(True)
        level = pactl_volume(item)
        scale.set_value(level)
        controls.pack_start(scale, True, True, 0)
        percent = Gtk.Label(label=f"{level}%")
        controls.pack_start(percent, False, False, 0)
        scale.connect("value-changed", lambda widget: self.change_audio(target, index, widget, percent))

    def refresh_audio(self):
        self.clear(self.outputs_page)
        self.clear(self.mixer_page)
        defaults = {"sinks": run("pactl", "get-default-sink").stdout.strip(),
                    "sources": run("pactl", "get-default-source").stdout.strip()}
        for kind, title in (("sinks", "Output"), ("sources", "Input")):
            self.audio_heading(self.outputs_page, title)
            items = pactl_items(kind)
            if kind == "sources":
                items = [item for item in items if not item.get("name", "").endswith(".monitor")]
            for item in items:
                self.audio_control(self.outputs_page, kind, item, item.get("name") == defaults[kind])
            if not items:
                self.outputs_page.pack_start(Gtk.Label(label="No devices found", xalign=0), False, False, 0)
        found = False
        for kind, title in (("sink-inputs", "Applications: playback"),
                            ("source-outputs", "Applications: recording")):
            items = pactl_items(kind)
            if items:
                found = True
                self.audio_heading(self.mixer_page, title)
                for item in items:
                    self.audio_control(self.mixer_page, kind, item)
        if not found:
            self.mixer_page.pack_start(Gtk.Label(label="No active audio applications", xalign=0), False, False, 0)
        self.outputs_page.show_all()
        self.mixer_page.show_all()

    def select_audio(self, target, name):
        result = run("pactl", f"set-default-{target}", name)
        self.report(result)
        if result.returncode == 0:
            streams = "sink-inputs" if target == "sink" else "source-outputs"
            move = "move-sink-input" if target == "sink" else "move-source-output"
            for item in pactl_items(streams):
                run("pactl", move, str(item["index"]), name)
        self.refresh_audio()

    def mute_audio(self, target, index):
        self.report(run("pactl", f"set-{target}-mute", index, "toggle"))
        self.refresh_audio()

    def change_audio(self, target, index, scale, label):
        value = round(scale.get_value())
        label.set_text(f"{value}%")
        run("pactl", f"set-{target}-volume", index, f"{value}%")

    def refresh_power(self):
        self.clear(self.power_list)
        available = run("powerprofilesctl", "list").stdout
        active = run("powerprofilesctl", "get").stdout.strip()
        profiles = [("power-saver", "Power saver"), ("balanced", "Balanced"),
                    ("performance", "Performance")]
        for profile, name in profiles:
            if re.search(rf"(?m)^\s*\*?\s*{profile}:", available):
                label = f"{'●' if active == profile else '○'}  {name}"
                self.power_list.pack_start(self.button(label, lambda _, p=profile: self.set_power(p), "list"),
                                           False, False, 0)
        self.power_list.show_all()

    def set_power(self, profile):
        self.report(run("powerprofilesctl", "set", profile))
        self.refresh_power()

    def periodic_refresh(self):
        if self.window and self.window.get_visible():
            self.refresh()
        return True

    def periodic_discovery(self):
        if self.window and self.window.get_visible():
            if self.wifi_expanded:
                self.scan_wifi()
            if self.bluetooth_expanded:
                self.scan_bluetooth()
        return True

    def toggle_wifi_list(self, *_):
        self.wifi_expanded = not self.wifi_expanded
        self.wifi_revealer.set_reveal_child(self.wifi_expanded)
        if self.wifi_expanded:
            self.scan_wifi()

    def toggle_bluetooth_list(self, *_):
        self.bluetooth_expanded = not self.bluetooth_expanded
        self.bluetooth_revealer.set_reveal_child(self.bluetooth_expanded)
        if self.bluetooth_expanded:
            self.scan_bluetooth()

    def refresh_wifi(self):
        self.clear(self.wifi_list)
        if self.wifi_switch.get_active():
            refresh = self.button("Scanning..." if self.wifi_scan_busy else "Refresh networks", self.scan_wifi, "list")
            refresh.set_sensitive(not self.wifi_scan_busy)
            self.wifi_list.pack_start(refresh, False, False, 0)
            for ssid, (active, signal, security) in wifi_networks():
                label = f"{'●' if active else '○'}  {ssid}  {signal}%"
                if security and security != "--":
                    label += "  · password"
                self.wifi_list.pack_start(self.button(label, lambda _, s=ssid, a=active, sec=security:
                                                      self.connect_wifi(s, a, sec), "list"), False, False, 0)
        self.wifi_list.show_all()

    def scan_wifi(self, *_):
        if self.wifi_scan_busy or not wifi_on():
            return
        self.wifi_scan_busy = True
        self.refresh_wifi()

        def done():
            self.wifi_scan_busy = False
            self.refresh_wifi()

        self.background(lambda: run("nmcli", "device", "wifi", "rescan"), done)

    def connect_wifi(self, ssid, active, security):
        if active:
            return
        args = ["nmcli", "device", "wifi", "connect", ssid]
        result = run(*args, timeout=25)
        if result.returncode and security and security != "--":
            dialog = Gtk.Dialog(title=f"Password: {ssid}", transient_for=self.window, modal=True)
            dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
            dialog.add_button("Connect", Gtk.ResponseType.OK)
            entry = Gtk.Entry()
            entry.set_visibility(False)
            entry.set_activates_default(True)
            dialog.set_default_response(Gtk.ResponseType.OK)
            dialog.get_content_area().pack_start(entry, True, True, 12)
            dialog.show_all()
            response = dialog.run()
            password = entry.get_text()
            dialog.destroy()
            if response != Gtk.ResponseType.OK or not password:
                return
            result = run(*args, "password", password, timeout=30)
        self.report(result)
        self.refresh_wifi()

    def refresh_bluetooth(self):
        self.clear(self.bluetooth_list)
        if self.bluetooth_switch.get_active():
            refresh = self.button("Scanning..." if self.bluetooth_scan_busy else "Find devices", self.scan_bluetooth, "list")
            refresh.set_sensitive(not self.bluetooth_scan_busy)
            self.bluetooth_list.pack_start(refresh, False, False, 0)
            for name, address, paired, connected in bluetooth_devices(self.show_unnamed_bluetooth):
                label = f"{'●' if connected else '○'}  {name}  ·  {'connected' if connected else 'paired' if paired else 'connect'}"
                self.bluetooth_list.pack_start(self.button(label, lambda _, a=address, p=paired, c=connected:
                                                           self.connect_bluetooth(a, p, c), "list"), False, False, 0)
            label = "Hide unnamed devices" if self.show_unnamed_bluetooth else "Show unnamed devices"
            self.bluetooth_list.pack_start(self.button(label, self.toggle_unnamed_bluetooth, "list"), False, False, 0)
        self.bluetooth_list.show_all()

    def toggle_unnamed_bluetooth(self, *_):
        self.show_unnamed_bluetooth = not self.show_unnamed_bluetooth
        self.refresh_bluetooth()

    def scan_bluetooth(self, *_):
        if self.bluetooth_scan_busy or not bluetooth_on():
            return
        self.bluetooth_scan_busy = True
        self.refresh_bluetooth()

        def scan():
            run("bluetoothctl", "pairable", "on")
            result = run("bluetoothctl", "--timeout", "8", "scan", "on", timeout=12)
            run("bluetoothctl", "scan", "off")
            return result

        def done():
            self.bluetooth_scan_busy = False
            self.refresh_bluetooth()

        self.background(scan, done)

    def connect_bluetooth(self, address, paired, connected):
        if connected:
            result = run("bluetoothctl", "disconnect", address)
        elif paired:
            result = run("bluetoothctl", "connect", address, timeout=30)
        else:
            run("bluetoothctl", "pairable", "on")
            result = run("bluetoothctl", "--agent=NoInputNoOutput", "pair", address, timeout=45)
            if result.returncode == 0:
                run("bluetoothctl", "trust", address)
                result = run("bluetoothctl", "connect", address, timeout=30)
        self.report(result)
        self.refresh_bluetooth()

    def toggle_wifi(self, switch, *_):
        if not self.updating:
            self.report(run("nmcli", "radio", "wifi", "on" if switch.get_active() else "off"))
            self.refresh_wifi()

    def toggle_bluetooth(self, switch, *_):
        if not self.updating:
            self.report(run("bluetoothctl", "power", "on" if switch.get_active() else "off"))
            self.refresh_bluetooth()

    def change_brightness(self, scale):
        if not self.updating:
            value = round(scale.get_value())
            self.brightness_label.set_text(f"{value}%")
            run("brightnessctl", "set", f"{value}%")

    def background(self, action, done):
        def worker():
            result = action()
            GLib.idle_add(lambda: (self.report(result), done(), False)[-1])
        threading.Thread(target=worker, daemon=True).start()

    def report(self, result):
        if result.returncode:
            message = (result.stderr or result.stdout or "Action failed").strip()[:240]
            run("notify-send", "Quick settings", message)

    def on_key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.window.hide()
            return True
        return False

    def on_delete(self, *_):
        self.window.hide()
        return True


def send_to_existing(path, mode):
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(0.5)
            client.connect(str(path))
            client.sendall(mode.encode())
        return True
    except (OSError, TimeoutError):
        return False


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in ("wifi", "sound", "brightness", "power") else "all"
    runtime = Path.home() / ".cache" / "waybar-quick-settings"
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = runtime / f"waybar-quick-settings-{os.getuid()}.sock"
    if send_to_existing(path, mode):
        return 0
    lock = open(runtime / f"waybar-quick-settings-{os.getuid()}.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        for _ in range(10):
            time.sleep(0.1)
            if send_to_existing(path, mode):
                return 0
        return 1
    try:
        path.unlink(missing_ok=True)
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(path))
        server.listen(5)
        server.settimeout(1)
        app = QuickSettings(mode)

        def listen():
            while True:
                try:
                    client, _ = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    return
                with client:
                    requested = client.recv(32).decode(errors="ignore")
                if requested in ("all", "wifi", "sound", "brightness", "power"):
                    GLib.idle_add(app.open_mode, requested)

        threading.Thread(target=listen, daemon=True).start()
        app.hold()
        return app.run([sys.argv[0]])
    finally:
        if 'server' in locals():
            server.close()
        path.unlink(missing_ok=True)
        lock.close()


if __name__ == "__main__":
    sys.exit(main())
