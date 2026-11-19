import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "lib/cli-helpers/local-config"
DISPATCHER = ROOT / "lib/cli-helpers/etc/NetworkManager/dispatcher.d"


def shell_function(file, name):
    """Load just the backup or restore function, without running its CLI."""
    source = (ROOT / file).read_text()
    begin = source.index(f"\n{name}() {{\n") + 1
    return source[begin:source.index("\n}", begin) + 2]


class LocalConfigTest(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name)

    def bash(self, code, *args, env=None):
        return subprocess.check_output(
            ["bash", "-ec", code, "_", *map(str, args)], env=env, text=True,
        )

    def stub(self, name, source):
        path = self.path / name
        path.write_text("#!/bin/bash\n" + source + "\n")
        path.chmod(0o755)
        return path

    def test_config_values_are_literal_and_missing_files_are_optional(self):
        cfg = self.path / "test.conf"
        sentinel = self.path / "executed"
        value = f"$(touch {sentinel}) x=y"
        cfg.write_text(f"setting={value}\n")
        result = self.bash('. "$1"; local_config_value "$2" setting', LIBRARY, cfg)
        self.assertEqual(result.strip(), value)
        self.assertFalse(sentinel.exists())
        self.assertEqual(self.bash('. "$1"; local_config_value "$2" setting', LIBRARY, sentinel), "")

    def test_private_config_backup_and_restore_keep_existing_values(self):
        source = self.path / "source"
        backup = self.path / "backup"
        target = self.path / "target"
        for directory in (source, target):
            (directory / "cli-helpers").mkdir(parents=True)
        (source / "cli-helpers/wifi.conf").write_text("home=New network\n")
        (source / "cli-helpers/setup.conf").write_text("vpn_name=Work VPN\n")
        (source / "cli-helpers/unrelated-secret.conf").write_text("unrelated\n")
        (target / "cli-helpers/wifi.conf").write_text("home=Existing network\n")
        code = (
            shell_function("setup-backup", "backup_local_config") + "\n"
            + shell_function("setup.sh", "restore_local_config") + "\n"
            + '''
. "$1"
LOCAL_CONFIG_DIR="$2"
BACKUP_DIR="$3"
failed=()
has_part() { test -d "$BACKUP_DIR/$1"; }
load_setup_config() { local_config_value "$LOCAL_CONFIG_DIR/cli-helpers/setup.conf" vpn_name; }
backup_local_config "$BACKUP_DIR"
test "${#failed[@]}" = 0
LOCAL_CONFIG_DIR="$4"
restore_local_config
test "${#failed[@]}" = 0
'''
        )
        self.assertEqual(self.bash(code, LIBRARY, source, backup, target).strip(), "Work VPN")
        moved = backup / "local-config/cli-helpers"
        self.assertEqual({file.name for file in moved.iterdir()}, {"wifi.conf", "setup.conf"})
        self.assertEqual((moved / "wifi.conf").stat().st_mode & 0o777, 0o600)
        self.assertEqual((target / "cli-helpers/setup.conf").stat().st_mode & 0o777, 0o600)
        self.assertEqual((target / "cli-helpers/wifi.conf").read_text(), "home=Existing network\n")

    def test_wifi_uses_private_aliases_with_spaces(self):
        (self.path / "cli-helpers").mkdir()
        (self.path / "cli-helpers/wifi.conf").write_text("work=Office Wi-Fi|Other network\n")
        self.stub("iw", 'printf "\tInterface wlan0\n\t\tssid Office Wi-Fi\n"')
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.path), PATH=f"{self.path}:{os.environ['PATH']}")
        self.assertEqual(self.bash('exec "$1"', ROOT / "wifi", env=env).strip(), "work")
        self.assertEqual(self.bash('exec "$1" --map "Other network"', ROOT / "wifi", env=env).strip(), "work")

    def test_vpn_dispatcher_filters_profile_and_passes_domains_as_arguments(self):
        config = self.path / "networkmanager.conf"
        config.write_text("vpn_profile=Work VPN\nvpn_domains=corp.example ops.example\n")
        helper = self.path / "networkmanager-functions"
        original = ROOT / "lib/cli-helpers/etc/cli-helpers/networkmanager-functions"
        helper.write_text(original.read_text().replace("/etc/cli-helpers/networkmanager.conf", str(config)))
        self.stub("resolvectl", 'printf "<%s>\n" "$@"')
        slack = self.stub("set-slack-profile", "echo slack")
        hook = self.path / "tun-up"
        hook.write_text((DISPATCHER / "tun-up").read_text()
                        .replace("/etc/cli-helpers/networkmanager.conf", str(config))
                        .replace("/etc/cli-helpers/networkmanager-functions", str(helper))
                        .replace("/usr/local/bin/set-slack-profile", str(slack)))
        env = dict(os.environ, VPN_IP4_DOMAINS="auto.example extra.example",
                   PATH=f"{self.path}:{os.environ['PATH']}", CONNECTION_ID="Work VPN")
        call = 'bash "$1" tun0 vpn-up'
        result = self.bash(call, hook, env=env)
        self.assertEqual(result.splitlines(), [
            "<domain>", "<tun0>", "<~.>", "<auto.example>", "<extra.example>",
            "<corp.example>", "<ops.example>", "slack",
        ])
        env["CONNECTION_ID"] = "Other"
        self.assertEqual(self.bash(call, hook, env=env), "")


if __name__ == "__main__":
    unittest.main()
