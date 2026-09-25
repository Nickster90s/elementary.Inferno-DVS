/*
 * Wingpanel indicator for Inferno DVS (GTK3, wingpanel 8).
 */

public class InfernoDvs.Indicator : Wingpanel.Indicator {
    private Backend backend;
    private Gtk.Image? display_icon = null;
    private Gtk.Grid? main_widget = null;
    private Granite.SwitchModelButton power;
    private Gtk.Label detail_label;
    private Gtk.Label clock_label;
    private Granite.SwitchModelButton out_switch;
    private Granite.SwitchModelButton in_switch;
    private bool updating = false;
    private bool busy = false;
    private uint poll_id = 0;
    private Status? last = null;

    public Indicator () {
        Object (code_name: "inferno-dvs");
    }

    construct {
        backend = new Backend ();
        visible = true;
        schedule_poll (5);
        refresh.begin ();
    }

    public override Gtk.Widget get_display_widget () {
        if (display_icon == null) {
            display_icon = new Gtk.Image.from_icon_name ("audio-card-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            display_icon.tooltip_text = "Inferno DVS";
            if (last != null) {
                update (last);
            } else {
                display_icon.opacity = 0.5;
            }
        }
        return display_icon;
    }

    public override Gtk.Widget? get_widget () {
        if (main_widget == null) {
            power = new Granite.SwitchModelButton ("Inferno DVS");
            power.get_style_context ().add_class (Granite.STYLE_CLASS_H4_LABEL);

            detail_label = new Gtk.Label ("") {
                xalign = 0, margin_start = 12, margin_end = 12, max_width_chars = 32, wrap = true
            };
            detail_label.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);

            clock_label = new Gtk.Label ("") {
                xalign = 0, margin_start = 12, margin_end = 12, margin_bottom = 3, max_width_chars = 32, wrap = true
            };
            clock_label.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);

            out_switch = new Granite.SwitchModelButton ("System Output");
            in_switch = new Granite.SwitchModelButton ("System Input");
            out_switch.notify["active"].connect (() => {
                if (!updating) {
                    run_quiet.begin ({ "default", "output", out_switch.active ? "on" : "off" });
                }
            });
            in_switch.notify["active"].connect (() => {
                if (!updating) {
                    run_quiet.begin ({ "default", "input", in_switch.active ? "on" : "off" });
                }
            });

            var settings_button = new Gtk.ModelButton () { text = "Soundcard Settings…" };
            settings_button.clicked.connect (open_settings);

            main_widget = new Gtk.Grid () { orientation = Gtk.Orientation.VERTICAL, margin_top = 3, margin_bottom = 3 };
            main_widget.add (power);
            main_widget.add (detail_label);
            main_widget.add (clock_label);
            main_widget.add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
            main_widget.add (out_switch);
            main_widget.add (in_switch);
            main_widget.add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 3, margin_bottom = 3 });
            main_widget.add (settings_button);
            main_widget.show_all ();

            power.notify["active"].connect (() => {
                if (!updating) {
                    set_power.begin (power.active);
                }
            });

            if (last != null) {
                update (last);
            }
        }
        return main_widget;
    }

    public override void opened () {
        schedule_poll (1);
        refresh.begin ();
    }

    public override void closed () {
        schedule_poll (5);
    }

    private void schedule_poll (uint seconds) {
        if (poll_id != 0) {
            Source.remove (poll_id);
        }
        poll_id = Timeout.add_seconds (seconds, () => {
            refresh.begin ();
            return Source.CONTINUE;
        });
    }

    private async void refresh () {
        if (busy) {
            return;
        }
        try {
            update (yield backend.status ());
        } catch (Error e) {
            debug ("inferno-dvs status: %s", e.message);
        }
    }

    private void update (Status s) {
        last = s;
        if (display_icon != null) {
            display_icon.opacity = s.running ? 1.0 : 0.5;
            var tip = "Inferno DVS: " + (s.running ? s.summary () : "off");
            if (s.running) {
                tip += "\n" + s.clock_text ();
            }
            display_icon.tooltip_text = tip;
        }
        if (main_widget == null) {
            return;
        }
        updating = true;
        power.active = s.running;
        out_switch.active = s.default_output;
        in_switch.active = s.default_input;
        out_switch.sensitive = s.running && s.tx_channels > 0;
        in_switch.sensitive = s.running && s.rx_channels > 0;
        updating = false;

        if (s.running) {
            detail_label.label = "%s · %s · %s".printf (s.name, s.summary (), s.ip != "" ? s.ip : s.interface);
        } else {
            detail_label.label = "%s · %s".printf (s.name, s.interface);
        }
        clock_label.label = s.clock_on_configured_nic () || !s.clock_running ()
            ? s.clock_text ()
            : "PTP daemon is on another interface";
    }

    private async void set_power (bool on) {
        busy = true;
        power.sensitive = false;
        try {
            yield backend.run ({ on ? "start" : "stop" });
        } catch (Error e) {
            warning ("inferno-dvs: %s", e.message);
        }
        busy = false;
        power.sensitive = true;
        yield refresh ();
    }

    private async void run_quiet (string[] args) {
        busy = true;
        try {
            yield backend.run (args);
        } catch (Error e) {
            warning ("inferno-dvs: %s", e.message);
        }
        busy = false;
        yield refresh ();
    }

    private void open_settings () {
        close ();
        try {
            var info = new DesktopAppInfo (APP_ID + ".desktop");
            if (info != null) {
                info.launch (null, null);
                return;
            }
            Process.spawn_command_line_async (APP_ID);
        } catch (Error e) {
            warning ("inferno-dvs: cannot open settings: %s", e.message);
        }
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }
    debug ("Activating Inferno DVS indicator");
    return new InfernoDvs.Indicator ();
}
