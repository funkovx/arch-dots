"""Regression checks for boot setup and machine-independent configuration."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class Portability(unittest.TestCase):
    def test_plymouth_setup_and_rollback(self):
        for fail in (False, True):
            with self.subTest(build_failure=fail), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                for folder in ("etc/default", "etc/plymouth", "etc/mkinitcpio.d", "boot/grub", "app", "commands"):
                    (root / folder).mkdir(parents=True)
                default = root / "etc/default/grub"
                default.write_text('GRUB_CMDLINE_LINUX_DEFAULT="rootflags=subvol=@ quiet"\n')
                original = default.read_text()
                (root / "etc/mkinitcpio.conf").write_text("HOOKS=(base udev autodetect kms block filesystems)\n")
                image = root / "boot/initramfs-linux.img"
                image.write_text("original initramfs")
                grub = root / "boot/grub/grub.cfg"
                grub.write_text("original grub config")
                (root / "etc/mkinitcpio.d/linux.preset").write_text(f"PRESETS=(default)\ndefault_image='{image}'\n")
                shutil.copytree(ROOT / "plymouth/arch-minimal", root / "app/arch-minimal")
                shutil.copy(ROOT / "plymouth/kernel-args.py", root / "app/kernel-args.py")
                script = (ROOT / "plymouth/install.sh").read_text()
                script = script.replace("if (( EUID != 0 )); then", "if false; then")
                for prefix in ("/etc/", "/boot/", "/var/lib/", "/usr/share/"):
                    script = script.replace(prefix, str(root) + prefix)
                (root / "app/install.sh").write_text(script)
                stubs = {
                    "pacman": "exit 0",
                    "plymouth-set-default-theme": f"echo Theme=arch-minimal > '{root}/etc/plymouth/plymouthd.conf'",
                    "mkinitcpio": f"echo new-initramfs > '{image}'\nexit {1 if fail else 0}",
                    "lsinitcpio": "echo usr/share/plymouth/themes/arch-minimal/logo.png",
                    "grub-mkconfig": 'echo "linux /vmlinuz quiet splash" > "$2"',
                    "systemctl": "exit 0",
                }
                for name, body in stubs.items():
                    path = root / "commands" / name
                    path.write_text("#!/bin/sh\n" + body + "\n")
                    path.chmod(0o755)
                env = {**os.environ, "PATH": str(root / "commands") + ":" + os.environ["PATH"]}
                result = subprocess.run(["bash", str(root / "app/install.sh")], env=env, capture_output=True, text=True)
                if fail:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(default.read_text(), original)
                    self.assertEqual(image.read_text(), "original initramfs")
                    self.assertEqual(grub.read_text(), "original grub config")
                    self.assertFalse((root / "etc/mkinitcpio.conf.d/99-dotfiles-plymouth.conf").exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("quiet splash", default.read_text())
                    hooks = (root / "etc/mkinitcpio.conf.d/99-dotfiles-plymouth.conf").read_text()
                    self.assertIn("kms plymouth block", hooks)

    def test_kernel_arguments_preserved_and_idempotent(self):
        helper = module("kernel_args", ROOT / "plymouth/kernel-args.py")
        original = 'GRUB_THEME="/existing/theme.txt"\nGRUB_CMDLINE_LINUX_DEFAULT="rootflags=subvol=@ loglevel=3 quiet"\n'
        result = helper.configure(original)
        self.assertEqual(result, helper.configure(result))
        self.assertIn("rootflags=subvol=@ loglevel=3", result)
        self.assertIn('GRUB_THEME="/existing/theme.txt"', result)
        self.assertIn("quiet splash", result)
        self.assertIn("splash", helper.configure('GRUB_CMDLINE_LINUX_DEFAULT=""\n'))

    def test_logo_detection(self):
        script = 'source "$1"; detect_logo "$2"'
        for identity, expected in (("LENOVO 21HM ThinkPad X1", "thinkpad"),
                                   ("ASUSTeK COMPUTER INC. Vivobook", "asus"),
                                   ("LENOVO Yoga", "none"), ("", "none")):
            result = subprocess.check_output(["bash", "-c", script, "_",
                                              str(ROOT / "grub/thinkgrub/prepare.sh"), identity], text=True)
            self.assertEqual(result.strip(), expected)

    def test_unknown_machine_has_no_logo(self):
        with tempfile.TemporaryDirectory() as temp:
            subprocess.run([str(ROOT / "grub/thinkgrub/prepare.sh"), temp, "none"], check=True, capture_output=True)
            theme = Path(temp, "theme.txt").read_text()
            self.assertNotIn('file = "logo.png"', theme)
            self.assertFalse(Path(temp, "logo.png").exists())

    def test_link_preserves_existing_directory_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, dest = root / "source", root / "config"
            source.mkdir(); dest.mkdir()
            (dest / "local.lua").write_text("keep me")
            script = 'source "$1"; safe_link "$2" "$3"; safe_link "$2" "$3"'
            subprocess.run(["bash", "-eu", "-c", script, "_", str(ROOT / "lib/install-common.sh"),
                            str(source), str(dest)], env={**os.environ, "XDG_STATE_HOME": str(root / "state")},
                           check=True, capture_output=True)
            self.assertEqual(dest.resolve(), source)
            backups = list((root / "state/dotfiles/backups").glob("*/config/local.lua"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), "keep me")

    def test_temperature_intel_amd_and_missing(self):
        sensor = module("cpu_temperature", ROOT / ".config/waybar/scripts/cpu-temperature.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hwmon = root / "class/hwmon/hwmon8"
            hwmon.mkdir(parents=True)
            self.assertIsNone(sensor.temperature(root))
            for name, label, raw in (("coretemp", "Package id 0", "57000"),
                                     ("k10temp", "Tctl", "63000")):
                (hwmon / "name").write_text(name)
                (hwmon / "temp2_label").write_text(label)
                (hwmon / "temp2_input").write_text(raw)
                self.assertEqual(sensor.temperature(root), int(raw) / 1000)


if __name__ == "__main__":
    unittest.main()
