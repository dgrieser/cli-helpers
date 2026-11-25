# The cwd segment of the prompt, but inside a git repository it shows only the
# name of the repository, after a ">_" icon, instead of the path. Outside one it
# is the stock cwd segment, with its settings ("cwd" in config.json).
# The repository name comes from the common git dir, so a linked worktree (e.g.
# ~/workspace.worktree/<repo path>/<branch>) shows the name of its main tree, not
# its branch folder; a submodule, whose git dir lives in the parent's
# .git/modules, shows its own folder name.
# powerline-shell loads this file by its path (config.json), not as a module of
# its package, so imports must be absolute.
import os
import re
import subprocess

from powerline_shell.segments.cwd import add_cwd_segment
from powerline_shell.utils import ThreadedSegment

# a shell prompt for a repository, in plain characters, no font needed
REPO_ICON = ">_"
# turquoise (#00afaf), one of the 256 terminal colors powerline-shell takes
REPO_BG = 37


def escape_bash(text):
    """Text for PS1 that bash shows as it is. Bash decodes the backslash
    escapes of PS1 first, then expands it like a double-quoted string, so $, `
    and \\ need a backslash in the second step, which takes two in the first.
    powerline-shell's own sanitizing escapes $ and ` once, so a name with a
    backslash before them would run a command."""
    return re.sub(r"[\\`$]", lambda m: "\\\\" + ("\\\\" if m.group() == "\\" else m.group()), text)


def git_repo_name(cwd):
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir", "--show-toplevel"],
            cwd=cwd, stderr=subprocess.DEVNULL).decode("utf-8")
    except (subprocess.CalledProcessError, OSError, UnicodeDecodeError):
        # not in a repository, inside .git (no toplevel) or no git at all
        return None
    lines = out.splitlines()
    if len(lines) != 2:
        return None
    common_dir, toplevel = lines
    if os.path.basename(common_dir) == ".git":
        return os.path.basename(os.path.dirname(common_dir))
    return os.path.basename(toplevel) or None


class Segment(ThreadedSegment):
    def run(self):
        self.repo = git_repo_name(self.powerline.cwd)

    def add_to_powerline(self):
        self.join()
        # for the title segment, which goes after this one
        self.powerline.git_repo = self.repo
        if not self.repo:
            add_cwd_segment(self.powerline)
            return
        theme = self.powerline.theme
        repo = self.repo
        if self.powerline.args.shell == "bash":
            repo = escape_bash(repo)
        # the icon where the path outside a repository starts with its home part "~"
        self.powerline.append(" %s " % REPO_ICON, theme.HOME_FG, REPO_BG, sanitize=False)
        self.powerline.append(" %s " % repo, theme.CWD_FG, theme.PATH_BG, sanitize=False)
