#!/bin/bash
# Sets up a new machine from this repo, restoring from a backup of setup-backup
# that it asks for once: the keyring with its SSH
# keys, SSH config and network connections, the install folders, cli-helpers itself, ~/bin from a backup, the Mittwald VPN,
# the base software, gh and glab with their logins (glab to gitlab.mittwald.it and,
# if you like, gitlab.com), the dotfiles of
# bash_aliases.d (asking for missing SSH keys and history backups), the reminders
# of reminder, the lists of ~/.kube/mittwald, the Downloads folder, the session of Sublime Text and the sessions and histories of
# Claude Code, Codex and opencode from a backup, the git repos of the workspace
# with what only they held (changes, stashes, local branches, worktrees), the categories of updater
# the user picks, the logins of Claude Code and Codex, the k-ctx shell shorthands, netbox-cli and a kubeconfig per
# NetBox cluster when the kubectl-helpers are installed, browser-router as the default browser and, on GNOME, the
# settings and app shortcuts. Run it as your user from a terminal, it asks for sudo.

APP_NAME="$(basename "${0}")"
REPO_DIR="$(cd "$(dirname "${0}")" && pwd)"

# the categories asked for after base, in this order, with what they are about;
# every group of updater has to be here or in SPECIAL_GROUPS
CATEGORIES=(dev k8s mw agents media comms desktop personal)
declare -A CATEGORY_DESCRIPTIONS=(
    [dev]="development tools, languages and containers"
    [k8s]="Kubernetes tools"
    [mw]="mittwald tools (need the glab login to gitlab.mittwald.it)"
    [agents]="AI coding agents"
    [media]="audio, video and image apps"
    [comms]="chat, mail and video calls"
    [desktop]="desktop apps"
    [personal]="your own tools and automations"
)
SPECIAL_GROUPS=(base gnome gnome-extensions)
MITTWALD_GITLAB="gitlab.mittwald.it"
# the VPN connection to it, which gen of ~/bin dials
VPN_NAME="mittwald"
GEN="${HOME}/bin/gen"
# the shorthands of k-ctx: c switches the cluster, s goes to an identifier, n
# switches the namespace, "for" loops over clusters and bm is the baremetal parent
K_CTX_SHELL_INIT=(--alias-env c --alias-go s --alias-ns n --alias-netbox-loop-prefix for
    --alias-evileye-loop-prefix for --alias-netbox-env-parent bm)

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

# Ctrl-C aborts the whole setup, also in a prompt: the prompts read it as a key
# in raw mode and exit with 130, so the shell itself gets no SIGINT
abort() {
    trap - INT
    echo 1>&2
    warning "Aborted"
    exit 130
}

# interrupted STATUS: a status of 130 aborts the setup, also from a command
# substitution, which signals this shell; any other status is returned
interrupted() {
    [ "${1}" -eq 130 ] || return "${1}"
    kill -INT "$$"
    exit 130
}

# the prompts of the repo, as cli-helpers is not installed yet at the start
prompt_run() {
    "${REPO_DIR}/${1}" "${@:2}"
    interrupted "${?}"
}

ask() {
    prompt_run prompt-yes-no "${1}"
}

run() {
    echo "+ ${*}" 1>&2
    "${@}"
    interrupted "${?}"
}

run_updater() {
    # the installed one, so a copy install uses its rewritten paths
    run /usr/local/bin/updater "${@}" && return 0
    failed+=("updater ${*}")
    info "updater ${*} failed, see the errors above and /var/log/updater.log"
    ask "Continue with the setup anyway?" || finish
}

# the summary of what failed, then the end
finish() {
    if [ "${#failed[@]}" -gt 0 ]; then
        info "Done, but these failed or were skipped, see /var/log/updater.log:"
        printf '  %s\n' "${failed[@]}" 1>&2
        exit 1
    fi
    info "Done"
    exit 0
}

bootstrap() {
    local packages=()
    command -v make > /dev/null 2>&1 || packages+=(make)
    command -v zip > /dev/null 2>&1 || packages+=(zip)
    command -v git > /dev/null 2>&1 || packages+=(git)
    # updater downloads with curl before base installs it
    command -v curl > /dev/null 2>&1 || packages+=(curl)
    [ "${#packages[@]}" -eq 0 ] && return 0
    info "Installing what the Makefile and updater need: ${packages[*]}"
    run sudo apt-get update -q && run sudo apt-get install -y "${packages[@]}" \
        || fail "Failed to install ${packages[*]}"
}

# the backup of setup-backup, asked for once: the ones on the attached drives
# and media (setup-backup --find), or any other folder; every restore step
# finds its part in it by the layout of setup-backup and skips a missing one
choose_backup() {
    local other="(another folder)" none="(no backup)" dir choice found
    local -a items=()
    info "Backup: restore from a backup of the old machine (setup-backup there)"
    while IFS= read -r dir; do
        items+=("${dir}"$'\t'"${dir}")
    done < <("${REPO_DIR}/setup-backup" --find)
    items+=("${other}"$'\t'"${other}" "${none}"$'\t'"${none}")
    [ "${#items[@]}" -eq 2 ] && echo "No backups on the attached drives and media" 1>&2
    choice="$(prompt_run prompt-select --delimiter $'\t' -p "Backup to restore from:" "${items[@]}")"
    [ -z "${choice}" ] || [ "${choice}" = "${none}" ] && return 0
    if [ "${choice}" = "${other}" ]; then
        choice="$(prompt_run prompt-folder "Backup folder (setup-backup-<host>-<date>):")"
        choice="${choice/#\~/${HOME}}"
        [ -z "${choice}" ] && return 0
    fi
    choice="${choice%/}"
    if [ ! -d "${choice}" ]; then
        warning "No such folder: ${choice}, restoring nothing"
        failed+=("backup ${choice}")
        return 0
    fi
    found=0
    for dir in keyrings reminder history Keys bin kube-mittwald sublime-text downloads agents git; do
        [ -d "${choice}/${dir}" ] && found=1
    done
    if [ "${found}" -eq 0 ]; then
        warning "${choice} is no backup of setup-backup, restoring nothing"
        failed+=("backup ${choice}")
        return 0
    fi
    BACKUP_DIR="${choice}"
    echo "Restoring from ${BACKUP_DIR}" 1>&2
}

# restore_part PART TARGET: the files of PART of the backup into the folder
# TARGET, with their subfolders; a file that is there already is kept
restore_part() {
    local src="${BACKUP_DIR}/${1}" dst="${2}" file rel count=0 kept=0
    while IFS= read -r -d '' file; do
        rel="${file#"${src}/"}"
        if [ -e "${dst}/${rel}" ]; then
            kept=$((kept + 1))
            continue
        fi
        mkdir -p "$(dirname "${dst}/${rel}")" && cp -P -p "${file}" "${dst}/${rel}" \
            && count=$((count + 1)) || failed+=("restore ${1}/${rel}")
    done < <(find "${src}" \( -type f -o -type l \) -print0)
    echo "${1}: restored ${count} files to ${dst}$([ "${kept}" -gt 0 ] && echo ", kept ${kept} that were there")" 1>&2
}

# has_part PART: whether the backup has PART; says so when not
has_part() {
    [ -z "${BACKUP_DIR}" ] && return 1
    [ -d "${BACKUP_DIR}/${1}" ] && return 0
    echo "No ${1}/ in the backup" 1>&2
    return 1
}

# the keyring of the old machine: the keyring files of the backup are imported into
# the login keyring, early, so the logins and tokens in it are there for the
# later steps; then the SSH keys and network connections (e.g. the Mittwald
# wifi and VPN) stored in the keyring with keyring-cli are restored
setup_keyring() {
    local keyring_cli="${REPO_DIR}/keyring-cli"
    local packages=() package file name type
    local -a files=() names
    info "Keyring: import the old keyring files of the backup (keyrings/), then restore the SSH keys, the SSH config and the network connections stored in the keyring"
    if ! busctl --user status org.freedesktop.secrets > /dev/null 2>&1; then
        warning "No keyring service running, skipping the keyring"
        failed+=("keyring")
        return 0
    fi
    for package in libsecret-tools jq python3-gi gir1.2-secret-1 python3-cryptography; do
        dpkg -s "${package}" > /dev/null 2>&1 || packages+=("${package}")
    done
    if [ "${#packages[@]}" -gt 0 ]; then
        if ! { run sudo apt-get update -q && run sudo apt-get install -y "${packages[@]}"; }; then
            failed+=("apt-get install ${packages[*]}")
            return 0
        fi
    fi

    if [ -n "${BACKUP_DIR}" ]; then
        mapfile -t files < <(find "${BACKUP_DIR}/keyrings" -maxdepth 1 -type f -name '*.keyring' 2>/dev/null | sort)
        [ "${#files[@]}" -eq 0 ] && echo "No keyring files in the backup" 1>&2
        for file in "${files[@]}"; do
            run "${keyring_cli}" import "${file}" || failed+=("keyring-cli import ${file}")
        done
    fi

    mapfile -t names < <("${keyring_cli}" ssh-list 2>/dev/null | tail -n +2 | awk '{ print $1 }')
    if [ "${#names[@]}" -gt 0 ] && ask "Restore the SSH keys of the keyring (${names[*]}) to ~/.ssh?"; then
        for name in "${names[@]}"; do
            if [ -e "${HOME}/.ssh/${name}" ]; then
                echo "Kept ${HOME}/.ssh/${name}" 1>&2
                continue
            fi
            run "${keyring_cli}" ssh-restore "${name}" || failed+=("keyring-cli ssh-restore ${name}")
        done
    fi

    # the SSH config is not in this public repo: it names internal hosts
    if secret-tool lookup type ssh-config name config > /dev/null 2>&1; then
        if [ -e "${HOME}/.ssh/config" ]; then
            echo "Kept ${HOME}/.ssh/config" 1>&2
        elif ask "Restore the SSH config of the keyring to ~/.ssh/config?"; then
            run "${keyring_cli}" ssh-config-restore || failed+=("keyring-cli ssh-config-restore")
        fi
    fi

    # nm-list is a display table: connection names may themselves contain spaces.
    mapfile -t names < <(secret-tool search --all --unlock type nm-connection part keyfile 2>&1 > /dev/null \
        | sed -n 's/^attribute\.name = //p' | sort -u)
    if [ "${#names[@]}" -gt 0 ] && ask "Restore the network connections of the keyring (${names[*]})?"; then
        # the VPN connections are OpenVPN ones, their plugin may be missing
        for name in "${names[@]}"; do
            type="$(nmcli -g connection.type connection show id "${name}" 2>/dev/null)"
            if [ -n "${type}" ]; then
                echo "Kept network connection ${name}" 1>&2
                continue
            fi
            type="$(secret-tool lookup type nm-connection name "${name}" part keyfile \
                | base64 -d | sed -n 's/^type=//p' | head -n 1)"
            if [ "${type}" = vpn ] && ! dpkg -s network-manager-openvpn-gnome > /dev/null 2>&1; then
                run sudo apt-get install -y network-manager-openvpn-gnome || failed+=("apt-get install network-manager-openvpn-gnome")
            fi
            run "${keyring_cli}" nm-restore "${name}" || failed+=("keyring-cli nm-restore ${name}")
        done
    fi
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
    local desktop_target="install-desktop"
    info "Installing cli-helpers"
    if ask "Install as symlinks back to this repo (for working on it; no installs copies)?"; then
        target="install-links"
        desktop_target="install-desktop-links"
    fi
    if [ -n "${MAKE_SUDO}" ]; then
        # Root installs the system files, but the bridge must point at our HOME.
        run sudo make -C "${REPO_DIR}" "${target}" "HOME=${HOME}" INSTALL_USER_ASSETS=0 \
            || fail "Failed to run make ${target}"
        run make -C "${REPO_DIR}" install-gnome-extension "${desktop_target}" \
            || fail "Failed to install the per-user assets"
        if command -v gnome-shell > /dev/null 2>&1 && command -v gnome-extensions > /dev/null 2>&1; then
            run gnome-extensions enable cli-helpers-window-bridge@dgrieser.de \
                || warning "Could not enable the GNOME extension; log out and back in, then enable it"
        fi
    else
        run make -C "${REPO_DIR}" "${target}" || fail "Failed to run make ${target}"
    fi
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

# the own scripts of ~/bin from bin/ of the backup, before the VPN: gen dials it
restore_bin() {
    has_part bin || return 0
    info "~/bin: restore your own scripts from the backup, gen among them dials the VPN"
    restore_part bin "${HOME}/bin"
}

# the VPN of Mittwald, fully set up before the glab login to gitlab.mittwald.it:
# the OpenVPN plugin of NetworkManager with its GNOME part, the connection loaded
# (from the keyring when the keyring step did not restore it) and gen to dial it
setup_vpn() {
    local packages=() package
    info "VPN: the OpenVPN plugin of NetworkManager, the ${VPN_NAME} connection and ${GEN} to dial it"
    # gen switches the wifi with iw
    for package in network-manager-openvpn network-manager-openvpn-gnome iw; do
        dpkg -s "${package}" > /dev/null 2>&1 || packages+=("${package}")
    done
    if [ "${#packages[@]}" -gt 0 ]; then
        if run sudo apt-get install -y "${packages[@]}"; then
            # the connections of a plugin that was missing are read again
            run sudo nmcli connection reload || failed+=("nmcli connection reload")
        else
            failed+=("apt-get install ${packages[*]}")
        fi
    fi

    if [ "$(nmcli -g connection.type connection show id "${VPN_NAME}" 2>/dev/null)" = vpn ]; then
        echo "VPN connection ${VPN_NAME} is loaded" 1>&2
    elif secret-tool lookup type nm-connection name "${VPN_NAME}" part keyfile > /dev/null 2>&1; then
        run "${REPO_DIR}/keyring-cli" nm-restore "${VPN_NAME}" || failed+=("keyring-cli nm-restore ${VPN_NAME}")
    else
        warning "No VPN connection ${VPN_NAME}, neither in NetworkManager nor in the keyring"
        failed+=("VPN connection ${VPN_NAME}")
    fi

    if [ ! -x "${GEN}" ]; then
        warning "No ${GEN} to dial the VPN, restore it with the backup of ~/bin"
        failed+=("${GEN}")
    fi
}

# gitlab.mittwald.it is only reachable through the VPN (or from the office)
dial_vpn() {
    local host="${1}"
    # any HTTP answer will do, only no connection at all means no VPN
    while ! curl -sS -o /dev/null --connect-timeout 5 "https://${host}" 2> /dev/null; do
        info "${host} is not reachable: dial the ${VPN_NAME} VPN now"
        if [ -x "${GEN}" ] && ask "Dial it with ${GEN}?"; then
            run "${GEN}"
            continue
        fi
        echo "Dial it in another terminal (${GEN} or nmcli connection up id ${VPN_NAME})" 1>&2
        ask "Try ${host} again?" || return 1
    done
}

# login_gitlab HOST [optional]: glab logged in to HOST; the login to
# gitlab.mittwald.it is needed for the mittwald tools, an optional one (gitlab.com)
# is only offered, and declining it is no failure
login_gitlab() {
    local host="${1}" optional="${2:-}"
    while ! glab auth status --hostname "${host}" > /dev/null 2>&1; do
        if [ -n "${optional}" ]; then
            info "glab is not logged in to ${host}"
            ask "Log in to ${host} (glab auth login --hostname ${host})?" || return 0
        else
            info "glab is not logged in to ${host}, it is needed for the mittwald tools"
            if ! ask "Log in now (glab auth login --hostname ${host})?"; then
                warning "Not logged in to ${host}, the mittwald tools will fail"
                failed+=("glab auth login --hostname ${host}")
                return 0
            fi
        fi
        if [ "${host}" = "${MITTWALD_GITLAB}" ] && ! dial_vpn "${host}"; then
            warning "No VPN, not logged in to ${host}, the mittwald tools will fail"
            failed+=("VPN for glab auth login --hostname ${host}")
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
    command -v glab > /dev/null 2>&1 && login_gitlab gitlab.com optional
}

# the Keys folder of the documents folder and the shell histories from Keys/
# and history/ of the backup, before the dotfiles: install-home of
# bash_aliases.d then links the SSH keys from there and asks for nothing
restore_keys_history() {
    local keys_dir
    if has_part Keys; then
        keys_dir="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "${HOME}/Documents")/Keys"
        info "Keys: restore the Keys folder of the documents folder from the backup"
        restore_part Keys "${keys_dir}"
    fi
    if has_part history; then
        info "Shell histories: restore them from the backup"
        restore_part history "${HOME}"
    fi
}

# the dotfiles of bash_aliases.d once more, now with a terminal: updater installed
# them without one, so it skipped the questions for a missing SSH key in the
# documents folder and for the backups of the shell histories (the ones the
# backup did not have)
install_dotfiles() {
    local dir="${HOME}/workspace/dgrieser/bash_aliases.d"
    if [ ! -f "${dir}/Makefile" ]; then
        warning "No ${dir}, skipping its dotfiles"
        failed+=("bash_aliases.d dotfiles")
        return
    fi
    info "Dotfiles: restore missing SSH keys and shell histories"
    run make -s -C "${dir}" install || failed+=("make -C ${dir} install")
}

# the reminders of the reminder tool from reminder/ of the backup, with the
# done ones and their display order
restore_reminders() {
    has_part reminder || return 0
    info "Reminders: restore them from the backup"
    restore_part reminder "${HOME}/.cache/reminder"
}

# the lists of ~/.kube/mittwald that the kubectl-helpers read (the evil-eye
# namespaces of k-ctx among them) from kube-mittwald/ of the backup
restore_kube_mittwald() {
    has_part kube-mittwald || return 0
    info "~/.kube/mittwald: restore the lists the kubectl-helpers read from the backup"
    restore_part kube-mittwald "${HOME}/.kube/mittwald"
}

# the Downloads folder from downloads/ of the backup; a file that is there
# already is kept
restore_downloads() {
    has_part downloads || return 0
    info "Downloads: restore the Downloads folder from the backup"
    restore_part downloads "$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "${HOME}/Downloads")"
}

# the session of Sublime Text from sublime-text/ of the backup: the windows and
# tabs it had open, with their unsaved text; before updater installs it, so
# its first start opens them; a running one would write its own session over it
restore_sublime() {
    local dir="${HOME}/.config/sublime-text/Local"
    has_part sublime-text || return 0
    info "Sublime Text: restore its session (the open files and their unsaved text) from the backup"
    if pgrep -x sublime_text > /dev/null 2>&1; then
        warning "Sublime Text is running and would write its session over the restored one"
        while pgrep -x sublime_text > /dev/null 2>&1; do
            if ! ask "Close Sublime Text now, then continue (no: skip its session)?"; then
                failed+=("sublime-text, it was running")
                return 0
            fi
        done
    fi
    restore_part sublime-text "${dir}"
}

# the sessions, histories, memories and settings of Claude Code, Codex and
# opencode from agents/ of the backup, one NAME.tar.gz each; before updater
# installs them, so it merges the shipped settings into the restored ones; a
# file that is here already is kept; the logins are not in the backup,
# login_agents asks for them
restore_agents() {
    local archive count=0
    has_part agents || return 0
    info "Agents: restore the sessions, histories, memories and settings of Claude Code, Codex and opencode from the backup"
    for archive in "${BACKUP_DIR}/agents"/*.tar.gz; do
        [ -f "${archive}" ] || continue
        echo "Restoring $(basename "${archive}" .tar.gz)" 1>&2
        if tar -xzf "${archive}" -C "${HOME}" --skip-old-files; then
            count=$((count + 1))
        else
            failed+=("agents $(basename "${archive}")")
        fi
    done
    echo "agents: restored ${count} to ${HOME}" 1>&2
}

# restore_git_repo DIR: the repo of DIR of git/ of the backup to its path under
# ~: cloned from its remotes when it is not there, then what only it held on the
# old machine from repo.bundle: the branches (one that went another way here is
# kept and the old one restored as NAME-setup-backup), the tags, the stashes and
# the worktrees with their uncommitted and untracked files; changes that do not
# fit the worktree as it is here become a stash instead
restore_git_repo() {
    local src="${1}" rel dst line kind a b c d e f sha cur wt path fresh=0 checked_out
    local -a remotes=() branches=() tags=() stashes=() worktrees=()
    rel="${src#"${BACKUP_DIR}/git/"}"
    dst="${HOME}/${rel}"
    # the fields are kept apart by \x1f, as read joins tabs in a row and loses
    # an empty field
    while IFS= read -r line; do
        IFS=$'\x1f' read -r kind line <<< "${line//$'\t'/$'\x1f'}"
        case "${kind}" in
            remote)   remotes+=("${line}") ;;
            branch)   branches+=("${line}") ;;
            tag)      tags+=("${line}") ;;
            stash)    stashes+=("${line}") ;;
            worktree) worktrees+=("${line}") ;;
        esac
    done < "${src}/manifest"

    echo "${rel}" 1>&2
    if [ ! -e "${dst}/.git" ]; then
        if [ "${#remotes[@]}" -gt 0 ]; then
            # from origin, or the first remote; the others are added after the clone
            IFS=$'\x1f' read -r a b <<< "${remotes[0]}"
            for line in "${remotes[@]}"; do
                [ "${line%%$'\x1f'*}" = origin ] && IFS=$'\x1f' read -r a b <<< "${line}"
            done
            run git clone -q -o "${a}" "${b}" "${dst}" || { failed+=("git clone ${b} ${dst}"); return 0; }
        else
            run git init -q "${dst}" || { failed+=("git init ${dst}"); return 0; }
        fi
        fresh=1
    fi
    for line in "${remotes[@]}"; do
        IFS=$'\x1f' read -r a b <<< "${line}"
        git -C "${dst}" remote get-url "${a}" > /dev/null 2>&1 && continue
        git -C "${dst}" remote add "${a}" "${b}" && git -C "${dst}" fetch -q "${a}" \
            || failed+=("git remote add ${a} ${b} in ${dst}")
    done

    if [ -f "${src}/repo.bundle" ]; then
        # the bundle builds on the commits of the remotes, which an old clone may lack
        git -C "${dst}" bundle verify -q "${src}/repo.bundle" > /dev/null 2>&1 \
            || git -C "${dst}" fetch -q --all
        if ! git -C "${dst}" fetch -q --no-tags "${src}/repo.bundle" '+refs/*:refs/setup-backup/*'; then
            failed+=("git ${rel}, the commits of the remotes it builds on are gone")
            return 0
        fi
    fi

    for line in "${branches[@]}"; do
        IFS=$'\x1f' read -r a b <<< "${line}"
        sha="$(git -C "${dst}" rev-parse "refs/setup-backup/heads/${a}")"
        if ! cur="$(git -C "${dst}" rev-parse -q --verify "refs/heads/${a}")"; then
            git -C "${dst}" update-ref "refs/heads/${a}" "${sha}"
        elif [ "${cur}" = "${sha}" ]; then
            :
        elif git -C "${dst}" merge-base --is-ancestor "${cur}" "${sha}"; then
            checked_out="$(git -C "${dst}" worktree list --porcelain \
                | awk -v ref="branch refs/heads/${a}" '/^worktree / { wt = substr($0, 10) } $0 == ref { print wt }')"
            if [ -n "${checked_out}" ]; then
                git -C "${checked_out}" merge -q --ff-only "${sha}" \
                    || failed+=("git ${rel}: fast-forward of ${a} in ${checked_out}")
            else
                git -C "${dst}" update-ref "refs/heads/${a}" "${sha}" "${cur}"
            fi
        else
            warning "${rel}: ${a} went another way here, the old one is ${a}-setup-backup"
            git -C "${dst}" update-ref "refs/heads/${a}-setup-backup" "${sha}"
        fi
        if [ -n "${b}" ] && git -C "${dst}" rev-parse -q --verify "refs/remotes/${b}" > /dev/null; then
            git -C "${dst}" branch -q --set-upstream-to="${b}" "${a}"
        fi
    done
    for a in "${tags[@]}"; do
        git -C "${dst}" rev-parse -q --verify "refs/tags/${a}" > /dev/null && continue
        git -C "${dst}" update-ref "refs/tags/${a}" "$(git -C "${dst}" rev-parse "refs/setup-backup/tags/${a}")"
    done
    # the oldest first, so they keep their order
    for (( c = ${#stashes[@]} - 1; c >= 0; c-- )); do
        IFS=$'\x1f' read -r a b <<< "${stashes[${c}]}"
        sha="$(git -C "${dst}" rev-parse "refs/setup-backup/backup/stash/${a}")"
        git -C "${dst}" stash list --format='%H' | grep -qx "${sha}" && continue
        git -C "${dst}" stash store -m "${b}" "${sha}" || failed+=("git ${rel}: stash ${b}")
    done

    for wt in "${worktrees[@]}"; do
        IFS=$'\x1f' read -r a path b c d e <<< "${wt}"
        path="${HOME}/${path}"
        if [ "${a}" -eq 0 ]; then
            path="${dst}"
            if [ "${fresh}" -eq 1 ]; then
                if [ -n "${b}" ]; then
                    git -C "${dst}" checkout -q "${b}"
                else
                    git -C "${dst}" checkout -q --detach "${c}"
                fi || failed+=("git ${rel}: checkout ${b:-${c}}")
            fi
        elif [ ! -e "${path}" ]; then
            if [ -n "${b}" ]; then
                run git -C "${dst}" worktree add -q "${path}" "${b}"
            else
                run git -C "${dst}" worktree add -q --detach "${path}" "${c}"
            fi || { failed+=("git ${rel}: worktree ${path}"); continue; }
        elif [ "$(git -C "${path}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
            != "$(git -C "${dst}" rev-parse --path-format=absolute --git-common-dir)" ]; then
            warning "${path} is there but no worktree of ${dst}, its changes are not restored"
            failed+=("git worktree ${path}")
            continue
        fi
        # changes that are there already (a second run) are left alone
        sha="$(git -C "${path}" stash create 2>/dev/null)"
        if [ -n "${d}" ] && [ -n "${sha}" ] \
            && [ "$(git -C "${path}" rev-parse "${sha}^{tree}")" = "$(git -C "${path}" rev-parse "${d}^{tree}")" ]; then
            d=""
        fi
        if [ -n "${d}" ]; then
            # onto the commit they were made on, into a clean worktree, else a stash
            if [ "$(git -C "${path}" rev-parse HEAD)" = "${c}" ] \
                && [ -z "$(git -C "${path}" status --porcelain --untracked-files=no)" ] \
                && git -C "${path}" stash apply -q --index "${d}" > /dev/null 2>&1; then
                :
            else
                warning "${path}: the uncommitted changes of the old machine are a stash now"
                git -C "${dst}" stash store -m "setup-backup changes of ${path#"${HOME}/"}" "${d}" \
                    || failed+=("git ${rel}: changes of ${path}")
            fi
        fi
        if [ "${e}" = 1 ]; then
            tar -xf "${src}/untracked-${a}.tar" -C "${path}" --skip-old-files \
                || failed+=("git ${rel}: untracked files of ${path}")
        fi
    done

    git -C "${dst}" for-each-ref --format='delete %(refname)' refs/setup-backup \
        | git -C "${dst}" update-ref --stdin
}

# the git repos of the workspace from git/ of the backup (see restore_git_repo);
# after the logins and SSH keys, as the missing ones are cloned
restore_git() {
    local manifest
    local -a dirs=()
    has_part git || return 0
    while IFS= read -r manifest; do
        dirs+=("$(dirname "${manifest}")")
    done < <(find "${BACKUP_DIR}/git" -name manifest | sort)
    [ "${#dirs[@]}" -eq 0 ] && return 0
    info "Git repos: restore what only they held (uncommitted changes, stashes, local branches, worktrees), the missing ones are cloned"
    printf '  %s\n' "${dirs[@]#"${BACKUP_DIR}/git/"}" 1>&2
    ask "Restore these ${#dirs[@]} git repos?" || return 0
    grep -qsF "${MITTWALD_GITLAB}" "${dirs[@]/%//manifest}" && ! dial_vpn "${MITTWALD_GITLAB}" \
        && warning "No VPN, the repos of ${MITTWALD_GITLAB} cannot be cloned"
    for manifest in "${dirs[@]}"; do
        restore_git_repo "${manifest}"
    done
}

# agent_cmd NAME: the installed command, also when the PATH of this shell does
# not have it yet: claude lives in ~/.local/bin, codex in the bin of nvm's node
agent_cmd() {
    local cmd
    cmd="$(command -v "${1}" 2>/dev/null)" && { echo "${cmd}"; return 0; }
    for cmd in "${HOME}/.local/bin/${1}" "${HOME}"/.nvm/versions/node/*/bin/"${1}"; do
        [ -x "${cmd}" ] && { echo "${cmd}"; return 0; }
    done
    return 1
}

# the logins of Claude Code and Codex, which setup-backup leaves out of the
# backup; one that is logged in already is not asked for
login_agents() {
    local claude codex
    if claude="$(agent_cmd claude)"; then
        if "${claude}" auth status --json 2>/dev/null | grep -q '"loggedIn": *true'; then
            echo "Claude Code is logged in" 1>&2
        else
            info "Claude Code: log in to your Anthropic account"
            if ask "Log in to Claude Code (claude auth login)?"; then
                run "${claude}" auth login || failed+=("claude auth login")
            fi
        fi
    fi
    if codex="$(agent_cmd codex)"; then
        if "${codex}" login status > /dev/null 2>&1; then
            echo "Codex is logged in" 1>&2
        else
            info "Codex: log in with ChatGPT or an API key"
            if ask "Log in to Codex (codex login)?"; then
                run "${codex}" login || failed+=("codex login")
            fi
        fi
    fi
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

# the shell shorthands of k-ctx, which .kube_aliases of bash_aliases.d sources;
# the file is generated, so it is written again rather than kept
setup_k_ctx_shell() {
    command -v k-ctx > /dev/null 2>&1 || return 0
    info "k-ctx shell shorthands: ${K_CTX_SHELL_INIT[*]}"
    run k-ctx shell-init "${K_CTX_SHELL_INIT[@]}" || failed+=("k-ctx shell-init")
}

# netbox-cli reads NETBOX_URL and NETBOX_TOKEN from the environment, which the
# .bashrc of bash_aliases.d exports with the token from the keyring; a shell
# started before the dotfiles has neither, so they are set here for this run
setup_netbox() {
    local block="${HOME}/workspace/dgrieser/bash_aliases.d/home/blocks/.bashrc"
    local url token
    netbox-cli get clusters -oname > /dev/null 2>&1 && return 0
    info "netbox-cli is not set up, it names the clusters and fetches their kubeconfigs"
    ask "Set up netbox-cli now (NETBOX_URL and NETBOX_TOKEN)?" || return 1

    url="${NETBOX_URL}"
    [ -z "${url}" ] && [ -f "${block}" ] \
        && url="$(sed -n 's/^export NETBOX_URL="\(.*\)"$/\1/p' "${block}" | head -n 1)"
    url="$(prompt_run prompt-input --prompt "NetBox URL:" --default "${url}")"
    [ -z "${url}" ] && return 1

    token="$(secret-tool lookup type dotfile-secret name NETBOX_TOKEN 2>/dev/null)"
    if [ -z "${token}" ]; then
        token="$(prompt_run prompt-input --protected --prompt "NetBox API token:")"
        [ -z "${token}" ] && return 1
        # stored where the dotfiles look for it, so the next shell has it too
        if printf '%s' "${token}" | secret-tool store --label="dotfile NETBOX_TOKEN" \
            type dotfile-secret name NETBOX_TOKEN; then
            install_dotfiles
        else
            warning "Could not store NETBOX_TOKEN in the keyring, it is only set for this run"
        fi
    fi

    export NETBOX_URL="${url}" NETBOX_TOKEN="${token}"
    # its error stays visible: a missing VPN or CA shows up as an SSL error
    netbox-cli get clusters -oname > /dev/null && return 0
    warning "netbox-cli still cannot reach ${url}"
    return 1
}

# a kubeconfig for every cluster NetBox knows, through k-ctx add of
# kubectl-helpers; a cluster with a kubeconfig in ~/.kube already is kept
setup_kubeconfigs() {
    local tool cluster
    local -a existing
    local -a missing=() clusters=()
    for tool in k-ctx kubectl kubelogin yq jq netbox-cli; do
        command -v "${tool}" > /dev/null 2>&1 || missing+=("${tool}")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        # only worth saying when the kubectl-helpers are there at all
        command -v k-ctx > /dev/null 2>&1 \
            && warning "Skipping the kubeconfigs, missing: ${missing[*]} (the k8s and mw categories)"
        return 0
    fi
    info "Kubeconfigs: fetch one for every cluster NetBox knows (k-ctx add)"
    if ! setup_netbox; then
        failed+=("netbox-cli setup, no kubeconfigs")
        return 0
    fi

    while IFS= read -r cluster; do
        [ -z "${cluster}" ] && continue
        existing=("${HOME}/.kube/${cluster,,}-m3-"*.config)
        [ -e "${existing[0]}" ] && continue
        clusters+=("${cluster}")
    done < <(netbox-cli get clusters -oname 2>/dev/null | sort -u)
    if [ "${#clusters[@]}" -eq 0 ]; then
        echo "Every cluster has a kubeconfig in ${HOME}/.kube" 1>&2
        return 0
    fi

    echo "${clusters[*]}" 1>&2
    ask "Fetch the kubeconfigs of these ${#clusters[@]} clusters?" || return 0
    for cluster in "${clusters[@]}"; do
        run k-ctx add --yes "${cluster}" || failed+=("k-ctx add ${cluster}")
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

trap abort INT
[ "$(id -u)" -eq 0 ] && fail "Run ${APP_NAME} as your user, it asks for sudo itself"
[ -t 0 ] || fail "Run ${APP_NAME} in a terminal, it asks questions"
command -v python3 > /dev/null 2>&1 || fail "python3 is required for the prompts"

MAKE_SUDO=""
BACKUP_DIR=""
info "Setting up this machine from ${REPO_DIR}"
bootstrap
choose_backup
setup_keyring
setup_dirs
install_cli_helpers
# gen needs the prompts, vpn-up and wifi of cli-helpers
restore_bin
setup_vpn
install_gh_glab
restore_sublime

info "Installing base"
# firmware updates are not part of setting up the software
run_updater base --exclude firmware
restore_keys_history
install_dotfiles
restore_reminders
restore_kube_mittwald
restore_downloads
restore_agents
restore_git

check_categories
select_categories
if [ "${#selected[@]}" -gt 0 ]; then
    info "Installing ${selected[*]}"
    run_updater "${selected[@]}"
fi
login_agents

hash -r
setup_k_ctx_shell
setup_kubeconfigs
set_default_browser
gnome_settings

# new GNOME extensions and group memberships (docker) only apply to a new session
info "Log out and back in, so new GNOME extensions and groups take effect"
finish
