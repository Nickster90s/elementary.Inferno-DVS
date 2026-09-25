/*
 * Inferno DVS — settings app (GTK4 + Granite 7, elementary OS 8).
 */

public class InfernoDvs.Application : Gtk.Application {
    public Application () {
        Object (application_id: APP_ID, flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void startup () {
        base.startup ();
        Granite.init ();

        var granite_settings = Granite.Settings.get_default ();
        var gtk_settings = Gtk.Settings.get_default ();
        gtk_settings.gtk_application_prefer_dark_theme =
            granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
        granite_settings.notify["prefers-color-scheme"].connect (() => {
            gtk_settings.gtk_application_prefer_dark_theme =
                granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
        });

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => quit ());
        add_action (quit_action);
        set_accels_for_action ("app.quit", { "<Control>q" });
    }

    protected override void activate () {
        var win = active_window ?? new MainWindow (this);
        win.present ();
    }

    public static int main (string[] args) {
        return new Application ().run (args);
    }
}
