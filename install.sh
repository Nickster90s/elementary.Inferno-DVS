#!/bin/bash
# Run as your normal user: asks for sudo only for the system-wide install.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# PipeWire keeps the ALSA plugin mmapped; meson overwrites files in place,
# which truncates the mapped file and kills PipeWire with SIGBUS. Unlink the
# old files first so the running process keeps its (now nameless) copy.
sudo find /usr/local/lib -path '*/inferno-dvs/libasound_module_pcm_inferno.so' -delete
sudo rm -f /usr/local/libexec/inferno-dvs/statime
sudo meson install -C "$here/build"
# ALSA caches loaded plugins by name, so only a PipeWire restart loads the
# new one. inferno-dvs.service is bound to pipewire and comes back with it.
if systemctl --user -q is-active inferno-dvs.service ||
   /usr/local/bin/inferno-dvs-ctl status 2>/dev/null | grep -q '^nodes=[1-9]'; then
    echo "Restarting PipeWire to load the new Inferno plugin (audio drops ~1 s)"
    systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service
    systemctl --user start inferno-dvs.service
fi
if systemctl -q is-active 'inferno-statime@*.service' 2>/dev/null; then
    echo "Note: the PTP daemon keeps running the old statime until it is restarted."
fi
sudo systemctl daemon-reload
systemctl --user daemon-reload
/usr/local/bin/inferno-dvs-ctl setup
echo
echo "Installed. Restart the panel to load the indicator:  killall io.elementary.wingpanel"
