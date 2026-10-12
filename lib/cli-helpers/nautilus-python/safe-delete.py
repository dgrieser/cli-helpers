# Files extension (nautilus-python, linked into ~/.local/share/nautilus-python/extensions
# by gnome-apply-settings) so that Files does not delete permanently by accident; Files
# has no settings for either:
# - Shift+Delete asks first, with Cancel focused, and then only moves to the trash, like
#   Delete does without asking, instead of deleting permanently. Only in the trash and
#   where there is no trash does it delete permanently, after asking, like Delete.
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


def can_trash(view):
    # Files enables move-to-trash only outside the trash and for a selection it can
    # trash. GTK 4 cannot ask a widget whether an action is enabled, but a button with
    # the action follows it with its sensitivity, once it is in the view
    probe = Gtk.Button(action_name="view.move-to-trash", visible=False)
    probe.set_parent(view)
    enabled = probe.get_sensitive()
    probe.unparent()
    return enabled


def on_confirm_trash(dialog, response, view):
    if response == "trash":
        view.activate_action("view.move-to-trash", None)


def confirm_trash(view):
    dialog = Adw.AlertDialog.new("Move to Trash?",
                                 "Shift+Delete moves the selected items to the trash, "
                                 "it does not delete them permanently.")
    dialog.add_response("cancel", "_Cancel")
    dialog.add_response("trash", "_Move to Trash")
    dialog.set_response_appearance("trash", Adw.ResponseAppearance.DESTRUCTIVE)
    # Cancel has the focus, so Enter cancels, and so does Escape
    dialog.set_default_response("cancel")
    dialog.set_close_response("cancel")
    dialog.connect("response", on_confirm_trash, view)
    dialog.present(view)


def shift_delete(widget, args):
    # outside the trash, Shift+Delete asks first and then moves to the trash, as Delete
    # does without asking; in the trash and where there is no trash, it does what Delete
    # does, which asks itself before it deletes permanently
    if can_trash(widget):
        confirm_trash(widget)
        return True
    return delete(widget, args)


SHIFT_DELETE = Gtk.CallbackAction.new(shift_delete)


def rebind_shift_delete(view):
    # the shortcuts of a widget class are shared by all its widgets, so this changes
    # Shift+Delete in every files view, also the ones of windows opened later
    for controller in view.observe_controllers():
        if controller.get_name() != "gtk-widget-class-shortcuts":
            continue
        for shortcut in controller:
            action = shortcut.get_action()
            if isinstance(action, Gtk.NamedAction) and action.get_action_name() in SHIFT_DELETE_ACTIONS:
                shortcut.set_action(SHIFT_DELETE)
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
