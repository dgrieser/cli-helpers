# Files extension (nautilus-python, linked into ~/.local/share/nautilus-python/extensions
# by gnome-apply-settings): the dialogs that confirm a permanent delete or emptying the
# trash focus Cancel, as Files 50.0 did, not the destructive Delete or Empty Trash that
# Files 50.2 focuses again (Enter sits next to Delete). Files has no setting for it.
import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, GObject, Gtk


def focus_cancel(widget, *args):
    # an emission hook runs before the class handler, so the default response is
    # changed before AdwAlertDialog's map focuses it
    if isinstance(widget, Adw.AlertDialog):
        default = widget.get_default_response()
        if (default and widget.has_response("cancel")
                and widget.get_response_appearance(default) == Adw.ResponseAppearance.DESTRUCTIVE):
            widget.set_default_response("cancel")
    # keeps the hook installed
    return True


# Files loads its extensions before it creates a widget, and the map signal only exists
# once the GtkWidget class is initialized
GObject.type_class_get(Gtk.Widget)
GObject.add_emission_hook(Gtk.Widget, "map", focus_cancel)
