#!/bin/sh
# Show Inferno DVS (and other devices without a card) in elementary's Sound
# settings and sound menu. Builds the installed release with the patch and
# replaces the two libraries; an elementary update undoes it, run this again.
#
# usage: elementary/install.sh            build and install
#        elementary/install.sh --restore  put the packaged libraries back
set -eu
here=$(cd "$(dirname "$0")" && pwd)
arch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
plug=/usr/lib/$arch/switchboard-3/system/libio.elementary.settings.sound.so
menu=/usr/lib/$arch/wingpanel/libsound.so

if [ "${1:-}" = --restore ]; then
    pkexec apt-get install --reinstall -y io.elementary.settings.sound wingpanel-indicator-sound
    exit
fi

pkexec apt-get install -y git meson valac libswitchboard-3-dev libwingpanel-dev libgranite-7-dev \
    libgranite-dev libadwaita-1-dev libpulse-dev libcanberra-dev libcanberra-gtk3-dev libnotify-dev

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
build() { # repo package
    tag=$(dpkg-query -W -f '${Version}' "$2" | cut -d+ -f1)
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "https://github.com/elementary/$1" "$work/$1"
    git -C "$work/$1" apply "$here/$1-cardless-devices.patch"
    meson setup "$work/$1/build" "$work/$1" --prefix=/usr >/dev/null
    ninja -C "$work/$1/build" >/dev/null
}
build settings-sound io.elementary.settings.sound
build wingpanel-indicator-sound wingpanel-indicator-sound

# The panel restarts by itself when its sound menu library is replaced.
pkexec sh -c "install -m644 '$work/settings-sound/build/src/$(basename "$plug")' '$plug' &&
              install -m644 '$work/wingpanel-indicator-sound/build/libsound.so' '$menu'"
echo "Installed. Reopen System Settings > Sound."
