# Inferno DVS for elementary OS

Turns an elementary OS computer into a **virtual Dante® soundcard**: other
devices on the Dante network see it, you patch it in Dante Controller, and it
appears in PipeWire as an output and an input that any Linux app can use. It
works like Audinate's Dante Virtual Soundcard (DVS) on Mac and Windows, and it
comes with a settings app and a Wingpanel indicator.

Under the hood it is built on:

- [**Inferno**](https://github.com/teodly/inferno), an open-source,
  reverse-engineered implementation of the Dante protocol, used through its
  ALSA plugin inside PipeWire;
- the [**Statime `inferno-dev` fork**](https://github.com/teodly/statime/tree/inferno-dev)
  for PTPv1 clock sync with the Dante network.

> **Unofficial.** This project is not affiliated with, authorised or endorsed
> by Audinate. Dante is a trademark of Audinate Pty Ltd. Inferno is described
> by its author as experimental; use it for non-critical work.

## What you get

| | |
|---|---|
| **Settings app** (*Inferno DVS*) | Device name, network interface, receive and transmit channel counts (0–128), sample rate (44.1/48/88.2/96 kHz), latency (0.25–40 ms), PipeWire buffer, start automatically, on/off switch, live clock status, and "use as system output/input" switches |
| **Wingpanel indicator** | On/off switch, name, channels, IP, clock state, System Output / System Input switches, and a link to the settings app |
| **PipeWire devices** | `<name> (Dante out, N ch)` is a sink, so audio played to it goes to the network. `<name> (Dante in, N ch)` is a source that brings audio in from the network |
| **`inferno-dvs-ctl`** | Command-line control, also used by the app and the indicator |

### Tested

On 2026-09-25, running on elementary OS 8.1 (PipeWire 1.0.5, wired NIC with
software timestamps), with a Focusrite RedNet AM2 as the PTP leader:

- The device appears in Dante Controller and can be patched.
- Audio from this PC played on a RedNet AM2 and on an ESP32-P4 based
  8-channel receiver, at 48 and 96 kHz.
- PTP stayed locked, with the offset from the leader within about ±300 ns.

## Latency

The upstream Inferno defaults are tuned for safety. This project changes three
things (patch `0002`, plus the helper):

| | Upstream Inferno | Inferno DVS |
|---|---|---|
| Send/receive threads | asks for SCHED_FIFO, which fails silently for desktop users, so they run at normal priority | realtime via **RealtimeKit** (RR 20, like PipeWire's own data thread) |
| Packet timestamp offset | fixed −500 µs | **−93 µs**, set with `tx_ts_offset_us` |
| PipeWire buffer | graph default (1024 samples at 48 kHz, resampled) | **256 samples at the Dante rate**, 32–1024 selectable |

Measured on 2026-09-26 at 96 kHz. The receiver was an ESP32-P4 Dante-compatible
DAC that timestamps packet arrival against a hardware PTP clock:

| Receiver latency | Late packets, upstream | Late packets, Inferno DVS |
|---|---|---|
| 2 ms | 0.001 % | 0 % |
| 1.5 ms | 0.5 % | 0.03 % |
| 1 ms | 62 % | 0.03–0.2 % |
| 0.75 ms (that DAC's minimum) | 96 % | 0.3 % |

Inferno's own send timing is 10–20 µs on average and under 200 µs at worst.
On the same network, packets from **Dante Virtual Soundcard** (Mac) arrived
540 µs late on average and up to 3.6 ms late, which is why DVS needs 4 ms. The
remaining late packets at 1 ms and below come from after the packet leaves the
PC (network and receiver), not from Inferno.

Notes:

- Receive latency only has to cover how late the *sender* is: 1 ms or less
  from Inferno or hardware devices, and about 4 ms from DVS.
- Inferno logs its lag statistics every 10 s:
  `journalctl --user -u pipewire | grep lag`.
- Turn off Energy-Efficient Ethernet on switches and on the NIC
  (`sudo ethtool --set-eee eno1 eee off`). Audinate recommends this for
  Dante; on this bench it made no measurable difference.

## How it works

```
  Dante network (eno1)                      this computer
 ───────────────────────┐
  PTPv1 leader  ───────►│ inferno-statime@eno1.service  (system, root)
                        │   Statime fork: PTPv1 follower on a virtual clock
                        │   (system clock and timesyncd are left alone)
                        │   └─► /tmp/ptp-usrvclock  (clock for Inferno)
                        │   └─► /run/inferno-dvs/statime.sock  (status JSON)
                        │
  Dante devices ◄──────►│ PipeWire  (user)
  (ARC, flows, audio)   │   inferno-dvs.service creates two ALSA adapter nodes
                        │   using Inferno's ALSA plugin. The Inferno instance
                        │   runs inside PipeWire and is the "Dante device".
 ───────────────────────┘
                          inferno-dvs-ctl ◄── settings app, panel indicator
```

- **`inferno-statime@<nic>.service`** is a system unit that runs Statime as a
  PTPv1 follower on one NIC. Enabling it, or moving it to another NIC, asks
  for your admin password through the normal elementary dialog. Once enabled
  it stays enabled across reboots.
- **`inferno-dvs.service`** is a user unit bound to `pipewire.service`. It
  creates the Inferno source and sink nodes (`inferno-dvs-ctl pw-up`). Turning
  the soundcard on or off never needs a password.
- The device ID is the NIC's MAC address padded with zeros, as on real Dante
  hardware.

Files it creates for you:

| Path | What |
|---|---|
| `~/.config/inferno-dvs/config.ini` | your settings |
| `~/.config/inferno-dvs/asound.conf` | generated ALSA device `inferno_dvs` |
| `~/.config/alsa/asoundrc` | gets one line that includes the file above |
| `~/.config/systemd/user/pipewire.service.d/inferno-dvs.conf` | allows the clock syscalls Inferno needs (`SystemCallFilter=@clock`) |
| `~/.local/state/inferno_aoip/<device id>/` | Inferno's saved subscriptions and channel names |

## Requirements

- elementary OS 8 (Ubuntu 24.04 base) with PipeWire and WirePlumber, which
  are the default
- a wired NIC on the Dante network (Dante devices often use 169.254.x.x
  link-local addresses; that is fine)
- build tools:

```bash
sudo apt install git meson valac libgtk-4-dev libgranite-7-dev \
                 libgtk-3-dev libgranite-dev libwingpanel-dev libasound2-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh   # Rust (cargo)
```

## Build and install

```bash
git clone https://github.com/Nickster90s/elementary.Inferno-DVS.git
cd elementary.Inferno-DVS
./build.sh                          # fetches Inferno + Statime, patches, builds everything
./install.sh                        # installs to /usr/local (asks for sudo)
killall io.elementary.wingpanel     # reload the panel so the indicator appears
```

`build.sh` clones Inferno and the Statime fork into `deps/` at the commits
this was tested with, and applies the patches in `patches/`. To use your own
checkouts instead: `INFERNO_DIR=... STATIME_DIR=... ./build.sh`.

`install.sh` also does the per-user setup. The first time, it restarts
PipeWire once to apply the sandbox override. When you reinstall while the
soundcard is running, it restarts PipeWire to load the new plugin, and audio
drops for about a second.

To remove everything: `./uninstall.sh`. Your settings in
`~/.config/inferno-dvs` are kept.

## Using it

1. Open **Inferno DVS** from the Applications menu, or from the panel
   indicator's *Soundcard Settings…*.
2. Pick the **network interface** that is on the Dante network, then set the
   **channel counts**, **sample rate** and **latency**, and press **Apply**.
3. Switch it **on**. The first time, you are asked for your password: this
   enables the PTP daemon on that NIC.
4. Wait for the clock line to say **"Locked to leader"**.
5. Patch in Dante Controller, as with any Dante device.
6. In your apps, pick **`<name> (Dante out/in, N ch)`**. To send all desktop
   audio to Dante, turn on **Use as system output**.

elementary's own Sound settings and sound indicator only list hardware sound
cards, so the Dante devices do not show up there. Use the System Output/Input
switches, or pick the device inside your app. Apps with their own device list
(Ardour, Reaper, OBS, `pavucontrol`) show it directly.

### Command line

```text
inferno-dvs-ctl status                      # state and config (keyfile format)
inferno-dvs-ctl start | stop | restart      # PipeWire nodes on/off
inferno-dvs-ctl set rx_channels=16 tx_channels=16 sample_rate=48000 latency_ms=1
inferno-dvs-ctl set pw_quantum=128 tx_ts_offset_us=-100
inferno-dvs-ctl clock-on | clock-off        # PTP daemon for the configured NIC
inferno-dvs-ctl default output on|off       # use as system sink
inferno-dvs-ctl default input on|off        # use as system source
inferno-dvs-ctl autostart on|off            # start with your session
inferno-dvs-ctl interfaces                  # NICs it can use
```

## Troubleshooting

- **Patch stays orange, or fails with "sample rate mismatch"**: the Linux
  device and the other device must run at the same sample rate. Check both in
  Dante Controller.
- **Occasional clicks**: raise the latency or the PipeWire buffer. Check
  `journalctl --user -u pipewire | grep lag` for how late packets arrive.
  From DVS you need about 4 ms. Inferno's
  README has tuning tips (`cyclictest`, `isolcpus`, PREEMPT_RT).
- **A receiver shows the patch green but plays nothing**: power-cycle the
  receiver. We saw a RedNet AM2 get stuck after its source device had
  restarted many times in a row.
- **Clock never locks**: make sure the chosen NIC is on the Dante network and
  a PTPv1 leader exists. See `journalctl -u 'inferno-statime@*'`.
- **Logs**: Inferno runs inside PipeWire, so use `journalctl --user -u pipewire`.
  For the node service: `journalctl --user -u inferno-dvs`.
- The error `unable to receive start time, ring_buffer addressing will be
  wrong!` at startup is harmless. PipeWire prepares each stream twice, and
  Inferno restarts its threads.

## Patches to Inferno

`patches/0003-dante-controller-control-plane.patch` answers Dante Controller
the way real devices do, so Controller shows and controls the device fully.
The byte layouts come from the ESP32 and FPGA AoIP projects, where they were
verified against Controller and against RedNet AM2/A16R and DVS captures:

| Request | Upstream Inferno | With the patch |
|---|---|---|
| Device properties 0x1100 / 0x1102 | all zeros, so Controller classifies the device as PTPv2 domain 0 and has no latency options | a RedNet AM2's tables with our latency, a 0.25 ms minimum and our sample rate |
| Device names 0x1003 | older guessed layout ("Cannot retrieve Device Latency") | the layout real devices send |
| Set latency 0x1101 | ignored | applied (see below) |
| Sample rate | "does not support sample rate configuration" | 44.1/48/88.2/96 kHz offered and settable |
| Clock status 0x20 | fixed seq/opcode that Controller ignores | DVS layout, echoing seq/opcode: PTPv1 follower, leader, frequency offset |
| Heartbeat | 0x8001–0x8003 | adds 0x8000 sync quality (offset and path delay from Statime) and 0x8004 |
| 0x2204, 0x2032, 0x4100, unknown opcodes | no reply, so Controller retries | answered as an AM2 does (0x22 = unsupported) |
| Restart race | a device reopened within a second panicked with "address in use" | waits for the previous instance to release its ports |

Latency and sample rate are fixed while an Inferno instance runs. When
Controller changes them, Inferno answers at once and writes
`controller_request.toml` in its state directory. The user unit
`inferno-dvs-requests.path` notices the file and runs
`inferno-dvs-ctl apply-requests`, which updates your settings and restarts the
PipeWire nodes on the new value.

`patches/0002-realtime-threads-and-tx-timestamp-offset.patch` makes Inferno's
send and receive threads realtime through RealtimeKit when direct
SCHED_FIFO is not allowed. It also makes the packet timestamp offset
configurable (`TX_TS_OFFSET_NS`) and logs send/arrival lag statistics. See
[Latency](#latency).

`patches/0001-mdns-srv-target-device-hostname.patch` fixes Inferno's mDNS
(searchfire). Each channel's SRV record pointed at `<channel>@<device>.local`
instead of the device's host name, and searchfire did not answer A queries for
the host name. Receivers that look the address up from the SRV target, such as
ESP-IDF based devices, could not resolve Inferno's channels and never
subscribed. The patch adds `ServiceBuilder::hostname()` and host-name matching
to searchfire, and uses them for channels and multicast bundles.

## Known limitations

- It is not compatible with Dante Domain Manager and does not support AES67.
- On NICs without a PTP hardware clock it uses software timestamps, which
  worked fine in testing.
- Changing latency or sample rate from Dante Controller restarts the Inferno
  device, so audio drops for a few seconds, much like a hardware device
  re-locking. PipeWire apps keep their streams.
- Meters in Dante Controller are not shown yet.

## License

GPL-3.0-or-later (see `LICENSE`). Inferno is GPL-3.0-or-later OR
AGPL-3.0-or-later. Statime is Apache-2.0 OR MIT.

Credits: Inferno by Teodor Woźniak and contributors; Statime by the Pendulum
project / Trifecta Tech Foundation, with PTPv1 and the virtual clock added in
the `inferno-dev` fork.
