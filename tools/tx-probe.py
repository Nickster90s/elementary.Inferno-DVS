#!/usr/bin/env python3
"""How long does a packet take from our send() to the PTP leader?

Linux port of osx.N-Series.AoIP driver/test/tx-probe.c. The leader answers
every PTPv1 Delay_Req with its hardware receive time t4, so a stream of
Delay_Reqs measures send() -> network stack -> driver -> USB/NIC -> switch ->
leader, packet by packet. Send times are CLOCK_MONOTONIC_RAW; the constant
offset and the few-ppm drift to the leader's clock are removed with a line
fitted through the fastest packet of each second, so what is left is the
extra delay each packet picked up on the way (what receivers see as spread).

usage: tx-probe.py <interface-ipv4> [seconds] [rate/s]
Writes probe.csv (send_raw_ns, extra_us) next to the current directory.
"""
import os
import random
import select
import socket
import struct
import sys
import time

PROBE_UUID = bytes([0x02, ord("N"), ord("S"), ord("P"), ord("R"), ord("B")])
MCAST = "224.0.1.129"


def listener(port, ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                 socket.inet_aton(MCAST) + socket.inet_aton(ip))
    return s


def raw_ns():
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC_RAW)


def main():
    ip = sys.argv[1]
    seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    rate = int(sys.argv[3]) if len(sys.argv) > 3 else 200
    ev, gen = listener(319, ip), listener(320, ip)
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tx.bind((ip, 0))
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 0)
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 46 << 2)  # like the audio

    # a Delay_Req needs the leader's grandmaster fields: wait for a Sync
    tmpl = None
    end = time.monotonic() + 5
    while tmpl is None and time.monotonic() < end:
        if select.select([ev], [], [], 0.3)[0]:
            buf = ev.recv(1500)
            if len(buf) >= 124 and buf[0] == 0 and buf[1] == 1 and buf[32] == 0:
                tmpl = bytearray(buf[:124])
    if tmpl is None:
        sys.exit("no Sync from a PTPv1 leader")
    leader_uuid = bytes(tmpl[22:28])
    leader_port = tmpl[28:30]
    tmpl[20] = 1
    tmpl[22:28] = PROBE_UUID
    tmpl[28:30] = b"\x00\x01"
    tmpl[32] = 1
    tmpl[33:40] = bytes(7)
    b = 40
    tmpl[b:b + 8] = bytes(8)
    tmpl[b + 43] = 0x7F
    tmpl[b + 44:b + 84] = bytes(40)
    tmpl[b + 55] = 255
    tmpl[b + 56:b + 60] = b"DFLT"
    tmpl[b + 61] = 1
    tmpl[b + 62:b + 68] = leader_uuid
    tmpl[b + 70:b + 72] = leader_port

    print(f"probing leader {leader_uuid.hex(':')} from {ip}: {rate}/s for {seconds} s", flush=True)
    sent = {}
    results = []  # (send_raw_ns, t4_ns, call_ns)
    seq = random.randrange(65536)
    interval = 1e9 / rate
    start = raw_ns()
    stop = start + seconds * 1_000_000_000
    nxt = start
    while raw_ns() < stop + 500_000_000:
        now = raw_ns()
        if now >= nxt and now < stop:
            nxt += int(interval / 2 + random.random() * interval)
            seq = (seq + 1) & 0xFFFF
            tmpl[30:32] = struct.pack(">H", seq)
            t0 = raw_ns()
            ok = tx.sendto(tmpl, (MCAST, 319))
            t1 = raw_ns()
            if ok == 124:
                sent[seq] = (t1, t1 - t0)
        if not select.select([gen], [], [], 0.001)[0]:
            continue
        buf = gen.recv(1500)
        if len(buf) < 60 or buf[0] != 0 or buf[1] != 1 or buf[32] != 3 or buf[50:56] != PROBE_UUID:
            continue
        rseq = struct.unpack(">H", buf[58:60])[0]
        if rseq not in sent:
            continue
        t_send, call = sent.pop(rseq)
        sec, ns = struct.unpack(">Ii", buf[40:48])
        results.append((t_send, sec * 1_000_000_000 + ns, call))

    if len(results) < 100:
        sys.exit(f"only {len(results)} answers")
    d = [(ts, t4 - ts, call) for ts, t4, call in results]
    med = sorted(x[1] for x in d)[len(d) // 2]
    d = [x for x in d if abs(x[1] - med) < 2_000_000]  # leader rollover glitches
    # fastest packet per second -> least-squares line = offset + drift
    best = {}
    for ts, tr, _ in d:
        k = (ts - start) // 1_000_000_000
        if k not in best or tr < best[k][1]:
            best[k] = (ts, tr)
    xs = [v[0] for v in best.values()]
    ys = [v[1] for v in best.values()]
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    extra = sorted(((tr - (my + slope * (ts - mx))) / 1000, ts, call / 1000) for ts, tr, call in d)
    base = extra[len(extra) // 1000][0]
    ex = [(e - base, ts, c) for e, ts, c in extra]
    n = len(ex)
    q = lambda p: ex[min(n - 1, int(n * p))][0]
    print(f"{n} answers, {len(sent)} without answer, drift {slope * 1e6:.2f} ppm")
    print(f"extra delay above the fastest 0.1 %, us: median {q(.5):.0f}  p99 {q(.99):.0f}  "
          f"p99.9 {q(.999):.0f}  p99.99 {q(.9999):.0f}  max {ex[-1][0]:.0f}")
    bounds = [25, 50, 100, 150, 200, 300, 400, 600, 800]
    counts = [0] * (len(bounds) + 1)
    for e, _, _ in ex:
        k = 0
        while k < len(bounds) and e >= bounds[k]:
            k += 1
        counts[k] += 1
    print("histogram:", "  ".join(f"<{b}:{c}" for b, c in zip(bounds, counts)), f" >={bounds[-1]}:{counts[-1]}")
    slow = sorted((x for x in ex if x[0] > 150), key=lambda x: x[1])
    print("above 150 us (t s: extra us / sendto us):",
          " ".join(f"{(ts - start) / 1e9:.2f}:{e:.0f}/{c:.0f}" for e, ts, c in slow[:60]) or "none")
    with open("probe.csv", "w") as f:
        f.write("send_raw_ns,extra_us,sendto_us\n")
        for e, ts, c in sorted(ex, key=lambda x: x[1]):
            f.write(f"{ts},{e:.1f},{c:.1f}\n")


if __name__ == "__main__":
    main()
