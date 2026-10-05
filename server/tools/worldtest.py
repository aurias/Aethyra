#!/usr/bin/env python3
"""Scripted acceptance checks against a real aethyra-server.

    worldtest.py BUILD_DIR [SCENARIO...] [--keep DIR]

BUILD_DIR holds the aethyra-server binary (and libtmwa-shared.so when it was
built shared). Each scenario starts a fresh world copied from server/world,
drives it with protocol clients and prints PASS/FAIL lines; the exit status
is the number of failed checks. --keep copies the final world directory to
DIR so later migrations can be tested against it.

Scenarios: baseline (default), pass1, migration.
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
        # Own process group: runuser/wine wrappers must not outlive a kill.
        self.proc = subprocess.Popen(cmd, cwd=self.dir, env=env,
                                     stdout=self.log, stderr=self.log,
                                     start_new_session=True)
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
            self.kill()
            return False
        return self.proc.returncode == 0

    def kill(self):
        if self.proc:
            try:
                os.killpg(self.proc.pid, 9)
            except ProcessLookupError:
                pass
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
        self.hue = {}            # hue index -> dict (0x021a)
        self.hue_head = {}
        self.skills = {}         # skill id -> (rank, proficiency)
        self.lots = {}           # index -> dict (0x021c)
        self.results = []        # 0x0219 results, newest last
        self.definitions = []
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
                    self.lots.pop(ioff - 2, None)
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
        elif pid == 0x021a:
            origin, version, points, ceiling, active, balance = \
                struct.unpack_from('<BBhBBH', body, 0)
            self.hue_head = dict(origin=origin, version=version,
                                 points=points, ceiling=ceiling,
                                 active=active, balance=balance)
            self.hue = {}
            for i in range(8, len(body), 30):
                (hue, access, mastery, cap, xp, nxt, energy, capacity, regen,
                 regen_pct, current, flow, allowance, used) = \
                    struct.unpack_from('<BBBBIIiiHHHHBB', body, i)
                self.hue[hue] = dict(mastery=mastery, cap=cap, xp=xp,
                                     next=nxt, energy=energy,
                                     capacity=capacity, regen=regen,
                                     regen_pct=regen_pct, current=current,
                                     flow=flow, allowance=allowance,
                                     used=used)
        elif pid == 0x021b:
            self.skills = {}
            for i in range(0, len(body), 7):
                sid, rank, prof = struct.unpack_from('<HBI', body, i)
                self.skills[sid] = (rank, prof)
        elif pid == 0x021c:
            ioff, nameid, charge, cond, supply = struct.unpack_from('<HHIHB', body, 0)
            self.lots[ioff - 2] = dict(item=nameid, charge=charge,
                                       condition=cond, supply=supply)
        elif pid == 0x0219:
            fields = struct.unpack_from('<IHBBHHHHHH', body, 0)
            names = ('request', 'skill', 'outcome', 'reason', 'energy',
                     'current', 'channel', 'personal', 'vessel', 'detail')
            r = dict(zip(names, fields))
            r['vessels'] = []
            for i in range(20, len(body), 11):
                ioff, nameid, amount, spent, fate, load = \
                    struct.unpack_from('<HHHHBH', body, i)
                r['vessels'].append(dict(index=ioff - 2, item=nameid,
                                         amount=amount, spent=spent,
                                         fate=fate, load=load))
            self.results.append(r)
        elif pid == 0x021f:
            self.definitions = [body[i:i + 136] for i in range(0, len(body), 136)]
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

    def gale(self):
        return self.hue.get(0, {}).get('energy')

    def act(self, skill, direction, flags=0, wait=0.6, request=None):
        """Use a skill; returns the server's result (or None)."""
        before = len(self.results)
        req = pc.use_skill(self.m, skill, direction, flags, request)
        self.pump(wait)
        for r in self.results[before:]:
            if r['request'] == req:
                return r
        return None

    def learn(self, skill, wait=0.5):
        before = len(self.results)
        self.m.send(struct.pack('<HH', 0x021e, skill))
        self.pump(wait)
        return self.results[-1] if len(self.results) > before else None

    def select(self, index, on=True, wait=0.5):
        before = len(self.results)
        self.m.send(struct.pack('<HHB', 0x021d, index + 2, 1 if on else 0))
        self.pump(wait)
        return self.results[-1] if len(self.results) > before else None

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
        check(a.hue_head.get('version') == 1 and 0 in a.hue,
              'new character has hue state v1 with Gale %s' % a.hue.get(0))
        for mob in (WILD_HERB, WILD_HERB, WILD_HERB,
                    WINDFLOWER, WINDFLOWER, WINDFLOWER):
            spawn(a, mob, 1)
            b.pump(0.1)
            plants = [i for i in a.find(mob)
                      if a.beings[i]['pos'] == (a.pos[0] + 1, a.pos[1])]
            a.mark()
            b.mark()
            r = a.act('scythe', 'right', wait=1.0)
            spent.append((r or {}).get('personal'))
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
        check(all(x == 4 for x in spent),
              'Wind Scythe spends 4 Gale energy each time %s' % spent)

        # Gust knocks a hopper back without damage; B sees the slide.
        spawn(a, HOPPER, 1)
        hoppers = [i for i in a.find(HOPPER)
                   if a.beings[i]['pos'] == (a.pos[0] + 1, a.pos[1])]
        a.mark()
        b.mark()
        time.sleep(1.6)  # skill cooldowns
        a.act('gust', 'right', wait=1.0)
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
        a.act('dash', 'left', wait=1.0)
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


# --------------------------------------------------------------------------
# Pass 1: character/hue/skill records, vessels, the shared resolver

OK, NO_ENERGY, CURRENT_LIMITED, OVERLOAD_RISK = 0, 9, 10, 11
NO_POINTS, NEEDS_LEVEL, NEEDS_MASTERY, NEEDS_PROF = 14, 15, 16, 17
OVERLOAD_FAILED = 21
REJECTED, SUCCEEDED, FAILED, LEARNED, SUPPLY = 0, 1, 2, 3, 4
SAFE, STRAINED, DESTROYED = 0, 1, 2
TEMPERED = 706
DASH, GUST, SCYTHE, FLOW = 1, 2, 3, 10


def gm(player, *commands, wait=0.4):
    for c in commands:
        player.say(c)
    player.pump(wait)


def summary(r):
    if not r:
        return 'no result'
    keys = ('outcome', 'reason', 'energy', 'current', 'channel', 'personal',
            'vessel', 'detail')
    return ' '.join('%s=%s' % (k, r[k]) for k in keys) + \
        (' vessels=%s' % r['vessels'] if r['vessels'] else '')


def hopper_ahead(a):
    """Spawn a Gust Hopper just right of the player; return its ids."""
    gm(a, '@killmonster2', '@heal', wait=0.3)
    spawn(a, HOPPER, 1)
    return [i for i in a.find(HOPPER)
            if a.beings[i]['pos'] == (a.pos[0] + 1, a.pos[1])]


def ready(a):
    """Full Gale energy and skills off cooldown."""
    gm(a, '@hueset energy gale 999', wait=0.2)
    time.sleep(1.6)
    a.pump(0.3)


def lot(a, index):
    return a.lots.get(index, {})


def gust(a, flags=0):
    ids = hopper_ahead(a)
    ready(a)
    a.mark()
    r = a.act(GUST, 'right', flags, wait=1.0)
    pushed = [sl for sl in a.slides() if sl[0] in ids]
    return r, pushed


def dash_distance(a, x=6, y=24):
    gm(a, '@warp gale-1 %d %d' % (x, y), wait=1.0)
    a.pos = (x, y)
    ready(a)
    r = a.act(DASH, 'right', wait=0.8)
    return r, a.pos[0] - x


def pass1(build, keep=None):
    world = World(build)
    print('world: %s' % world.dir)
    try:
        world.start()
        a = Player('aethyra-test', 'test-pass', name='Wanderer').connect()
        b = Player('friend', 'friend-pass', name='Breezy', register=True).connect()
        a.pump(0.5)

        # Inspection: a new character's records.
        g = a.hue.get(0, {})
        check(g.get('mastery') == 1 and g.get('cap') == 10 and
              g.get('energy') == g.get('capacity') == 60 and
              g.get('current') == 6 and g.get('allowance') == 1,
              'Gale record: mastery 1/10, energy 60/60, channel 6, '
              'allowance 1 (%s)' % g)
        check(a.skills == {DASH: (1, 0), GUST: (1, 0), SCYTHE: (1, 0)} and
              a.hue_head.get('points') == 0,
              'starting skills Dash/Gust/Wind Scythe rank 1, 0 points '
              '(%s, %s)' % (a.skills, a.hue_head))
        check(len(a.definitions) >= 10, 'client received %d definitions'
              % len(a.definitions))

        r, d1 = dash_distance(a)
        check(r and r['outcome'] == SUCCEEDED and d1 == 6,
              'Dash rank 1 travels 6 tiles (%s)' % d1)

        # Safe reusable use from the personal reserve.
        r, pushed = gust(a)
        check(r and r['outcome'] == SUCCEEDED and r['personal'] == 15 and
              r['vessel'] == 0 and pushed,
              'Gust rank 1 from personal reserve: %s' % summary(r))
        b.pump(0.3)

        # Insufficient energy: rejected before anything is spent.
        gm(a, '@hueset energy gale 5')
        time.sleep(1.6)
        a.mark()
        r = a.act(GUST, 'right')
        check(r and r['outcome'] == REJECTED and r['reason'] == NO_ENERGY
              and r['personal'] == 0 and not a.slides(),
              'insufficient energy rejects Gust: %s' % summary(r))

        # A repeated request resolves once.
        ready(a)
        pc._request[0] += 1
        req = pc._request[0]
        pc.use_skill(a.m, SCYTHE, 'right', 0, req)
        pc.use_skill(a.m, SCYTHE, 'right', 0, req)
        a.pump(0.8)
        same = [x for x in a.results if x['request'] == req]
        check(len(same) == 1 and same[0]['personal'] == 4,
              'a duplicated request resolves once (%d results)' % len(same))

        # Proficiency and mastery progress from a meaningful use.
        prof0, xp0 = a.skills[GUST][1], a.hue[0]['xp']
        r, pushed = gust(a)
        check(pushed and a.skills[GUST][1] == prof0 + 5 and
              a.hue[0]['xp'] > xp0,
              'displacing an enemy advances Gust proficiency %d -> %d and '
              'mastery progress %d -> %d' % (prof0, a.skills[GUST][1], xp0,
                                             a.hue[0]['xp']))
        prof1, xp1 = a.skills[GUST][1], a.hue[0]['xp']
        ready(a)
        a.mark()
        gm(a, '@killmonster2')
        r = a.act(GUST, 'right')
        check(r and r['outcome'] == SUCCEEDED and a.skills[GUST][1] == prof1
              and a.hue[0]['xp'] == xp1,
              'a gust into empty air costs energy but awards nothing')

        # Learning: each prerequisite is checked and explained.
        r = a.learn(GUST)
        check(r and r['reason'] == NO_POINTS, 'upgrade without points: '
              'reason %s' % (r and r['reason']))
        gm(a, '@hueset points 1')
        r = a.learn(GUST)
        check(r and r['reason'] == NEEDS_LEVEL and r['detail'] == 2,
              'upgrade needs level 2: %s' % summary(r))
        gm(a, '@blvl 3', wait=0.8)
        check(a.hue_head.get('points') == 4,
              'levels 2-4 grant 3 skill points (%s)' % a.hue_head.get('points'))
        r = a.learn(GUST)
        check(r and r['reason'] == NEEDS_MASTERY and r['detail'] == 3,
              'upgrade needs mastery 3: %s' % summary(r))
        gm(a, '@hueset mastery gale 6')
        r = a.learn(GUST)
        check(r and r['reason'] == NEEDS_PROF and r['detail'] == 50,
              'upgrade needs proficiency 50: %s' % summary(r))
        gm(a, '@hueset prof 2 50')
        r = a.learn(GUST)
        check(r and r['outcome'] == LEARNED and a.skills[GUST][0] == 2 and
              a.hue_head.get('points') == 3,
              'Gust upgraded to rank 2 for one point: %s' % summary(r))

        # Current-limited despite ample energy (rank 2 needs 9, channel 8).
        ready(a)
        energy = a.gale()
        a.mark()
        r = a.act(GUST, 'right')
        check(r and r['reason'] == CURRENT_LIMITED and r['detail'] == 8 and
              r['personal'] == 0 and energy >= 18,
              'Gust rank 2 is current-limited with %s energy: %s'
              % (energy, summary(r)))

        # A Breeze Reed stack supplies the missing current safely.
        gm(a, '@item 701 10', '@item 703 2', '@item %d 1' % TEMPERED, wait=0.8)
        reeds, herbs = a.index_of(REED), a.count(HERB)
        temp = a.index_of(TEMPERED)
        check(lot(a, reeds).get('charge') == 20000 and
              lot(a, reeds).get('condition') == 100 and
              lot(a, temp).get('charge') == 40000,
              'vessels arrive precharged: reeds %s, tempered %s'
              % (lot(a, reeds), lot(a, temp)))
        ready(a)
        a.act(SCYTHE, 'right')
        check(lot(a, reeds).get('charge') == 20000,
              'unselected vessels are never drawn on')
        r = a.select(reeds)
        check(r and r['outcome'] == SUPPLY and lot(a, reeds).get('supply') == 1,
              'Breeze Reeds selected as supply 1')
        b.mark()
        r, pushed = gust(a)
        b.pump(0.3)
        check(any(sl[0] == pushed[0][0] for sl in b.slides()) if pushed else False,
              'the second client sees the vessel-backed knockback')
        v = r and r['vessels']
        check(r and r['outcome'] == SUCCEEDED and v and v[0]['fate'] == SAFE
              and r['personal'] + r['vessel'] == 18 and pushed,
              'Gust rank 2 succeeds safely with reeds: %s' % summary(r))
        check(lot(a, reeds).get('charge') == 20000 - (r['vessel'] * 1000 + 9) // 10
              and a.count(REED) == 10,
              'the reed stack pays its share and stays (charge %s)'
              % lot(a, reeds).get('charge'))
        r, pushed = gust(a)
        check(r and r['outcome'] == SUCCEEDED and a.count(REED) == 10,
              'the reeds are reusable for rated use')

        # Rank 3 needs 14: channel 8 + reeds 4 cannot deliver it safely.
        gm(a, '@hueset prof 2 150')
        r = a.learn(GUST)
        check(r and r['outcome'] == LEARNED and a.skills[GUST][0] == 3,
              'Gust upgraded to rank 3')
        ready(a)
        charge = lot(a, reeds).get('charge')
        r = a.act(GUST, 'right')
        check(r and r['reason'] == OVERLOAD_RISK and r['detail'] == 150 and
              r['vessel'] == 0 and lot(a, reeds).get('charge') == charge,
              'rank 3 would overload the reeds (150%%): asks first, spends '
              'nothing: %s' % summary(r))
        gm(a, '@huecharge', '@item 701 10', wait=0.8)
        check(a.count(REED) == 20 and len([i for i, e in a.inventory.items()
                                            if e[0] == REED]) == 1,
              'full reeds merge into one stack of 20')
        ready(a)
        r = a.act(GUST, 'right')
        check(r and r['reason'] == OVERLOAD_RISK and r['detail'] == 150,
              'twice the reeds deliver no more safe current: %s' % summary(r))

        # Controlled risky outcomes (developer fixture forces the rolls).
        gm(a, '@hueforce 1')
        r, pushed = gust(a, flags=1)
        v = r and r['vessels']
        check(r and r['outcome'] == SUCCEEDED and v and
              v[0]['fate'] == STRAINED and pushed and
              lot(a, reeds).get('condition') == 80,
              'forced success, stack survives strained (condition %s): %s'
              % (lot(a, reeds).get('condition'), summary(r)))
        gm(a, '@hueforce 0')
        r, pushed = gust(a, flags=1)
        check(r and r['outcome'] == FAILED and r['reason'] == OVERLOAD_FAILED
              and r['personal'] > 0 and not pushed,
              'forced failure: energy spent, nobody pushed: %s' % summary(r))
        # An unrelated (unselected, differently worn) reed stack.
        gm(a, '@item 701 2', wait=0.6)
        others = [i for i, e in a.inventory.items()
                  if e[0] == REED and i != reeds]
        check(len(others) == 1 and a.count(REED) == 22,
              'new reeds form their own stack beside the worn one')
        gm(a, '@hueforce 3')
        r, pushed = gust(a, flags=1)
        v = r and r['vessels']
        check(r and r['outcome'] == SUCCEEDED and v and
              v[0]['fate'] == DESTROYED and a.count(REED) == 2 and
              a.count(HERB) == herbs and a.count(TEMPERED) == 1 and
              lot(a, temp).get('charge') == 40000,
              'forced destruction removes exactly the selected stack '
              '(reeds left %d, herbs %d, tempered %d): %s'
              % (a.count(REED), a.count(HERB), a.count(TEMPERED), summary(r)))
        check(lot(a, others[0]).get('supply') == 0 if others else False,
              'the unrelated stack was never selected')
        a.select(others[0])
        gm(a, '@hueforce 2')
        r, pushed = gust(a, flags=1)
        v = r and r['vessels']
        check(r and r['outcome'] == FAILED and v and v[0]['fate'] == DESTROYED
              and a.count(REED) == 0 and not pushed,
              'forced failure with destruction: %s' % summary(r))

        # Seeded rolls repeat exactly.
        gm(a, '@hueforce -1')
        outcomes = []
        for _ in range(2):
            gm(a, '@item 701 5', wait=0.6)
            idx = [i for i, e in a.inventory.items() if e[0] == REED][0]
            a.select(idx)
            gm(a, '@hueseed 7')
            r, _ = gust(a, flags=1)
            outcomes.append((r['outcome'], [x['fate'] for x in r['vessels']]))
            if a.count(REED):            # drop survivors: next run is fresh
                idx = a.index_of(REED)
                a.m.send(struct.pack('<HHH', 0x00a2, idx + 2, a.count(REED)))
                a.pump(0.5)
        check(outcomes[0] == outcomes[1],
              'the same seed gives the same overload outcome %s' % outcomes)

        # A better-grade vessel delivers it safely.
        a.select(temp)
        r, pushed = gust(a)
        v = r and r['vessels']
        check(r and r['outcome'] == SUCCEEDED and v and v[0]['fate'] == SAFE
              and pushed,
              'the Tempered Reed (test grade) carries rank 3 safely: %s'
              % summary(r))

        # Mastery: the advanced profile channels 16 alone.
        gm(a, '@hueprofile advanced', wait=1.0)
        r, pushed = gust(a)
        check(r and r['outcome'] == SUCCEEDED and r['vessel'] == 0 and pushed,
              'mastery 20 casts rank 3 from the personal reserve: %s'
              % summary(r))
        r, d3 = dash_distance(a)
        check(d3 > d1, 'Dash rank 3 goes further than rank 1 (%d > %d)'
              % (d3, d1))

        # Flow: Steady Flow 2 (+50%) lets mastery 6 use reeds safely.
        gm(a, '@hueset mastery gale 6', '@item 701 4', wait=0.6)
        a.select(a.index_of(REED))
        r, pushed = gust(a)
        v = r and r['vessels']
        check(r and r['outcome'] == SUCCEEDED and v and v[0]['fate'] == SAFE
              and v[0]['load'] == 100,
              'Steady Flow makes the same reeds safe at 100%% load: %s'
              % summary(r))

        # A normal player cannot use developer controls.
        before = dict(b.hue.get(0, {}))
        gm(b, '@hueforce 3', '@hueset mastery gale 50', '@hueprofile advanced',
           '@hueset energy gale 0', wait=0.8)
        check(b.hue.get(0, {}).get('mastery') == 1 and
              b.hue.get(0, {}).get('energy', 0) > 0 and
              b.skills.get(GUST, (0,))[0] == 1,
              'non-GM players cannot change hue state or rolls')

        # Transfer: drop part of a stack, the friend picks it up.
        gm(a, '@huecharge 12', '@item 701 6', wait=0.6)
        idx = [i for i, e in a.inventory.items() if e[0] == REED][0]
        state = (lot(a, idx).get('charge'), lot(a, idx).get('condition'))
        b.walk(*a.pos)
        b.pump(2.5)
        b.mark()
        a.m.send(struct.pack('<HHH', 0x00a2, idx + 2, 3))
        a.pump(0.5)
        b.pump(0.5)
        floor = [x for p_, x in b.events if p_ in (0x009d, 0x009e)]
        if floor:
            fid = struct.unpack_from('<I', floor[-1], 0)[0]
            b.m.send(struct.pack('<HI', 0x009f, fid))
            b.pump(1.0)
        bidx = b.index_of(REED)
        check(bidx is not None and b.count(REED) == 3 and
              (lot(b, bidx).get('charge'), lot(b, bidx).get('condition')) == state,
              'dropped reeds keep their charge/condition for the friend '
              '%s -> %s' % (state, lot(b, bidx) if bidx is not None else None))

        # Reconnect and host restart keep every record.
        a_state = (dict(a.hue), dict(a.skills), a.items(),
                   {i: dict(l) for i, l in a.lots.items()})
        a.disconnect()
        b.disconnect()
        time.sleep(1)
        a.connect()
        a.pump(0.5)
        check(a.skills == a_state[1] and a.items() == a_state[2] and
              {i: (l['charge'], l['condition']) for i, l in a.lots.items()} ==
              {i: (l['charge'], l['condition']) for i, l in a_state[3].items()}
              and a.hue[0]['mastery'] == a_state[0][0]['mastery'],
              'reconnect keeps skills, inventory, lots and mastery')
        a.disconnect()
        time.sleep(1)
        check(world.stop(), 'server stops cleanly')
        world.start()
        a.connect()
        b.connect()
        a.pump(0.5)
        check(a.skills == a_state[1] and a.items() == a_state[2] and
              {i: (l['charge'], l['condition']) for i, l in a.lots.items()} ==
              {i: (l['charge'], l['condition']) for i, l in a_state[3].items()},
              'host restart keeps skills, inventory and lots')
        check(b.count(REED) == 3 and
              (lot(b, b.index_of(REED)).get('charge'),
               lot(b, b.index_of(REED)).get('condition')) == state,
              "the friend's transferred reeds survive the restart")
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


def migration(build, keep=None):
    """Load a Pass 0 save (no hue state) with this server."""
    world = World(build)
    fixture = os.path.join(HERE, 'fixtures', 'demo-save-v0')
    for name in os.listdir(fixture):
        if name.endswith('.txt'):
            shutil.copy(os.path.join(fixture, name),
                        os.path.join(world.dir, 'save', name))
    print('world: %s' % world.dir)
    try:
        world.start()
        a = Player('aethyra-test', 'test-pass').connect()
        a.pump(0.5)
        check(a.items() == {702: 1, 701: 5, 703: 2, 710: 1},
              'migrated inventory is intact %s' % a.items())
        check(a.pos == (10, 23), 'migrated position is intact %s' % (a.pos,))
        g = a.hue.get(0, {})
        check(a.hue_head.get('version') == 1 and g.get('energy') == 60 and
              g.get('mastery') == 1,
              'Gale reserve migrated from SP 68, clamped to capacity 60 (%s)' % g)
        check(a.skills == {DASH: (1, 0), GUST: (1, 0), SCYTHE: (1, 0)} and
              a.hue_head.get('points') == 1,
              'introductory skills granted; level 2 gives 1 skill point '
              '(%s, points %s)' % (a.skills, a.hue_head.get('points')))
        reeds = a.index_of(REED)
        check(lot(a, reeds).get('charge') == 20000,
              'legacy reeds become precharged vessels %s' % lot(a, reeds))
        spawn_ok = True
        try:
            gm(a, '@killmonster2')
            spawn(a, MEADOW_GRASS, 1)
            r = a.act(SCYTHE, 'right', wait=1.0)
            spawn_ok = r and r['outcome'] == SUCCEEDED and r['detail'] >= 1
        except Exception:
            spawn_ok = False
        check(spawn_ok, 'Wind Scythe still harvests after migration')
        save = os.path.join(world.dir, 'save')
        check(os.path.exists(os.path.join(save, 'athena.txt.pre-hue1')) and
              os.path.exists(os.path.join(save, 'storage.txt.pre-hue1')),
              'the legacy saves were backed up before migration')
        b = Player('friend', 'friend-pass').connect()
        check(b.hue_head.get('version') == 1 and b.count(REED) == 0,
              'second migrated character loads')
        a.disconnect()
        b.disconnect()
        time.sleep(1)
        world.stop()
        with open(os.path.join(save, 'athena.txt')) as f:
            text = f.read()
        check('\t1;1;' in text, 'saves are written in the hue format')
        world.start()
        a.connect()
        a.pump(0.5)
        check(a.hue_head.get('version') == 1 and REED in a.items(),
              'the migrated world reloads')
        a.disconnect()
        time.sleep(1)
        world.stop()
    finally:
        world.kill()
        if keep:
            if os.path.exists(keep):
                shutil.rmtree(keep)
            shutil.copytree(world.dir, keep, ignore=shutil.ignore_patterns(
                'bin', 'log', 'server.stop'))


SCENARIOS = {'baseline': baseline, 'pass1': pass1, 'migration': migration}


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
