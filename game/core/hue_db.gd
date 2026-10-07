class_name HueDB
extends RefCounted
## Hue definitions and provisional balance, read from res://data/hue.
##
## The formats are the ones the tmwa-based server used (server/world/db/hue),
## so the same files carry over. Every number here is tuning data, not lore.

const HUES := ["gale", "tide", "ember", "terra", "verdant", "aura", "decay", "void"]
const GALE := 0
const EMBER := 2

## Action kinds; new kinds need code, new numbers are data.
const KIND := {"dash": 1, "gust": 2, "scythe": 3, "featherfall": 4, "jump": 5,
		"spark": 6, "flow": 10}
const DASH := 1
const GUST := 2
const SCYTHE := 3
const FEATHERFALL := 4
const JUMP := 5
const SPARK := 6
const FLOW := 10

var balance := {}            # key -> int; "rows" -> Array of row dicts
var skills := {}             # id -> Array of rank dicts (index rank-1)
var vessels := {}            # item id -> vessel dict
var origins := {}            # id -> grant dict
var profiles := {}           # name -> grant dict
var regions := []            # {map, hue, pct}
var combos := []             # {base, modifier, effect, effect_pct, energy_pct, current_pct, description}
var errors: Array[String] = []


static func load_from(dir: String) -> HueDB:
	var db := HueDB.new()
	db._read_balance(dir + "/balance.conf")
	db._read_skills(dir + "/skills.txt")
	db._read_vessels(dir + "/vessels.txt")
	db._read_grants(dir + "/origins.txt", false)
	db._read_grants(dir + "/profiles.txt", true)
	db._read_regions(dir + "/regions.txt")
	db._read_combos(dir + "/combos.txt")
	if db.balance.get("rows", []).is_empty():
		db.errors.append("balance.conf has no mastery_row")
	if not db.origins.has(1):
		db.errors.append("origins.txt needs origin 1")
	return db


static func hue_index(name: String) -> int:
	return HUES.find(name)


static func hue_name(index: int) -> String:
	return HUES[index] if index >= 0 and index < HUES.size() else "?"


static func hue_title(index: int) -> String:
	return hue_name(index).capitalize()


func _lines(path: String) -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot read " + path)
		return out
	var n := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges(false, true)
		n += 1
		if line.is_empty() or line.begins_with("//"):
			continue
		out.append([n, line])
	return out


func _bad(path: String, n: int, line: String) -> void:
	errors.append("%s line %d is invalid: %s" % [path, n, line])


func _read_balance(path: String) -> void:
	balance = {"rows": []}
	for entry in _lines(path):
		var line: String = entry[1]
		var colon := line.find(":")
		if colon < 0:
			_bad(path, entry[0], line)
			continue
		var key := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		if key == "mastery_row":
			var v := value.split(" ", false)
			if v.size() != 6:
				_bad(path, entry[0], line)
				continue
			balance.rows.append({"mastery": int(v[0]), "capacity": int(v[1]),
					"regen": int(v[2]), "current": int(v[3]),
					"allowance": int(v[4]), "flow_pct": int(v[5])})
		elif value.is_valid_int():
			balance[key] = int(value)
		else:
			_bad(path, entry[0], line)


func _read_skills(path: String) -> void:
	for entry in _lines(path):
		var line: String = entry[1]
		var f := line.split("|")
		if f.size() != 20 or hue_index(f[3]) < 0 or not KIND.has(f[4]):
			_bad(path, entry[0], line)
			continue
		var s := {
			"id": int(f[0]), "rank": int(f[1]), "name": f[2],
			"hue": hue_index(f[3]), "kind": KIND[f[4]],
			"energy": int(f[5]), "current": int(f[6]),
			"exec_ms": int(f[7]), "cooldown_ms": int(f[8]),
			"req_level": int(f[9]), "cost": int(f[9]), "req_mastery": int(f[10]),
			"req_prof": int(f[11]), "prof_cap": int(f[12]),
			"p1": int(f[13]), "p2": int(f[14]), "p3": int(f[15]),
			"prof_award": int(f[16]), "mastery_award": int(f[17]),
			"exp_award": int(f[18]), "description": f[19],
		}
		var ranks: Array = skills.get(s.id, [])
		if s.rank != ranks.size() + 1:
			_bad(path, entry[0], line)
			continue
		if (s.kind == FLOW) != (s.current == 0):
			_bad(path, entry[0], line)
			continue
		ranks.append(s)
		skills[s.id] = ranks


func _read_vessels(path: String) -> void:
	for entry in _lines(path):
		var f := (entry[1] as String).split("|")
		if f.size() != 8 or hue_index(f[1]) < 0:
			_bad(path, entry[0], entry[1])
			continue
		vessels[int(f[0])] = {"item": int(f[0]), "hue": hue_index(f[1]),
				"grade": int(f[2]), "capacity": int(f[3]),
				"safe_current": int(f[4]), "max_condition": int(f[5]),
				"initial_charge": int(f[6]), "label": f[7]}


func _parse_skill_list(text: String) -> Array:
	var out := []
	for part in text.split(",", false):
		var p := part.split(":")
		out.append([int(p[0]), int(p[1])])
	return out


func _read_grants(path: String, profile: bool) -> void:
	for entry in _lines(path):
		var f := (entry[1] as String).split("|")
		if profile and f.size() == 7:
			profiles[f[0]] = {"name": f[0], "hue": hue_index(f[1]),
					"mastery": int(f[2]), "mastery_cap": int(f[3]),
					"skills": _parse_skill_list(f[4]),
					"skill_points": int(f[5]), "level": int(f[6])}
		elif not profile and f.size() == 7:
			origins[int(f[0])] = {"name": f[1], "hue": hue_index(f[2]),
					"mastery": int(f[3]), "mastery_cap": int(f[4]),
					"skills": _parse_skill_list(f[5]),
					"skill_points": int(f[6]), "level": 0}
		else:
			_bad(path, entry[0], entry[1])


func _read_regions(path: String) -> void:
	for entry in _lines(path):
		var f := (entry[1] as String).split("|")
		if f.size() != 3:
			_bad(path, entry[0], entry[1])
			continue
		regions.append({"map": f[0], "hue": hue_index(f[1]), "pct": int(f[2])})


func _read_combos(path: String) -> void:
	for entry in _lines(path):
		var f := (entry[1] as String).split("|")
		if f.size() != 7 or f[2] != "ignite":
			_bad(path, entry[0], entry[1])
			continue
		combos.append({"base": int(f[0]), "modifier": int(f[1]),
				"effect": f[2], "effect_pct": int(f[3]),
				"energy_pct": int(f[4]), "current_pct": int(f[5]),
				"description": f[6]})


## Definition of skill id at rank (1-based), or {}.
func rank(id: int, r: int) -> Dictionary:
	var ranks: Array = skills.get(id, [])
	return ranks[r - 1] if r >= 1 and r <= ranks.size() else {}


func max_rank(id: int) -> int:
	return skills.get(id, []).size()


func combo(base: int, modifier: int) -> Dictionary:
	for c in combos:
		if c.base == base and c.modifier == modifier:
			return c
	return {}


## Capability row for a mastery value (the highest row not above it).
func mastery_row(mastery: int) -> Dictionary:
	var rows: Array = balance.rows
	var best: Dictionary = rows[0]
	for r in rows:
		if r.mastery <= mastery:
			best = r
	return best


func region_pct(map_name: String, hue: int) -> int:
	for r in regions:
		if r.hue == hue and r.map == map_name:
			return r.pct
	return 100 if hue == GALE else 0


func b(key: String, default := 0) -> int:
	return balance.get(key, default)
