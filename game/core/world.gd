class_name World
extends RefCounted
## The authoritative world, run by the host. It owns every being, rule and
## save; peers only send requests (handle()) and receive events (out).
## It is plain logic with an explicit clock (tick(ms)), so tests drive it
## headless and deterministically.
##
## Events are dictionaries with a "t" type. Those with a "to" peer id are
## private to that player; the rest go to everyone.

const MAX_INVENTORY := 40
const PLAYER_ATTACK_MS := 900
const RESPAWN_DELAY_MS := 3000
const AUTOSAVE_MS := 30000
const TALK_RANGE := 3
const CACHE_MS := 600000

var db: HueDB
var prog: Progression
var hue: HueRules
var map: GameMap
var items := {}         # id -> {id, name, kind, effects, description}
var mobs := {}          # id -> mobs.txt row
var dialogues := {}     # key -> dialogue
var errors: Array[String] = []

var now := 0
var beings := {}        # id -> Being
var players := {}       # peer -> Being
var out: Array = []     # events waiting for the network layer
var rng := RandomNumberGenerator.new()
var save_dir := ""      # "" keeps characters in memory only
var gm_everyone := false
var stored := {}        # characters saved this session (and in memory-only worlds)

var _next_id := 100
var _next_regen := 0
var _next_autosave := 0
var _dirty := {}        # player ids whose private state changed
var _groups := []       # spawn groups: {spawn, alive, pending: [respawn times]}
var _astar := AStarGrid2D.new()


func _init(map_name := "gale-1", data_dir := "res://data") -> void:
	db = HueDB.load_from(data_dir + "/hue")
	errors.append_array(db.errors)
	prog = Progression.load_from(data_dir, db)
	errors.append_array(prog.errors)
	hue = HueRules.new(self, db, prog)
	map = GameMap.load_file("%s/maps/%s.txt" % [data_dir, map_name])
	errors.append_array(map.errors)
	items = read_items(data_dir + "/world/items.txt")
	if items.is_empty():
		errors.append("no items in %s/world/items.txt" % data_dir)
	_read_mobs(data_dir + "/world/mobs.txt")
	var f := FileAccess.open(data_dir + "/world/npcs.json", FileAccess.READ)
	if f:
		dialogues = JSON.parse_string(f.get_as_text())
	if not errors.is_empty():
		return
	_build_paths()
	for n in map.npcs:
		var b := _add_being(Being.NPC, n.name, Vector2i(n.x, n.y))
		b.key = n.dialogue
	for g in map.spawns.size():
		_groups.append({"spawn": map.spawns[g], "alive": 0, "pending": []})
		for k in map.spawns[g].count:
			_spawn_mob(g)
	_next_regen = db.b("regen_interval_ms", 1000)
	_next_autosave = AUTOSAVE_MS


static func read_items(path: String) -> Dictionary:
	var items := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return items
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		var p := line.split("|")
		var effects := []
		for e in p[3].split(",", false):
			effects.append(e.strip_edges().split(" ", false))
		items[int(p[0])] = {"id": int(p[0]), "name": p[1], "kind": p[2], "effects": effects,
				"description": p[4]}
	return items


func _read_mobs(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot read " + path)
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		var p := line.split("|")
		var drops := []
		for d in p[11].split(",", false):
			var q := d.split(":")
			drops.append([int(q[0]), int(q[1])])
		mobs[int(p[0])] = {"id": int(p[0]), "name": p[1], "level": int(p[2]), "hp": int(p[3]),
				"exp": int(p[4]), "atk_min": int(p[5]), "atk_max": int(p[6]),
				"speed": int(p[7]), "attack_ms": int(p[8]), "sight": int(p[9]),
				"aggressive": p[10] == "1", "drops": drops}


func _build_paths() -> void:
	_astar.region = Rect2i(0, 0, map.w, map.h)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	_astar.update()
	for y in map.h:
		for x in map.w:
			_astar.set_point_solid(Vector2i(x, y), not map.walkable(x, y))


func _add_being(kind: int, name: String, pos: Vector2i) -> Being:
	var b := Being.new()
	b.id = _next_id
	_next_id += 1
	b.kind = kind
	b.name = name
	b.pos = pos
	beings[b.id] = b
	return b


# --------------------------------------------------------------------------
# Events

func broadcast(ev: Dictionary) -> void:
	out.append(ev)


func send(p: Being, ev: Dictionary) -> void:
	if p.kind != Being.PLAYER:
		return
	ev = ev.duplicate()
	ev.to = p.peer
	out.append(ev)


func tell(p: Being, text: String) -> void:
	send(p, {"t": "msg", "text": text})


func private_changed(p: Being) -> void:
	if p.kind == Being.PLAYER:
		_dirty[p.id] = true


## Everything a player sees of their own character.
func private_state(p: Being) -> Dictionary:
	var ready := {}
	for skill in p.session.ready:
		if p.session.ready[skill] > now:
			ready[str(skill)] = p.session.ready[skill] - now
	var active := []
	for a in p.session.active:
		if a.until > now:
			active.append({"skill": a.skill, "hue": a.hue, "left": a.until - now})
	var hues := []
	for i in p.ch.hue.hues.size():
		var r: Dictionary = p.ch.hue.hues[i]
		hues.append({} if not r.access else {"capacity": hue.capacity(p.ch, i),
				"channel": hue.channel(p.ch, i), "dissonance": prog.dissonance(p.ch, i),
				"regen": hue.regen_amount(p.ch, i, map.concentration(p.pos, i)),
				"conc": map.concentration(p.pos, i), "offers": prog.talent_offers(p.ch, i),
				"soft_cap": prog.soft_cap(r, map.zone_at(p.pos))})
	var z := map.zone_at(p.pos)
	return {"t": "me", "to": p.peer, "id": p.id, "name": p.name, "hp": p.hp,
			"max_hp": p.max_hp, "hue": p.ch.hue.duplicate(true), "derived": hues,
			"body": p.ch.body.duplicate(true), "equipment": p.ch.equipment.duplicate(true),
			"feats": p.ch.progress.feats.duplicate(), "anchors": p.ch.anchors.duplicate(true),
			"stats": {"attack": attack_bonus(p), "defense": defense(p), "move_ms": p.step_ms,
					"notice": prog.stat(p.ch, "notice", 100, 10), "yield": prog.stat(p.ch, "yield", 100)},
			"zone": {"key": z.key, "name": z.name, "band": z.band, "limit": prog.training_limit(z)},
			"inventory": p.ch.inventory.duplicate(true), "ready": ready, "active": active,
			"gm": is_gm(p)}


func effect(b: Being, name: String) -> void:
	if name != "":
		broadcast({"t": "effect", "id": b.id, "name": name})


# --------------------------------------------------------------------------
# Players: joining, leaving, saves

## Recompute what modifiers derive: health and walking pace.
func refresh_stats(p: Being) -> void:
	p.max_hp = prog.stat(p.ch, "max_hp", db.b("base_hp", 60), 1)
	p.hp = mini(p.hp, p.max_hp)
	p.step_ms = prog.stat(p.ch, "move_ms", db.b("move_ms", 150), 60)
	private_changed(p)


func attack_bonus(p: Being) -> int:
	return prog.stat(p.ch, "attack", 0)


func defense(p: Being) -> int:
	return prog.stat(p.ch, "defense", 0)


## Train body stats from an activity and say what rose.
func train(p: Being, activity: String, units: int) -> void:
	if p == null or p.kind != Being.PLAYER:
		return
	var said := prog.train(p.ch, activity, units)
	for line in said:
		tell(p, line)
	if not said.is_empty():
		refresh_stats(p)
	private_changed(p)


static func valid_name(n: String) -> bool:
	if n.length() < 2 or n.length() > 20:
		return false
	for c in n:
		if not (c.is_valid_identifier() or c == " " or c.is_valid_int() or c == "-"):
			return false
	return n.strip_edges() == n


func _char_path(n: String) -> String:
	return "%s/characters/%s.json" % [save_dir, n.to_lower().replace(" ", "_")]


func load_character(n: String) -> Dictionary:
	if stored.has(n.to_lower()):
		return stored[n.to_lower()].duplicate(true)
	if save_dir == "" or not FileAccess.file_exists(_char_path(n)):
		return {}
	var text := FileAccess.get_file_as_string(_char_path(n))
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("unreadable character save " + _char_path(n))
		return {}
	return Save.ints(data)


func save_character(p: Being) -> void:
	p.ch.x = p.pos.x
	p.ch.y = p.pos.y
	p.ch.fx = p.facing.x
	p.ch.fy = p.facing.y
	p.ch.hp = p.hp if not p.dead else p.max_hp
	stored[p.name.to_lower()] = p.ch.duplicate(true)
	if save_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(save_dir + "/characters")
	Save.write_json(_char_path(p.name), p.ch)


func save_all() -> void:
	for peer in players:
		save_character(players[peer])


## A peer enters the world as a character, created on first use. secret is
## the joining client's own token for that name. Returns "" or why not.
func join(peer: int, n: String, secret: String) -> String:
	n = n.strip_edges()
	if not valid_name(n):
		return "Names are 2-20 letters, digits, spaces or dashes."
	if players.has(peer):
		return "Already in the world."
	for q in players.values():
		if q.name.to_lower() == n.to_lower():
			return "%s is already in the world." % q.name
	var ch := load_character(n)
	if ch.is_empty():
		ch = new_character(n, secret)
	elif ch.get("secret", "") != secret:
		return "%s belongs to someone else in this world." % ch.name
	var p := _add_being(Being.PLAYER, ch.name, Vector2i(ch.x, ch.y))
	p.peer = peer
	p.ch = ch
	p.facing = Vector2i(ch.get("fx", 0), ch.get("fy", 1))
	p.new_session()
	hue.repair(ch)
	ch.erase("conditions")
	p.hp = 1
	refresh_stats(p)
	p.hp = clampi(ch.hp, 1, p.max_hp)
	if not map.walkable(p.pos.x, p.pos.y):
		p.pos = map.spawn
	players[peer] = p
	send(p, {"t": "welcome", "id": p.id, "map": map.name, "now": now})
	for b in beings.values():
		if b != p:
			send(p, {"t": "spawn", "being": b.public()})
	broadcast({"t": "spawn", "being": p.public()})
	out.append(private_state(p))
	broadcast({"t": "chat", "from": "", "text": "%s has entered the world." % p.name})
	return ""


func new_character(n: String, secret: String) -> Dictionary:
	var ch := {"version": 2, "name": n, "secret": secret,
			"hp": db.b("base_hp", 60), "x": map.spawn.x, "y": map.spawn.y, "fx": 0, "fy": 1,
			"inventory": []}
	hue.init_character(ch, 1)
	prog.ensure(ch)
	return ch


func leave(peer: int) -> void:
	var p: Being = players.get(peer)
	if p == null:
		return
	save_character(p)
	players.erase(peer)
	beings.erase(p.id)
	_dirty.erase(p.id)
	for b in beings.values():
		if b.target == p.id:
			b.target = 0
	broadcast({"t": "despawn", "id": p.id})
	broadcast({"t": "chat", "from": "", "text": "%s has left the world." % p.name})


func is_gm(p: Being) -> bool:
	return gm_everyone or p.peer == 1


# --------------------------------------------------------------------------
# Requests from peers

func handle(peer: int, req: Dictionary) -> void:
	var p: Being = players.get(peer)
	if p == null or typeof(req.get("t")) != TYPE_STRING:
		return
	req = Save.ints(req)
	match req.t:
		"walk":
			if not p.dead:
				p.target = 0
				walk_to(p, Vector2i(req.get("x", 0), req.get("y", 0)))
		"step":
			if not p.dead:
				p.target = 0
				var d := Vector2i(clampi(req.get("dx", 0), -1, 1), clampi(req.get("dy", 0), -1, 1))
				if d != Vector2i.ZERO:
					set_facing(p, d)
					p.path.clear()
					if map.ground_step(p.pos, d):
						p.path.append(p.pos + d)
		"face":
			var d := Vector2i(clampi(req.get("dx", 0), -1, 1), clampi(req.get("dy", 0), -1, 1))
			if d != Vector2i.ZERO and not p.dead:
				set_facing(p, d)
		"stop":
			p.path.clear()
			p.target = 0
		"attack":
			var t: Being = beings.get(req.get("id", 0))
			if t and t.kind == Being.MOB and not t.dead and not t.is_vegetation() and not p.dead:
				p.target = t.id
		"hue":
			var d := Vector2i(clampi(req.get("dx", 0), -1, 1), clampi(req.get("dy", 0), -1, 1))
			p.path.clear()
			hue.action(p, req.get("skill", 0), d, req.get("flags", 0), req.get("request", 0),
					req.get("target", 0), req.get("modifier", 0))
		"learn":
			hue.learn(p, req.get("skill", 0))
		"supply":
			hue.select_supply(p, req.get("index", -1), req.get("on", 0) != 0)
		"use":
			use_item(p, req.get("index", -1))
		"talk":
			talk(p, req.get("id", 0))
		"choose":
			choose(p, req.get("index", -1))
		"close":
			p.dialog = {}
		"chat":
			chat(p, str(req.get("text", "")))
		"talent":
			var id := str(req.get("id", ""))
			var why := prog.pick_talent(p.ch, id)
			tell(p, why if why != "" else "You learned the talent %s." % prog.talents[id].name)
			refresh_stats(p)
		"equip":
			equip(p, req.get("index", -1))
		"unequip":
			unequip(p, str(req.get("slot", "")))
		"socket":
			socket(p, str(req.get("slot", "")), req.get("index", -1))
		"altar":
			altar_roll(p, str(req.get("slot", "")))


# --------------------------------------------------------------------------
# Movement

func set_facing(b: Being, d: Vector2i) -> void:
	if d == Vector2i.ZERO or d == b.facing:
		return
	b.facing = d
	broadcast({"t": "face", "id": b.id, "fx": d.x, "fy": d.y})


func walk_to(b: Being, goal: Vector2i) -> void:
	b.path.clear()
	if not map.inside(goal.x, goal.y) or goal == b.pos:
		return
	var path := _astar.get_id_path(b.pos, goal, true)
	for k in range(1, path.size()):
		b.path.append(path[k])


func _step(b: Being) -> void:
	var n: Vector2i = b.path.pop_front()
	var d := n - b.pos
	if maxi(absi(d.x), absi(d.y)) != 1 or not map.ground_step(b.pos, d):
		b.path.clear()
		return
	b.facing = d
	b.pos = n
	b.next_step = now + b.step_ms
	broadcast({"t": "move", "id": b.id, "x": n.x, "y": n.y, "ms": b.step_ms})
	if b.kind == Being.PLAYER:
		_arrived(b)


## A player reached a cell: exploration, caches, the zone they are in.
func _arrived(p: Being) -> void:
	if prog.explore(p.ch, map.name, p.pos, map.w, map.h):
		train(p, "explore", 1)
	for c in beings.values():
		if c.kind == Being.CACHE and c.pos == p.pos and c.key == p.name:
			_recover(p, c)
	var z := map.zone_at(p.pos)
	if p.session.get("zone", "") != z.key:
		p.session.zone = z.key
		if z.key != "":
			tell(p, "%s (%s)" % [z.name, z.band])
		private_changed(p)


## Move instantly (skills, knockback, falls), with an animation kind.
func slide(b: Being, to: Vector2i, kind: int) -> void:
	b.path.clear()
	b.pos = to
	b.next_step = now + 300
	broadcast({"t": "slide", "id": b.id, "x": to.x, "y": to.y, "kind": kind})
	if b.kind == Being.PLAYER:
		_arrived(b)


func stagger(b: Being, ms: int) -> void:
	b.path.clear()
	b.can_move_at = now + ms
	b.attackable_at = now + ms


## Whether a being other than self stands on cell (one can land among plants).
func occupied(cell: Vector2i, self_being: Being) -> bool:
	for b in beings.values():
		if b == self_being or b.pos != cell:
			continue
		if b.kind == Being.CACHE or (b.kind == Being.MOB and (b.dead or b.is_vegetation())):
			continue
		if b.kind == Being.PLAYER and b.dead:
			continue
		return true
	return false


func beings_near(pos: Vector2i, r: int) -> Array:
	var near := []
	for b in beings.values():
		if maxi(absi(b.pos.x - pos.x), absi(b.pos.y - pos.y)) <= r:
			near.append(b)
	return near


func alive(b: Being) -> bool:
	return b != null and beings.has(b.id) and not b.dead


static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --------------------------------------------------------------------------
# Combat, experience, death

func damage(b: Being, amount: int, src: Being, kind := "hit") -> void:
	if b.dead:
		return
	if b.kind == Being.PLAYER and kind == "hit":
		amount = maxi(1, amount - defense(b))
	b.hp = maxi(0, b.hp - amount)
	if src and src.kind == Being.PLAYER and b != src:
		train(src, "deal", amount)
		if kind in ["fire", "burn"]:
			train(src, "hue_deal", amount)
	if b.kind == Being.PLAYER:
		train(b, "take", amount)
	broadcast({"t": "damage", "id": b.id, "src": src.id if src else 0, "amount": amount,
			"hp": b.hp, "kind": kind})
	if b.kind == Being.PLAYER:
		private_changed(b)
	elif src and src.kind == Being.PLAYER and not b.is_vegetation():
		b.target = src.id      # it fights back
	if b.hp <= 0:
		kill(b, src)


func kill(b: Being, killer: Being) -> void:
	if b.dead:
		return
	b.dead = true
	b.hp = 0
	b.path.clear()
	b.target = 0
	b.burn = {}
	broadcast({"t": "die", "id": b.id})
	if b.kind == Being.PLAYER:
		b.respawn_at = now + RESPAWN_DELAY_MS
		b.dialog = {}
		for m in beings.values():
			if m.target == b.id:
				m.target = 0
		_death_chain(b)
		private_changed(b)
		return
	if killer and killer.kind == Being.PLAYER:
		var extra: int = prog.stat(killer.ch, "yield", 100) - 100
		for drop in b.mob.drops:
			if rng.randi_range(0, 9999) < drop[1]:
				give_item(killer, drop[0], 1 + (1 if rng.randi_range(0, 99) < extra else 0))
		if b.is_vegetation():
			train(killer, "harvest", 1)
	var g: Dictionary = _groups[b.group]
	g.alive -= 1
	var delay: int = g.spawn.respawn_ms
	g.pending.append(now + delay + rng.randi_range(0, delay / 2))
	b.respawn_at = now + 1500     # corpse lingers, then goes


## Where a fallen player wakes, and what the site takes, by zone depth:
## edge -> town; frontier -> your camp in this biome, else town; deep and
## beyond -> an anchor whose protection covers the concentration, else town
## and the site's penalty (and the overwhelmed anchor's tether breaks).
func _death_chain(p: Being) -> void:
	var z := map.zone_at(p.pos)
	var rule: String = prog.bands.get(z.band, {"respawn": "town"}).respawn
	var conc := 0
	for h in z.conc:
		conc = maxi(conc, z.conc[h])
	var anchor: Dictionary = p.ch.anchors.get(map.name, {})
	p.session.wake = map.spawn
	var where := "in the clearing"
	match rule:
		"camp":
			if not anchor.is_empty():
				p.session.wake = Vector2i(anchor.x, anchor.y)
				where = "at your camp"
		"node":
			if not anchor.is_empty() and anchor.protection >= conc:
				p.session.wake = Vector2i(anchor.x, anchor.y)
				where = "at your warded camp"
			else:
				if not anchor.is_empty():
					p.ch.anchors.erase(map.name)
					tell(p, "The %s here overwhelms your camp's wards: its tether snaps." % z.name)
				_site_penalty(p, z)
	tell(p, "You fall. You will wake %s." % where)


func _site_penalty(p: Being, z: Dictionary) -> void:
	match z.penalty:
		"drop_vessels":
			var lots := []
			for i in p.ch.inventory.size():
				var lot = p.ch.inventory[i]
				if lot != null and not hue.vessel_at(p.ch, i).is_empty():
					lots.append(lot.duplicate(true))
					p.ch.inventory[i] = null
					hue.slot_changed(p.ch, i)
			if not lots.is_empty():
				var c := _add_being(Being.CACHE, "%s's vessels" % p.name, p.pos)
				c.key = p.name
				c.ch = {"items": lots}
				c.respawn_at = now + CACHE_MS
				broadcast({"t": "spawn", "being": c.public()})
				tell(p, "Your vessels spill where you fell. Return for them before the wind takes them.")
		"mastery":
			var best := -1
			for h in z.conc:
				if p.ch.hue.hues[h].access and (best < 0 or z.conc[h] > z.conc[best]):
					best = h
			if best >= 0:
				p.ch.hue.hues[best].xp = 0
				tell(p, "The %s here scatters your %s progress." % [z.name, HueDB.hue_title(best)])
		"condition":
			p.ch["conditions"] = [{"name": "Shaken", "until": now + 60000, "mods": [["max_hp", 0, -20]]}]
			tell(p, "You wake shaken: less health for a while.")


func _recover(p: Being, c: Being) -> void:
	for lot in c.ch.get("items", []):
		add_lot(p, lot)
	tell(p, "You gather what you dropped.")
	beings.erase(c.id)
	broadcast({"t": "despawn", "id": c.id})


func _player_tick(p: Being) -> void:
	if p.dead:
		if now >= p.respawn_at:
			p.dead = false
			refresh_stats(p)
			p.hp = p.max_hp
			p.pos = p.session.get("wake", map.spawn)
			p.path.clear()
			p.safe_until = now + 5000
			broadcast({"t": "spawn", "being": p.public()})
			private_changed(p)
		return
	var t: Being = beings.get(p.target)
	if p.target and (t == null or t.dead):
		p.target = 0
		t = null
	if t:
		if cheb(t.pos, p.pos) <= 1 and map.same_level(p.pos, t.pos):
			p.path.clear()
			set_facing(p, (t.pos - p.pos).sign())
			if now >= p.next_attack:
				p.next_attack = now + PLAYER_ATTACK_MS
				broadcast({"t": "attack", "id": p.id, "target": t.id})
				damage(t, rng.randi_range(db.b("attack_min", 3), db.b("attack_max", 6)) + attack_bonus(p), p)
		elif p.path.is_empty() or cheb(p.path.back(), t.pos) > 1:
			walk_to(p, t.pos)
			if not p.path.is_empty() and p.path.back() == t.pos:
				p.path.pop_back()
			if p.path.is_empty():
				p.target = 0      # cannot reach it from here
	if not p.path.is_empty() and now >= p.next_step:
		_step(p)


func _mob_tick(b: Being) -> void:
	if b.dead:
		if b.respawn_at and now >= b.respawn_at:
			b.respawn_at = 0
			beings.erase(b.id)
			broadcast({"t": "despawn", "id": b.id})
		return
	hue.burn_tick(b)
	if b.dead or b.is_vegetation() or now < b.can_move_at:
		return
	var sight: int = b.mob.sight
	var t: Being = beings.get(b.target)
	if t and (t.dead or t.kind != Being.PLAYER or now < t.safe_until or cheb(t.pos, b.pos) > sight * 2
			or not map.same_level(t.pos, b.pos)):
		b.target = 0
		t = null
	if t == null and b.mob.aggressive:
		var best := sight + 1
		for q in players.values():
			var dist := cheb(q.pos, b.pos)
			# Vigilance: you notice them first, so they notice you later.
			if dist > sight * prog.stat(q.ch, "notice", 100, 10) / 100:
				continue
			if not q.dead and now >= q.safe_until and dist < best and map.same_level(q.pos, b.pos):
				best = dist
				t = q
		if t:
			b.target = t.id
	if t:
		if cheb(t.pos, b.pos) <= 1:
			set_facing(b, (t.pos - b.pos).sign())
			if now >= b.next_attack and now >= b.attackable_at:
				b.next_attack = now + b.mob.attack_ms
				broadcast({"t": "attack", "id": b.id, "target": t.id})
				damage(t, rng.randi_range(b.mob.atk_min, b.mob.atk_max), b)
		elif now >= b.next_step:
			var s := (t.pos - b.pos).sign()
			for d in [s, Vector2i(s.x, 0), Vector2i(0, s.y)]:
				if d != Vector2i.ZERO and map.ground_step(b.pos, d):
					b.path = [b.pos + d]
					_step(b)
					break
		return
	if not b.path.is_empty():
		if now >= b.next_step:
			_step(b)
	elif now >= b.next_wander:
		b.next_wander = now + rng.randi_range(2000, 5000)
		var d := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		var c := b.pos
		for k in rng.randi_range(1, 3):
			if d == Vector2i.ZERO or not map.ground_step(c, d):
				break
			c += d
			b.path.append(c)


func _spawn_mob(g: int) -> Being:
	var s: Dictionary = _groups[g].spawn
	var def: Dictionary = mobs.get(s.mob, {})
	if def.is_empty():
		errors.append("unknown monster %d" % s.mob)
		return null
	var cell := Vector2i(-1, -1)
	for attempt in 50:
		var c := Vector2i(s.x + rng.randi_range(-s.rx, s.rx), s.y + rng.randi_range(-s.ry, s.ry))
		if map.walkable(c.x, c.y) and not occupied(c, null):
			cell = c
			break
	if cell.x < 0:
		return null
	var b := _add_being(Being.MOB, def.name, cell)
	b.cls = s.mob
	b.mob = def
	b.group = g
	b.max_hp = def.hp
	b.hp = def.hp
	b.step_ms = maxi(def.speed, 100)
	b.next_wander = now + rng.randi_range(500, 4000)
	_groups[g].alive += 1
	return b


## A developer fixture: one monster of a kind at a cell, outside any group.
func spawn_at(mob_id: int, cell: Vector2i) -> Being:
	var def: Dictionary = mobs.get(mob_id, {})
	if def.is_empty():
		return null
	_groups.append({"spawn": {"mob": mob_id, "x": cell.x, "y": cell.y, "rx": 0, "ry": 0,
			"count": 0, "respawn_ms": 3600000}, "alive": 0, "pending": []})
	var b := _spawn_mob(_groups.size() - 1)
	if b:
		b.pos = cell
		broadcast({"t": "spawn", "being": b.public()})
	return b


# --------------------------------------------------------------------------
# Items

func item_name(id: int) -> String:
	return items[id].name if items.has(id) else "item %d" % id


func count_item(p: Being, id: int) -> int:
	var n := 0
	for lot in p.ch.inventory:
		if lot != null and lot.item == id:
			n += lot.amount
	return n


func give_item(p: Being, id: int, amount: int) -> bool:
	if prog.gear.has(id):
		# Equipment is one instance per item: rarity, sockets, enchants.
		for k in amount:
			var g: Dictionary = prog.gear[id]
			var sockets := []
			sockets.resize(g.sockets)
			sockets.fill(0)
			if not add_lot(p, {"item": id, "amount": 1, "rarity": 0, "sockets": sockets, "enchants": []}):
				return false
		send(p, {"t": "loot", "item": id, "amount": amount})
		return true
	var lot := {"item": id, "amount": amount, "charge": 0, "condition": 0, "init": false}
	hue.init_lot(lot)
	if not add_lot(p, lot):
		return false
	send(p, {"t": "loot", "item": id, "amount": amount})
	return true


## Put a lot into the pack, merging with an identical lot (never gear).
func add_lot(p: Being, lot: Dictionary) -> bool:
	var inv: Array = p.ch.inventory
	var slot := -1
	if not prog.gear.has(int(lot.item)):
		for i in inv.size():
			var o = inv[i]
			# Stacks merge only when every unit shares the same lot state.
			if o != null and o.item == lot.item and o.get("charge", 0) == lot.get("charge", 0) \
					and o.get("condition", 0) == lot.get("condition", 0) \
					and o.get("init", false) == lot.get("init", false):
				o.amount += lot.amount
				slot = i
				break
	if slot < 0:
		slot = inv.find(null)
		if slot < 0:
			if inv.size() >= MAX_INVENTORY:
				tell(p, "Your pack is full.")
				return false
			inv.append(lot)
			slot = inv.size() - 1
		else:
			inv[slot] = lot
	private_changed(p)
	return true


func remove_item_at(p: Being, i: int, amount: int) -> void:
	var lot = p.ch.inventory[i]
	if lot == null:
		return
	lot.amount -= amount
	if lot.amount <= 0:
		p.ch.inventory[i] = null
		hue.slot_changed(p.ch, i)
	private_changed(p)


func take_item(p: Being, id: int, amount: int) -> bool:
	if count_item(p, id) < amount:
		return false
	for i in p.ch.inventory.size():
		var lot = p.ch.inventory[i]
		if amount > 0 and lot != null and lot.item == id:
			var n := mini(amount, lot.amount)
			remove_item_at(p, i, n)
			amount -= n
	return true


func use_item(p: Being, i: int) -> void:
	if p.dead or i < 0 or i >= p.ch.inventory.size() or p.ch.inventory[i] == null:
		return
	var it: Dictionary = items.get(p.ch.inventory[i].item, {})
	if it.get("kind") == "gear":
		equip(p, i)
		return
	if it.get("kind") == "kit":
		_use_kit(p, i, it)
		return
	if it.get("kind") != "use":
		tell(p, "You cannot use that.")
		return
	var said := []
	for e in it.effects:
		match e[0]:
			"heal":
				var before := p.hp
				p.hp = mini(p.max_hp, p.hp + int(e[1]))
				said.append("%d HP" % (p.hp - before))
				broadcast({"t": "heal", "id": p.id, "hp": p.hp})
			"restore":
				var h := HueDB.hue_index(e[1])
				said.append("%d %s energy" % [hue.restore(p, h, int(e[2])), HueDB.hue_title(h)])
	remove_item_at(p, i, 1)
	tell(p, "%s restores %s." % [it.name, " and ".join(said)])


func _use_kit(p: Being, i: int, it: Dictionary) -> void:
	for e in it.effects:
		if e[0] == "anchor":
			var z := map.zone_at(p.pos)
			if z.band == "edge":
				tell(p, "This close to town there is no need for a camp.")
				return
			p.ch.anchors[map.name] = {"x": p.pos.x, "y": p.pos.y, "protection": int(e[1])}
			remove_item_at(p, i, 1)
			tell(p, "You set a camp here (wards %d). If you fall in this land, you may wake here." % int(e[1]))
			return


# --------------------------------------------------------------------------
# Equipment

func slot_for(p: Being, item: int) -> String:
	var slot: String = prog.gear[item].slot
	if slot == "ring":
		return "ring2" if p.ch.equipment.has("ring1") and not p.ch.equipment.has("ring2") else "ring1"
	return slot


func equip(p: Being, i: int) -> void:
	if i < 0 or i >= p.ch.inventory.size() or p.ch.inventory[i] == null:
		return
	var inst: Dictionary = p.ch.inventory[i]
	if not prog.gear.has(int(inst.item)):
		tell(p, "You cannot wear that.")
		return
	var slot := slot_for(p, inst.item)
	var old = p.ch.equipment.get(slot)
	p.ch.inventory[i] = old
	hue.slot_changed(p.ch, i)
	p.ch.equipment[slot] = inst
	tell(p, "You put on the %s." % item_name(inst.item))
	refresh_stats(p)


func unequip(p: Being, slot: String) -> void:
	if not p.ch.equipment.has(slot):
		return
	if not add_lot(p, p.ch.equipment[slot]):
		tell(p, "Your pack is full.")
		return
	p.ch.equipment.erase(slot)
	refresh_stats(p)


## Set a gem from the pack into a free socket of equipped gear.
func socket(p: Being, slot: String, gem_index: int) -> void:
	var inst: Dictionary = p.ch.equipment.get(slot, {})
	if inst.is_empty() or gem_index < 0 or gem_index >= p.ch.inventory.size() or p.ch.inventory[gem_index] == null:
		return
	var gem: int = p.ch.inventory[gem_index].item
	if not prog.gems.has(gem):
		tell(p, "That is not a gem.")
		return
	var free: int = inst.sockets.find(0)
	if free < 0:
		tell(p, "The %s has no free socket." % item_name(inst.item))
		return
	inst.sockets[free] = gem
	remove_item_at(p, gem_index, 1)
	tell(p, "You set the %s into the %s." % [item_name(gem), item_name(inst.item)])
	refresh_stats(p)


## At an altar or a core, push an equipped item's rarity up. Costs energy of
## the site's strongest hue; failure keeps the item but spends the energy.
## (Provisional: the design leaves altar costs and failure open.)
func altar_roll(p: Being, slot: String) -> void:
	var inst: Dictionary = p.ch.equipment.get(slot, {})
	if inst.is_empty():
		return
	var z := map.zone_at(p.pos)
	if not (z.band in ["core", "altar"]):
		tell(p, "Only at a core or an altar can an item be raised.")
		return
	var h := -1
	for k in z.conc:
		if h < 0 or z.conc[k] > z.conc[h]:
			h = k
	var cost := db.b("altar_energy_cost", 30)
	var r: Dictionary = p.ch.hue.hues[h] if h >= 0 else {}
	if r.is_empty() or not r.access or r.energy < cost:
		tell(p, "Raising it needs %d %s energy." % [cost, HueDB.hue_title(h)])
		return
	var rar: int = inst.get("rarity", 0)
	if rar >= prog.rarities.size() - 1:
		tell(p, "It cannot be raised further.")
		return
	r.energy -= cost
	if rng.randi_range(0, 99) < prog.rarities[rar].up_chance:
		inst.rarity = rar + 1
		for k in prog.rarities[rar + 1].sockets - prog.rarities[rar].sockets:
			inst.sockets.append(0)
		tell(p, "The %s rises to %s." % [item_name(inst.item), prog.rarities[rar + 1].name])
	else:
		tell(p, "The %s drinks the energy but does not change." % item_name(inst.item))
	refresh_stats(p)


# --------------------------------------------------------------------------
# NPCs

func talk(p: Being, npc_id: int) -> void:
	var n: Being = beings.get(npc_id)
	if n == null or n.kind != Being.NPC or p.dead:
		return
	if cheb(n.pos, p.pos) > TALK_RANGE:
		walk_to(p, n.pos + Vector2i(0, 1))
		tell(p, "Come closer to talk to %s." % n.name)
		return
	var dlg: Dictionary = dialogues.get(n.key, {})
	if dlg.is_empty():
		return
	p.path.clear()
	p.dialog = {"npc": n.id, "key": n.key}
	_enter_node(p, dlg.start)


func _enter_node(p: Being, node_key: String) -> void:
	var dlg: Dictionary = dialogues[p.dialog.key]
	if node_key == "":
		p.dialog = {}
		send(p, {"t": "dialog_close"})
		return
	var node: Dictionary = dlg.nodes[node_key]
	if node.has("if"):
		var cond: Dictionary = node["if"]
		var ok := true
		if cond.has("have"):
			for pair in cond.have:
				ok = ok and count_item(p, int(pair[0])) >= int(pair[1])
		if cond.has("grant"):
			ok = false
			for pair in cond.grant:
				ok = hue.grant_skill(p, int(pair[0]), int(pair[1])) or ok
		_enter_node(p, node.then if ok else node["else"])
		return
	for act in node.get("do", []):
		match act[0]:
			"take": take_item(p, int(act[1]), int(act[2]))
			"give": give_item(p, int(act[1]), int(act[2]))
			"train": train(p, str(act[1]), int(act[2]))
	p.dialog.node = node_key
	var choices := []
	for c in node.get("choices", []):
		choices.append(c[0])
	send(p, {"t": "dialog", "npc": p.dialog.npc, "name": dlg.name, "lines": node.get("say", []),
			"choices": choices, "more": node.has("next")})


func choose(p: Being, index: int) -> void:
	if p.dialog.is_empty() or not p.dialog.has("node"):
		return
	var node: Dictionary = dialogues[p.dialog.key].nodes[p.dialog.node]
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		_enter_node(p, node.get("next", ""))
	elif index >= 0 and index < choices.size():
		_enter_node(p, choices[index][1])


# --------------------------------------------------------------------------
# Chat and developer fixtures

func chat(p: Being, text: String) -> void:
	text = text.strip_edges().left(200)
	if text.is_empty():
		return
	if text.begins_with("@"):
		if is_gm(p):
			command(p, text.substr(1))
		else:
			tell(p, "Only the host can use @ commands.")
		return
	broadcast({"t": "chat", "from": p.name, "id": p.id, "text": text})


func command(p: Being, text: String) -> void:
	var a := text.split(" ", false)
	if a.is_empty():
		return
	var arg := func(k: int, def := 0) -> int: return int(a[k]) if a.size() > k else def
	match a[0]:
		"hueinfo":
			var st: Dictionary = p.ch.hue
			var pts := []
			for i in st.hues.size():
				if st.hues[i].access:
					pts.append("%s %d" % [HueDB.hue_name(i), st.hues[i].points])
			tell(p, "Hue state v%d, origin %d, points %s, balance v%d, forced %d"
					% [st.version, st.origin, ", ".join(pts), db.b("balance_version"), p.session.forced])
		"hueprofile":
			tell(p, "Profile applied." if a.size() > 1 and hue.apply_profile(p, a[1]) else "Unknown profile.")
		"hueforce":
			hue.force_outcome(p, arg.call(1, -1))
		"hueseed":
			hue.seed(p, arg.call(1))
		"huecharge":
			hue.charge_vessels(p, arg.call(1, -1))
		"huedebug":
			p.session.debug = not p.session.debug
			tell(p, "Hue diagnostics on." if p.session.debug else "Hue diagnostics off.")
		"hueset":
			# @hueset energy|mastery <hue> <n>, points <n>, prof <skill> <n>
			match a[1] if a.size() > 1 else "":
				"energy": hue.set_energy(p, HueDB.hue_index(a[2]), arg.call(3))
				"mastery": hue.set_mastery(p, HueDB.hue_index(a[2]), arg.call(3))
				"points":
					# @hueset points <hue> <n>
					p.ch.hue.hues[HueDB.hue_index(a[2])].points = clampi(arg.call(3), 0, 999)
					private_changed(p)
				"cap":
					p.ch.hue.hues[HueDB.hue_index(a[2])].cap = clampi(arg.call(3), 1, 50)
					private_changed(p)
				"prof": hue.set_proficiency(p, arg.call(2), arg.call(3))
		"huegrant":
			# @huegrant access <hue> | skill <id> <rank>
			if a.size() > 2 and a[1] == "access":
				hue.grant_access(p, HueDB.hue_index(a[2]))
			elif a.size() > 3 and a[1] == "skill":
				hue.grant_skill(p, int(a[2]), int(a[3]))
		"item":
			give_item(p, arg.call(1), maxi(1, arg.call(2, 1)))
		"warp":
			slide(p, Vector2i(arg.call(1), arg.call(2)), HueRules.Slide.DASH)
		"spawn":
			spawn_at(arg.call(1), Vector2i(arg.call(2, p.pos.x), arg.call(3, p.pos.y)))
		"body":
			# @body <stat> <level>
			if a.size() > 2 and p.ch.body.has(a[1]):
				p.ch.body[a[1]] = {"lvl": clampi(arg.call(2), 0, 999), "xp": 0}
				refresh_stats(p)
		"technique":
			# @technique <hue> <hue>: a hybrid technique for that pair
			if a.size() > 2:
				var key := Progression.pair_key(HueDB.hue_index(a[1]), HueDB.hue_index(a[2]))
				if not p.ch.hue.techniques.has(key):
					p.ch.hue.techniques.append(key)
				refresh_stats(p)
		"heal":
			p.hp = p.max_hp
			private_changed(p)
			broadcast({"t": "heal", "id": p.id, "hp": p.hp})
		_:
			tell(p, "Unknown command @%s." % a[0])


# --------------------------------------------------------------------------
# The clock

func tick(ms: int) -> void:
	var end := now + ms
	# Advance in small steps so movement and timers keep their pace.
	while now < end:
		now = mini(end, now + 50)
		_tick_once()


func _tick_once() -> void:
	for p in players.values():
		_player_tick(p)
	for b in beings.values():
		if b.kind == Being.MOB:
			_mob_tick(b)
		elif b.kind == Being.CACHE and now >= b.respawn_at:
			beings.erase(b.id)
			broadcast({"t": "despawn", "id": b.id})
	for g in _groups.size():
		var group: Dictionary = _groups[g]
		var due: Array = group.pending.filter(func(t): return t <= now)
		group.pending = group.pending.filter(func(t): return t > now)
		for t in due:
			var b := _spawn_mob(g)
			if b:
				broadcast({"t": "spawn", "being": b.public()})
	if now >= _next_regen:
		_next_regen = now + db.b("regen_interval_ms", 1000)
		for p in players.values():
			if hue.regen(p):
				private_changed(p)
			if p.ch.has("conditions"):
				var before: int = p.ch.conditions.size()
				p.ch.conditions = p.ch.conditions.filter(func(c): return c.until > now)
				if p.ch.conditions.size() != before:
					tell(p, "You feel steady again.")
					refresh_stats(p)
	if now >= _next_autosave:
		_next_autosave = now + AUTOSAVE_MS
		save_all()
	flush()


## Send queued private state snapshots.
func flush() -> void:
	for id in _dirty:
		var p: Being = beings.get(id)
		if p and p.kind == Being.PLAYER:
			out.append(private_state(p))
	_dirty.clear()


## Hand the queued events to the caller.
func drain() -> Array:
	flush()
	var events := out
	out = []
	return events
