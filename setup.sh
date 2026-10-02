#!/bin/bash
# Sets up a new machine from this repo: the install folders, cli-helpers itself,
# the base software, gh and glab with their logins, the categories of updater
# the user picks, browser-router as the default browser and, on GNOME, the
# settings and app shortcuts. Run it as your user from a terminal, it asks for sudo.

APP_NAME="$(basename "${0}")"
REPO_DIR="$(cd "$(dirname "${0}")" && pwd)"

# the categories asked for after base, in this order, with what they are about;
# every group of updater has to be here or in SPECIAL_GROUPS
CATEGORIES=(dev k8s mw agents media comms desktop)
declare -A CATEGORY_DESCRIPTIONS=(
    [dev]="development tools, languages and containers"
    [k8s]="Kubernetes tools"
    [mw]="mittwald tools (need the glab login to gitlab.mittwald.it)"
    [agents]="AI coding agents"
    [media]="audio, video and image apps"
    [comms]="chat, mail and video calls"
    [desktop]="desktop apps"
)
SPECIAL_GROUPS=(base gnome gnome-extensions)
MITTWALD_GITLAB="gitlab.mittwald.it"

failed=()

info() {
    echo 1>&2
    echo -e "\033[1m${1}\033[0m" 1>&2
}

warning() {
    echo "WARNING: ${1}" 1>&2
}

fail() {
    echo "ERROR: ${1}" 1>&2
    exit 1
}

# the prompts of the repo, as cli-helpers is not installed yet at the start
ask() {
    "${REPO_DIR}/prompt-yes-no" "${1}"
}

run() {
    echo "+ ${*}" 1>&2
    "${@}"
}

run_updater() {
    # the installed one, so a copy install uses its rewritten paths
    run /usr/local/bin/updater "${@}" || failed+=("updater ${*}")
}

bootstrap() {
    local packages=()
    command -v make > /dev/null 2>&1 || packages+=(make)
    command -v zip > /dev/null 2>&1 || packages+=(zip)
    command -v git > /dev/null 2>&1 || packages+=(git)
    [ "${#packages[@]}" -eq 0 ] && return 0
    info "Installing what the Makefile needs: ${packages[*]}"
    run sudo apt-get update -q && run sudo apt-get install -y "${packages[@]}" \
        || fail "Failed to install ${packages[*]}"
}

setup_dirs() {
    if make -s -C "${REPO_DIR}" check-dirs > /dev/null 2>&1; then
        info "The install folders are writable for $(id -un)"
        return 0
    fi
    info "The install folders under /usr/local are not writable for $(id -un)"
    if ask "Create them and make them group-writable for the group $(id -gn) (sudo make setup-dirs)?"; then
        run sudo make -C "${REPO_DIR}" setup-dirs || fail "Failed to set up the install folders"
        return 0
    fi
    warning "Installing with sudo instead"
    MAKE_SUDO="sudo"
}

install_cli_helpers() {
    local target="install"
    info "Installing cli-helpers"
    if ask "Install as symlinks back to this repo (for working on it; no installs copies)?"; then
        target="install-links"
    fi
    # shellcheck disable=SC2086
    run ${MAKE_SUDO} make -C "${REPO_DIR}" "${target}" || fail "Failed to run make ${target}"
    # without sudo the .pth file in the system's site-packages is only warned about
    if [ "$(cat /usr/lib/python3/dist-packages/usr-local-python3.pth 2>/dev/null)" != "/usr/local/lib/python3/dist-packages" ]; then
        run sudo make -C "${REPO_DIR}" install-pth || failed+=("sudo make install-pth")
    fi
    hash -r
}

login_github() {
    while ! gh auth status --hostname github.com > /dev/null 2>&1; do
        info "gh is not logged in to github.com, it is needed for the releases on GitHub"
        if ! ask "Log in now (gh auth login)?"; then
            warning "Not logged in to github.com, the software from GitHub will fail"
            failed+=("gh auth login")
            return 0
        fi
        gh auth login
    done
    echo "Logged in to github.com" 1>&2
}

login_gitlab() {
    local host="${1}"
    while ! glab auth status --hostname "${host}" > /dev/null 2>&1; do
        info "glab is not logged in to ${host}, it is needed for the mittwald tools"
        if ! ask "Log in now (glab auth login --hostname ${host})?"; then
            warning "Not logged in to ${host}, the mittwald tools will fail"
            failed+=("glab auth login --hostname ${host}")
            return 0
        fi
        glab auth login --hostname "${host}"
    done
    echo "Logged in to ${host}" 1>&2
}

install_gh_glab() {
    info "Installing gh and glab, most software comes from their releases"
    run_updater gh glab
    hash -r
    command -v gh > /dev/null 2>&1 && login_github
    command -v glab > /dev/null 2>&1 && login_gitlab "${MITTWALD_GITLAB}"
}

check_categories() {
    local group
    local known
    while IFS=$'\t' read -r group _; do
        for known in "${CATEGORIES[@]}" "${SPECIAL_GROUPS[@]}"; do
            [ "${known}" = "${group}" ] && continue 2
        done
        warning "updater group ${group} is not asked for by ${APP_NAME}"
        CATEGORIES+=("${group}")
    done < <(/usr/local/bin/updater --list)
}

members() {
    /usr/local/bin/updater --list | awk -F '\t' -v group="${1}" '$1 == group { gsub(/ /, ", ", $2); print $2 }'
}

select_categories() {
    local category
    local description
    selected=()
    if command -v gnome-shell > /dev/null 2>&1; then
        info "GNOME extensions: $(members gnome-extensions)"
        ask "Install the GNOME extensions?" && selected+=(gnome-extensions)
    fi
    for category in "${CATEGORIES[@]}"; do
        description="${CATEGORY_DESCRIPTIONS[${category}]:-}"
        info "${category}${description:+: ${description}}"
        echo "$(members "${category}")" 1>&2
        ask "Install ${category}?" && selected+=("${category}")
    done
}

set_default_browser() {
    command -v xdg-settings > /dev/null 2>&1 || return 0
    [ "$(xdg-settings get default-web-browser 2>/dev/null)" = "browser-router.desktop" ] && return 0
    info "browser-router opens authentication URLs in a small window above the others, every other URL in google-chrome"
    command -v google-chrome > /dev/null 2>&1 || warning "google-chrome is not installed, it is in the dev category (updater chrome)"
    if ask "Make browser-router the default browser?"; then
        run browser-router --set-default || failed+=("browser-router --set-default")
    fi
}

gnome_settings() {
    command -v gnome-shell > /dev/null 2>&1 || return 0
    info "GNOME settings: keyboard, appearance, dock, power, Files, Ptyxis and extensions (gnome-apply-settings)"
    if ask "Apply the GNOME settings?"; then
        run gnome-apply-settings || failed+=("gnome-apply-settings")
    fi
    info "App shortcuts: $(app-shortcut --list 2>/dev/null | awk '{ print $1 }' | paste -sd ' ')"
    if ask "Bind the app shortcuts as GNOME custom shortcuts (app-shortcut --bind)?"; then
        run app-shortcut --bind || failed+=("app-shortcut --bind")
    fi
}

[ "$(id -u)" -eq 0 ] && fail "Run ${APP_NAME} as your user, it asks for sudo itself"
[ -t 0 ] || fail "Run ${APP_NAME} in a terminal, it asks questions"
command -v python3 > /dev/null 2>&1 || fail "python3 is required for the prompts"

MAKE_SUDO=""
info "Setting up this machine from ${REPO_DIR}"
bootstrap
setup_dirs
install_cli_helpers
install_gh_glab

info "Installing base"
run_updater base

check_categories
select_categories
if [ "${#selected[@]}" -gt 0 ]; then
    info "Installing ${selected[*]}"
    run_updater "${selected[@]}"
fi

set_default_browser
gnome_settings

# new GNOME extensions and group memberships (docker) only apply to a new session
info "Log out and back in, so new GNOME extensions and groups take effect"

if [ "${#failed[@]}" -gt 0 ]; then
    info "Done, but these failed or were skipped, see /var/log/updater.log:"
    printf '  %s\n' "${failed[@]}" 1>&2
    exit 1
fi
info "Done"
