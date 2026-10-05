#!/usr/bin/env python3
"""Scripted acceptance checks against a real aethyra-server.

    worldtest.py BUILD_DIR [SCENARIO...] [--keep DIR]

BUILD_DIR holds the aethyra-server binary (and libtmwa-shared.so when it was
built shared). Each scenario starts a fresh world copied from server/world,
drives it with protocol clients and prints PASS/FAIL lines; the exit status
is the number of failed checks. --keep copies the final world directory to
DIR so later migrations can be tested against it.

Scenarios: baseline (default).
"""

import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import protoclient as pc  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, '..', 'world')
HOST = '127.0.0.1'
PORT = 6901

failures = []


def check(ok, what):
    print('%s  %s' % ('PASS' if ok else 'FAIL', what))
    if not ok:
        failures.append(what)
    return ok


# --------------------------------------------------------------------------
# World process

class World:
    """A world directory and the server process running it."""

    def __init__(self, build, directory=None, gm_accounts=(2000000,)):
        self.build = os.path.abspath(build)
        self.dir = directory or tempfile.mkdtemp(prefix='aethyra-world-')
        self.proc = None
        if directory is None:
            shutil.rmtree(self.dir)
            shutil.copytree(TEMPLATE, self.dir)
            with open(os.path.join(self.dir, 'save', 'gm_account.txt'), 'w') as f:
                for account in gm_accounts:
                    f.write('%d 99\n' % account)
        self.bin = os.path.join(self.dir, 'bin')
        os.makedirs(self.bin, exist_ok=True)
        os.makedirs(os.path.join(self.dir, 'log'), exist_ok=True)
        for name in os.listdir(self.build):
            if name in ('aethyra-server', 'aethyra-server.exe') or \
                    name.startswith('libtmwa-shared.so'):
                shutil.copy2(os.path.join(self.build, name), self.bin)
        self.stop_file = os.path.join(self.dir, 'server.stop')

    def start(self):
        if os.path.exists(self.stop_file):
            os.remove(self.stop_file)
        exe = os.path.join(self.bin, 'aethyra-server')
        cmd = [exe, '--world', self.dir, '--stop-file', self.stop_file]
        if os.path.exists(exe + '.exe'):  # Windows build: run under Wine
            cmd = ['wine', exe + '.exe', '--world', 'Z:' + self.dir,
                   '--stop-file', 'Z:' + self.stop_file]
        elif os.getuid() == 0:  # the servers refuse to run as root
            subprocess.run(['chown', '-R', 'nobody', self.dir], check=True)
            cmd = ['runuser', '-u', 'nobody', '--'] + cmd
        env = dict(os.environ, LD_LIBRARY_PATH=self.bin)
        self.log = open(os.path.join(self.dir, 'log', 'server.out'), 'ab')
        self.proc = subprocess.Popen(cmd, cwd=self.dir, env=env,
                                     stdout=self.log, stderr=self.log)
        deadline = time.time() + (60 if cmd[0] == "wine" else 20)
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError('server exited; see %s/log' % self.dir)
            try:
                socket.create_connection((HOST, 5121), timeout=1).close()
                time.sleep(0.5)
                return
            except OSError:
                time.sleep(0.2)
        raise RuntimeError('server did not start')

    def stop(self):
        """Stop the way the hosting client does: write the stop file."""
        with open(self.stop_file, 'w') as f:
            f.write('stop\n')
        try:
            self.proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
            return False
        return self.proc.returncode == 0

    def kill(self):
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()


# --------------------------------------------------------------------------
# Player connection with tracked state

def decode_pos2(b):
    sx = (b[0] << 2) | (b[1] >> 6)
    sy = ((b[1] & 0x3f) << 4) | (b[2] >> 4)
    dx = ((b[2] & 0x0f) << 6) | (b[3] >> 2)
    dy = ((b[3] & 0x03) << 8) | b[4]
    return (sx, sy), (dx, dy)


class Player:
    def __init__(self, user, password, slot=0, name=None, register=False):
        self.user, self.password, self.slot = user, password, slot
        if register or name:
            login_name = user + '_M' if register else user
            if name:
                pc.create_char(HOST, PORT, login_name, password, name, slot)
        self.m = None

    def connect(self):
        self.m, self.lengths, self.name, self.pos = pc.enter_map(
            HOST, PORT, self.user, self.password, self.slot)
        self.id = self.m_account_id()
        self.inventory = {}      # index -> [name id, amount]
        self.stats = {}          # sp type -> value
        self.beings = {}         # block id -> {'class', 'pos'}
        self.events = []         # (packet id, body) after the last mark
        self.npc_text = []
        self.npc_state = None    # 'next', 'menu', 'close'
        self.pump(1.0)
        return self

    def m_account_id(self):
        return self._account_id

    def disconnect(self):
        if self.m:
            self.m.sock.close()
            self.m = None

    # --- packet handling
    def pump(self, seconds):
        for pid, body in pc.drain(self.m, self.lengths, seconds):
            self.handle(pid, body)
            self.events.append((pid, body))

    def mark(self):
        self.events = []

    def handle(self, pid, body):
        if pid in (0x0078, 0x01d8, 0x01d9):
            bid, cls = struct.unpack_from('<IH', body, 0)[0], \
                struct.unpack_from('<H', body, 12)[0]
            self.beings[bid] = {'class': cls, 'pos': pc.decode_pos(body[44:47])}
        elif pid == 0x007c:
            bid = struct.unpack_from('<I', body, 0)[0]
            cls = struct.unpack_from('<H', body, 18)[0]
            self.beings[bid] = {'class': cls, 'pos': pc.decode_pos(body[34:37])}
        elif pid in (0x007b, 0x01da):
            bid = struct.unpack_from('<I', body, 0)[0]
            cls = struct.unpack_from('<H', body, 12)[0]
            _, dst = decode_pos2(body[48:53])
            self.beings[bid] = {'class': cls, 'pos': dst}
        elif pid == 0x0080:
            self.beings.pop(struct.unpack_from('<I', body, 0)[0], None)
        elif pid == 0x0217:
            bid, x, y, kind = struct.unpack_from('<IHHB', body, 0)
            if bid == self.id:
                self.pos = (x, y)
            elif bid in self.beings:
                self.beings[bid]['pos'] = (x, y)
        elif pid == 0x0087:
            _, self.pos = decode_pos2(body[4:9])
        elif pid == 0x0088:
            bid, x, y = struct.unpack_from('<IHH', body, 0)
            if bid == self.id:
                self.pos = (x, y)
            elif bid in self.beings:
                self.beings[bid]['pos'] = (x, y)
        elif pid == 0x01ee:
            for i in range(0, len(body), 18):
                ioff, nameid = struct.unpack_from('<HH', body, i)
                amount = struct.unpack_from('<H', body, i + 6)[0]
                self.inventory[ioff - 2] = [nameid, amount]
        elif pid == 0x00a4:
            for i in range(0, len(body), 20):
                ioff, nameid = struct.unpack_from('<HH', body, i)
                self.inventory[ioff - 2] = [nameid, 1]
        elif pid == 0x00a0:
            ioff, amount, nameid = struct.unpack_from('<HHH', body, 0)
            if body[20] == 0:
                entry = self.inventory.setdefault(ioff - 2, [nameid, 0])
                entry[1] += amount
        elif pid == 0x00af:
            ioff, amount = struct.unpack_from('<HH', body, 0)
            entry = self.inventory.get(ioff - 2)
            if entry:
                entry[1] -= amount
                if entry[1] <= 0:
                    del self.inventory[ioff - 2]
        elif pid == 0x00a8:
            ioff, amount, ok = struct.unpack_from('<HHB', body, 0)
            if ok and ioff - 2 in self.inventory:
                self.inventory[ioff - 2][1] = amount
                if amount == 0:
                    del self.inventory[ioff - 2]
        elif pid == 0x01c8:
            ioff, _, bid, amount, ok = struct.unpack_from('<HHIHB', body, 0)
            if ok and bid == self.id and ioff - 2 in self.inventory:
                self.inventory[ioff - 2][1] = amount
                if amount == 0:
                    del self.inventory[ioff - 2]
        elif pid == 0x00b0:
            kind, value = struct.unpack_from('<HI', body, 0)
            self.stats[kind] = value
        elif pid == 0x00b4:
            self.npc_text.append(body[4:].split(b'\0')[0].decode(errors='replace'))
        elif pid == 0x00b5:
            self.npc_state = 'next'
        elif pid == 0x00b7:
            self.npc_state = 'menu'
        elif pid == 0x00b6:
            self.npc_state = 'close'

    # --- queries
    def items(self):
        counts = {}
        for nameid, amount in self.inventory.values():
            counts[nameid] = counts.get(nameid, 0) + amount
        return counts

    def count(self, nameid):
        return self.items().get(nameid, 0)

    def index_of(self, nameid):
        for index, (nid, _) in self.inventory.items():
            if nid == nameid:
                return index
        return None

    def got(self, pid):
        return [body for p, body in self.events if p == pid]

    def slides(self):
        return [struct.unpack_from('<IHHB', b, 0) for b in self.got(0x0217)]

    def find(self, cls):
        """Being ids of a client-visible class (monster ids are sent as is)."""
        return [bid for bid, b in self.beings.items() if b['class'] == cls]

    # --- actions
    def say(self, text):
        pc.say(self.m, self.name, text)

    def skill(self, skill, direction):
        pc.use_skill(self.m, skill, direction)

    def walk(self, x, y):
        self.m.send(struct.pack('<H', 0x0085) + pc.encode_pos(x, y))

    def use_item(self, index):
        self.m.send(struct.pack('<HHI', 0x00a7, index + 2, 0))

    def npc_click(self, npc):
        self.m.send(struct.pack('<HIB', 0x0090, npc, 0))

    def npc_next(self, npc):
        self.m.send(struct.pack('<HI', 0x00b9, npc))

    def npc_menu(self, npc, choice):
        self.m.send(struct.pack('<HIB', 0x00b8, npc, choice))

    def npc_close(self, npc):
        self.m.send(struct.pack('<HI', 0x0146, npc))

    def talk(self, npc, choices):
        """Run a dialogue, answering menus with choices in order."""
        self.npc_text = []
        self.npc_state = None
        self.npc_click(npc)
        choices = list(choices)
        for _ in range(20):
            self.pump(0.5)
            state, self.npc_state = self.npc_state, None
            if state == 'next':
                self.npc_next(npc)
            elif state == 'menu':
                self.npc_menu(npc, choices.pop(0))
            elif state == 'close':
                self.npc_close(npc)
                self.pump(0.5)
                return True
        return False


# enter_map does not expose the account id; wrap it so Player can learn it.
_enter_map = pc.enter_map


def _enter_map_tracking(host, port, user, password, slot):
    original = pc.char_connect

    def char_connect(*args):
        c, chars = original(*args)
        Player._last_account = c.account_id
        return c, chars
    pc.char_connect = char_connect
    try:
        return _enter_map(host, port, user, password, slot)
    finally:
        pc.char_connect = original


pc.enter_map = _enter_map_tracking
Player.m_account_id = lambda self: Player._last_account


# --------------------------------------------------------------------------
# Scenarios

AMA = 105           # NPC class
HERB, PETAL, TONIC, REED, FIBER = 703, 704, 710, 701, 702
WILD_HERB, WINDFLOWER, MEADOW_GRASS, HOPPER = 1102, 1103, 1101, 1010


def spawn(player, mob, dx, dy=0):
    x, y = player.pos
    player.say('@spawn %d 1 %d %d' % (mob, x + dx, y + dy))
    player.pump(0.6)


def baseline(build, keep=None):
    world = World(build)
    print('world: %s' % world.dir)
    try:
        world.start()
        a = Player('aethyra-test', 'test-pass', name='Wanderer')
        b = Player('friend', 'friend-pass', name='Breezy', register=True)
        a.connect()
        b.connect()
        a.pump(0.5)
        check(a.id in b.beings and b.id in a.beings,
              'two players see each other on gale-1')
        npcs = a.find(AMA)
        check(len(npcs) == 1, 'Windkeeper Ama is visible')

        # Wind Scythe harvests in front; both clients see the plant go.
        a.walk(12, 24)
        a.pump(1.5)
        start = dict(a.items())
        spent = []
        for mob in (WILD_HERB, WILD_HERB, WILD_HERB,
                    WINDFLOWER, WINDFLOWER, WINDFLOWER):
            spawn(a, mob, 1)
            b.pump(0.1)
            plants = [i for i in a.find(mob)
                      if a.beings[i]['pos'] == (a.pos[0] + 1, a.pos[1])]
            a.mark()
            b.mark()
            pre = a.stats.get(7)
            a.skill('scythe', 'right')
            a.pump(1.0)
            sp_after = [struct.unpack_from('<HI', x, 0)[1]
                        for x in a.got(0x00b0)
                        if struct.unpack_from('<H', x, 0)[0] == 7]
            spent.append((pre, sp_after))
            b.pump(0.3)
            cut = all(p not in a.beings for p in plants) and plants
            seen = all(p in [struct.unpack_from('<I', x, 0)[0]
                             for x in b.got(0x0080)] for p in plants)
            check(bool(cut) and seen,
                  'Wind Scythe cuts %d (seen by both clients)' % mob)
        check(a.count(HERB) - start.get(HERB, 0) >= 3 and
              a.count(PETAL) - start.get(PETAL, 0) >= 3,
              'harvest gives 3 Meadow Herbs and 3 Windflower Petals '
              '(have %s)' % a.items())
        check(all(any(y < x for x, y in zip([pre] + after, after))
                  for pre, after in spent),
              'Wind Scythe spends Gale energy %s' % spent)

        # Gust knocks a hopper back without damage; B sees the slide.
        spawn(a, HOPPER, 1)
        hoppers = [i for i in a.find(HOPPER)
                   if a.beings[i]['pos'] == (a.pos[0] + 1, a.pos[1])]
        a.mark()
        b.mark()
        time.sleep(1.6)  # skill cooldowns
        a.skill('gust', 'right')
        a.pump(1.0)
        b.pump(0.3)
        knocked = [s for s in a.slides() if s[0] in hoppers and s[3] == 1]
        check(bool(knocked) and knocked[0][1] > a.pos[0] + 1,
              'Gust knocks the hopper back %s' % knocked)
        check(any(s[0] in hoppers for s in b.slides()),
              'second client sees the knockback')
        hits = [x for x in a.got(0x008a)
                if struct.unpack_from('<II', x, 0) [0] == a.id and
                struct.unpack_from('<II', x, 0)[1] in hoppers]
        check(not hits and all(h in a.beings for h in hoppers),
              'Gust does no damage')

        # Dash moves the player; B sees it.
        before = a.pos
        a.mark()
        b.mark()
        time.sleep(1.3)
        a.skill('dash', 'left')
        a.pump(1.0)
        b.pump(0.3)
        mine = [s for s in a.slides() if s[0] == a.id and s[3] == 0]
        check(bool(mine) and a.pos[0] < before[0],
              'Dash moves the player %s -> %s' % (before, a.pos))
        check(any(s[0] == a.id for s in b.slides()),
              'second client sees the dash')

        # Ama's exchange.
        a.walk(13, 23)
        a.pump(1.5)
        herbs, petals = a.count(HERB), a.count(PETAL)
        ok = a.talk(npcs[0], [2])
        check(ok and a.count(TONIC) == 1 and a.count(HERB) == herbs - 3 and
              a.count(PETAL) == petals - 3,
              "Ama's exchange: 3 herbs + 3 petals -> Gale Tonic")

        # Use the tonic.
        a.mark()
        a.use_item(a.index_of(TONIC))
        a.pump(1.0)
        used = [struct.unpack_from('<HHIHB', x, 0) for x in a.got(0x01c8)]
        check(bool(used) and used[0][4] == 1 and a.count(TONIC) == 0,
              'Gale Tonic is consumed on use')

        # Reconnect keeps inventory and position.
        snapshot, where = a.items(), a.pos
        a.disconnect()
        b.pump(1.5)
        check(a.id not in b.beings, 'second client sees the player leave')
        time.sleep(1)
        a.connect()
        check(a.items() == snapshot,
              'reconnect keeps inventory %s (was %s)' % (a.items(), snapshot))
        check(a.pos == where, 'reconnect keeps position %s' % (a.pos,))

        # Host restart keeps everything.
        a.disconnect()
        b.disconnect()
        time.sleep(1)
        check(world.stop(), 'server stops cleanly via the stop file')
        world.start()
        a.connect()
        check(a.items() == snapshot,
              'host restart keeps inventory %s' % a.items())
        check(a.pos == where, 'host restart keeps position %s' % (a.pos,))
        b.connect()
        check(a.id in b.beings, 'friend rejoins after restart')
        a.disconnect()
        b.disconnect()
        time.sleep(1)
        world.stop()
    finally:
        world.kill()
        if keep:
            if os.path.exists(keep):
                shutil.rmtree(keep)
            shutil.copytree(world.dir, keep, ignore=shutil.ignore_patterns(
                'bin', 'log', 'server.stop'))
            print('world kept in %s' % keep)


SCENARIOS = {'baseline': baseline}


def main(argv):
    args = argv[1:]
    keep = None
    if '--keep' in args:
        i = args.index('--keep')
        keep = args[i + 1]
        del args[i:i + 2]
    if not args:
        sys.stderr.write(__doc__)
        return 2
    build, names = args[0], args[1:] or ['baseline']
    for name in names:
        print('== %s' % name)
        SCENARIOS[name](build, keep)
    print('%d check(s) failed' % len(failures))
    return len(failures)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
