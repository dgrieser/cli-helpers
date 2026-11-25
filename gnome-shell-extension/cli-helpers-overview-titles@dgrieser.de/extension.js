import Clutter from 'gi://Clutter';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';
import {WindowPreview} from 'resource:///org/gnome/shell/ui/windowPreview.js';

// space between the title box and the left and right edges of the preview
const MARGIN = 12;

// terminals put the running command after the title ("Title — claude -r"), and
// the shell's own title when no command runs; lower case, as X11 classes are
// capitalized (Gnome-terminal, Terminator) and Wayland app ids are not
const TERMINAL_CLASSES = new Set([
    'org.gnome.ptyxis',
    'org.gnome.terminal',
    'gnome-terminal',
    'org.gnome.console',
    'kgx',
    'com.mitchellh.ghostty',
    'terminator',
]);
const COMMAND_SEPARATOR = ' — ';
// separators between a title and the app name that apps append to it
const APP_SEPARATORS = [' — ', ' – ', ' - '];
// what apps put in front of the title to show a state: spinners, stars,
// unread marks; symbols only, so a path like ~/workspace stays whole
const LEADING_STATUS = /^[\p{So}*•\s]+/u;

// where the title sits on the preview, by the setting position: the factor of
// its vertical alignment, and its distance from the edge in margins
const POSITIONS = {
    top: {factor: 0, shift: 1},
    center: {factor: 0.5, shift: 0},
    bottom: {factor: 1, shift: -1},
};
// what the color settings accept: #rgb to #rrggbbaa, rgb(...) and rgba(...);
// the settings end up in inline CSS, so anything else falls back to the default
const CSS_COLOR = /^(#[0-9a-f]{3,8}|rgba?\(\s*[\d.]+%?(\s*,\s*[\d.]+%?){2,3}\s*\))$/i;
// what the font family setting accepts: names, spaces, dashes and commas
const FONT_FAMILY = /^[\w\s,-]+$/u;

// The heading and body lines of the title of the window.
export function caption(title, wmClass, appName) {
    let body = (title ?? '').trim().replace(LEADING_STATUS, '').trim();
    let heading = appName ?? '';

    if (TERMINAL_CLASSES.has((wmClass ?? '').toLowerCase())) {
        const at = body.lastIndexOf(COMMAND_SEPARATOR);
        if (at > 0) {
            heading = body.slice(at + COMMAND_SEPARATOR.length).trim().split(/\s+/)[0];
            body = body.slice(0, at).trim();
        } else if (body) {
            heading = body;
            body = '';
        }
    } else if (appName) {
        const separator = APP_SEPARATORS.find(s => body.endsWith(s + appName));
        if (separator)
            body = body.slice(0, -(separator + appName).length).trim();
    }

    if (!heading) {
        heading = body;
        body = '';
    }
    return [heading, body === heading ? '' : body];
}

function windowCaption(metaWindow) {
    const app = Shell.WindowTracker.get_default().get_window_app(metaWindow);
    return caption(metaWindow.get_title(), metaWindow.get_wm_class(), app?.get_name());
}

function setting(settings, key, pattern) {
    const value = settings.get_string(key).trim();
    if (pattern.test(value))
        return value;
    return settings.get_default_value(key).deepUnpack();
}

// The inline styles and the position of the titles, from the settings.
function appearance(settings) {
    const color = setting(settings, 'text-color', CSS_COLOR);
    const family = setting(settings, 'font-family', FONT_FAMILY);
    const text = size => `color: ${color}; font-family: ${family}; font-size: ${size}px;`;
    return {
        box: `background-color: ${setting(settings, 'background-color', CSS_COLOR)}; ` +
            `border-radius: ${settings.get_int('corner-radius')}px;`,
        heading: `${text(settings.get_int('heading-font-size'))} font-weight: bold;`,
        body: text(settings.get_int('body-font-size')),
        position: POSITIONS[settings.get_string('position')] ?? POSITIONS.center,
    };
}

function captionLabel(styleClass) {
    const label = new St.Label({style_class: styleClass, x_align: Clutter.ActorAlign.CENTER});
    label.clutter_text.single_line_mode = true;
    label.clutter_text.ellipsize = Pango.EllipsizeMode.END;
    return label;
}

export default class OverviewTitlesExtension extends Extension {
    enable() {
        this._titles = new Set();
        this._injections = new InjectionManager();
        this._settings = this.getSettings();
        const titles = this._titles;
        const settings = this._settings;

        this._injections.overrideMethod(WindowPreview.prototype, '_init', original => function (...args) {
            original.apply(this, args);
            addTitle(this, titles, settings);
        });

        // the title fades out with the window icon when the overview goes to the app grid
        this._injections.overrideMethod(WindowPreview.prototype, '_updateIconScale', original => function (...args) {
            original.apply(this, args);
            if (this._cliHelpersTitle)
                this._cliHelpersTitle.opacity = Math.round(255 * this._icon.scale_x);
        });

        // the large title replaces the small caption that GNOME shows on hover
        this._injections.overrideMethod(WindowPreview.prototype, 'showOverlay', original => function (...args) {
            original.apply(this, args);
            if (this._cliHelpersTitle)
                this._title.hide();
        });
    }

    disable() {
        this._injections.clear();
        this._injections = null;
        for (const title of this._titles)
            title.destroy();
        this._titles = null;
        this._settings = null;
    }
}

function addTitle(preview, titles, settings) {
    const container = preview.window_container;
    const {scaleFactor} = St.ThemeContext.get_for_stage(global.stage);

    const heading = captionLabel('cli-helpers-overview-title-heading');
    const body = captionLabel('cli-helpers-overview-title-body');
    const box = new St.BoxLayout({
        style_class: 'cli-helpers-overview-title',
        orientation: Clutter.Orientation.VERTICAL,
        x_align: Clutter.ActorAlign.CENTER,
    });
    box.add_child(heading);
    box.add_child(body);

    // The bin spans the preview's width, less the margins, and centers the box
    // in it: the box is as wide as its text, and the text ellipsizes when the
    // preview is narrower.
    const title = new St.Bin({child: box, reactive: false});
    title.add_constraint(new Clutter.BindConstraint({
        source: container,
        coordinate: Clutter.BindCoordinate.POSITION,
    }));
    title.add_constraint(new Clutter.BindConstraint({
        source: container,
        coordinate: Clutter.BindCoordinate.WIDTH,
        offset: -2 * MARGIN * scaleFactor,
    }));
    title.add_constraint(new Clutter.AlignConstraint({
        source: container,
        align_axis: Clutter.AlignAxis.X_AXIS,
        factor: 0.5,
    }));
    const yAlign = new Clutter.AlignConstraint({
        source: container,
        align_axis: Clutter.AlignAxis.Y_AXIS,
    });
    title.add_constraint(yAlign);

    const style = () => {
        const look = appearance(settings);
        box.style = look.box;
        heading.style = look.heading;
        body.style = look.body;
        yAlign.factor = look.position.factor;
        title.translation_y = look.position.shift * MARGIN * scaleFactor;
    };
    style();
    settings.connectObject('changed', style, title);

    const update = () => {
        const [headingText, bodyText] = windowCaption(preview.metaWindow);
        heading.text = headingText;
        body.text = bodyText;
        body.visible = bodyText !== '';
        box.visible = headingText !== '';
    };
    update();
    preview.metaWindow.connectObject('notify::title', update, title);

    preview.add_child(title);
    preview._cliHelpersTitle = title;
    preview._updateIconScale();
    titles.add(title);
    title.connect('destroy', () => {
        titles.delete(title);
        if (preview._cliHelpersTitle === title)
            delete preview._cliHelpersTitle;
    });
}
