#!/bin/bash
# Sets up a new machine from this repo: the keyring from a backup with its SSH
# keys, SSH config and network connections, the install folders, cli-helpers itself,
# the base software, gh and glab with their logins, the dotfiles of
# bash_aliases.d (asking for missing SSH keys and history backups), the reminders
# of reminder from a backup, the categories of updater
# the user picks, the k-ctx shell shorthands, netbox-cli and a kubeconfig per
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
    [ "${#packages[@]}" -eq 0 ] && return 0
    info "Installing what the Makefile needs: ${packages[*]}"
    run sudo apt-get update -q && run sudo apt-get install -y "${packages[@]}" \
        || fail "Failed to install ${packages[*]}"
}

# the keyring of the old machine: a backup of its keyring files is imported into
# the login keyring, early, so the logins and tokens in it are there for the
# later steps; then the SSH keys and network connections (e.g. the Mittwald
# wifi and VPN) stored in the keyring with keyring-cli are restored
setup_keyring() {
    local keyring_cli="${REPO_DIR}/keyring-cli"
    local packages=() package path file name type
    local -a files names
    info "Keyring: import a backup of the old keyring files (~/.local/share/keyrings/*.keyring), then restore the SSH keys, the SSH config and the network connections stored in the keyring"
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

    if ask "Import a keyring backup?"; then
        path="$("${REPO_DIR}/prompt-file" "Keyring file or folder:")"
        path="${path/#\~/${HOME}}"
        if [ -d "${path}" ]; then
            mapfile -t files < <(find "${path}" -maxdepth 1 -type f -name '*.keyring' | sort)
            [ "${#files[@]}" -eq 0 ] && warning "No *.keyring files in ${path}"
        elif [ -n "${path}" ]; then
            files=("${path}")
        fi
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

# the dotfiles of bash_aliases.d once more, now with a terminal: updater installed
# them without one, so it skipped the questions for a missing SSH key in the
# documents folder and for the backups of the shell histories
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

# the reminders of the reminder tool from a backup: a copy of ~/.cache/reminder
# as a folder, or that folder in a .tar.gz, .tgz or .zip; a reminder that is
# here already is kept, and so is the display order
restore_reminders() {
    local dir="${HOME}/.cache/reminder"
    local path src tmp file name
    info "Reminders: restore a backup of ${dir} (the *.md reminders, the done ones and their order)"
    ask "Import a backup of the reminders?" || return 0
    path="$("${REPO_DIR}/prompt-file" "Reminder folder or archive:")"
    path="${path/#\~/${HOME}}"
    [ -z "${path}" ] && return 0

    if [ -d "${path}" ]; then
        src="${path}"
    elif [ -f "${path}" ]; then
        tmp="$(mktemp -d)" || { failed+=("reminders ${path}"); return 0; }
        case "${path}" in
            *.tar.gz|*.tgz) tar -xzf "${path}" -C "${tmp}" ;;
            *.zip)          command -v unzip > /dev/null 2>&1 || run sudo apt-get install -y unzip
                            unzip -q "${path}" -d "${tmp}" ;;
            *)              warning "Not a folder, .tar.gz, .tgz or .zip: ${path}"; false ;;
        esac || { rm -rf "${tmp}"; failed+=("reminders ${path}"); return 0; }
        # the archive may hold the folder itself or only what is in it
        src="$(find "${tmp}" \( -name '*.md' -o -name '*.md_*' -o -name .order \) -type f \
            -printf '%h\n' | sort | head -n 1)"
    else
        warning "No such file or folder: ${path}"
        failed+=("reminders ${path}")
        return 0
    fi

    if [ -z "${src}" ] || ! compgen -G "${src}/*.md*" > /dev/null; then
        warning "No reminders in ${path}"
        failed+=("reminders ${path}")
    else
        mkdir -p "${dir}"
        for file in "${src}"/*.md "${src}"/*.md_* "${src}/.order"; do
            [ -f "${file}" ] || continue
            name="$(basename "${file}")"
            if [ -e "${dir}/${name}" ]; then
                echo "Kept ${dir}/${name}" 1>&2
                continue
            fi
            # the reminders without an order are listed by their modification time
            cp -p "${file}" "${dir}/${name}" || failed+=("reminders ${name}")
        done
        echo "Restored the reminders to ${dir}" 1>&2
    fi
    [ -n "${tmp}" ] && rm -rf "${tmp}"
    return 0
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
    url="$("${REPO_DIR}/prompt-input" --prompt "NetBox URL:" --default "${url}")"
    [ -z "${url}" ] && return 1

    token="$(secret-tool lookup type dotfile-secret name NETBOX_TOKEN 2>/dev/null)"
    if [ -z "${token}" ]; then
        token="$("${REPO_DIR}/prompt-input" --protected --prompt "NetBox API token:")"
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

[ "$(id -u)" -eq 0 ] && fail "Run ${APP_NAME} as your user, it asks for sudo itself"
[ -t 0 ] || fail "Run ${APP_NAME} in a terminal, it asks questions"
command -v python3 > /dev/null 2>&1 || fail "python3 is required for the prompts"

MAKE_SUDO=""
info "Setting up this machine from ${REPO_DIR}"
bootstrap
setup_keyring
setup_dirs
install_cli_helpers
install_gh_glab

info "Installing base"
# firmware updates are not part of setting up the software
run_updater base --exclude firmware
install_dotfiles
restore_reminders

check_categories
select_categories
if [ "${#selected[@]}" -gt 0 ]; then
    info "Installing ${selected[*]}"
    run_updater "${selected[@]}"
fi

hash -r
setup_k_ctx_shell
setup_kubeconfigs
set_default_browser
gnome_settings

# new GNOME extensions and group memberships (docker) only apply to a new session
info "Log out and back in, so new GNOME extensions and groups take effect"
finish
