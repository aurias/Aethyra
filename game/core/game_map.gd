class_name GameMap
extends RefCounted
## A map: walkability, elevation and what stands on it, read from
## res://data/maps/<name>.txt (written by tools/content/make_meadow.py).
##
## Terrain rules are ported from the tmwa-based server (terrain.cpp):
## walkable cells on different levels only meet at stairs, so walking never
## changes level; Dash, featherfall, jumps and forced falls go through leap().
## The client's landing preview runs the same code on the same data.

enum Leap { OK, NOT_AT_EDGE, TOO_FAR, NO_LANDING, OBSTRUCTED, WRONG_WAY, TOO_HIGH }

const CLIFF := -1
const STAIR := -2
const BLOCKING := "~TtODuBbr#"

var name := ""
var title := ""
var w := 0
var h := 0
var spawn := Vector2i.ZERO
var elev := PackedInt32Array()      # level, CLIFF or STAIR
var ground := PackedStringArray()   # one row string per y
var blocked := PackedByteArray()    # obstacles (not cliffs)
var npcs := []                      # {key, name, x, y, dialogue}
var spawns := []                    # {mob, x, y, rx, ry, count, respawn_ms}
var errors: Array[String] = []


static func load_named(map_name: String) -> GameMap:
	return load_file("res://data/maps/%s.txt" % map_name)


static func load_file(path: String) -> GameMap:
	var m := GameMap.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		m.errors.append("cannot read " + path)
		return m
	var section := ""
	var elev_rows := []
	var ground_rows := []
	while not f.eof_reached():
		var line := f.get_line().strip_edges(false, true)
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("["):
			section = line
			continue
		match section:
			"[elevation]":
				elev_rows.append(line)
			"[ground]":
				ground_rows.append(line)
			"[things]":
				m._read_thing(line)
			_:
				m._read_header(line)
	m._build(elev_rows, ground_rows)
	return m


func _read_header(line: String) -> void:
	var colon := line.find(":")
	var key := line.substr(0, colon).strip_edges()
	var v := line.substr(colon + 1).strip_edges()
	match key:
		"name": name = v
		"title": title = v
		"size":
			var p := v.split(" ", false)
			w = int(p[0])
			h = int(p[1])
		"spawn":
			var p := v.split(" ", false)
			spawn = Vector2i(int(p[0]), int(p[1]))


func _read_thing(line: String) -> void:
	var f := line.split("|")
	if f[0] == "npc" and f.size() == 6:
		npcs.append({"key": f[1], "name": f[2], "x": int(f[3]), "y": int(f[4]),
				"dialogue": f[5]})
	elif f[0] == "spawn" and f.size() == 8:
		spawns.append({"mob": int(f[1]), "x": int(f[2]), "y": int(f[3]),
				"rx": int(f[4]), "ry": int(f[5]), "count": int(f[6]),
				"respawn_ms": int(f[7])})
	else:
		errors.append("bad thing: " + line)


func _build(elev_rows: Array, ground_rows: Array) -> void:
	if elev_rows.size() != h or ground_rows.size() != h:
		errors.append("%s: expected %d rows of each layer" % [name, h])
		return
	elev.resize(w * h)
	blocked.resize(w * h)
	for y in h:
		var er: String = elev_rows[y]
		var gr: String = ground_rows[y]
		if er.length() != w or gr.length() != w:
			errors.append("%s: row %d is not %d wide" % [name, y, w])
			return
		ground.append(gr)
		for x in w:
			var c := er[x]
			elev[x + y * w] = CLIFF if c == "C" else STAIR if c == "S" else int(c)
			blocked[x + y * w] = 1 if BLOCKING.contains(gr[x]) else 0


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func ground_at(x: int, y: int) -> String:
	return ground[y][x] if inside(x, y) else "#"


func level(x: int, y: int) -> int:
	if not inside(x, y):
		return 0
	var v := elev[x + y * w]
	return v if v >= 0 else 0


## The level a cell is drawn at: cliffs belong to the ground below them,
## stairs to the higher of their ends.
func raw(x: int, y: int) -> int:
	return elev[x + y * w] if inside(x, y) else 0


func cliff(x: int, y: int) -> bool:
	return inside(x, y) and elev[x + y * w] == CLIFF


func stair(x: int, y: int) -> bool:
	return inside(x, y) and elev[x + y * w] == STAIR


func walkable(x: int, y: int) -> bool:
	return inside(x, y) and blocked[x + y * w] == 0 and not cliff(x, y)


## Blocked and not a cliff face: trees, water, the forest edge.
func obstacle(x: int, y: int) -> bool:
	return not inside(x, y) or (not walkable(x, y) and not cliff(x, y))


## Whether beings on these cells share a level (a stair joins both of its
## neighbours' levels). Attacks, Gust and Spark need this.
func same_level(a: Vector2i, b: Vector2i) -> bool:
	if stair(a.x, a.y) or stair(b.x, b.y):
		return true
	return level(a.x, a.y) == level(b.x, b.y)


## One ground step: the target is walkable, on a compatible level, and a
## diagonal step does not cut a blocked corner.
func ground_step(from: Vector2i, d: Vector2i) -> bool:
	var n := from + d
	if not walkable(n.x, n.y) or not same_level(from, n):
		return false
	if d.x != 0 and d.y != 0 and (not walkable(from.x + d.x, from.y) or not walkable(from.x, from.y + d.y)):
		return false
	return true


## Cross the cliff face in front of from along d. dir is -1 to go down
## (featherfall, falls), +1 to go up (jump). Returns {result, at, span,
## levels}. Landing occupancy is the caller's to check.
func leap(from: Vector2i, d: Vector2i, dir: int, max_levels: int, max_span: int) -> Dictionary:
	var out := {"result": Leap.NOT_AT_EDGE, "at": from, "span": 0, "levels": 0}
	if d == Vector2i.ZERO or stair(from.x, from.y):
		return out
	var lvl_from := level(from.x, from.y)
	var c := from
	while true:
		var n := c + d
		if d.x != 0 and d.y != 0 and (obstacle(c.x + d.x, c.y) or obstacle(c.x, c.y + d.y)):
			out.result = Leap.OBSTRUCTED if out.span else Leap.NOT_AT_EDGE
			return out
		if not cliff(n.x, n.y):
			c = n
			break
		out.span += 1
		if out.span > 16:
			out.result = Leap.TOO_FAR
			return out
		c = n
	if out.span == 0:
		return out
	out.at = c
	var landable := walkable(c.x, c.y) and not stair(c.x, c.y)
	out.levels = level(c.x, c.y) - lvl_from
	# A ledge the other way is the other move's, however wide it is.
	if landable and out.levels * dir <= 0:
		out.result = Leap.WRONG_WAY
	elif out.span > max_span:
		out.result = Leap.TOO_FAR
	elif not landable:
		out.result = Leap.NO_LANDING
	elif absi(out.levels) > max_levels:
		out.result = Leap.TOO_HIGH
	else:
		out.result = Leap.OK
	return out


## Up to range ground steps along d. Returns the cell reached.
func travel(from: Vector2i, d: Vector2i, steps: int) -> Vector2i:
	var c := from
	for i in steps:
		if d == Vector2i.ZERO or not ground_step(c, d):
			break
		c += d
	return c
