PREFIX ?= /usr/local
DESTDIR ?=

BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/cli-helpers
COMPLETIONSDIR ?= $(PREFIX)/share/bash-completion/completions
COMPLETION := bash_completion/cli-helpers
ENABLE_GNOME_EXTENSION ?= 1

EXTENSION_UUID := cli-helpers-window-bridge@dgrieser.de
EXTENSION_DIR := gnome-shell-extension/$(EXTENSION_UUID)
EXTENSION_ZIP ?= /tmp/$(EXTENSION_UUID).shell-extension.zip
SHAREDDIR := lib/cli-helpers
SHARED := lib-desktop gnome-clipboard-bridge gnome-display-config gnome-window-bridge
SCRIPTS := $(shell find . -maxdepth 1 -type f -perm /111 -printf '%f\n' | sort)
LINKS := $(shell find . -maxdepth 1 -type l -printf '%f\n' | sort)

REPO_DIR := $(CURDIR)

.PHONY: list install install-links extension-zip install-gnome-extension install-completions install-completions-links uninstall list-install

list:
	@printf 'Available targets:\n'
	@printf '  make list                     Show this help and available commands\n'
	@printf '  make list-install             Show install destinations and installed files\n'
	@printf '  make extension-zip            Package the GNOME extension\n'
	@printf '  make install-gnome-extension  Install the packaged GNOME extension\n'
	@printf '  sudo make install-completions Install bash completion for all commands\n'
	@printf '  sudo make install             Install commands, shared helpers, and GNOME extension\n'
	@printf '  sudo make install-links       Install as symlinks back to this repo (no file copy)\n'
	@printf '  sudo make uninstall           Remove installed files\n'
	@printf '\nAvailable commands:\n'
	@printf '%s\n' $(SCRIPTS) $(LINKS) | sed 's/^/  /'

install:
	for dir in "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)"; do \
		[ -d "$$dir" ] || mkdir -p "$$dir"; \
	done
	for script in $(SCRIPTS); do \
		install -m 0755 "$$script" "$(DESTDIR)$(BINDIR)/$$script"; \
		sed -i 's#/usr/local/lib/cli-helpers#$(LIBDIR)#g' "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		install -m 0755 "$(SHAREDDIR)/$$shared" "$(DESTDIR)$(LIBDIR)/$$shared"; \
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
	for dir in "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)"; do \
		[ -d "$$dir" ] || mkdir -p "$$dir"; \
	done
	for script in $(SCRIPTS); do \
		ln -sfn "$(REPO_DIR)/$$script" "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		ln -sfn "$(REPO_DIR)/$(SHAREDDIR)/$$shared" "$(DESTDIR)$(LIBDIR)/$$shared"; \
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
	@printf 'GNOME extension -> gnome-extensions install --force %s\n' "$(EXTENSION_ZIP)"
	@printf 'Bash completion -> %s\n' "$(DESTDIR)$(COMPLETIONSDIR)"
	@printf '  %s (one symlink per command)\n' "$(COMPLETION)"
