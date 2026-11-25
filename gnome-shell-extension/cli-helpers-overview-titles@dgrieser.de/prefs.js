import Adw from 'gi://Adw';
import Gdk from 'gi://Gdk';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import Pango from 'gi://Pango';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const POSITIONS = [['top', 'Top'], ['center', 'Center'], ['bottom', 'Bottom']];

function sizeRow(settings, key, title, subtitle) {
    const range = settings.settings_schema.get_key(key).get_range().recursiveUnpack()[1];
    const row = Adw.SpinRow.new_with_range(range[0], range[1], 1);
    row.set({title, subtitle});
    settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT);
    return row;
}

function fontRow(settings) {
    const button = new Gtk.FontDialogButton({
        dialog: new Gtk.FontDialog({title: 'Title Font'}),
        level: Gtk.FontLevel.FAMILY,
        valign: Gtk.Align.CENTER,
    });
    const load = () => {
        button.font_desc = Pango.FontDescription.from_string(settings.get_string('font-family'));
    };
    load();
    button.connect('notify::font-desc', () => {
        const family = button.font_desc?.get_family();
        if (family && family !== settings.get_string('font-family'))
            settings.set_string('font-family', family);
    });
    settings.connect('changed::font-family', load);

    const row = new Adw.ActionRow({title: 'Font', activatable_widget: button});
    row.add_suffix(button);
    return row;
}

function colorRow(settings, key, title) {
    const button = new Gtk.ColorDialogButton({
        dialog: new Gtk.ColorDialog({title, with_alpha: true}),
        valign: Gtk.Align.CENTER,
    });
    const load = () => {
        const rgba = new Gdk.RGBA();
        if (rgba.parse(settings.get_string(key)))
            button.rgba = rgba;
    };
    load();
    button.connect('notify::rgba', () => {
        const value = button.rgba.to_string();
        if (value !== settings.get_string(key))
            settings.set_string(key, value);
    });
    settings.connect(`changed::${key}`, load);

    const row = new Adw.ActionRow({title, activatable_widget: button});
    row.add_suffix(button);
    return row;
}

function positionRow(settings) {
    const row = new Adw.ComboRow({
        title: 'Position',
        subtitle: 'Where the title sits on the window preview',
        model: Gtk.StringList.new(POSITIONS.map(([, label]) => label)),
    });
    const load = () => {
        row.selected = Math.max(0, POSITIONS.findIndex(([value]) => value === settings.get_string('position')));
    };
    load();
    row.connect('notify::selected', () => {
        const [value] = POSITIONS[row.selected] ?? POSITIONS[1];
        if (value !== settings.get_string('position'))
            settings.set_string('position', value);
    });
    settings.connect('changed::position', load);
    return row;
}

export default class OverviewTitlesPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        window._settings = settings;

        const page = new Adw.PreferencesPage({title: 'Appearance', icon_name: 'preferences-desktop-appearance-symbolic'});

        const text = new Adw.PreferencesGroup({title: 'Text'});
        text.add(fontRow(settings));
        text.add(sizeRow(settings, 'heading-font-size', 'First Line Size', 'App name or running command, in pixels'));
        text.add(sizeRow(settings, 'body-font-size', 'Second Line Size', 'Window title, in pixels'));
        text.add(colorRow(settings, 'text-color', 'Text Color'));
        page.add(text);

        const box = new Adw.PreferencesGroup({title: 'Box'});
        box.add(colorRow(settings, 'background-color', 'Background Color'));
        box.add(sizeRow(settings, 'corner-radius', 'Corner Radius', 'In pixels'));
        box.add(positionRow(settings));
        page.add(box);

        const reset = new Adw.PreferencesGroup();
        const button = new Gtk.Button({label: 'Reset to Defaults', halign: Gtk.Align.CENTER});
        button.add_css_class('pill');
        button.connect('clicked', () => {
            for (const key of settings.settings_schema.list_keys())
                settings.reset(key);
        });
        reset.add(button);
        page.add(reset);

        window.add(page);
    }
}
