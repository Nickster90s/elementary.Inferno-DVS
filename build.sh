#!/bin/bash
# Build everything:
#   1. fetch Inferno + the Statime inferno-dev fork at tested commits (deps/)
#   2. apply our Inferno patches (patches/)
#   3. cargo build the Inferno ALSA plugin and Statime
#   4. meson build the settings app and the Wingpanel indicator
# Install afterwards with ./install.sh.
#
# Use existing checkouts instead of deps/ with INFERNO_DIR=... STATIME_DIR=...
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cargo="${CARGO:-$(command -v cargo || echo "$HOME/.cargo/bin/cargo")}"

INFERNO_URL=https://github.com/teodly/inferno
INFERNO_REV=9767558e0905c9e9c960f5a60e050fbdc38300b7
STATIME_URL=https://github.com/teodly/statime
STATIME_REV=244f20a56c173b1881f2e5e83652bb8b8209b2ab   # branch inferno-dev

fetch() {  # url rev dir
    if [ ! -d "$3/.git" ]; then
        git clone --recurse-submodules "$1" "$3"
        git -C "$3" checkout -q "$2"
        git -C "$3" submodule update -q --init --recursive
    fi
}

inferno="${INFERNO_DIR:-$here/deps/inferno}"
statime="${STATIME_DIR:-$here/deps/statime}"
mkdir -p "$here/deps"
[ -n "${INFERNO_DIR:-}" ] || fetch "$INFERNO_URL" "$INFERNO_REV" "$inferno"
[ -n "${STATIME_DIR:-}" ] || fetch "$STATIME_URL" "$STATIME_REV" "$statime"

for p in "$here"/patches/*.patch; do
    if git -C "$inferno" apply --check "$p" 2>/dev/null; then
        echo "applying $(basename "$p")"
        git -C "$inferno" apply "$p"
    elif git -C "$inferno" apply --check --reverse "$p" 2>/dev/null; then
        echo "already applied: $(basename "$p")"
    else
        echo "error: $(basename "$p") does not apply to $inferno" >&2
        exit 1
    fi
done

(cd "$inferno" && "$cargo" build --release -p alsa_pcm_inferno)
(cd "$statime" && "$cargo" build --release -p statime-linux)

mkdir -p "$here/rust-out"
cp "$inferno/target/release/libasound_module_pcm_inferno.so" "$here/rust-out/"
cp "$statime/target/release/statime" "$here/rust-out/"
strip "$here/rust-out/statime" "$here/rust-out/libasound_module_pcm_inferno.so"

[ -d "$here/build" ] || meson setup "$here/build" "$here" --prefix=/usr/local
meson compile -C "$here/build"
