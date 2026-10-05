#!/usr/bin/env python3
"""Minimal protocol client for scripting and testing an Aethyra server.

It speaks the same login/char packets as the game client, so it can set up
test accounts and characters without the GUI:

    protoclient.py create-char HOST PORT USER PASS NAME [SLOT]
    protoclient.py list-chars  HOST PORT USER PASS
    protoclient.py walk        HOST PORT USER PASS SLOT X Y [LINGER_SECS]
    protoclient.py skills      HOST PORT USER PASS SLOT

"walk" enters the map with the character in SLOT, walks to (X, Y), reports
the server's answer and stays connected for LINGER_SECS so other clients
can observe it.

Append _M or _F to USER to register a new account on first login (the
server must have new_account enabled).
"""

import os
import re
import socket
import struct
import sys
import time

# Aethyra protocol 2 (AETHYRA_PROTOCOL_BASE + 2); see server mmo/version.hpp.
CLIENT_PROTOCOL_VERSION = 102


class Conn:
    def __init__(self, host, port):
        self.sock = socket.create_connection((host, port), timeout=5)
        self.buf = b''

    def send(self, data):
        self.sock.sendall(data)

    def read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError('server closed the connection')
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    def packet(self, sizes):
        """Read one packet; sizes maps id -> fixed size, or -1 for variable."""
        pid = struct.unpack('<H', self.read(2))[0]
        size = sizes.get(pid)
        if size is None:
            raise ValueError('unexpected packet 0x%04x' % pid)
        if size == -1:
            size = struct.unpack('<H', self.read(2))[0]
            return pid, self.read(size - 4)
        return pid, self.read(size - 2)


def client_packet_lengths():
    """Packet sizes the client expects, read from its own table.

    The client source is the reference for what the server may send to it,
    so the test client uses the same table rather than keeping a copy.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, '..', '..', 'src', 'eathena', 'net', 'network.cpp')
    with open(path) as f:
        text = f.read()
    start = text.index('packet_lengths[] = {') + len('packet_lengths[] = {')
    body = re.sub(r'//[^\n]*', '', text[start:text.index('};', start)])
    values = [int(v) for v in body.replace('\n', ' ').split(',') if v.strip()]
    return {pid: size for pid, size in enumerate(values) if size != 0}


def encode_pos(x, y, direction=0):
    return bytes([(x >> 2) & 0xff, ((x << 6) | (y >> 4)) & 0xff,
                  ((y << 4) | direction) & 0xff])


def decode_pos(b):
    return (b[0] << 2) | (b[1] >> 6), ((b[1] & 0x3f) << 4) | (b[2] >> 4)


def fixed_str(text, size):
    return text.encode()[:size - 1].ljust(size, b'\0')


def login(host, port, user, password):
    c = Conn(host, port)
    c.send(struct.pack('<HI24s24sB', 0x0064, CLIENT_PROTOCOL_VERSION,
                       fixed_str(user, 24), fixed_str(password, 24), 0x01))
    while True:
        pid, body = c.packet({0x0063: -1, 0x0069: -1, 0x006a: 23, 0x0081: 3})
        if pid == 0x0063:
            continue  # update host
        if pid != 0x0069:
            raise RuntimeError('login refused: packet 0x%04x code %d'
                               % (pid, body[0]))
        login_id1, account_id, login_id2 = struct.unpack_from('<III', body, 0)
        sex = body[42]
        servers = body[43:]
        ip = socket.inet_ntoa(servers[0:4])
        char_port = struct.unpack_from('<H', servers, 4)[0]
        return account_id, login_id1, login_id2, sex, ip, char_port


def char_connect(host, port, user, password):
    account_id, id1, id2, sex, ip, char_port = login(host, port, user, password)
    if ip in ('0.0.0.0', '127.0.0.1'):
        ip = host
    c = Conn(ip, char_port)
    c.account_id, c.login_id1, c.sex = account_id, id1, sex
    c.send(struct.pack('<HIIIHB', 0x0065, account_id, id1, id2,
                       CLIENT_PROTOCOL_VERSION, sex))
    c.read(4)  # 0x8000 hold packet
    pid, body = c.packet({0x006b: -1, 0x006c: 3, 0x0081: 3})
    if pid != 0x006b:
        raise RuntimeError('char server refused: 0x%04x' % pid)
    chars = []
    entries = body[20:]
    for i in range(0, len(entries), 106):
        entry = entries[i:i + 106]
        name = entry[74:98].split(b'\0')[0].decode()
        slot = entry[104]
        chars.append((slot, name))
    return c, chars


def create_char(host, port, user, password, name, slot=0):
    c, chars = char_connect(host, port, user, password)
    if any(n == name for _, n in chars):
        print('character %s already exists' % name)
        return 0
    stats = bytes([5] * 6)  # placeholder until stats are replaced by hues
    c.send(struct.pack('<H24s6sBHH', 0x0067, fixed_str(name, 24), stats,
                       slot, 0, 0))
    pid, body = c.packet({0x006d: 108, 0x006e: 3})
    if pid != 0x006d:
        print('character creation refused (code %d)' % body[0])
        return 1
    print('created character %s in slot %d' % (name, slot))
    return 0


def enter_map(host, port, user, password, slot):
    """Log in, select the character in slot and enter the map.

    Returns (map connection, packet lengths, character name, (x, y)).
    """
    c, chars = char_connect(host, port, user, password)
    name = dict(chars).get(slot, '')
    c.send(struct.pack('<HB', 0x0066, slot))
    pid, body = c.packet({0x0071: 28, 0x006c: 3, 0x0081: 3})
    if pid != 0x0071:
        raise RuntimeError('character select refused: 0x%04x' % pid)
    char_id = struct.unpack_from('<I', body, 0)[0]
    map_ip = socket.inet_ntoa(body[20:24])
    map_port = struct.unpack_from('<H', body, 24)[0]
    if map_ip in ('0.0.0.0', '127.0.0.1'):
        map_ip = host

    m = Conn(map_ip, map_port)
    m.send(struct.pack('<HIIIIB', 0x0072, c.account_id, char_id, c.login_id1,
                       0, c.sex))
    m.read(4)  # 0x8000 hold packet
    lengths = client_packet_lengths()
    pid, body = m.packet(lengths)
    if pid != 0x0073:
        raise RuntimeError('map server refused: 0x%04x' % pid)
    pos = decode_pos(body[4:7])
    print('entered map at (%d, %d)' % pos)
    m.send(struct.pack('<H', 0x007d))  # map loaded
    m.sock.settimeout(0.2)
    return m, lengths, name, pos


def drain(m, lengths, seconds):
    """Read packets for a while; returns [(id, body)]."""
    got = []
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            got.append(m.packet(lengths))
        except socket.timeout:
            continue
    return got


def walk(host, port, user, password, slot, x, y, linger):
    m, lengths, _, _ = enter_map(host, port, user, password, slot)
    m.send(struct.pack('<H', 0x0085) + encode_pos(x, y))
    result = 1
    for pid, body in drain(m, lengths, max(linger, 3)):
        if pid == 0x0087:
            src = decode_pos(body[4:7])
            print('walk accepted: (%d, %d) -> (%d, %d)' % (
                src[0], src[1], x, y))
            result = 0
    if result:
        print('no walk response from server')
    return result


def say(m, name, text):
    message = ('%s : %s' % (name, text)).encode() + b'\0'
    m.send(struct.pack('<HH', 0x008c, len(message) + 4) + message)


SKILLS = {'dash': 1, 'gust': 2, 'scythe': 3}
DIRS = {'down': 1, 'left': 2, 'up': 4, 'right': 8}


_request = [0]


def use_skill(m, skill, direction, flags=0, request=None):
    """Send a hue action; skill is a name or a numeric skill id."""
    if request is None:
        _request[0] += 1
        request = _request[0]
    skill_id = SKILLS.get(skill, skill)
    m.send(struct.pack('<HHBBI', 0x0218, skill_id, DIRS[direction], flags,
                       request))
    return request


def describe(packets, self_id=None):
    """Summarise the packets the skills produce."""
    lines = []
    for pid, body in packets:
        if pid == 0x0217:
            bid, x, y, kind = struct.unpack_from('<IHHB', body, 0)
            who = 'self' if bid == self_id else 'being %d' % bid
            lines.append('slide %s -> (%d, %d) %s'
                         % (who, x, y, ('dash', 'knockback')[kind]))
        elif pid == 0x00b0 and struct.unpack_from('<H', body, 0)[0] == 7:
            lines.append('gale energy now %d' % struct.unpack_from('<I', body, 2)[0])
        elif pid == 0x00a0:
            amount, item = struct.unpack_from('<HH', body, 2)
            lines.append('got item %d x%d' % (item, amount))
        elif pid == 0x0080:
            lines.append('being %d removed' % struct.unpack_from('<I', body, 0)[0])
        elif pid == 0x019b:
            lines.append('effect %d' % struct.unpack_from('<I', body, 4)[0])
        elif pid == 0x008e:
            lines.append('message: %s' % body[2:].split(b'\0')[0].decode(errors='replace'))
    return lines


def skills_test(host, port, user, password, slot):
    """Spawn a plant and a hopper beside the character (needs GM level for
    @spawn), then use Wind Scythe, Gust and Dash and report the results."""
    m, lengths, name, (x, y) = enter_map(host, port, user, password, slot)
    drain(m, lengths, 1)
    say(m, name, '@spawn 1101 1 %d %d' % (x + 1, y))
    say(m, name, '@spawn 1010 1 %d %d' % (x + 2, y))
    drain(m, lengths, 1)
    for skill, direction, wait in (('scythe', 'right', 1.0),
                                   ('gust', 'right', 1.0),
                                   ('dash', 'left', 1.0)):
        use_skill(m, skill, direction)
        print('== %s %s' % (skill, direction))
        for line in describe(drain(m, lengths, wait)):
            print('   ' + line)
    return 0


def main(argv):
    if len(argv) == 7 and argv[1] == 'skills':
        return skills_test(argv[2], int(argv[3]), argv[4], argv[5], int(argv[6]))
    if len(argv) >= 9 and argv[1] == 'walk':
        linger = float(argv[9]) if len(argv) > 9 else 0
        return walk(argv[2], int(argv[3]), argv[4], argv[5], int(argv[6]),
                    int(argv[7]), int(argv[8]), linger)
    if len(argv) >= 6 and argv[1] == 'create-char':
        slot = int(argv[7]) if len(argv) > 7 else 0
        return create_char(argv[2], int(argv[3]), argv[4], argv[5], argv[6],
                           slot)
    if len(argv) == 6 and argv[1] == 'list-chars':
        _, chars = char_connect(argv[2], int(argv[3]), argv[4], argv[5])
        for slot, name in chars:
            print('%d %s' % (slot, name))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
