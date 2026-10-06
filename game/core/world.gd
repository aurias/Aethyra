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
const AUTOSAVE_MS := 60000
const TALK_RANGE := 3
const EXP_TABLE := [9, 16, 25, 36, 77, 112, 153, 200, 253, 320, 385, 490, 585, 700, 830,
		970, 1120, 1260, 1420, 1620]

var db: HueDB
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
	hue = HueRules.new(self, db)
	map = GameMap.load_file("%s/maps/%s.txt" % [data_dir, map_name])
	errors.append_array(map.errors)
	_read_items(data_dir + "/world/items.txt")
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


func _read_items(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot read " + path)
		return
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
	return {"t": "me", "to": p.peer, "id": p.id, "name": p.name, "level": p.ch.level,
			"exp": p.ch.exp, "exp_next": exp_next(p.ch.level), "hp": p.hp,
			"max_hp": p.max_hp, "hue": p.ch.hue.duplicate(true),
			"inventory": p.ch.inventory.duplicate(true), "ready": ready, "active": active,
			"gm": is_gm(p)}


func effect(b: Being, name: String) -> void:
	if name != "":
		broadcast({"t": "effect", "id": b.id, "name": name})


# --------------------------------------------------------------------------
# Players: joining, leaving, saves

static func max_hp_for(level: int) -> int:
	return 40 + 10 * (level - 1)


static func exp_next(level: int) -> int:
	if level <= EXP_TABLE.size():
		return EXP_TABLE[level - 1]
	return int(EXP_TABLE.back() * pow(1.15, level - EXP_TABLE.size()))


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
	p.max_hp = max_hp_for(ch.level)
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
	var ch := {"version": 1, "name": n, "secret": secret, "level": 1, "exp": 0,
			"hp": max_hp_for(1), "x": map.spawn.x, "y": map.spawn.y, "fx": 0, "fy": 1,
			"inventory": []}
	hue.init_character(ch, 1)
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


## Move instantly (skills, knockback, falls), with an animation kind.
func slide(b: Being, to: Vector2i, kind: int) -> void:
	b.path.clear()
	b.pos = to
	b.next_step = now + 300
	broadcast({"t": "slide", "id": b.id, "x": to.x, "y": to.y, "kind": kind})


func stagger(b: Being, ms: int) -> void:
	b.path.clear()
	b.can_move_at = now + ms
	b.attackable_at = now + ms


## Whether a being other than self stands on cell (one can land among plants).
func occupied(cell: Vector2i, self_being: Being) -> bool:
	for b in beings.values():
		if b == self_being or b.pos != cell:
			continue
		if b.kind == Being.MOB and (b.dead or b.is_vegetation()):
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
	b.hp = maxi(0, b.hp - amount)
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
		tell(b, "The wind lets you down gently. You will wake in the clearing.")
		private_changed(b)
		return
	if killer and killer.kind == Being.PLAYER:
		gain_exp(killer, b.mob.exp)
		for drop in b.mob.drops:
			if rng.randi_range(0, 9999) < drop[1]:
				give_item(killer, drop[0], 1)
	var g: Dictionary = _groups[b.group]
	g.alive -= 1
	var delay: int = g.spawn.respawn_ms
	g.pending.append(now + delay + rng.randi_range(0, delay / 2))
	b.respawn_at = now + 1500     # corpse lingers, then goes


func gain_exp(p: Being, amount: int) -> void:
	if amount <= 0 or p.kind != Being.PLAYER:
		return
	p.ch.exp += amount
	while p.ch.exp >= exp_next(p.ch.level):
		p.ch.exp -= exp_next(p.ch.level)
		set_level(p, p.ch.level + 1)
	private_changed(p)


func set_level(p: Being, level: int) -> void:
	p.ch.level = level
	p.max_hp = max_hp_for(level)
	p.hp = p.max_hp
	hue.level_points(p.ch)
	broadcast({"t": "level", "id": p.id, "level": level, "hp": p.hp, "max_hp": p.max_hp})
	tell(p, "You reached level %d." % level)
	private_changed(p)


func _player_tick(p: Being) -> void:
	if p.dead:
		if now >= p.respawn_at:
			p.dead = false
			p.hp = p.max_hp
			p.pos = map.spawn
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
				damage(t, rng.randi_range(3, 6) + p.ch.level, p)
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
	var lot := {"item": id, "amount": amount, "charge": 0, "condition": 0, "init": false}
	hue.init_lot(lot)
	var inv: Array = p.ch.inventory
	var slot := -1
	for i in inv.size():
		var o = inv[i]
		# Stacks merge only when every unit shares the same lot state.
		if o != null and o.item == id and o.charge == lot.charge and o.condition == lot.condition \
				and o.get("init", false) == lot.init:
			o.amount += amount
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
	send(p, {"t": "loot", "item": id, "amount": amount})
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
			tell(p, "Hue state v%d, origin %d, %d skill points (granted to level %d), balance v%d, forced %d"
					% [st.version, st.origin, st.skill_points, st.points_level,
					db.b("balance_version"), p.session.forced])
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
					p.ch.hue.skill_points = clampi(arg.call(2), 0, 999)
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
		"level":
			set_level(p, clampi(arg.call(1, 1), 1, 99))
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
