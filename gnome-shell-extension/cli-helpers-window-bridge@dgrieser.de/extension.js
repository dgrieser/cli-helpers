import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const BUS_NAME = 'de.david.grieser.CliHelpers.WindowBridge';
const OBJECT_PATH = '/de/david/grieser/CliHelpers/WindowBridge';

const IFACE_XML = `
<node>
  <interface name="de.david.grieser.CliHelpers.WindowBridge">
    <method name="ListWindows">
      <arg type="s" direction="out" name="windows_json"/>
    </method>
    <method name="GetActiveWindow">
      <arg type="s" direction="out" name="window_id"/>
    </method>
    <method name="FocusWindow">
      <arg type="s" direction="in" name="window_id"/>
      <arg type="b" direction="out" name="focused"/>
    </method>
    <method name="GetPointerMonitor">
      <arg type="s" direction="out" name="monitor"/>
    </method>
    <method name="GetActiveWindowMonitor">
      <arg type="s" direction="out" name="monitor"/>
    </method>
    <method name="SetClipboardText">
      <arg type="s" direction="in" name="selection"/>
      <arg type="s" direction="in" name="text"/>
      <arg type="b" direction="out" name="copied"/>
    </method>
    <method name="GetClipboardText">
      <arg type="s" direction="in" name="selection"/>
      <arg type="s" direction="out" name="text"/>
    </method>
    <method name="ClearClipboard">
      <arg type="s" direction="in" name="selection"/>
      <arg type="b" direction="out" name="cleared"/>
    </method>
    <method name="SetWindowAbove">
      <arg type="s" direction="in" name="window_id"/>
      <arg type="b" direction="out" name="set"/>
    </method>
    <method name="SetWindowGeometry">
      <arg type="s" direction="in" name="window_id"/>
      <arg type="i" direction="in" name="x"/>
      <arg type="i" direction="in" name="y"/>
      <arg type="i" direction="in" name="width"/>
      <arg type="i" direction="in" name="height"/>
      <arg type="b" direction="out" name="set"/>
    </method>
    <method name="CloseWindow">
      <arg type="s" direction="in" name="window_id"/>
      <arg type="b" direction="out" name="closed"/>
    </method>
    <method name="SetWindowLabel">
      <arg type="s" direction="in" name="window_id"/>
      <arg type="s" direction="in" name="text"/>
      <arg type="b" direction="out" name="set"/>
    </method>
    <signal name="ClipboardChanged">
      <arg type="s" name="selection"/>
      <arg type="b" name="sensitive"/>
    </signal>
  </interface>
</node>`;

// Shell monitor objects carry no connector name of their own on current GNOME
// versions, so ask Mutter for it and only fall back to coordinates when even
// that stays silent.
function connectorForMonitorIndex(index) {
    let manager = null;

    try {
        manager = global.backend?.get_monitor_manager?.() ?? null;
        // GNOME Shell before 45 reached the backend through Meta.
        if (!manager && typeof Meta.get_backend === 'function')
            manager = Meta.get_backend()?.get_monitor_manager?.() ?? null;
    } catch (error) {
        manager = null;
    }
    if (!manager)
        return '';

    // Mutter maps a connector to the same monitor index the shell uses, so this
    // needs no assumption about the order of the monitor list.
    try {
        if (typeof manager.get_monitor_for_connector === 'function') {
            for (const monitor of manager.get_monitors?.() ?? []) {
                const connector = monitor.get_connector?.();
                if (!connector)
                    continue;
                if (manager.get_monitor_for_connector(connector) === index)
                    return connector;
            }
        }
    } catch (error) {
        // fall through to the remaining strategies
    }

    // Logical monitors are numbered like the shell indexes them.
    try {
        for (const logicalMonitor of manager.get_logical_monitors?.() ?? []) {
            if (logicalMonitor.get_number?.() !== index)
                continue;
            for (const monitor of logicalMonitor.get_monitors?.() ?? []) {
                const connector = monitor.get_connector?.();
                if (connector)
                    return connector;
            }
        }
    } catch (error) {
        // fall through to the remaining strategies
    }

    // Last resort: the flat list of active monitors, in index order.
    try {
        const monitors = (manager.get_monitors?.() ?? [])
            .filter(monitor => monitor.is_active?.() ?? true);
        const connector = monitors[index]?.get_connector?.();
        if (connector)
            return connector;
    } catch (error) {
        // fall through to the coordinate fallback
    }

    return '';
}

function monitorName(index) {
    const monitor = Main.layoutManager.monitors[index];
    if (!monitor)
        return '';

    return monitor.connector ||
        monitor.name ||
        connectorForMonitorIndex(index) ||
        `${monitor.x},${monitor.y}`;
}

// The monitors in a file, rewritten whenever they change, so a script knows their
// geometry instantly instead of asking Mutter's DisplayConfig, which takes Python a
// tenth of a second: "pid <gnome-shell>", then per monitor
// "<connector> <x> <y> <width> <height> <scale>" in logical pixels, the lines of
// gnome-display-config list --geometry. It is only valid while that gnome-shell
// runs, and it is removed when the extension is disabled (on the lock screen as
// well), so a reader never gets a stale one.
const MONITORS_FILE = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'cli-helpers', 'monitors']);

function writeMonitors() {
    const lines = [`pid ${Gio.Credentials.new().get_unix_pid()}`];
    Main.layoutManager.monitors.forEach((monitor, index) => {
        // the scale like Python's %g, as gnome-display-config prints it
        const scale = Number(global.display.get_monitor_scale(index).toPrecision(6));
        lines.push(`${monitorName(index)} ${monitor.x} ${monitor.y} ${monitor.width} ${monitor.height} ${scale}`);
    });
    try {
        GLib.mkdir_with_parents(GLib.path_get_dirname(MONITORS_FILE), 0o700);
        GLib.file_set_contents(MONITORS_FILE, `${lines.join('\n')}\n`);
    } catch (error) {
        console.warn(`cli-helpers: cannot write ${MONITORS_FILE}: ${error.message}`);
    }
}

function windowId(window) {
    return String(window.get_id());
}

// A D-Bus call carries no input event, so the shell's current event time is
// usually 0. Mutter treats that as "older than the last user interaction" and
// answers an activation request with a demands-attention flag instead of focus,
// so ask the display for a fresh timestamp whenever no event time is available.
function currentTime() {
    const time = global.get_current_time();
    if (time !== 0)
        return time;

    try {
        return global.display.get_current_time_roundtrip();
    } catch (error) {
        return 0;
    }
}

// make_above() only moves a window into the "above" layer, it does not restack
// it inside that layer, so a window that is already kept on top (a browser with
// "Always on Top", for example) stays in front of it. Raising afterwards puts
// the window at the top of its own layer.
function raiseWindow(window) {
    const workspace = window.get_workspace();
    if (workspace && typeof window.raise_and_make_recent_on_workspace === 'function') {
        window.raise_and_make_recent_on_workspace(workspace);
        return;
    }
    window.raise();
}

// Mutter dropped meta_window_get_maximized() after GNOME 47, so ask the
// current API first and keep the old call for older shells.
function windowIsMaximized(window) {
    if (typeof window.is_maximized === 'function')
        return window.is_maximized();
    if (typeof window.get_maximized === 'function')
        return window.get_maximized() !== 0;
    return !!(window.maximized_horizontally || window.maximized_vertically);
}

function serializeWindow(window) {
    const frame = window.get_frame_rect();
    const workspace = window.get_workspace();
    const sandboxedAppId = typeof window.get_sandboxed_app_id === 'function'
        ? window.get_sandboxed_app_id()
        : '';
    return {
        id: windowId(window),
        title: window.get_title() || '',
        wm_class: window.get_wm_class() || '',
        sandboxed_app_id: sandboxedAppId || '',
        // the process owning the window, for finding the window of a process
        pid: typeof window.get_pid === 'function' ? window.get_pid() : 0,
        workspace: workspace ? workspace.index() : -1,
        monitor: monitorName(window.get_monitor()),
        x: frame.x,
        y: frame.y,
        width: frame.width,
        height: frame.height,
    };
}

// A badge at the bottom of a window, so windows that look alike (the login
// windows of different identity providers, for example) can be told apart. It
// is a child of the window actor, so it moves, stacks and goes away with the
// window. It lets clicks through.
const LABEL_STYLE = 'background-color: rgba(0, 0, 0, 0.75); color: #ffffff; ' +
    'font-size: 10pt; font-weight: bold; padding: 3px 10px; border-radius: 12px;';
const LABEL_MARGIN = 10;

// The actor covers the whole buffer, which includes the shadows of a
// client-side decorated window, so the label is placed by the frame instead.
function placeWindowLabel(window, label) {
    const frame = window.get_frame_rect();
    const buffer = window.get_buffer_rect();
    const [, , width, height] = label.get_preferred_size();
    label.set_position(
        Math.round(frame.x - buffer.x + (frame.width - width) / 2),
        Math.round(frame.y - buffer.y + frame.height - height - LABEL_MARGIN));
}

function clipboardType(selection) {
    if (selection === 'clipboard')
        return St.ClipboardType.CLIPBOARD;
    if (selection === 'primary')
        return St.ClipboardType.PRIMARY;
    throw new Error(`Invalid clipboard selection: ${selection}`);
}

// A password manager marks the text it copies with this type (KDE's convention,
// which KeePassXC and others follow on every desktop), so a clipboard history
// leaves it out.
const SENSITIVE_MIMETYPE = 'x-kde-passwordManagerHint';

function hasText(mimetypes) {
    return mimetypes.some(type => type.startsWith('text/plain') ||
        type === 'UTF8_STRING' || type === 'STRING' || type === 'TEXT');
}

export default class CliHelpersWindowBridgeExtension extends Extension {
    enable() {
        // the label of each labeled window, by window
        this._labels = new Map();
        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(IFACE_XML, this);
        this._dbusImpl.export(Gio.DBus.session, OBJECT_PATH);
        this._busId = Gio.bus_own_name(
            Gio.BusType.SESSION,
            BUS_NAME,
            Gio.BusNameOwnerFlags.REPLACE,
            null,
            null,
            null
        );
        writeMonitors();
        this._monitorsChangedId = Main.layoutManager.connect('monitors-changed', writeMonitors);
        this._selectionOwnerChangedId = global.display.get_selection().connect('owner-changed',
            (_selection, selectionType, source) => this._clipboardOwnerChanged(selectionType, source));
    }

    disable() {
        if (this._selectionOwnerChangedId) {
            global.display.get_selection().disconnect(this._selectionOwnerChangedId);
            this._selectionOwnerChangedId = null;
        }
        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = null;
        }
        for (const label of this._labels.values())
            label.destroy();
        this._labels.clear();
        GLib.unlink(MONITORS_FILE);
        if (this._busId) {
            Gio.bus_unown_name(this._busId);
            this._busId = null;
        }
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }
    }

    // Every new text in the clipboard, whoever copied it, for clip-history watch
    // to record. Only that it changed is announced, not the text: the watcher
    // asks for it with GetClipboardText. The primary selection changes with
    // every selected word, so it is left out.
    _clipboardOwnerChanged(selectionType, source) {
        if (selectionType !== Meta.SelectionType.SELECTION_CLIPBOARD || !source || !this._dbusImpl)
            return;

        const mimetypes = source.get_mimetypes();
        if (!hasText(mimetypes))
            return;
        this._dbusImpl.emit_signal('ClipboardChanged',
            GLib.Variant.new('(sb)', ['clipboard', mimetypes.includes(SENSITIVE_MIMETYPE)]));
    }

    _windows() {
        return global.display.get_tab_list(Meta.TabList.NORMAL_ALL, null)
            .filter(window => !window.skip_taskbar);
    }

    _findWindow(id) {
        return this._windows().find(window => windowId(window) === id) || null;
    }

    ListWindows() {
        return JSON.stringify(this._windows().map(serializeWindow));
    }

    GetActiveWindow() {
        const window = global.display.get_focus_window();
        return window ? windowId(window) : '';
    }

    FocusWindow(id) {
        const window = this._findWindow(id);
        if (!window)
            return false;

        Main.activateWindow(window, currentTime());
        window.unset_demands_attention();
        raiseWindow(window);
        return true;
    }

    GetPointerMonitor() {
        const [x, y] = global.get_pointer();
        for (let i = 0; i < Main.layoutManager.monitors.length; i++) {
            const monitor = Main.layoutManager.monitors[i];
            if (x >= monitor.x && x < monitor.x + monitor.width &&
                y >= monitor.y && y < monitor.y + monitor.height)
                return monitorName(i);
        }
        return '';
    }

    GetActiveWindowMonitor() {
        const window = global.display.get_focus_window();
        return window ? monitorName(window.get_monitor()) : '';
    }

    SetClipboardText(selection, text) {
        St.Clipboard.get_default().set_text(clipboardType(selection), text);
        return true;
    }

    GetClipboardTextAsync([selection], invocation) {
        try {
            St.Clipboard.get_default().get_text(
                clipboardType(selection),
                (_clipboard, text) => {
                    invocation.return_value(GLib.Variant.new('(s)', [text || '']));
                }
            );
        } catch (error) {
            invocation.return_dbus_error(
                'de.david.grieser.CliHelpers.WindowBridge.Error',
                error.message
            );
        }
    }

    ClearClipboard(selection) {
        St.Clipboard.get_default().set_text(clipboardType(selection), '');
        return true;
    }

    SetWindowAbove(id) {
        const window = this._findWindow(id);
        if (!window)
            return false;
        window.make_above();
        raiseWindow(window);
        return true;
    }

    SetWindowGeometry(id, x, y, width, height) {
        const window = this._findWindow(id);
        if (!window)
            return false;

        if (window.is_fullscreen())
            window.unmake_fullscreen();
        if (windowIsMaximized(window))
            window.unmaximize(Meta.MaximizeFlags.BOTH);
        window.move_resize_frame(true, x, y, width, height);
        return true;
    }

    CloseWindow(id) {
        const window = this._findWindow(id);
        if (!window || !window.can_close())
            return false;
        window.delete(currentTime());
        return true;
    }

    // Replaces the label of the window; an empty text removes it.
    SetWindowLabel(id, text) {
        const window = this._findWindow(id);
        const actor = window?.get_compositor_private();
        if (!actor)
            return false;

        this._labels.get(window)?.destroy();
        if (!text)
            return true;

        const label = new St.Label({text, style: LABEL_STYLE});
        actor.add_child(label);
        this._labels.set(window, label);
        label.connect('destroy', () => {
            if (this._labels.get(window) === label)
                this._labels.delete(window);
        });
        // The buffer follows the frame only after the client has drawn the
        // new size, so the label is placed again on both.
        const place = () => placeWindowLabel(window, label);
        window.connectObject('size-changed', place, label);
        actor.connectObject('notify::size', place, label);
        place();
        return true;
    }
}
