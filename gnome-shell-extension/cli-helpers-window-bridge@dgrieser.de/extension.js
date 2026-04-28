import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const BUS_NAME = 'de.dgrieser.CliHelpers.WindowBridge';
const OBJECT_PATH = '/de/dgrieser/CliHelpers/WindowBridge';

const IFACE_XML = `
<node>
  <interface name="de.dgrieser.CliHelpers.WindowBridge">
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
  </interface>
</node>`;

function monitorName(index) {
    const monitor = Main.layoutManager.monitors[index];
    if (!monitor)
        return '';

    return monitor.connector || monitor.name || `${monitor.x},${monitor.y}`;
}

function windowId(window) {
    return String(window.get_id());
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
        workspace: workspace ? workspace.index() : -1,
        monitor: monitorName(window.get_monitor()),
        x: frame.x,
        y: frame.y,
        width: frame.width,
        height: frame.height,
    };
}

export default class CliHelpersWindowBridgeExtension extends Extension {
    enable() {
        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(IFACE_XML, this);
        this._dbusImpl.export(Gio.DBus.session, OBJECT_PATH);
        this._busId = Gio.bus_own_name(
            Gio.BusType.SESSION,
            BUS_NAME,
            Gio.BusNameOwnerFlags.REPLACE,
            null,
            null
        );
    }

    disable() {
        if (this._busId) {
            Gio.bus_unown_name(this._busId);
            this._busId = null;
        }
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }
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

        Main.activateWindow(window, global.get_current_time());
        return true;
    }

    GetPointerMonitor() {
        const [x, y] = global.get_pointer();
        for (const monitor of Main.layoutManager.monitors) {
            if (x >= monitor.x && x < monitor.x + monitor.width &&
                y >= monitor.y && y < monitor.y + monitor.height)
                return monitor.connector || monitor.name || '';
        }
        return '';
    }

    GetActiveWindowMonitor() {
        const window = global.display.get_focus_window();
        return window ? monitorName(window.get_monitor()) : '';
    }
}
