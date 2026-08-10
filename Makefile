PREFIX ?= /usr/local
DESTDIR ?=

BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/cli-helpers
# /etc/profile.d/python.sh puts this directory on PYTHONPATH
PYTHONDIR ?= $(PREFIX)/lib/python3/dist-packages
COMPLETIONSDIR ?= $(PREFIX)/share/bash-completion/completions
COMPLETION := bash_completion/cli-helpers
ENABLE_GNOME_EXTENSION ?= 1
UPDATE_ARGS ?=

EXTENSION_UUID := cli-helpers-window-bridge@dgrieser.de
EXTENSION_DIR := gnome-shell-extension/$(EXTENSION_UUID)
EXTENSION_ZIP ?= /tmp/$(EXTENSION_UUID).shell-extension.zip
SHAREDDIR := lib/cli-helpers
SHARED := lib-desktop gnome-clipboard-bridge gnome-display-config gnome-window-bridge
# commands that are also importable Python modules: they get installed a second
# time as <name>.py into $(PYTHONDIR), so other tools can import them instead of
# piping through them
MODULES := toage
SCRIPTS := $(shell find . -maxdepth 1 -type f -perm /111 -printf '%f\n' | sort)
LINKS := $(shell find . -maxdepth 1 -type l -printf '%f\n' | sort)

REPO_DIR := $(CURDIR)

.PHONY: list update install install-links extension-zip install-gnome-extension install-completions install-completions-links uninstall list-install

list:
	@printf 'Available targets:\n'
	@printf '  make list                     Show this help and available commands\n'
	@printf '  make list-install             Show install destinations and installed files\n'
	@printf '  make extension-zip            Package the GNOME extension\n'
	@printf '  make update                   Run updater (pass options with UPDATE_ARGS="...")\n'
	@printf '  make install-gnome-extension  Install the packaged GNOME extension\n'
	@printf '  sudo make install-completions Install bash completion for all commands\n'
	@printf '  sudo make install             Install commands, shared helpers, and GNOME extension\n'
	@printf '  sudo make install-links       Install as symlinks back to this repo (no file copy)\n'
	@printf '  sudo make uninstall           Remove installed files\n'
	@printf '\nAvailable commands:\n'
	@printf '%s\n' $(SCRIPTS) $(LINKS) | sed 's/^/  /'

update:
	./updater $(UPDATE_ARGS)

install:
	for dir in "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(PYTHONDIR)"; do \
		[ -d "$$dir" ] || mkdir -p "$$dir"; \
	done
	for script in $(SCRIPTS); do \
		install -m 0755 "$$script" "$(DESTDIR)$(BINDIR)/$$script"; \
		sed -i 's#/usr/local/lib/cli-helpers#$(LIBDIR)#g' "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		install -m 0755 "$(SHAREDDIR)/$$shared" "$(DESTDIR)$(LIBDIR)/$$shared"; \
	done
	for module in $(MODULES); do \
		install -m 0644 "$$module" "$(DESTDIR)$(PYTHONDIR)/$$module.py"; \
		rm -f "$(DESTDIR)$(PYTHONDIR)/__pycache__/$$module".*.pyc; \
	done
	sed -i 's#/usr/local/share/gnome-shell/extensions#$(HOME)/.local/share/gnome-shell/extensions#g' "$(DESTDIR)$(LIBDIR)/gnome-window-bridge"
	$(MAKE) install-gnome-extension
	$(MAKE) install-completions
	for link in $(LINKS); do \
		target="$$(readlink "$$link")"; \
		ln -sfn "$$target" "$(DESTDIR)$(BINDIR)/$$link"; \
	done
	if [ -z "$(DESTDIR)" ] && [ "$(ENABLE_GNOME_EXTENSION)" != "0" ]; then \
		if command -v gnome-extensions >/dev/null 2>&1; then \
			gnome-extensions enable "$(EXTENSION_UUID)" || \
				echo "WARNING: Could not enable $(EXTENSION_UUID). You may need to restart GNOME Shell or run: gnome-extensions enable $(EXTENSION_UUID)" 1>&2; \
		else \
			echo "WARNING: gnome-extensions not found; enable $(EXTENSION_UUID) manually after install." 1>&2; \
		fi; \
	else \
		echo "Skipping GNOME extension enable step."; \
	fi

install-links:
	for dir in "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(PYTHONDIR)"; do \
		[ -d "$$dir" ] || mkdir -p "$$dir"; \
	done
	for script in $(SCRIPTS); do \
		ln -sfn "$(REPO_DIR)/$$script" "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		ln -sfn "$(REPO_DIR)/$(SHAREDDIR)/$$shared" "$(DESTDIR)$(LIBDIR)/$$shared"; \
	done
	for module in $(MODULES); do \
		ln -sfn "$(REPO_DIR)/$$module" "$(DESTDIR)$(PYTHONDIR)/$$module.py"; \
		rm -f "$(DESTDIR)$(PYTHONDIR)/__pycache__/$$module".*.pyc; \
	done
	$(MAKE) install-gnome-extension
	$(MAKE) install-completions-links
	for link in $(LINKS); do \
		ln -sfn "$(REPO_DIR)/$$link" "$(DESTDIR)$(BINDIR)/$$link"; \
	done
	if [ -z "$(DESTDIR)" ] && [ "$(ENABLE_GNOME_EXTENSION)" != "0" ]; then \
		if command -v gnome-extensions >/dev/null 2>&1; then \
			gnome-extensions enable "$(EXTENSION_UUID)" || \
				echo "WARNING: Could not enable $(EXTENSION_UUID). You may need to restart GNOME Shell or run: gnome-extensions enable $(EXTENSION_UUID)" 1>&2; \
		else \
			echo "WARNING: gnome-extensions not found; enable $(EXTENSION_UUID) manually after install." 1>&2; \
		fi; \
	else \
		echo "Skipping GNOME extension enable step."; \
	fi

extension-zip:
	rm -f "$(EXTENSION_ZIP)"
	cd "$(EXTENSION_DIR)" && zip -r "$(EXTENSION_ZIP)" .

install-gnome-extension: extension-zip
	gnome-extensions install --force "$(EXTENSION_ZIP)"

install-completions:
	[ -d "$(DESTDIR)$(COMPLETIONSDIR)" ] || mkdir -p "$(DESTDIR)$(COMPLETIONSDIR)"
	install -m 0644 "$(COMPLETION)" "$(DESTDIR)$(COMPLETIONSDIR)/cli-helpers"
	for name in $(SCRIPTS) $(LINKS); do \
		if [ -e "/usr/share/bash-completion/completions/$$name" ]; then \
			echo "Skipping completion for $$name (system completion exists)"; \
			continue; \
		fi; \
		ln -sfn cli-helpers "$(DESTDIR)$(COMPLETIONSDIR)/$$name"; \
	done

install-completions-links:
	[ -d "$(DESTDIR)$(COMPLETIONSDIR)" ] || mkdir -p "$(DESTDIR)$(COMPLETIONSDIR)"
	ln -sfn "$(REPO_DIR)/$(COMPLETION)" "$(DESTDIR)$(COMPLETIONSDIR)/cli-helpers"
	for name in $(SCRIPTS) $(LINKS); do \
		if [ -e "/usr/share/bash-completion/completions/$$name" ]; then \
			echo "Skipping completion for $$name (system completion exists)"; \
			continue; \
		fi; \
		ln -sfn "$(REPO_DIR)/$(COMPLETION)" "$(DESTDIR)$(COMPLETIONSDIR)/$$name"; \
	done

uninstall:
	for script in $(SCRIPTS) $(LINKS); do \
		rm -f "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		rm -f "$(DESTDIR)$(LIBDIR)/$$shared"; \
	done
	rmdir "$(DESTDIR)$(LIBDIR)" 2>/dev/null || true
	for module in $(MODULES); do \
		rm -f "$(DESTDIR)$(PYTHONDIR)/$$module.py"; \
		rm -f "$(DESTDIR)$(PYTHONDIR)/__pycache__/$$module".*.pyc; \
	done
	for name in $(SCRIPTS) $(LINKS); do \
		target="$(DESTDIR)$(COMPLETIONSDIR)/$$name"; \
		case "$$([ -L "$$target" ] && readlink "$$target")" in \
			*cli-helpers) rm -f "$$target";; \
		esac; \
	done
	rm -f "$(DESTDIR)$(COMPLETIONSDIR)/cli-helpers"
	gnome-extensions uninstall "$(EXTENSION_UUID)" || true

list-install:
	@printf 'Scripts -> %s\n' "$(DESTDIR)$(BINDIR)"
	@printf '%s\n' $(SCRIPTS) $(LINKS) | sed 's/^/  /'
	@printf 'Shared -> %s\n' "$(DESTDIR)$(LIBDIR)"
	@printf '%s\n' $(SHARED) | sed 's#^#  $(SHAREDDIR)/#'
	@printf 'Python modules -> %s\n' "$(DESTDIR)$(PYTHONDIR)"
	@printf '%s\n' $(MODULES) | sed 's#^#  #;s#$$#.py#'
	@printf 'GNOME extension -> gnome-extensions install --force %s\n' "$(EXTENSION_ZIP)"
	@printf 'Bash completion -> %s\n' "$(DESTDIR)$(COMPLETIONSDIR)"
	@printf '  %s (one symlink per command)\n' "$(COMPLETION)"
