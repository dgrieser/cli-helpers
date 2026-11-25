# The window title, set by the prompt itself: powerline-shell puts the escape
# sequence into PS1, so the shell runs no command of its own for it. The title
# is what the cwd_git segment shows (inside a git repository its name and
# branch, "repo @ branch"; elsewhere the path with ~ for the home), followed by
# the kube context in brackets when the prompt shows one.
# Nothing is looked up twice: this segment goes last in config.json, so the
# others are done and it reads their results; the title goes first into the
# prompt, where it takes no colors and leaves the separators alone.
# powerline-shell loads this file by its path (config.json), not as a module of
# its package, so imports must be absolute.
import os
import re

from powerline_shell.segments.cwd import replace_home_dir
from powerline_shell.utils import BasicSegment

# the logo kube-current puts before the context; the segment of the prompt that
# starts with it is the kube context
KUBE_LOGO = u"\U000f10fe"

TITLE_TEMPLATES = {
    "bash": "\\[\\e]2;%s\\a\\]",
    "zsh": "%%{\033]2;%s\007%%}",
    "tcsh": "%%{\033]2;%s\007%%}",
    "bare": "\033]2;%s\007",
}

# what ends or breaks the escape sequence
CONTROL_CHARS = re.compile(u"[\x00-\x1f\x7f-\x9f]")


def kube_context(powerline):
    for segment in powerline.segments:
        content = segment[0].strip()
        if content.startswith(KUBE_LOGO):
            # append escaped $ and ` for bash; the title escapes them again
            return re.sub(r"\\([`$])", r"\1", content[len(KUBE_LOGO):].strip())
    return ""


def escape(title, shell):
    title = CONTROL_CHARS.sub("", title)
    if shell == "bash":
        # as escape_bash of cwd_git: bash decodes the backslash escapes of PS1
        # first, then expands it like a double-quoted string, so $, ` and \
        # need a backslash in the second step, which takes two in the first
        return re.sub(r"[\\`$]", lambda m: "\\\\" + ("\\\\" if m.group() == "\\" else m.group()), title)
    if shell == "zsh":
        return title.replace("%", "%%")
    return title


class Segment(BasicSegment):
    def add_to_powerline(self):
        powerline = self.powerline
        shell = powerline.args.shell
        # the Linux console has no window to name
        if shell not in TITLE_TEMPLATES or os.getenv("TERM") == "linux":
            return
        # set by cwd_git; None outside a repository, missing without cwd_git
        repo = getattr(powerline, "git_repo", None)
        branch = getattr(powerline, "git_branch", None)
        if repo:
            title = "%s @ %s" % (repo, branch) if branch else repo
        else:
            title = replace_home_dir(powerline.cwd)
        kube = kube_context(powerline)
        if kube:
            title = "%s [%s]" % (title, kube)
        content = TITLE_TEMPLATES[shell] % escape(title, shell)
        # no colors and no separator: the next segment draws as if it came first
        powerline.segments.insert(0, (content, None, None, "", None))
