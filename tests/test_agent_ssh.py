import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / "agent-ssh"

# Stands in for ssh. The connection is "open" while the file up exists; the file
# fail names why opening one does not work: network, or auth (a login that only
# a person can give, so it works without BatchMode).
STUB = r"""#!/bin/bash
echo "${*}" >> "${STUB_DIR}/calls"
batch=no
for word in "${@}"; do [ "${word}" = "BatchMode=yes" ] && batch=yes; done
case " ${*} " in
    *" -O check "*) [ -e "${STUB_DIR}/up" ] || { echo "Control socket connect: No such file" 1>&2; exit 255; } ;;
    *" -O exit "*) rm -f "${STUB_DIR}/up" ;;
    *" -f -N "*)
        reason="$(cat "${STUB_DIR}/fail" 2>/dev/null)"
        if [ "${reason}" = network ]; then
            echo "ssh: connect to host example port 22: Network is unreachable" 1>&2; exit 255
        elif [ "${reason}" = auth ] && [ "${batch}" = yes ]; then
            echo "user@example: Permission denied (publickey,password)." 1>&2; exit 255
        fi
        touch "${STUB_DIR}/up" ;;
    *)
        # STUB_RUN: this machine is the host, the last word is the remote command
        [ -n "${STUB_RUN}" ] || { echo "ran: ${*}"; exit 0; }
        sh -c "${@: -1}"
        status="${?}"
        # STUB_LOSE: the connection goes away while that command runs
        [ ! -e "${STUB_DIR}/lose" ] || { rm -f "${STUB_DIR}/lose"; exit 255; }
        exit "${status}" ;;
esac
"""


class Base(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.stub = self.dir / "ssh"
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        self.sockets = self.dir / "sockets"
        self.sockets.mkdir()

    def run_tool(self, *words, stdin=subprocess.DEVNULL, **more):
        env = dict(os.environ, AGENT_SSH_SSH=str(self.stub), AGENT_SSH_DIR=str(self.sockets), STUB_DIR=str(self.dir),
                   **more)
        return subprocess.run([str(TOOL), *words], env=env, stdin=stdin, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True, check=False)

    def watcher(self, *words):
        """A watcher whose first look found the connection open."""
        env = dict(os.environ, AGENT_SSH_SSH=str(self.stub), AGENT_SSH_DIR=str(self.sockets), STUB_DIR=str(self.dir))
        process = subprocess.Popen([str(TOOL), "watch", "--interval", "1", "--no-notify", *words], env=env,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   universal_newlines=True)
        self.addCleanup(process.kill)
        first = process.stderr.readline()
        self.assertIn(" open: ", first)
        return process

    def calls(self):
        path = self.dir / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def up(self):
        return (self.dir / "up").exists()


class AgentSshTest(Base):

    def test_open_then_exec_then_close(self):
        done = self.run_tool("open", "user@example", "--", "-p", "2222")
        self.assertEqual(done.returncode, 0, done.stderr)
        socket_path = str(self.sockets / "cm-user@example")
        self.assertEqual(done.stdout.strip(), socket_path)
        opened = [call for call in self.calls() if " -f -N " in f" {call} "]
        self.assertEqual(len(opened), 1)
        self.assertIn(f"ControlPath={socket_path}", opened[0])
        self.assertIn("ControlPersist=8h", opened[0])
        self.assertIn("BatchMode=no -p 2222 user@example", opened[0])

        self.assertEqual(self.run_tool("path", "user@example").stdout.strip(), socket_path)
        done = self.run_tool("status", "user@example")
        self.assertEqual((done.returncode, done.stdout.split()[0]), (0, "open"))

        done = self.run_tool("exec", "user@example", "ls", "-la", "/tmp")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         f"ran: -o ControlMaster=no -o ControlPath={socket_path} -o BatchMode=yes "
                         "-o ProxyCommand=false user@example ls -la /tmp")

        self.assertEqual(self.run_tool("close", "user@example").returncode, 0)
        self.assertFalse(self.up())
        done = self.run_tool("status", "user@example")
        self.assertEqual((done.returncode, done.stdout.split()[0]), (1, "closed"))

    def test_open_twice_opens_once(self):
        self.run_tool("open", "example")
        done = self.run_tool("open", "example")
        self.assertEqual(done.returncode, 0)
        self.assertIn("Already open", done.stderr)
        self.assertEqual(done.stdout.strip(), str(self.sockets / "cm-example"), "scripts take the socket from stdout")
        self.assertEqual(len([call for call in self.calls() if " -f -N " in f" {call} "]), 1)

    def test_exec_never_opens_a_connection(self):
        done = self.run_tool("exec", "example", "true")
        self.assertEqual(done.returncode, 255)
        self.assertIn("No open connection to example", done.stderr)
        self.assertEqual([call for call in self.calls() if "-O check" not in call], [])

    def test_name_and_persist(self):
        done = self.run_tool("open", "--name", "jump", "--persist", "30m", "user@host.example.com")
        self.assertEqual(done.stdout.strip(), str(self.sockets / "cm-jump"))
        self.assertIn("ControlPersist=30m", "\n".join(self.calls()))
        for words in (["open", "--name", "../x", "example"], ["open", "--persist", "soon", "example"],
                      ["open", "-oProxyCommand=evil"], ["watch", "--interval", "0", "example"], ["fly", "example"]):
            self.assertEqual(self.run_tool(*words).returncode, 1, words)

    def test_watch_opens_the_connection_again(self):
        self.run_tool("open", "example")
        (self.dir / "up").unlink()
        leftover = socket.socket(socket.AF_UNIX)
        self.addCleanup(leftover.close)
        leftover.bind(str(self.sockets / "cm-example"))
        (self.dir / "calls").unlink()

        done = self.run_tool("watch", "--interval", "1", "--count", "2", "--no-notify", "example")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(self.up())
        self.assertFalse((self.sockets / "cm-example").exists(), "the socket of the dead connection is removed")
        self.assertIn("example open", done.stderr)

    def test_watch_does_not_ask_when_the_host_is_not_reached(self):
        self.run_tool("open", "example")
        (self.dir / "calls").unlink()
        (self.dir / "fail").write_text("network")
        watcher = self.watcher("--count", "3", "example")
        (self.dir / "up").unlink()
        _, stderr = watcher.communicate(timeout=30)
        self.assertEqual(watcher.returncode, 1)
        self.assertIn("is gone, opening it again", stderr)
        self.assertIn("not reached: ssh: connect to host example port 22: Network is unreachable", stderr)
        opened = [call for call in self.calls() if " -f -N " in f" {call} "]
        self.assertTrue(opened)
        self.assertTrue(all("BatchMode=yes" in call for call in opened), "nothing is asked for")

    def test_watch_without_a_terminal_does_not_ask_for_a_login(self):
        self.run_tool("open", "example")
        (self.dir / "up").unlink()
        (self.dir / "calls").unlink()
        (self.dir / "fail").write_text("auth")
        # state is unknown at the start: the first open asks, as the person is there
        watcher = self.watcher("--count", "3", "example")
        self.assertIn("BatchMode=no", "\n".join(self.calls()))
        (self.dir / "calls").unlink()
        (self.dir / "up").unlink()
        _, stderr = watcher.communicate(timeout=30)
        self.assertEqual(watcher.returncode, 1)
        self.assertIn("asks for a login and this is no terminal", stderr)
        self.assertTrue(all("BatchMode=no" not in call for call in self.calls()))

    def test_status_lists_every_connection(self):
        self.run_tool("open", "example")
        listener = socket.socket(socket.AF_UNIX)
        self.addCleanup(listener.close)
        listener.bind(str(self.sockets / "cm-example"))
        done = self.run_tool("status")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(done.stdout.split()[:2], ["open", "example"])

    def test_completion(self):
        # how bash_completion/cli-helpers finds out that the tool completes itself
        self.assertRegex(TOOL.read_text(), r'(?m)^[ \t]*"?--bash-completion"?\)')
        self.assertIn("watch", self.run_tool("--bash-completion", "agent-ssh").stdout.split())
        self.run_tool("open", "example")
        listener = socket.socket(socket.AF_UNIX)
        self.addCleanup(listener.close)
        listener.bind(str(self.sockets / "cm-example"))
        self.assertIn("example", self.run_tool("--bash-completion", "exec", "exec").stdout.split())


@unittest.skipUnless(shutil.which("tmux"), "needs tmux")
class TmuxTest(Base):
    """exec --tmux with this machine as the host and a tmux server of its own."""

    def setUp(self):
        super().setUp()
        # short: the socket of the tmux server lies below it
        self.tmux_dir = tempfile.mkdtemp(prefix="assh", dir="/tmp")
        self.addCleanup(shutil.rmtree, self.tmux_dir, ignore_errors=True)
        self.home = self.dir / "home"
        self.home.mkdir()
        self.host = {"STUB_RUN": "1", "TMUX_TMPDIR": self.tmux_dir, "HOME": str(self.home), "TMUX": ""}
        self.addCleanup(self.tmux, "kill-server")
        self.run_tool("open", "example")

    def tmux(self, *words):
        env = dict(os.environ, TMUX_TMPDIR=self.tmux_dir, TMUX="")
        return subprocess.run(["tmux", *words], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              universal_newlines=True, check=False).stdout.split()

    def results(self):
        cache = self.home / ".cache" / "agent-ssh"
        return sorted(cache.iterdir()) if cache.exists() else []

    def test_command_runs_in_the_session_and_its_result_comes_back(self):
        done = self.run_tool("exec", "--tmux", "example", "echo out; echo err >&2; exit 3", **self.host)
        self.assertEqual((done.returncode, done.stdout.split()), (3, ["out", "err"]), done.stderr)
        self.assertIn("tmux session agent-ssh, window ", done.stderr)
        self.assertEqual(self.results(), [], "a result that arrived is removed from the host")

        done = self.run_tool("exec", "-t", "example", "printf", "'%s|'", "'a b'", '"it\'s"', **self.host)
        self.assertEqual((done.returncode, done.stdout), (0, "a b|it's|"), done.stderr)
        self.assertEqual(self.tmux("list-sessions", "-F", "#{session_name}"), ["agent-ssh"], "one session, used again")
        self.assertEqual(len(self.tmux("list-windows", "-t", "=agent-ssh", "-F", "#{window_id}")), 1,
                         "the window of a command goes with it")

    def test_calls_at_the_same_moment_share_the_session(self):
        env = dict(os.environ, AGENT_SSH_SSH=str(self.stub), AGENT_SSH_DIR=str(self.sockets),
                   STUB_DIR=str(self.dir), **self.host)
        calls = [subprocess.Popen([str(TOOL), "exec", "--tmux", "example", f"echo {number}"], env=env,
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  universal_newlines=True) for number in range(6)]
        results = [(call.communicate(timeout=60)[0].strip(), call.returncode) for call in calls]
        self.assertEqual(results, [(str(number), 0) for number in range(6)])
        self.assertEqual(self.tmux("list-sessions", "-F", "#{session_name}"), ["agent-ssh"])

    def test_result_stays_on_the_host_when_the_connection_goes_away(self):
        (self.dir / "lose").touch()
        done = self.run_tool("exec", "--tmux", "--session", "work", "example", "echo kept; exit 4", **self.host)
        self.assertEqual(done.returncode, 255)
        self.assertEqual(self.tmux("list-sessions", "-F", "#{session_name}"), ["work"])
        (result,) = self.results()
        self.assertIn(str(result), done.stderr)
        self.assertEqual(((result / "output").read_text(), (result / "status").read_text()), ("kept\n", "4\n"))

    def test_command_whose_window_is_closed_is_an_error(self):
        watcher = subprocess.Popen(
            [str(TOOL), "exec", "--tmux", "example", "sleep 60"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, universal_newlines=True,
            env=dict(os.environ, AGENT_SSH_SSH=str(self.stub), AGENT_SSH_DIR=str(self.sockets),
                     STUB_DIR=str(self.dir), **self.host))
        self.addCleanup(watcher.kill)
        window = watcher.stderr.readline().split("window ")[1].split(",")[0]
        self.tmux("kill-window", "-t", window)
        _, stderr = watcher.communicate(timeout=30)
        self.assertEqual(watcher.returncode, 255)
        self.assertIn("the window of the command is gone", stderr)

    def test_open_makes_the_session(self):
        self.run_tool("close", "example")
        done = self.run_tool("open", "--tmux", "--session", "prepared", "example", **self.host)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.tmux("list-sessions", "-F", "#{session_name}"), ["prepared"])

    def test_attaching_needs_a_terminal_and_a_name_tmux_can_take(self):
        done = self.run_tool("exec", "--tmux", "example", **self.host)
        self.assertEqual(done.returncode, 1)
        self.assertIn("needs a terminal", done.stderr)
        self.assertEqual(self.run_tool("exec", "--tmux", "--session", "a.b", "example", "true").returncode, 1)


if __name__ == "__main__":
    unittest.main()
