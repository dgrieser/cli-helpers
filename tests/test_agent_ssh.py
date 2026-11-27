import os
from pathlib import Path
import pty
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest

TOOL = Path(__file__).resolve().parents[1] / "agent-ssh"

# Stands in for ssh. A connection is "open" while the file SOCKET.up exists; the
# file fail makes opening one fail - with "auth" in it only where nothing may
# be asked for (BatchMode=yes): a host that wants a login from a person.
STUB = r"""#!/bin/bash
echo "${*}" >> "${STUB_DIR}/calls"
case " ${*} " in *" -f -N "*) pwd >> "${STUB_DIR}/opened-in" ;; esac
socket=""
for word in "${@}"; do
    case "${word}" in ControlPath=*) socket="${word#ControlPath=}" ;; esac
done
case " ${*} " in
    *" -O check "*) [ -e "${socket}.up" ] || { echo "Control socket connect: No such file" 1>&2; exit 255; } ;;
    *" -O exit "*) rm -f "${socket}.up" ;;
    *" -f -N "*)
        # the login takes its time
        [ ! -e "${STUB_DIR}/slow" ] || sleep 2
        if [ -e "${STUB_DIR}/fail" ]; then
            case "$(cat "${STUB_DIR}/fail"):${*}" in
                auth:*BatchMode=no*) ;;
                auth:*) echo "user@example: Permission denied (publickey,password)." 1>&2; exit 255 ;;
                *) echo "ssh: connect to host example port 22: Network is unreachable" 1>&2; exit 255 ;;
            esac
        fi
        # the ask is taken back while the user logs in
        [ ! -e "${STUB_DIR}/withdraw" ] || rm -f "${socket%.sock}.ask"
        touch "${socket}.up" ;;
    *)
        # STUB_RUN: this machine is the host, the last word is the remote command
        [ -n "${STUB_RUN}" ] || { echo "ran: ${*}"; exit 0; }
        sh -c "${@: -1}"
        status="${?}"
        # the connection goes away while that command runs
        [ ! -e "${STUB_DIR}/lose" ] || { rm -f "${STUB_DIR}/lose"; exit 255; }
        exit "${status}" ;;
esac
"""


class Base(unittest.TestCase):
    def setUp(self):
        # short: the control sockets lie in it
        self.dir = Path(tempfile.mkdtemp(prefix="assh", dir="/tmp"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.stub = self.dir / "ssh"
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        self.state = self.dir / "s"
        self.env = dict(os.environ, AGENT_SSH_SSH=str(self.stub), AGENT_SSH_DIR=str(self.state),
                        STUB_DIR=str(self.dir))

    def run_tool(self, *words, typed=None, **more):
        """The tool as an agent runs it: no terminal."""
        return subprocess.run([str(TOOL), *words], env=dict(self.env, **more), input=typed,
                              stdin=subprocess.DEVNULL if typed is None else None,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=False)

    def start(self, *words, **more):
        process = subprocess.Popen([str(TOOL), *words], env=dict(self.env, **more), stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        self.addCleanup(process.stderr.close)
        self.addCleanup(process.stdout.close)
        return process

    def start_grant(self, *words, typed=""):
        """agent-ssh grant as the user runs it: on a terminal, TYPED is what they answer. It never ends by itself."""
        primary, secondary = pty.openpty()
        self.addCleanup(os.close, primary)
        number = len(list(self.dir.glob("grant-*.out")))
        output = [self.dir / f"grant-{number}.out", self.dir / f"grant-{number}.err"]
        with open(output[0], "w") as stdout, open(output[1], "w") as stderr:
            process = subprocess.Popen([str(TOOL), "grant", "--no-notify", "--interval", "1", *words], env=self.env,
                                       stdin=secondary, stdout=stdout, stderr=stderr)
        os.close(secondary)
        os.write(primary, typed.encode())
        process.output = output
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        return process

    def wait_until(self, condition, what):
        deadline = time.time() + 30
        while not condition():
            self.assertLess(time.time(), deadline, what)
            time.sleep(0.05)

    def grant(self, *words, typed=""):
        """A grant that is ended once it has nothing left to do: (exit status, tickets, stderr)."""
        process = self.start_grant(*words, typed=typed)
        self.wait_until(lambda: process.poll() is not None or "waiting for asks" in process.output[1].read_text(),
                        "the grant neither ended nor came to rest")
        ended = process.poll() is None
        if ended:
            process.send_signal(signal.SIGINT)
        code = process.wait(timeout=30)
        return (0 if ended and code == 130 else code), process.output[0].read_text().split(), \
            process.output[1].read_text()

    def calls(self):
        path = self.dir / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def opened(self):
        return [call for call in self.calls() if " -f -N " in f" {call} "]

    def asks(self):
        return sorted(path.stem for path in self.state.glob("*.ask"))

    def wait_for_ask(self):
        deadline = time.time() + 20
        while not self.asks():
            self.assertLess(time.time(), deadline, "no ask appeared")
            time.sleep(0.05)
        return self.asks()[0]


class AgentSshTest(Base):
    def test_agent_asks_user_grants_agent_opens(self):
        asking = self.start("ask", "--no-notify", "user@example", "--", "-p", "2222")
        ask = self.wait_for_ask()
        self.assertEqual(self.opened(), [], "asking opens nothing")

        code, tickets, stderr = self.grant(typed="y\n")
        self.assertEqual((code, tickets), (0, [ask]), stderr)
        self.assertIn("user@example", stderr)
        self.assertIn("[-p 2222]", stderr, "the user sees the ssh options that were asked for")
        (opened,) = self.opened()
        self.assertIn(f"ControlPath={self.state}/{ask}.sock", opened)
        self.assertIn("ControlPersist=8h", opened)
        self.assertTrue(opened.endswith("-o BatchMode=no -p 2222 user@example"),
                        f"the host may ask for the login, whatever the ssh config says: {opened}")

        stdout, stderr = asking.communicate(timeout=30)
        self.assertEqual((asking.returncode, stdout.strip()), (0, ask), stderr)
        self.assertIn("waiting for 'agent-ssh grant'", stderr)

        done = self.run_tool("open", "--direct", ask, "ls", "-la", "/tmp")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         f"ran: -o ControlMaster=no -o ControlPath={self.state}/{ask}.sock -o BatchMode=yes "
                         "-o ProxyCommand=false user@example ls -la /tmp")
        self.assertEqual(self.run_tool("path", ask).stdout.strip(), f"{self.state}/{ask}.sock")

    def test_open_connection_gives_its_ticket_at_once(self):
        code, (ticket,), _ = self.grant("example")
        self.assertEqual(code, 0)
        done = self.run_tool("ask", "example")
        self.assertEqual((done.returncode, done.stdout.strip()), (0, ticket), done.stderr)
        self.assertEqual(self.asks(), [])
        # other ssh options are another connection
        done = self.run_tool("ask", "--no-notify", "--wait", "1", "example", "--", "-p", "2222")
        self.assertEqual(done.returncode, 1)
        self.run_tool("close", self.asks()[0])

        code, tickets, stderr = self.grant("example")
        self.assertEqual((code, tickets), (0, [ticket]))
        self.assertIn("Already open", stderr)
        self.assertEqual(len(self.opened()), 1)

    def test_two_asks_for_one_host_are_one_ask(self):
        first = self.start("ask", "--no-notify", "example")
        ask = self.wait_for_ask()
        second = self.start("ask", "--no-notify", "example")
        time.sleep(0.5)
        self.assertEqual(self.asks(), [ask])
        self.assertEqual(self.grant(typed="\n")[:2], (0, [ask]))
        for asking in (first, second):
            stdout, _ = asking.communicate(timeout=30)
            self.assertEqual((asking.returncode, stdout.strip()), (0, ask))
        self.assertEqual(len(self.opened()), 1)

    def test_ask_that_is_not_granted_in_time_stays(self):
        done = self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        self.assertEqual((done.returncode, done.stdout), (1, ""))
        self.assertIn("No connection within 1 seconds", done.stderr)
        (ask,) = self.asks()
        status = self.run_tool("status").stdout
        self.assertRegex(status, rf"^ask   {ask}  example  \d+s  from ")

        # granted later, with nobody waiting: the next ask finds the connection
        self.assertEqual(self.grant("--yes")[:2], (0, [ask]))
        done = self.run_tool("ask", "example")
        self.assertEqual((done.returncode, done.stdout.strip()), (0, ask))
        self.assertRegex(self.run_tool("status").stdout, rf"^open  {ask}  example  ")

    def test_not_now_keeps_the_ask_and_deny_ends_it(self):
        asking = self.start("ask", "--no-notify", "example")
        ask = self.wait_for_ask()
        self.assertEqual(self.grant(typed="n\n")[:2], (0, []))
        self.assertEqual(self.asks(), [ask])
        self.assertIsNone(asking.poll(), "the agent keeps waiting")

        code, tickets, stderr = self.grant(typed="d\n")
        self.assertEqual((code, tickets), (0, []))
        self.assertIn("Denied", stderr)
        _, stderr = asking.communicate(timeout=30)
        self.assertEqual(asking.returncode, 1)
        self.assertIn("was denied", stderr)
        self.assertEqual(self.opened(), [])

    def test_login_that_fails_keeps_the_ask_of_the_agent(self):
        self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        (ask,) = self.asks()
        (self.dir / "fail").touch()
        code, tickets, stderr = self.grant("example")
        self.assertEqual((code, tickets), (1, []))
        self.assertIn("No connection to example, the ask stays", stderr)
        self.assertEqual(self.asks(), [ask])
        # an ask that was only made by the failed grant leaves nothing behind
        self.assertEqual(self.grant("other.example")[0], 1)
        self.assertEqual(self.asks(), [ask])

    def test_ask_taken_back_during_the_login_leaves_no_connection(self):
        self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        (ask,) = self.asks()
        (self.dir / "withdraw").touch()
        code, tickets, stderr = self.grant("--yes")
        self.assertEqual(tickets, [], stderr)
        self.assertFalse((self.state / f"{ask}.sock.up").exists(), "the connection is closed again")
        self.assertEqual(self.run_tool("status").stdout, "")

    def test_ssh_options_mean_the_directory_they_were_asked_in(self):
        here, there = self.dir / "here", self.dir / "there"
        for directory in (here, there):
            directory.mkdir()
            subprocess.run([str(TOOL), "ask", "--no-notify", "--wait", "1", "example", "--", "-i", "./key"],
                           env=self.env, cwd=directory, stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=False)
        self.assertEqual(len(self.asks()), 2, "the same relative path elsewhere is another file")
        code, tickets, stderr = self.grant("--yes")
        self.assertEqual((code, len(tickets)), (0, 2), stderr)
        self.assertEqual(sorted((self.dir / "opened-in").read_text().split()), [str(here), str(there)])

    def test_two_grants_for_one_ask_open_one_connection(self):
        self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        (ask,) = self.asks()
        (self.dir / "slow").touch()
        results = []
        grants = [threading.Thread(target=lambda: results.append(self.grant("--yes"))) for _ in range(2)]
        for grant in grants:
            grant.start()
            time.sleep(0.5)
        for grant in grants:
            grant.join()
        self.assertEqual(sorted(tickets for _, tickets, _ in results), [[], [ask]])
        self.assertIn("Another agent-ssh grant is opening this connection", "".join(r[2] for r in results))
        self.assertEqual(len(self.opened()), 1)
        done = self.run_tool("open", ask, "true")
        self.assertEqual(done.returncode, 0, "the connection of the first grant is still there")

    def test_failed_grant_keeps_the_ask_an_agent_joined_meanwhile(self):
        (self.dir / "slow").touch()
        (self.dir / "fail").touch()
        results = []
        grant = threading.Thread(target=lambda: results.append(self.grant("example")))
        grant.start()
        ask = self.wait_for_ask()
        joined = self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        grant.join()
        self.assertEqual(results[0][0], 1)
        self.assertIn("No connection within", joined.stderr, "the agent was not told that it was denied")
        self.assertEqual(self.asks(), [ask])

    def test_two_grants_for_one_host_at_once_open_one_connection(self):
        (self.dir / "slow").touch()
        results = []
        grants = [threading.Thread(target=lambda: results.append(self.grant("example"))) for _ in range(2)]
        for grant in grants:
            grant.start()
            time.sleep(0.5)
        for grant in grants:
            grant.join()
        (ticket,) = [tickets[0] for _, tickets, _ in results if tickets]
        self.assertEqual(sorted(code for code, _, _ in results), [0, 1])
        self.assertEqual(self.run_tool("open", ticket, "true").returncode, 0)
        self.assertEqual(len(self.opened()), 1)

    def test_grant_stays_and_opens_a_connection_that_is_gone_again(self):
        grant = self.start_grant("example")
        self.wait_until(lambda: grant.output[0].read_text().strip(), "no ticket")
        ticket = grant.output[0].read_text().strip()
        up = self.state / f"{ticket}.sock.up"
        for _ in range(2):
            up.unlink()
            self.wait_until(up.exists, "the connection was not opened again")
        self.assertIsNone(grant.poll(), "it watches until it is ended")
        self.assertIn(f"example ({ticket}) is gone, opening it again", grant.output[1].read_text())
        again = [call for call in self.opened()[1:]]
        self.assertEqual(len(again), 2)
        self.assertTrue(all("BatchMode=yes" in call and f"{ticket}.sock" in call for call in again),
                        "the same ticket, and nothing is asked for")
        self.assertEqual(self.run_tool("open", ticket, "true").returncode, 0)

    def test_ticket_of_a_connection_that_is_gone_stays_while_a_grant_runs(self):
        grant = self.start_grant("example")
        self.wait_until(lambda: grant.output[0].read_text().strip(), "no ticket")
        ticket = grant.output[0].read_text().strip()
        (self.dir / "fail").write_text("network")
        (self.state / f"{ticket}.sock.up").unlink()

        done = self.run_tool("open", "--wait", "1", ticket, "true")
        self.assertEqual(done.returncode, 255)
        self.assertIn("is not back within 1 seconds", done.stderr)
        opening = self.start("open", "--direct", ticket, "true")
        self.assertRegex(self.run_tool("status").stdout, rf"^gone  {ticket}  example  ")
        self.wait_until(lambda: "not reached: ssh: connect to host example" in grant.output[1].read_text(),
                        "no try to open it again")
        self.assertNotIn("BatchMode=no", "\n".join(self.opened()[1:]), "a host that is not reached is not asked for")

        asking = self.start("ask", "example")
        time.sleep(1.5)
        self.assertIsNone(asking.poll(), "the agent waits for the connection")
        self.assertEqual(self.asks(), [], "and that is no new ask")
        (self.dir / "fail").unlink()
        stdout, stderr = asking.communicate(timeout=60)
        self.assertEqual((asking.returncode, stdout.strip()), (0, ticket), stderr)
        stdout, stderr = opening.communicate(timeout=60)
        self.assertEqual(opening.returncode, 0, "open waited for the connection too")
        self.assertIn("ran: ", stdout)

        # closed: nothing left to open again
        self.assertEqual(self.run_tool("close", ticket).returncode, 0)
        time.sleep(3)
        self.assertEqual(self.run_tool("status").stdout, "")

    def test_host_that_wants_a_login_gets_the_terminal_of_the_grant(self):
        grant = self.start_grant("example")
        self.wait_until(lambda: grant.output[0].read_text().strip(), "no ticket")
        ticket = grant.output[0].read_text().strip()
        (self.dir / "fail").write_text("auth")
        up = self.state / f"{ticket}.sock.up"
        up.unlink()
        self.wait_until(up.exists, "the connection was not opened again")
        self.assertIn(f"example ({ticket}) asks for a login", grant.output[1].read_text())
        again = self.opened()[1:]
        self.assertEqual(["BatchMode=yes" in call for call in again], [True, False], "first without a question")

    def test_without_a_grant_running_a_gone_connection_is_forgotten(self):
        _, (ticket,), _ = self.grant("example")
        (self.state / f"{ticket}.sock.up").unlink()
        self.assertEqual(self.run_tool("status").stdout, "")
        done = self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        self.assertEqual(done.returncode, 1)
        self.assertNotEqual(self.asks(), [ticket])

    def test_grant_is_for_a_person_at_a_terminal(self):
        self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        for words in (["grant"], ["grant", "--yes"], ["grant", "example"]):
            done = self.run_tool(*words)
            self.assertEqual(done.returncode, 1, words)
            self.assertIn("needs a terminal", done.stderr)
        self.assertEqual(self.opened(), [])

    def test_grant_without_asks_says_so(self):
        code, tickets, stderr = self.grant()
        self.assertEqual((code, tickets), (0, []))
        self.assertIn("watching 0 connection(s), waiting for asks", stderr)

    def test_open_never_opens_a_connection(self):
        done = self.run_tool("open", "abc123", "true")
        self.assertEqual(done.returncode, 255)
        self.assertIn("No ticket abc123", done.stderr)

        _, (ticket,), _ = self.grant("example", "--", "-p", "2222")
        (self.state / f"{ticket}.sock.up").unlink()
        done = self.run_tool("open", ticket, "true")
        self.assertEqual(done.returncode, 255)
        self.assertIn(f"The connection of ticket {ticket} is gone: run 'agent-ssh ask example -- -p 2222' in ",
                      done.stderr)
        self.assertEqual(len(self.opened()), 1)
        self.assertEqual(self.run_tool("status").stdout, "", "the ticket of a connection that is gone is gone too")

    def test_close(self):
        _, (ticket,), _ = self.grant("--persist", "30m", "example")
        self.assertIn("ControlPersist=30m", self.opened()[0])
        self.assertEqual(self.run_tool("close", ticket).returncode, 0)
        self.assertFalse((self.state / f"{ticket}.sock.up").exists())
        self.assertEqual(self.run_tool("open", ticket, "true").returncode, 255)

        self.run_tool("ask", "--no-notify", "--wait", "1", "example")
        (ask,) = self.asks()
        self.assertEqual(self.run_tool("close", ask).returncode, 0)
        self.assertEqual(self.asks(), [])

    def test_what_is_not_a_ticket_or_a_destination_is_refused(self):
        for words in (["open", "../x", "true"], ["open", "ABC123"], ["ask", "-oProxyCommand=evil"],
                      ["ask", "a b"], ["ask", "example", "--", "-o\nx"], ["ask"], ["open"], ["fly", "example"],
                      ["ask", "--wait", "soon", "example"], ["open", "--session", "a.b", "abc123", "true"]):
            self.assertEqual(self.run_tool(*words).returncode, 1, words)
        self.assertEqual(self.calls(), [])

    def test_completion(self):
        # how bash_completion/cli-helpers finds out that the tool completes itself
        self.assertRegex(TOOL.read_text(), r'(?m)^[ \t]*"?--bash-completion"?\)')
        self.assertIn("grant", self.run_tool("--bash-completion", "agent-ssh").stdout.split())
        _, (ticket,), _ = self.grant("example")
        self.assertIn(ticket, self.run_tool("--bash-completion", "open", "open").stdout.split())


def path_without(directory, *names):
    """A PATH of everything in /usr/bin but NAMES: the host has no such tool."""
    directory.mkdir()
    for tool in Path("/usr/bin").iterdir():
        if tool.name not in names:
            (directory / tool.name).symlink_to(tool)
    return str(directory)


class SessionTest(Base):
    """open with this machine as the host."""

    def setUp(self):
        super().setUp()
        self.home = self.dir / "home"
        self.home.mkdir()
        self.host = {"STUB_RUN": "1", "HOME": str(self.home)}
        _, (self.ticket,), _ = self.grant("example")

    def results(self):
        cache = self.home / ".cache" / "agent-ssh"
        return sorted(path for path in cache.iterdir() if path.is_dir()) if cache.exists() else []

    def test_direct_is_what_ssh_does(self):
        done = self.run_tool("open", "--direct", self.ticket, "cat; echo err >&2; exit 3", typed="in\n", **self.host)
        self.assertEqual((done.returncode, done.stdout, done.stderr), (3, "in\n", "err\n"))

    def test_host_without_tmux_and_screen_runs_the_command_directly(self):
        path = path_without(self.dir / "bin", "tmux", "screen")
        done = self.run_tool("open", self.ticket, "echo out; exit 3", PATH=path, **self.host)
        self.assertEqual((done.returncode, done.stdout), (3, "out\n"), done.stderr)
        self.assertIn("neither tmux nor screen", done.stderr)
        self.assertEqual(self.results(), [])

    def test_attaching_needs_a_terminal(self):
        done = self.run_tool("open", self.ticket, **self.host)
        self.assertEqual(done.returncode, 1)
        self.assertIn("needs a terminal", done.stderr)


@unittest.skipUnless(shutil.which("tmux"), "needs tmux")
class TmuxTest(SessionTest):
    """open with a tmux server of its own on the host."""

    kind = "tmux"

    def setUp(self):
        super().setUp()
        self.host.update(TMUX_TMPDIR=str(self.dir), TMUX="")
        self.addCleanup(self.multiplexer, "kill-server")

    def multiplexer(self, *words):
        env = dict(os.environ, TMUX_TMPDIR=str(self.dir), TMUX="")
        return subprocess.run(["tmux", *words], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              universal_newlines=True, check=False).stdout

    def sessions(self):
        return self.multiplexer("list-sessions", "-F", "#{session_name}").split()

    def close_window(self):
        for line in self.multiplexer("list-windows", "-t", "=agent-ssh", "-F", "#{window_id} #{window_name}").splitlines():
            if line.endswith(" agent-ssh"):
                self.multiplexer("kill-window", "-t", line.split()[0])

    def test_command_runs_in_the_session_and_its_result_comes_back(self):
        done = self.run_tool("open", self.ticket, "echo out; echo err >&2; exit 3", **self.host)
        self.assertEqual((done.returncode, done.stdout.split()), (3, ["out", "err"]), done.stderr)
        self.assertIn(f"{self.kind} session agent-ssh, result in ", done.stderr)
        self.assertEqual(self.results(), [], "a result that arrived is removed from the host")

        done = self.run_tool("open", self.ticket, "printf", "'%s|'", "'a b'", '"it\'s"', **self.host)
        self.assertEqual((done.returncode, done.stdout), (0, "a b|it's|"), done.stderr)
        self.assertEqual(self.sessions(), ["agent-ssh"], "one session, used again")

    def test_calls_at_the_same_moment_share_the_session(self):
        calls = [self.start("open", self.ticket, f"echo {number}", **self.host) for number in range(6)]
        results = [(call.communicate(timeout=60)[0].strip(), call.returncode) for call in calls]
        self.assertEqual(results, [(str(number), 0) for number in range(6)])
        self.assertEqual(self.sessions(), ["agent-ssh"])

    def test_result_stays_on_the_host_when_the_connection_goes_away(self):
        (self.dir / "lose").touch()
        done = self.run_tool("open", "--session", "work", self.ticket, "echo kept; exit 4", **self.host)
        self.assertEqual(done.returncode, 255)
        self.assertEqual(self.sessions(), ["work"])
        (result,) = self.results()
        self.assertIn(str(result), done.stderr)
        self.assertEqual(((result / "output").read_text(), (result / "status").read_text()), ("kept\n", "4\n"))

    def test_command_whose_window_is_closed_is_an_error(self):
        running = self.start("open", self.ticket, "sleep 60", **self.host)
        self.assertIn(" session agent-ssh, result in ", running.stderr.readline())
        self.wait_until(lambda: self.results() and (self.results()[0] / "pid").exists(), "the command did not start")
        self.close_window()
        _, stderr = running.communicate(timeout=30)
        self.assertEqual(running.returncode, 255)
        self.assertIn("the command is gone and left no exit status", stderr)


@unittest.skipUnless(shutil.which("screen"), "needs screen")
class ScreenTest(TmuxTest):
    """The same on a host that has screen and no tmux."""

    kind = "screen"

    def setUp(self):
        SessionTest.setUp(self)
        sockets = self.dir / "screen"
        sockets.mkdir(mode=0o700)
        self.host.update(SCREENDIR=str(sockets), PATH=path_without(self.dir / "bin", "tmux"), STY="")
        self.addCleanup(self.end_sessions)

    def multiplexer(self, *words):
        env = dict(os.environ, SCREENDIR=self.host["SCREENDIR"], STY="")
        return subprocess.run(["screen", *words], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              universal_newlines=True, check=False).stdout

    def sessions(self):
        return [line.split()[0].split(".", 1)[1] for line in self.multiplexer("-ls").splitlines()
                if line.startswith("\t")]

    def end_sessions(self):
        for name in self.sessions():
            self.multiplexer("-S", name, "-X", "quit")

    def close_window(self):
        self.multiplexer("-S", "agent-ssh", "-p", "agent-ssh", "-X", "kill")


if __name__ == "__main__":
    unittest.main()
