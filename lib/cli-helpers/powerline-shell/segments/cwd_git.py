# The cwd segment of the prompt, but inside a git repository it shows only the
# name of the repository instead of the path. Outside one it is the stock cwd
# segment, with its settings ("cwd" in config.json).
# The repository name comes from the common git dir, so a linked worktree (e.g.
# ~/workspace.worktree/<repo path>/<branch>) shows the name of its main tree, not
# its branch folder; a submodule, whose git dir lives in the parent's
# .git/modules, shows its own folder name.
# powerline-shell loads this file by its path (config.json), not as a module of
# its package, so imports must be absolute.
import os
import subprocess

from powerline_shell.segments.cwd import add_cwd_segment
from powerline_shell.utils import ThreadedSegment


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
        if not self.repo:
            add_cwd_segment(self.powerline)
            return
        theme = self.powerline.theme
        self.powerline.append(" %s " % self.repo, theme.CWD_FG, theme.PATH_BG)
