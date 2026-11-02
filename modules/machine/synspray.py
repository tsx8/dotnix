#!/usr/bin/env python3
"""Replay outgoing IPv6 TCP SYNs at a fixed spacing.

The campus IPv6 path drops the occasional packet, and a lost SYN costs the
caller a full 1 s TCP RTO. Spacing byte-identical copies 20 ms apart keeps the
5-tuple and ISN unchanged, so the server treats them as retransmissions of one
attempt while the copies land on different queue states.

Passive: frames are cloned off the wire and reinjected, so the kernel still
owns the connection and no data path is redirected. Once the server's SYN-ACK
is seen the remaining copies are dropped, so a healthy handshake pays no extra
packets.
"""

import ctypes
import heapq
import itertools
import select
import socket
import struct
import sys
import time

IFACE = sys.argv[1] if len(sys.argv) > 1 else "eno1"
COPIES = int(sys.argv[2]) if len(sys.argv) > 2 else 7
GAP = float(sys.argv[3]) if len(sys.argv) > 3 else 0.020
RESPRAY_WINDOW = 3.0
RESPRAY_LIMIT = 2
STATE_TTL = 2.0

ETHERTYPE_IPV6 = 0x86DD
IPV6_NEXTHDR = 14 + 6
TCP_FLAGS = 14 + 40 + 13
SO_ATTACH_FILTER = 26
FLAG_SYN = 0x02
FLAG_ACK = 0x10

# Socket-level filter so the kernel wakes us only for IPv6 TCP SYN and SYN-ACK.
# The capture socket has to be ETH_P_ALL because the kernel delivers outgoing
# frames only to ptype_all; without the filter every packet would be copied and
# queued, which is a core of work during a large download. Offsets are absolute
# from the link-layer header.
BPF_LD, BPF_ALU, BPF_JMP, BPF_RET = 0x00, 0x04, 0x05, 0x06
BPF_W, BPF_H, BPF_B, BPF_IMM, BPF_ABS = 0x00, 0x08, 0x10, 0x00, 0x20
BPF_JEQ, BPF_AND, BPF_K = 0x10, 0x50, 0x00


def attachSynFilter(sock):
    prog = [
        (BPF_LD | BPF_H | BPF_ABS, 0, 0, 12),
        (BPF_JMP | BPF_JEQ | BPF_K, 0, 6, ETHERTYPE_IPV6),
        (BPF_LD | BPF_B | BPF_ABS, 0, 0, IPV6_NEXTHDR),
        (BPF_JMP | BPF_JEQ | BPF_K, 0, 4, socket.IPPROTO_TCP),
        (BPF_LD | BPF_B | BPF_ABS, 0, 0, TCP_FLAGS),
        (BPF_ALU | BPF_AND | BPF_K, 0, 0, FLAG_SYN),
        (BPF_JMP | BPF_JEQ | BPF_K, 0, 1, FLAG_SYN),
        (BPF_RET | BPF_K, 0, 0, 0xFFFF),
        (BPF_RET | BPF_K, 0, 0, 0),
    ]
    raw = b"".join(struct.pack("HBBI", code, jt, jf, k) for code, jt, jf, k in prog)
    code = ctypes.create_string_buffer(raw, len(raw))
    sock.setsockopt(
        socket.SOL_SOCKET,
        SO_ATTACH_FILTER,
        struct.pack("<H6xQ", len(prog), ctypes.addressof(code)),
    )


def parseTcp(frame):
    """Return (flag, local_port, remote_port, key) for IPv6 TCP, else None."""
    if len(frame) < 54:
        return None
    off = 14
    ethertype = struct.unpack("!H", frame[12:14])[0]
    if ethertype == 0x8100:
        off = 18
        ethertype = struct.unpack("!H", frame[16:18])[0]
    if ethertype != ETHERTYPE_IPV6:
        return None
    ip = frame[off:]
    if len(ip) < 41 or (ip[0] >> 4) != 6 or ip[6] != socket.IPPROTO_TCP:
        return None
    tcp = ip[40:]
    flags = tcp[13]
    if not flags & FLAG_SYN:
        return None
    doff = (tcp[12] >> 4) * 4
    sport, dport = struct.unpack("!HH", tcp[0:4])
    seq = struct.unpack("!I", tcp[4:8])[0]
    if flags & FLAG_ACK:
        return flags, dport, sport, None
    return flags, sport, dport, (sport, seq, bytes(tcp[20:doff]))


class Sprayer:
    def __init__(self, iface, copies, gap):
        self.copies = copies
        self.gap = gap
        self.pending = []
        self.seq = itertools.count()
        self.echo = {}
        self.sprayed = {}
        self.cap = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        self.cap.bind((iface, 0))
        attachSynFilter(self.cap)
        # Protocol 0 keeps the send socket from queueing received frames.
        self.snd = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, 0)
        self.snd.bind((iface, 0))
        self.nextPrune = 0.0

    def flush(self, now):
        while self.pending and self.pending[0][0] <= now:
            _, _, frame, _ = heapq.heappop(self.pending)
            self.snd.send(frame)

    def cancel(self, flow):
        kept = [e for e in self.pending if e[3] != flow]
        if len(kept) != len(self.pending):
            self.pending = kept
            heapq.heapify(self.pending)

    def prune(self, now):
        self.echo = {k: v for k, v in self.echo.items() if now - v[1] < STATE_TTL}
        self.sprayed = {
            f: [t for t in ts if now - t < RESPRAY_WINDOW] for f, ts in self.sprayed.items()
        }
        self.sprayed = {f: ts for f, ts in self.sprayed.items() if ts}

    def handle(self, frame, now):
        parsed = parseTcp(frame)
        if parsed is None:
            return
        flags, local, remote, key = parsed
        flow = (local, remote)
        if key is None:
            if self.echo:
                self.cancel(flow)
            return
        if self.echo.get(key, (0, 0))[0] > 0:
            self.echo[key] = (self.echo[key][0] - 1, now)
            return
        recent = self.sprayed.get(flow, [])
        if len(recent) >= RESPRAY_LIMIT or self.copies <= 0:
            self.sprayed[flow] = recent
            return
        recent.append(now)
        self.sprayed[flow] = recent
        for i in range(1, self.copies + 1):
            heapq.heappush(self.pending, (now + i * self.gap, next(self.seq), frame, flow))
        self.echo[key] = (self.copies, now)

    def run(self):
        while True:
            now = time.time()
            self.flush(now)
            if now >= self.nextPrune:
                self.prune(now)
                self.nextPrune = now + 1.0
            if self.pending:
                timeout = max(0.0, self.pending[0][0] - now)
            else:
                timeout = max(0.0, self.nextPrune - now)
            readable, _, _ = select.select([self.cap], [], [], timeout)
            if readable:
                self.handle(self.cap.recv(65535), time.time())


if __name__ == "__main__":
    try:
        Sprayer(IFACE, COPIES, GAP).run()
    except KeyboardInterrupt:
        pass
