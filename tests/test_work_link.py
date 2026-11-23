from contextlib import redirect_stderr, redirect_stdout
import importlib.machinery
import importlib.util
from io import StringIO
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

source = Path(__file__).resolve().parents[1] / "work-link"
loader = importlib.machinery.SourceFileLoader("work_link", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
work_link = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = work_link
loader.exec_module(work_link)


class ConnectionPolicyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)
        self.budget = work_link.AuthBudget(self.state)
        self.config = work_link.Config("VPN", "https://internal.example.com/", ["Work", "Home"], [])
        self.network = Mock()
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/1", wifi="Guest")
        self.network.probe.return_value = False
        self.network.vpn_up.side_effect = self.rejected
        self.network.better_wifi.return_value = None
        self.credential = Mock(return_value="fake credential")
        self.now = 1000
        self.restart()

    def restart(self):
        self.keeper = work_link.Keeper(
            self.config, self.network, self.budget, Mock(), self.credential, lambda: self.now,
        )

    def step(self):
        with self.budget.lock():
            return self.keeper.step()

    def rejected(self, profile, uplink, password, reserve):
        reserve()
        self.assertEqual(
            self.budget.used(), self.network.vpn_up.call_count,
            "The attempt must be persisted before sending credentials.",
        )
        return "authentication rejected"

    def test_native_connection_is_kept_when_internal_https_works(self):
        self.network.probe.return_value = True
        self.assertTrue(self.step())
        self.network.wifi_up.assert_not_called()
        self.network.vpn_up.assert_not_called()

    def test_unknown_wifi_gets_vpn_after_failed_probe_without_switching(self):
        def connected(profile, uplink, password, reserve):
            reserve()
            self.assertEqual(self.budget.used(), 1)
            return "connected"

        self.network.vpn_up.side_effect = connected
        self.network.probe.side_effect = [False, True]
        self.assertTrue(self.step())
        self.network.wifi_up.assert_not_called()
        self.network.vpn_up.assert_called_once()
        self.assertEqual(self.budget.used(), 0)

    def test_attempt_limit_survives_service_restart_and_wifi_switch(self):
        self.assertFalse(self.step())
        self.assertFalse(self.step())  # backoff
        self.now += 30
        self.assertFalse(self.step())
        self.budget = work_link.AuthBudget(self.state)
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/2", wifi="Home")
        self.restart()
        self.now += 3600
        self.assertFalse(self.step())
        self.assertEqual(self.network.vpn_up.call_count, 2)
        self.assertEqual(self.budget.used(), 2)
        self.assertEqual(self.credential.call_count, 2)

    def test_ambiguous_timeout_is_also_capped(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        def timed_out(profile, uplink, password, reserve):
            reserve()
            return "activation timed out"

        self.network.vpn_up.side_effect = timed_out
        for _ in range(5):
            self.assertFalse(self.step())
            self.now += 120
        self.assertEqual(self.network.vpn_up.call_count, 2)
        self.assertIn("paused after two attempts", self.keeper.notify.call_args.args[0])

    def test_credential_failures_back_off_without_spending_attempts(self):
        self.credential.return_value = None
        self.assertFalse(self.step())
        self.assertFalse(self.step())
        self.credential.assert_called_once()
        self.now += 15
        self.assertFalse(self.step())
        self.assertEqual(self.credential.call_count, 2)
        self.assertEqual(self.budget.used(), 0)
        self.network.vpn_up.assert_not_called()

    def test_background_checks_twice_before_dialling(self):
        self.keeper.background = True
        self.network.probe.side_effect = [False, True]
        self.assertFalse(self.step())
        self.now += 5
        self.assertTrue(self.step())
        self.credential.assert_not_called()

    def test_background_notifies_once_per_sustained_outage_with_cooldown(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        self.credential.return_value = None
        self.assertFalse(self.step())
        self.now += work_link.ALERT_DELAY - 1
        self.assertFalse(self.step())
        self.keeper.notify.assert_not_called()
        self.now += 1
        self.assertFalse(self.step())
        self.now += 120
        self.assertFalse(self.step())
        self.keeper.notify.assert_called_once()

        def outage():
            self.now += 120  # Past the credential backoff.
            self.network.probe.return_value = True
            self.assertTrue(self.step())
            self.network.probe.return_value = False
            self.assertFalse(self.step())
            self.now += work_link.ALERT_DELAY
            self.assertFalse(self.step())

        outage()  # Within the cooldown of the first alert.
        self.keeper.notify.assert_called_once()
        self.now += work_link.ALERT_COOLDOWN
        outage()
        self.assertEqual(self.keeper.notify.call_count, 2)

    def test_missing_uplink_does_not_notify(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        self.network.snapshot.return_value = work_link.Snapshot()
        self.assertFalse(self.step())
        self.now += work_link.ALERT_DELAY * 10
        self.assertFalse(self.step())
        self.keeper.notify.assert_not_called()

    def test_stale_vpn_is_restarted_once_per_outage(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/1", wifi="Guest", vpn="activated")
        self.assertFalse(self.step())
        self.now += work_link.STALE_VPN_DELAY - 1
        self.assertFalse(self.step())
        self.network.vpn_down.assert_not_called()
        self.now += 1
        self.assertFalse(self.step())
        self.network.vpn_down.assert_called_once_with("VPN")
        self.now += work_link.STALE_VPN_DELAY
        self.assertFalse(self.step())
        self.network.vpn_down.assert_called_once()
        self.network.vpn_up.assert_not_called()

    def test_new_vpn_gets_full_grace_period_after_long_outage(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        self.network.snapshot.return_value = work_link.Snapshot()
        self.assertFalse(self.step())
        self.now += 600
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/1", wifi="Guest", vpn="activated")
        self.assertFalse(self.step())
        self.network.vpn_down.assert_not_called()
        self.now += work_link.STALE_VPN_DELAY
        self.assertFalse(self.step())
        self.network.vpn_down.assert_called_once()

    def test_preferred_wifi_in_range_is_switched_to_at_most_every_interval(self):
        self.keeper.background = True
        self.network.probe.return_value = True
        self.network.better_wifi.return_value = ("work", "wlan0", "Work")
        self.network.wifi_up.return_value = False
        self.assertTrue(self.step())
        self.network.wifi_up.assert_called_once_with("work", "wlan0")
        self.now += work_link.UPGRADE_INTERVAL - 1
        self.assertTrue(self.step())
        self.network.better_wifi.assert_called_once()
        self.now += 1
        self.network.better_wifi.return_value = None
        self.assertTrue(self.step())  # The failed profile backs off.
        self.assertEqual(self.network.better_wifi.call_args.args[1], {"work"})
        self.network.wifi_up.assert_called_once()
        self.network.better_wifi.return_value = ("work", "wlan0", "Work")
        self.now += work_link.UPGRADE_BACKOFF
        self.assertTrue(self.step())
        self.assertEqual(self.network.better_wifi.call_args.args[1], set())
        self.assertEqual(self.network.wifi_up.call_count, 2)

    def test_failed_switch_skips_that_profile_during_recovery(self):
        self.keeper.background = True
        self.network.probe.return_value = True
        self.network.better_wifi.return_value = ("work", "wlan0", "Work")
        choices = (("work", "wlan0", "Work"), ("home", "wlan0", "Home"))
        disconnected = work_link.Snapshot(choices=choices)
        connected = work_link.Snapshot(uplink="/uplink/2", wifi="Home")
        self.network.snapshot.side_effect = [connected, disconnected] + [disconnected] * 3 + [connected]
        self.network.wifi_up.side_effect = [False, True]
        self.assertFalse(self.step())  # Switch fails and leaves Wi-Fi disconnected.
        self.assertTrue(self.step())
        self.assertEqual([call.args for call in self.network.wifi_up.call_args_list],
                         [("work", "wlan0"), ("home", "wlan0")])

    def test_foreground_connect_never_switches_wifi(self):
        self.network.probe.return_value = True
        self.network.better_wifi.return_value = ("work", "wlan0", "Work")
        self.assertTrue(self.step())
        self.network.better_wifi.assert_not_called()
        self.network.wifi_up.assert_not_called()

    def test_uplink_change_keeps_one_time_code_cooldown(self):
        self.assertFalse(self.step())
        self.assertEqual(self.network.vpn_up.call_count, 1)
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/2", wifi="Home")
        self.now += 1
        self.assertFalse(self.step())
        self.assertEqual(self.network.vpn_up.call_count, 1)
        self.now += work_link.OTP_WINDOW
        self.assertFalse(self.step())
        self.assertEqual(self.network.vpn_up.call_count, 2)

    def test_vpn_lockout_notifies_immediately_and_only_once(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        self.assertFalse(self.step())  # Initial HTTPS failure confirmation.
        self.now += 4
        self.assertFalse(self.step())
        self.keeper.notify.assert_not_called()
        self.now += work_link.OTP_WINDOW - 1
        self.assertFalse(self.step())
        self.assertEqual(self.network.vpn_up.call_count, 1)  # Waits for a new one-time code.
        self.now += 1
        self.assertFalse(self.step())
        self.keeper.notify.assert_called_once()
        self.assertIn("rejected the login", self.keeper.notify.call_args.args[0])
        self.assertTrue(self.keeper.notify.call_args.kwargs["urgent"])
        self.now += 120
        self.assertFalse(self.step())
        self.keeper.notify.assert_called_once()

    def test_radio_off_and_captive_portal_do_not_notify(self):
        self.keeper.background = True
        self.keeper.notify = Mock()
        for snapshot in (work_link.Snapshot(offline_by_choice=True),
                         work_link.Snapshot(uplink="/uplink/1", wifi="Guest", portal=True)):
            self.network.snapshot.return_value = snapshot
            self.assertFalse(self.step())
            self.now += work_link.ALERT_DELAY
            self.assertFalse(self.step())
        self.keeper.notify.assert_not_called()

    def test_link_change_during_credential_lookup_does_not_spend_an_attempt(self):
        self.network.vpn_up.side_effect = None
        self.network.vpn_up.return_value = "network changed before dialling"
        self.assertFalse(self.step())
        self.assertEqual(self.budget.used(), 0)

    def test_pressed_radio_switch_or_portal_does_not_dial(self):
        self.network.snapshot.return_value = work_link.Snapshot()
        self.assertFalse(self.step())
        self.network.wifi_up.assert_not_called()
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/1", wifi="Guest", portal=True)
        self.assertFalse(self.step())
        self.credential.assert_not_called()

    def test_disconnected_wifi_tries_available_profiles_in_order(self):
        choices = (("work", "wlan0", "Work"), ("home", "wlan0", "Home"))
        disconnected = work_link.Snapshot(choices=choices)
        connected = work_link.Snapshot(uplink="/uplink/2", wifi="Home")
        self.network.snapshot.side_effect = [disconnected, disconnected, disconnected, connected]
        self.network.wifi_up.side_effect = [False, True]
        self.network.probe.return_value = True
        self.assertTrue(self.step())
        self.assertEqual([call.args for call in self.network.wifi_up.call_args_list],
                         [("work", "wlan0"), ("home", "wlan0")])

    def test_concurrent_gnome_connection_wins_before_fallback(self):
        disconnected = work_link.Snapshot(choices=(("work", "wlan0", "Work"),))
        connected = work_link.Snapshot(uplink="/uplink/2", wifi="Guest")
        self.network.snapshot.side_effect = [disconnected, connected, connected]
        self.network.probe.return_value = True
        self.assertTrue(self.step())
        self.network.wifi_up.assert_not_called()

    def test_vpn_already_starting_is_not_duplicated(self):
        self.network.snapshot.return_value = work_link.Snapshot(uplink="/uplink/1", wifi="Guest", vpn="activating")
        self.assertFalse(self.step())
        self.network.vpn_up.assert_not_called()

    def test_concurrent_cli_and_service_cannot_reserve_twice(self):
        with self.budget.lock(), self.assertRaises(BlockingIOError):
            with work_link.AuthBudget(self.state).lock():
                pass

    def test_corrupt_attempt_state_fails_closed(self):
        self.budget.state.write_text("unknown")
        with self.assertRaises(ValueError):
            self.step()
        self.network.vpn_up.assert_not_called()


class NetworkAdapterTest(unittest.TestCase):
    def test_status_follow_streams_unit_journal(self):
        for flag in ("-f", "--follow"):
            with (self.subTest(flag=flag),
                  patch.object(sys, "argv", ["work-link", "status", flag]),
                  patch.object(work_link.subprocess, "run") as run):
                run.return_value.returncode = 0
                self.assertEqual(work_link.main(), 0)
                command = run.call_args.args[0]
                self.assertEqual(command[:4], ["journalctl", "--user", "--unit", "work-link.service"])
                self.assertIn("--follow", command)

    def test_quiet_status_keeps_exit_codes_and_prints_nothing(self):
        with (patch.object(sys, "argv", ["work-link", "status", "--quiet"]),
              patch.object(work_link.Config, "load"),
              patch.object(work_link, "Network") as network,
              patch.object(work_link.AuthBudget, "used", return_value=0),
              redirect_stdout(StringIO()) as stdout,
              redirect_stderr(StringIO()) as stderr):
            network.return_value.snapshot.return_value = work_link.Snapshot(uplink="/uplink/1")
            network.return_value.probe.side_effect = [True, False]
            self.assertEqual(work_link.main(), 0)
            self.assertEqual(work_link.main(), 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")

    def test_one_use_agent_only_answers_one_request_for_the_target(self):
        agent = work_link.OneUseAgent("target", "fake credential")
        connection = Mock()
        request = work_link.NM.SecretAgentGetSecretsFlags.ALLOW_INTERACTION
        callback = Mock()
        connection.get_uuid.return_value = "other"
        agent.do_get_secrets(connection, "/", "vpn", [], request, callback, None)
        self.assertIsNone(callback.call_args.args[2])
        connection.get_uuid.return_value = "target"
        agent.do_get_secrets(connection, "/", "vpn", [], request, callback, None)
        secret = callback.call_args.args[2].unpack()
        self.assertEqual(secret["vpn"]["secrets"]["password"], "fake credential")
        agent.do_get_secrets(connection, "/", "vpn", [], request, callback, None)
        self.assertIsNone(callback.call_args.args[2])
        self.assertIsNotNone(callback.call_args.args[3])

    def activate_with_plugin_signals(self, senders):
        NM = work_link.NM
        bus = Mock()
        client = Mock()
        active = Mock()

        def activate(profile, specific, uplink, cancellable, callback):
            callback(client, None)
            handler = bus.signal_subscribe.call_args.args[6]
            for sender in senders:
                handler(bus, sender, "/", work_link.VPN_PLUGIN, "StateChanged", work_link.GLib.Variant("(u)", (3,)))
            handler(bus, senders[0], "/", work_link.VPN_PLUGIN, "Failure",
                    work_link.GLib.Variant("(u)", (int(NM.VpnPluginFailure.LOGIN_FAILED),)))
            changed = active.connect.call_args.args[1]
            changed(active, int(NM.VpnConnectionState.FAILED), int(NM.VpnConnectionStateReason.UNKNOWN))

        client.activate_connection_async.side_effect = activate
        client.activate_connection_finish.return_value = active
        active.get_vpn_state.return_value = NM.VpnConnectionState.PREPARE
        with (patch.object(work_link.Gio, "bus_get_sync", return_value=bus),
              patch.object(work_link.GLib, "MainLoop")):
            outcome = work_link.Network.activate_vpn(client, Mock(), "/uplink/1")
        bus.signal_unsubscribe.assert_called_once()
        return outcome

    def test_plugin_login_failure_is_reported_as_rejection(self):
        self.assertEqual(self.activate_with_plugin_signals([":1.2"]), "authentication rejected")

    def test_login_failure_with_concurrent_vpn_plugin_is_ambiguous(self):
        self.assertEqual(self.activate_with_plugin_signals([":1.2", ":1.3"]), "activation failed")

    def test_probe_requires_valid_tls_and_uses_https_only(self):
        with patch.object(work_link.subprocess, "run") as run:
            run.return_value = work_link.subprocess.CompletedProcess([], 60, stdout=b"302")
            self.assertFalse(work_link.Network().probe("https://internal.example.com/"))
            args = run.call_args.args[0]
            self.assertNotIn("--insecure", args)
            self.assertIn("=https", args)
            run.return_value = work_link.subprocess.CompletedProcess([], 0, stdout=b"302")
            self.assertTrue(work_link.Network().probe("https://internal.example.com/"))


if __name__ == "__main__":
    unittest.main()
