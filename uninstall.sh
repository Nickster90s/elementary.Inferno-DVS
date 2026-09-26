#!/bin/bash
# Remove Inferno DVS. Your settings in ~/.config/inferno-dvs are kept;
# delete that directory yourself if you want them gone.
set -uo pipefail

/usr/local/bin/inferno-dvs-ctl default output off 2>/dev/null
/usr/local/bin/inferno-dvs-ctl default input off 2>/dev/null
systemctl --user disable --now inferno-dvs.service inferno-dvs-requests.path 2>/dev/null
sudo systemctl disable --now 'inferno-statime@*.service' 2>/dev/null

sudo rm -f /usr/local/bin/inferno-dvs-ctl \
           /usr/local/bin/io.github.nickster90s.inferno-dvs \
           /usr/local/share/applications/io.github.nickster90s.inferno-dvs.desktop \
           /usr/local/lib/systemd/system/inferno-statime@.service \
           /usr/local/lib/systemd/user/inferno-dvs.service \
           /usr/local/lib/systemd/user/inferno-dvs-requests.path \
           /usr/local/lib/systemd/user/inferno-dvs-requests.service \
           /usr/local/libexec/inferno-dvs/statime
sudo find /usr/local/lib -path '*/inferno-dvs/libasound_module_pcm_inferno.so' -delete
sudo rm -f "$(pkg-config --variable=indicatorsdir wingpanel 2>/dev/null || echo /usr/lib/x86_64-linux-gnu/wingpanel)/libinferno-dvs.so"
sudo rmdir /usr/local/libexec/inferno-dvs 2>/dev/null
sudo find /usr/local/lib -type d -name inferno-dvs -empty -delete

rm -f "$HOME/.config/systemd/user/pipewire.service.d/inferno-dvs.conf"
# Drop our include from the user ALSA config.
rc="${XDG_CONFIG_HOME:-$HOME/.config}/alsa/asoundrc"
[ -f "$rc" ] && sed -i '/# Inferno DVS virtual soundcard/d; /inferno-dvs\/asound.conf>/d' "$rc"

sudo systemctl daemon-reload
systemctl --user daemon-reload
echo "Removed. Restart the panel (killall io.elementary.wingpanel) and PipeWire"
echo "(systemctl --user restart pipewire) to finish."
