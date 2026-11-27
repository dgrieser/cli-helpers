# Working agreements

- Never run `git commit` or `git push` unless I explicitly ask for it. Finish the work, report it as uncommitted, do not offer the commit as a next step.
- Always run the `codex-review` command to review the changes you made. Fix the findings and re-run codex-review until it stops reporting issues.
```
usage: codex-review [OPTIONS] [full | base [BRANCH] | uncommitted | commit [SHA]]

Runs a Codex review of the current Git repository with codex exec review.

Without a target, the review is chosen from the repository state:
  - uncommitted changes (staged, unstaged, untracked): those changes
  - on the default branch (as detected by git-default): the whole repository
  - on any other branch: the changes against the default branch

The response goes to stdout.

Targets:
    full                Review the whole repository
    base [BRANCH]       Review changes against BRANCH (default: the default branch; "default" also stands for it)
    uncommitted         Review staged, unstaged, and untracked changes
    commit [SHA]        Review commit SHA, any commit ref (default: HEAD)

Options:
    -p, --print         Print only the response, even in an interactive terminal
    -h, --help          Display this help

    --bash-completion   Print completion candidates and exit
```

- Always respond in english, even when working on german repos, or repos with german labels.

# Remote hosts (agent-ssh)

Hosts that need my login (password, second factor) are reached through a connection I grant: `agent-ssh` from my cli-helpers repo (`~/workspace/dgrieser/cli-helpers`). `agent-ssh --help` has the details.

- Get a ticket: `agent-ssh ask DESTINATION`. It waits until I ran `agent-ssh grant` in a terminal and prints the ticket; an open connection gives it at once. Not granted in time: tell me, ask again later. Never try to log in yourself, and never run `grant`: it is mine.
- Run commands: `agent-ssh open TICKET COMMAND`. Exit status 255 means the connection is gone: ask again (my `grant` keeps running and opens it again under the same ticket, `ask` waits for that).
- Long-running commands: `agent-ssh open --tmux TICKET COMMAND`. They survive a lost connection; on 255 the result stays on the host in `~/.cache/agent-ssh/<id>` (`output`, `status`; the path is printed on stderr).
- Other tools (`scp`, `rsync -e`, scripts that call `ssh`): `-o ControlPath="$(agent-ssh path TICKET)"`.

# Git worktrees

I manage worktrees with `git-worktree` from my dev-helpers repo (`~/workspace/dgrieser/dev-helpers`, installed to `/usr/local/bin`). Use it instead of raw `git worktree add`/`remove` so worktrees land where I expect them.

- Layout: main trees live under `$WORKSPACE` (`~/workspace`). Worktrees mirror that path under `$WORKSPACE_WORKTREE` (`~/workspace.worktree`): `$WORKSPACE_WORKTREE/<path under $WORKSPACE>/<branch>`. A repo elsewhere in `$HOME` goes to `$WORKSPACE_WORKTREE/home.dir/<path under $HOME>/<branch>`.
- Commands (run from any worktree of the repo, or pass `-w <dir>`):
  - `git-worktree add -b <branch> [-c]` — adds the worktree and prints its path. Refuses a branch already checked out elsewhere.
  - `git-worktree list` — every worktree of the repo, main tree first; marks `(prunable)` and `(unregistered)`.
  - `git-worktree go -b <branch>` — prints the path of an existing worktree.
  - `git-worktree delete -b <branch>` — removes the worktree and prints the main tree path. Without `-b` it removes the linked worktree it runs in.
  - `git-worktree move-to-main` — moves uncommitted changes (staged, unstaged, untracked) from the current linked worktree to the main tree. The main tree must be clean.
- Without `-b`, or without a command, it opens interactive pickers/prompts (`prompt-select`, `prompt-complete`, `fzf`). Those need a TTY, so always pass the command and `-b` when running it yourself.
- A branch that does not exist yet triggers a "Create it?" prompt. To create it without any question, pass `-c`/`--create`: it branches from `-B <base>`, else from the default remote branch, and fetches the base first unless `--no-fetch` is given:
  ```bash
  git-worktree add -b <branch> -c [-B origin/<base>] [--no-fetch]
  ```
- The tool only prints a path; it cannot change the shell's directory. A shell wrapper changes into it, e.g. `gw() { local d; d="$(git-worktree "$@")" && [ -d "$d" ] && cd "$d"; }`. When you work in a worktree, `cd` into the printed path or use absolute paths.
- `git-mr`/`git-pr` merging from a linked worktree removes that worktree after the run (unless it has uncommitted changes) and checks out the target branch in the main tree. The shell hook in `shell/dev-helpers.bash` moves shells left in a removed worktree back to the main tree at the next prompt.
- Never delete a worktree with uncommitted changes without asking me.
