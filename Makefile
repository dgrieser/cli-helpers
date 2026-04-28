PREFIX ?= /usr/local
DESTDIR ?=

BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/cli-helpers
GNOME_EXTENSIONS_DIR ?= $(HOME)/.local/share/gnome-shell/extensions
ENABLE_GNOME_EXTENSION ?= 1

EXTENSION_UUID := cli-helpers-window-bridge@dgrieser.de
SHAREDDIR := lib/cli-helpers
SHARED := lib-desktop gnome-display-config gnome-window-bridge
SCRIPTS := $(shell find . -maxdepth 1 -type f -perm /111 -printf '%f\n' | sort)
LINKS := $(shell find . -maxdepth 1 -type l -printf '%f\n' | sort)

.PHONY: list install uninstall list-install

list:
	@printf 'Available targets:\n'
	@printf '  make list          Show this help and available commands\n'
	@printf '  make list-install  Show install destinations and installed files\n'
	@printf '  sudo make install  Install commands, shared helpers, and GNOME extension\n'
	@printf '  sudo make uninstall  Remove installed files\n'
	@printf '\nAvailable commands:\n'
	@printf '%s\n' $(SCRIPTS) $(LINKS) | sed 's/^/  /'

install:
	install -d "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(GNOME_EXTENSIONS_DIR)/$(EXTENSION_UUID)"
	for script in $(SCRIPTS); do \
		install -m 0755 "$$script" "$(DESTDIR)$(BINDIR)/$$script"; \
		sed -i 's#/usr/local/lib/cli-helpers#$(LIBDIR)#g' "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		install -m 0755 "$(SHAREDDIR)/$$shared" "$(DESTDIR)$(LIBDIR)/$$shared"; \
	done
	sed -i 's#/usr/local/share/gnome-shell/extensions#$(GNOME_EXTENSIONS_DIR)#g' "$(DESTDIR)$(LIBDIR)/gnome-window-bridge"
	cp -a "gnome-shell-extension/$(EXTENSION_UUID)/." "$(DESTDIR)$(GNOME_EXTENSIONS_DIR)/$(EXTENSION_UUID)/"
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

uninstall:
	for script in $(SCRIPTS) $(LINKS); do \
		rm -f "$(DESTDIR)$(BINDIR)/$$script"; \
	done
	for shared in $(SHARED); do \
		rm -f "$(DESTDIR)$(LIBDIR)/$$shared"; \
	done
	rmdir "$(DESTDIR)$(LIBDIR)" 2>/dev/null || true
	rm -rf "$(DESTDIR)$(GNOME_EXTENSIONS_DIR)/$(EXTENSION_UUID)"

list-install:
	@printf 'Scripts -> %s\n' "$(DESTDIR)$(BINDIR)"
	@printf '%s\n' $(SCRIPTS) $(LINKS) | sed 's/^/  /'
	@printf 'Shared -> %s\n' "$(DESTDIR)$(LIBDIR)"
	@printf '%s\n' $(SHARED) | sed 's#^#  $(SHAREDDIR)/#'
	@printf 'GNOME extension -> %s\n' "$(DESTDIR)$(GNOME_EXTENSIONS_DIR)/$(EXTENSION_UUID)"
