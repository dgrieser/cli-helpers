# Files extension (nautilus-python, linked into ~/.local/share/nautilus-python/extensions
# by gnome-apply-settings) so that Files does not delete permanently by accident; Files
# has no settings for either:
# - Shift+Delete does what Delete does: it moves to the trash instead of deleting
#   permanently. Only in the trash and where there is no trash does it delete
#   permanently, after asking, like Delete.
# - the dialogs that confirm a permanent delete or emptying the trash focus Cancel, as
#   Files 50.0 did, not Delete or Empty Trash as Files 50.2 does again (Enter sits next
#   to Delete)
import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, GObject, Gtk

FILES_VIEW = "NautilusFilesView"
# the actions of Delete in the files view, of which Files enables one at a time: outside
# the trash, in the trash, and where there is no trash
DELETE_ACTIONS = [Gtk.NamedAction.new(f"view.{name}")
                  for name in ("move-to-trash", "delete-from-trash", "delete-permanently-menu-item")]
# the actions of Shift+Delete, both delete permanently
SHIFT_DELETE_ACTIONS = ("view.delete-permanently-shortcut", "view.permanent-delete-permanently-menu-item")

shift_delete_rebound = False


def delete(widget, args):
    # like the shortcut controller does for Delete: a disabled action does not activate,
    # so the enabled one does
    return any(action.activate(Gtk.ShortcutActionFlags(0), widget, None) for action in DELETE_ACTIONS)


DELETE = Gtk.CallbackAction.new(delete)


def rebind_shift_delete(view):
    # the shortcuts of a widget class are shared by all its widgets, so this changes
    # Shift+Delete in every files view, also the ones of windows opened later
    for controller in view.observe_controllers():
        if controller.get_name() != "gtk-widget-class-shortcuts":
            continue
        for shortcut in controller:
            action = shortcut.get_action()
            if isinstance(action, Gtk.NamedAction) and action.get_action_name() in SHIFT_DELETE_ACTIONS:
                shortcut.set_action(DELETE)
        return True
    return False


def focus_cancel(dialog):
    default = dialog.get_default_response()
    if (not default or not dialog.has_response("cancel")
            or dialog.get_response_appearance(default) != Adw.ResponseAppearance.DESTRUCTIVE):
        return
    dialog.set_default_response("cancel")
    # a dialog inside its window gets its focus after being mapped, on the default
    # response; one in a window of its own already focused it while being mapped
    if dialog.get_focus() is not None:
        dialog.set_focus(None)
        dialog.grab_focus()


def on_map(widget, *args):
    global shift_delete_rebound
    if not shift_delete_rebound and widget.__gtype__.name == FILES_VIEW:
        shift_delete_rebound = rebind_shift_delete(widget)
    elif isinstance(widget, Adw.AlertDialog):
        focus_cancel(widget)
    # keeps the hook installed
    return True


# Files loads its extensions before it creates a widget, and the map signal only exists
# once the GtkWidget class is initialized
GObject.type_class_get(Gtk.Widget)
GObject.add_emission_hook(Gtk.Widget, "map", on_map)
