# The cwd segment of the prompt, but inside a git repository it shows only the
# name of the repository, after the git logo, instead of the path. Outside one it
# is the stock cwd segment, with its settings ("cwd" in config.json).
# The repository name comes from the common git dir, so a linked worktree (e.g.
# ~/workspace.worktree/<repo path>/<branch>) shows the name of its main tree, not
# its branch folder; a submodule, whose git dir lives in the parent's
# .git/modules, shows its own folder name.
# A linked worktree gets WORKTREE_MARK after the logo and a violet fade instead
# of the orange one, so it stands apart from the main tree of the same name.
# powerline-shell loads this file by its path (config.json), not as a module of
# its package, so imports must be absolute.
import os
import re
import subprocess

from powerline_shell.segments.cwd import add_cwd_segment
from powerline_shell.utils import ThreadedSegment

# the git logo, nf-fa-git (Font Awesome, needs a Nerd Font)
REPO_ICON = u"\uf1d3"
# after the logo in a linked worktree
WORKTREE_MARK = "*"
# the logo's cells (space, logo, space) fade from a light to a dark git orange,
# one background each, in 24-bit color
REPO_FADE = ((0xF5, 0x73, 0x4F), (0xC8, 0x38, 0x1E))
# the closest of the 256 terminal colors (#d75f5f), all powerline-shell takes:
# the whole segment's background where the terminal has no 24-bit color, and
# the one a segment before it (ssh) draws its separator on
REPO_BG = 167
# the same for a linked worktree: light to dark violet, closest #875fd7
WORKTREE_FADE = ((0xA8, 0x7C, 0xF0), (0x6A, 0x3C, 0xC0))
WORKTREE_BG = 98
# the terminals that say they show 24-bit color
TRUECOLOR = ("truecolor", "24bit")


def escape_bash(text):
    """Text for PS1 that bash shows as it is. Bash decodes the backslash
    escapes of PS1 first, then expands it like a double-quoted string, so $, `
    and \\ need a backslash in the second step, which takes two in the first.
    powerline-shell's own sanitizing escapes $ and ` once, so a name with a
    backslash before them would run a command."""
    return re.sub(r"[\\`$]", lambda m: "\\\\" + ("\\\\" if m.group() == "\\" else m.group()), text)


def fade_cells(powerline, cells, fg, fade):
    """The cells, each on its own background, stepping from the first color of
    fade to the second; the foreground stays on the last color after them, so
    the separator that follows takes it."""
    (r1, g1, b1), (r2, g2, b2) = fade
    steps = max(len(cells) - 1, 1)
    out = [powerline.fgcolor(fg)]
    for i, cell in enumerate(cells):
        rgb = (r1 + (r2 - r1) * i // steps, g1 + (g2 - g1) * i // steps, b1 + (b2 - b1) * i // steps)
        out.append(powerline.color_template % ("[48;2;%d;%d;%dm" % rgb))
        out.append(cell)
    out.append(powerline.color_template % ("[38;2;%d;%d;%dm" % (r2, g2, b2)))
    return "".join(out)


def git_branch(git_dir):
    """The branch HEAD is on, read from the HEAD file, so it costs no second git
    run; the short commit when detached, None when unreadable."""
    try:
        with open(os.path.join(git_dir, "HEAD"), encoding="utf-8") as handle:
            head = handle.readline().strip()
    except (OSError, UnicodeDecodeError):
        return None
    if head.startswith("ref: "):
        ref = head[len("ref: "):]
        return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref
    return head[:7] or None


def git_repo(cwd):
    """The name of the repository, its branch and whether cwd is in a linked
    worktree; (None, None, False) outside one."""
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir", "--show-toplevel",
             "--git-dir"],
            cwd=cwd, stderr=subprocess.DEVNULL).decode("utf-8")
    except (subprocess.CalledProcessError, OSError, UnicodeDecodeError):
        # not in a repository, inside .git (no toplevel) or no git at all
        return None, None, False
    lines = out.splitlines()
    if len(lines) != 3:
        return None, None, False
    common_dir, toplevel, git_dir = lines
    if os.path.basename(common_dir) == ".git":
        name = os.path.basename(os.path.dirname(common_dir))
    else:
        name = os.path.basename(toplevel)
    if not name:
        return None, None, False
    # a linked worktree has its own git dir (with its own HEAD) below
    # worktrees/ of the common one; the main tree and a submodule share theirs
    linked = os.path.normpath(git_dir) != os.path.normpath(common_dir)
    return name, git_branch(git_dir), linked


class Segment(ThreadedSegment):
    def run(self):
        self.repo, self.branch, self.linked = git_repo(self.powerline.cwd)

    def add_to_powerline(self):
        self.join()
        # for the title segment, which goes after this one
        self.powerline.git_repo = self.repo
        self.powerline.git_branch = self.branch
        if not self.repo:
            add_cwd_segment(self.powerline)
            return
        theme = self.powerline.theme
        repo = self.repo
        if self.powerline.args.shell == "bash":
            repo = escape_bash(repo)
        if self.linked:
            icon, fade, bg = REPO_ICON + WORKTREE_MARK, WORKTREE_FADE, WORKTREE_BG
        else:
            icon, fade, bg = REPO_ICON, REPO_FADE, REPO_BG
        # the icon where the path outside a repository starts with its home part "~"
        if os.getenv("COLORTERM") in TRUECOLOR:
            # the cells bring their own colors; no separator color, so the arrow
            # keeps the foreground the fade ends on
            content = fade_cells(self.powerline, [" ", icon, " "], theme.HOME_FG, fade)
            self.powerline.segments.append((content, None, bg, self.powerline.separator, None))
        else:
            self.powerline.append(" %s " % icon, theme.HOME_FG, bg, sanitize=False)
        self.powerline.append(" %s " % repo, theme.CWD_FG, theme.PATH_BG, sanitize=False)
