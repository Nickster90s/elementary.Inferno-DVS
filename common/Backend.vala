/*
 * Shared by the app (GTK4) and the Wingpanel indicator (GTK3): talks to
 * inferno-dvs-ctl, which prints GLib.KeyFile-compatible output.
 */

namespace InfernoDvs {
    public const string APP_ID = "io.github.nickster90s.inferno-dvs";

    public class Iface : Object {
        public string name { get; construct; }
        public string mac { get; construct; }
        public string ipv4 { get; construct; }
        public string state { get; construct; }
        public bool wireless { get; construct; }

        public Iface (string name, string mac, string ipv4, string state, bool wireless) {
            Object (name: name, mac: mac, ipv4: ipv4, state: state, wireless: wireless);
        }

        public string label () {
            var ip = ipv4 != "" ? ipv4 : (state == "up" ? "no IPv4" : state);
            return "%s (%s)".printf (name, ip);
        }
    }

    public class Status : Object {
        public bool running;
        public string service = "";
        public string statime = "";
        public string node_state = "";
        public string ptp_state = "";
        public string ptp_offset_ns = "";
        public string ip = "";
        public bool autostart;
        public bool default_output;
        public bool default_input;

        public string name = "";
        public string interface = "";
        public int rx_channels;
        public int tx_channels;
        public int sample_rate;
        public double latency_ms;

        public bool clock_running () {
            return statime != "" && statime != "inactive";
        }

        public bool clock_on_configured_nic () {
            return statime.contains ("inferno-statime@%s.service".printf (interface));
        }

        public bool ptp_locked () {
            return ptp_state == "slave" || ptp_state == "uncalibrated";
        }

        /* One-line human summary of the clock. */
        public string clock_text () {
            if (!clock_running ()) {
                return "PTP daemon not running";
            }
            switch (ptp_state) {
                case "slave":
                    var off = ptp_offset_ns != "" ? " · offset %s".printf (format_ns (ptp_offset_ns)) : "";
                    return "Locked to leader" + off;
                case "uncalibrated":
                    return "Locking…";
                case "listening":
                    return "Listening for a PTP leader";
                case "master":
                    return "No leader found (would be leader)";
                case "unavailable":
                    return "PTP daemon starting…";
                default:
                    return "PTP: " + ptp_state;
            }
        }

        public string summary () {
            if (!running) {
                return "Off";
            }
            return "%d in · %d out · %s kHz".printf (rx_channels, tx_channels, format_rate (sample_rate));
        }
    }

    public string format_ns (string ns_str) {
        var ns = double.parse (ns_str);
        var a = ns.abs ();
        if (a < 1000) {
            return "%.0f ns".printf (ns);
        } else if (a < 1000000) {
            return "%.1f µs".printf (ns / 1000.0);
        }
        return "%.2f ms".printf (ns / 1000000.0);
    }

    public string format_rate (int rate) {
        if (rate % 1000 == 0) {
            return "%d".printf (rate / 1000);
        }
        return "%.1f".printf (rate / 1000.0);
    }

    public class Backend : Object {
        public string ctl_path { get; construct; }

        public Backend () {
            var path = Environment.get_variable ("INFERNO_DVS_CTL");
            if (path == null) {
                path = Environment.find_program_in_path ("inferno-dvs-ctl");
            }
            if (path == null) {
                path = "/usr/local/bin/inferno-dvs-ctl";
            }
            Object (ctl_path: path);
        }

        /* Run the helper; returns stdout. Throws with stderr on failure. */
        public async string run (string[] args, Cancellable? cancellable = null) throws Error {
            string[] argv = { ctl_path };
            foreach (var a in args) {
                argv += a;
            }
            var proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string? out_s, err_s;
            yield proc.communicate_utf8_async (null, cancellable, out out_s, out err_s);
            if (!proc.get_successful ()) {
                var msg = (err_s ?? "").strip ();
                throw new IOError.FAILED (msg != "" ? msg : "inferno-dvs-ctl %s failed".printf (args[0]));
            }
            return out_s ?? "";
        }

        public async Status status () throws Error {
            var kf = new KeyFile ();
            kf.load_from_data (yield run ({ "status" }), -1, KeyFileFlags.NONE);
            var s = new Status ();
            s.running = get_bool (kf, "status", "running");
            s.service = get_str (kf, "status", "service");
            s.statime = get_str (kf, "status", "statime");
            s.node_state = get_str (kf, "status", "node_state");
            s.ptp_state = get_str (kf, "status", "ptp_state");
            s.ptp_offset_ns = get_str (kf, "status", "ptp_offset_ns");
            s.ip = get_str (kf, "status", "ip");
            s.autostart = get_bool (kf, "status", "autostart");
            s.default_output = get_bool (kf, "status", "default_output");
            s.default_input = get_bool (kf, "status", "default_input");
            s.name = get_str (kf, "config", "name");
            s.interface = get_str (kf, "config", "interface");
            s.rx_channels = int.parse (get_str (kf, "config", "rx_channels"));
            s.tx_channels = int.parse (get_str (kf, "config", "tx_channels"));
            s.sample_rate = int.parse (get_str (kf, "config", "sample_rate"));
            s.latency_ms = double.parse (get_str (kf, "config", "latency_ms"));
            return s;
        }

        public async Iface[] interfaces () throws Error {
            var kf = new KeyFile ();
            kf.load_from_data (yield run ({ "interfaces" }), -1, KeyFileFlags.NONE);
            Iface[] result = {};
            foreach (var g in kf.get_groups ()) {
                result += new Iface (g, get_str (kf, g, "mac"), get_str (kf, g, "ipv4"),
                                     get_str (kf, g, "state"), get_bool (kf, g, "wireless"));
            }
            return result;
        }

        private static string get_str (KeyFile kf, string g, string k) {
            try {
                return kf.get_string (g, k);
            } catch (Error e) {
                return "";
            }
        }

        private static bool get_bool (KeyFile kf, string g, string k) {
            return get_str (kf, g, k) == "true";
        }
    }
}
