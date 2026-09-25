public class InfernoDvs.MainWindow : Gtk.ApplicationWindow {
    private const int[] RATES = { 44100, 48000, 88200, 96000 };
    private const double[] LATENCIES = { 1, 2, 4, 5, 6, 10, 20, 40 };
    private const int MAX_CHANNELS = 128;

    private Backend backend;
    private Status? last;
    private Iface[] ifaces = {};
    private bool loading = false;
    private bool busy = false;
    private bool dirty = false;

    private Gtk.Image state_icon;
    private Gtk.Label title_label;
    private Gtk.Label summary_label;
    private Gtk.Switch power_switch;
    private Gtk.Label clock_label;
    private Gtk.Image clock_icon;
    private Gtk.Button clock_button;

    private Gtk.Entry name_entry;
    private Gtk.DropDown iface_drop;
    private Gtk.StringList iface_model;
    private Gtk.SpinButton rx_spin;
    private Gtk.SpinButton tx_spin;
    private Gtk.DropDown rate_drop;
    private Gtk.DropDown latency_drop;
    private Gtk.Switch autostart_switch;
    private Gtk.Switch default_out_switch;
    private Gtk.Switch default_in_switch;
    private Gtk.Button apply_button;
    private Granite.Toast toast;

    public MainWindow (Gtk.Application app) {
        Object (application: app, title: "Inferno DVS", default_width: 480, resizable: false);
    }

    construct {
        backend = new Backend ();

        var headerbar = new Gtk.HeaderBar () {
            show_title_buttons = true,
            title_widget = new Gtk.Label (null)
        };
        headerbar.add_css_class (Granite.STYLE_CLASS_FLAT);
        headerbar.add_css_class (Granite.STYLE_CLASS_DEFAULT_DECORATION);
        set_titlebar (headerbar);

        /* --- status header --- */
        state_icon = new Gtk.Image.from_icon_name ("audio-card") { pixel_size = 48 };
        title_label = new Gtk.Label ("Inferno DVS") { xalign = 0 };
        title_label.add_css_class (Granite.HeaderLabel.Size.H2.to_string ());
        summary_label = new Gtk.Label ("") { xalign = 0 };
        summary_label.add_css_class (Granite.CssClass.DIM);
        power_switch = new Gtk.Switch () { valign = Gtk.Align.CENTER, tooltip_text = "Start or stop the virtual soundcard" };

        var titles = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, valign = Gtk.Align.CENTER };
        titles.append (title_label);
        titles.append (summary_label);

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        header.append (state_icon);
        header.append (titles);
        header.append (power_switch);

        /* --- clock row --- */
        clock_icon = new Gtk.Image.from_icon_name ("content-loading-symbolic");
        clock_label = new Gtk.Label ("") { xalign = 0, hexpand = true, wrap = true };
        clock_button = new Gtk.Button.with_label ("Enable clock") {
            valign = Gtk.Align.CENTER,
            visible = false,
            tooltip_text = "Start the PTP daemon on the selected network interface (asks for your password)"
        };
        var clock_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        clock_row.append (clock_icon);
        clock_row.append (clock_label);
        clock_row.append (clock_button);

        /* --- settings --- */
        name_entry = new Gtk.Entry () { max_length = 31, hexpand = true, placeholder_text = "Dante device name" };

        iface_model = new Gtk.StringList (null);
        iface_drop = new Gtk.DropDown (iface_model, null);

        rx_spin = new Gtk.SpinButton.with_range (0, MAX_CHANNELS, 1);
        tx_spin = new Gtk.SpinButton.with_range (0, MAX_CHANNELS, 1);
        rx_spin.set_increments (1, 8);
        tx_spin.set_increments (1, 8);

        string[] rate_labels = {};
        foreach (var r in RATES) {
            rate_labels += format_rate (r) + " kHz";
        }
        rate_drop = new Gtk.DropDown.from_strings (rate_labels);

        string[] lat_labels = {};
        foreach (var l in LATENCIES) {
            lat_labels += "%g ms".printf (l);
        }
        latency_drop = new Gtk.DropDown.from_strings (lat_labels);

        autostart_switch = new Gtk.Switch () { halign = Gtk.Align.START, valign = Gtk.Align.CENTER };

        var grid = new Gtk.Grid () { column_spacing = 12, row_spacing = 6 };
        int row = 0;
        add_row (grid, ref row, "Device name", name_entry);
        add_row (grid, ref row, "Network interface", iface_drop);
        add_row (grid, ref row, "Receive channels", rx_spin, "Dante → this computer (PipeWire source)");
        add_row (grid, ref row, "Transmit channels", tx_spin, "This computer → Dante (PipeWire sink)");
        add_row (grid, ref row, "Sample rate", rate_drop);
        add_row (grid, ref row, "Latency", latency_drop);
        add_row (grid, ref row, "Start automatically", autostart_switch);

        default_out_switch = new Gtk.Switch () { halign = Gtk.Align.START, valign = Gtk.Align.CENTER };
        default_in_switch = new Gtk.Switch () { halign = Gtk.Align.START, valign = Gtk.Align.CENTER };
        var sys_grid = new Gtk.Grid () { column_spacing = 12, row_spacing = 6 };
        int sys_row = 0;
        add_row (sys_grid, ref sys_row, "Use as system output", default_out_switch,
                 "Send desktop and app audio to Dante (the default sound output)");
        add_row (sys_grid, ref sys_row, "Use as system input", default_in_switch,
                 "Use Dante as the default microphone / recording input");
        var size_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
        size_group.add_widget (grid.get_child_at (0, 0));
        size_group.add_widget (sys_grid.get_child_at (0, 0));

        apply_button = new Gtk.Button.with_label ("Apply") { halign = Gtk.Align.END, sensitive = false };
        apply_button.add_css_class (Granite.CssClass.SUGGESTED);

        var note = new Gtk.Label ("Unofficial implementation of the Dante protocol (Inferno). Not affiliated with Audinate.") {
            wrap = true, xalign = 0, hexpand = true
        };
        note.add_css_class (Granite.CssClass.SMALL);
        note.add_css_class (Granite.CssClass.DIM);

        var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        footer.append (note);
        footer.append (apply_button);

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_start = 18, margin_end = 18, margin_bottom = 18
        };
        content.append (header);
        content.append (clock_row);
        content.append (new Granite.HeaderLabel ("Soundcard"));
        content.append (grid);
        content.append (new Granite.HeaderLabel ("System Audio"));
        content.append (sys_grid);
        content.append (footer);

        toast = new Granite.Toast ("");
        var overlay = new Gtk.Overlay () { child = content };
        overlay.add_overlay (toast);
        child = overlay;

        /* --- signals --- */
        name_entry.changed.connect (mark_dirty);
        iface_drop.notify["selected"].connect (mark_dirty);
        rx_spin.value_changed.connect (mark_dirty);
        tx_spin.value_changed.connect (mark_dirty);
        rate_drop.notify["selected"].connect (mark_dirty);
        latency_drop.notify["selected"].connect (mark_dirty);
        apply_button.clicked.connect (() => apply.begin ());
        clock_button.clicked.connect (() => enable_clock.begin ());
        power_switch.state_set.connect ((on) => {
            if (!loading) {
                set_power.begin (on);
            }
            return false;
        });
        autostart_switch.state_set.connect ((on) => {
            if (!loading) {
                run_quiet.begin ({ "autostart", on ? "on" : "off" });
            }
            return false;
        });

        default_out_switch.state_set.connect ((on) => {
            if (!loading) {
                run_quiet.begin ({ "default", "output", on ? "on" : "off" });
            }
            return false;
        });
        default_in_switch.state_set.connect ((on) => {
            if (!loading) {
                run_quiet.begin ({ "default", "input", on ? "on" : "off" });
            }
            return false;
        });

        load.begin ();
        Timeout.add_seconds (2, () => {
            refresh.begin ();
            return Source.CONTINUE;
        });
    }

    private void add_row (Gtk.Grid grid, ref int row, string label, Gtk.Widget widget, string? hint = null) {
        var l = new Gtk.Label (label) { xalign = 1, halign = Gtk.Align.END };
        grid.attach (l, 0, row);
        grid.attach (widget, 1, row);
        if (hint != null) {
            widget.tooltip_text = hint;
        }
        row++;
    }

    private void mark_dirty () {
        if (loading) {
            return;
        }
        dirty = true;
        apply_button.sensitive = !busy;
    }

    private void show_error (string msg) {
        warning ("%s", msg);
        toast.title = msg.length > 160 ? msg.substring (0, 160) + "…" : msg;
        toast.send_notification ();
    }

    /* Full (re)load of the settings form from the helper. */
    private async void load () {
        try {
            ifaces = yield backend.interfaces ();
            var s = yield backend.status ();
            loading = true;

            var names = new string[ifaces.length];
            for (int i = 0; i < ifaces.length; i++) {
                names[i] = ifaces[i].label ();
            }
            iface_model.splice (0, iface_model.get_n_items (), names);
            uint sel = 0;
            for (int i = 0; i < ifaces.length; i++) {
                if (ifaces[i].name == s.interface) {
                    sel = i;
                }
            }
            iface_drop.selected = sel;

            name_entry.text = s.name;
            rx_spin.value = s.rx_channels;
            tx_spin.value = s.tx_channels;
            rate_drop.selected = index_of_rate (s.sample_rate);
            latency_drop.selected = index_of_latency (s.latency_ms);
            autostart_switch.active = s.autostart;
            dirty = false;
            apply_button.sensitive = false;
            loading = false;
            update_status (s);
        } catch (Error e) {
            loading = false;
            show_error (e.message);
        }
    }

    private async void refresh () {
        if (busy) {
            return;
        }
        try {
            update_status (yield backend.status ());
        } catch (Error e) {
            warning ("status: %s", e.message);
        }
    }

    private void update_status (Status s) {
        last = s;
        loading = true;
        power_switch.active = s.running;
        power_switch.state = s.running;
        autostart_switch.active = s.autostart;
        default_out_switch.active = s.default_output;
        default_in_switch.active = s.default_input;
        default_out_switch.sensitive = s.running && s.tx_channels > 0;
        default_in_switch.sensitive = s.running && s.rx_channels > 0;
        loading = false;

        title_label.label = s.name;
        if (s.running) {
            summary_label.label = "%s · %s".printf (s.summary (), s.ip != "" ? s.ip : s.interface);
        } else {
            summary_label.label = "Stopped";
        }

        if (!s.clock_on_configured_nic ()) {
            clock_icon.icon_name = "dialog-warning-symbolic";
            clock_label.label = s.clock_running ()
                ? "PTP daemon is running on another interface"
                : "PTP daemon is not running — audio needs a clock";
            clock_button.label = "Enable clock on %s".printf (s.interface);
            clock_button.visible = true;
        } else {
            clock_icon.icon_name = s.ptp_locked () ? "emblem-ok-symbolic"
                                 : (s.ptp_state == "slave" ? "emblem-ok-symbolic" : "content-loading-symbolic");
            clock_label.label = s.clock_text ();
            clock_button.visible = false;
        }
    }

    private uint index_of_rate (int rate) {
        for (int i = 0; i < RATES.length; i++) {
            if (RATES[i] == rate) {
                return i;
            }
        }
        return 1;
    }

    private uint index_of_latency (double ms) {
        for (int i = 0; i < LATENCIES.length; i++) {
            if ((LATENCIES[i] - ms).abs () < 0.001) {
                return i;
            }
        }
        return 2;
    }

    private string selected_iface () {
        var i = iface_drop.selected;
        return i < ifaces.length ? ifaces[i].name : "";
    }

    private void set_busy (bool b) {
        busy = b;
        apply_button.sensitive = !b && dirty;
        power_switch.sensitive = !b;
        clock_button.sensitive = !b;
    }

    private async void apply () {
        set_busy (true);
        var old_iface = last != null ? last.interface : "";
        var new_iface = selected_iface ();
        try {
            yield backend.run ({
                "set",
                "name=" + name_entry.text.strip (),
                "interface=" + new_iface,
                "rx_channels=%d".printf ((int) rx_spin.value),
                "tx_channels=%d".printf ((int) tx_spin.value),
                "sample_rate=%d".printf (RATES[rate_drop.selected]),
                "latency_ms=%g".printf (LATENCIES[latency_drop.selected])
            });
            dirty = false;

            /* The PTP daemon follows the NIC; moving it needs the admin password. */
            if (last != null && (new_iface != old_iface || !last.clock_on_configured_nic ())
                && last.clock_running ()) {
                yield backend.run ({ "clock-on" });
            }
            if (last != null && last.running) {
                yield backend.run ({ "start" });
            }
        } catch (Error e) {
            show_error (e.message);
        }
        set_busy (false);
        yield load ();
    }

    private async void enable_clock () {
        set_busy (true);
        try {
            if (dirty) {
                set_busy (false);
                yield apply ();
                set_busy (true);
            }
            yield backend.run ({ "clock-on" });
        } catch (Error e) {
            show_error (e.message);
        }
        set_busy (false);
        yield refresh ();
    }

    private async void set_power (bool on) {
        set_busy (true);
        try {
            if (on && dirty) {
                set_busy (false);
                yield apply ();
                set_busy (true);
            }
            if (on && last != null && !last.clock_on_configured_nic ()) {
                yield backend.run ({ "clock-on" });
            }
            yield backend.run ({ on ? "start" : "stop" });
        } catch (Error e) {
            show_error (e.message);
        }
        set_busy (false);
        yield refresh ();
    }

    private async void run_quiet (string[] args) {
        try {
            yield backend.run (args);
        } catch (Error e) {
            show_error (e.message);
        }
    }
}
