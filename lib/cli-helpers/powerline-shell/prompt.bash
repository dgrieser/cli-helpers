# The bash prompt of powerline-shell, sourced by ~/.bashrc; installed by updater
# (software pip-tools) together with config.json. A shell with TERM_SIMPLE set
# (launcher-terminal) gets that short prompt instead.

### PS1 settings
# mark a command whose output left the cursor mid-line, and start the prompt on
# the next line instead: the two-cell mark plus COLUMNS-2 spaces advance exactly
# one line width, so the terminal wraps; \r\e[K then clears the spaces that landed on the
# new line. at column 0 the deferred wrap keeps us on the same line and the
# prompt overwrites the mark, so a clean line costs nothing.
# \e[0m first closes any color the command left open, \u21b5 is the return
# symbol in grey. no \[ \] here: those mark invisible runs inside PS1 only, and
# this is written by PROMPT_COMMAND, not by the prompt.
function _eol_mark()
{
    printf '\e[0m \e[38;5;244m\u21b5\e[0m%*s\r\e[K' "$(( ${COLUMNS:-80} - 2 ))" ''
}

function _powerline_ps1()
{
    local status=$?
    # the prompt must start at column 0: a command that left the cursor
    # mid-line (the echoed ^C after ctrl+c, or output without a trailing
    # newline) would otherwise make bash draw the prompt there, and readline's
    # redraw (\r, no \e[K) leaves the prompt's tail on screen
    _eol_mark
    # checked here, not when sourced: ~/.bashrc puts ~/.local/bin on PATH later;
    # without powerline-shell (not installed yet) the prompt stays as it is
    command -v powerline-shell > /dev/null || return
    PS1=$(powerline-shell $status)
    new_title="$(dirs)"
    kctx="$(kube-current -s -n)"
    [ -n "${kctx}" ] && new_title="${new_title} [${kctx}]"
    title "${new_title}"
}

function _simple_ps1()
{
    # same clean-line reset as _powerline_ps1
    _eol_mark
    PS1="${TERM_SIMPLE}"
}

function title()
{
   echo -en "\e]2;$1\a"
}


### prompt settings
if [[ $TERM != linux && $TERM_SIMPLE != "" && ! $PROMPT_COMMAND =~ _simple_ps1 ]]; then
    PROMPT_COMMAND="_simple_ps1; $PROMPT_COMMAND"
fi
if [[ $TERM != linux && $TERM_SIMPLE == "" && ! $PROMPT_COMMAND =~ _powerline_ps1 ]]; then
    PROMPT_COMMAND="_powerline_ps1; $PROMPT_COMMAND"
fi
