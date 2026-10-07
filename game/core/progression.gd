class_name Progression
extends RefCounted
## Character growth without a character level: per-hue milestones and
## talents, trained body stats, soft mastery caps raised by feats, hue
## dissonance, and equipment, all feeding one modifier system.
## See docs/design/Aethyra-Progression-Framework-v0.1.md. Every number is data
## in res://data/progression, res://data/hue and res://data/world.

const SLOTS := ["head", "body", "hands", "legs", "feet", "main", "off", "ring1", "ring2", "amulet"]
const BANDS := ["edge", "frontier", "deep", "core", "altar"]

var db: HueDB
var bands := {}         # band -> {limit, respawn}
var body := {}          # stat -> {name, activities: {activity: xp}, mods, description}
var milestones := []    # {hue (-1 = all), from, to, step, points, talent}
var talents := {}       # id -> {id, hue, min_mastery, name, mods, description}
var feats := {}         # id -> {...}
var relations := {}     # "a:b" (a < b) -> {relation, pct}
var gear := {}          # item -> {slot, tier, mods, sockets, tags}
var gems := {}          # item -> {mods, tags}
var rarities := []      # {name, pct, sockets, up_chance}
var errors: Array[String] = []


static func load_from(data_dir: String, hue_db: HueDB) -> Progression:
	var p := Progression.new()
	p.db = hue_db
	for f in p._rows(data_dir + "/progression/bands.txt", 3):
		p.bands[f[0]] = {"limit": int(f[1]), "respawn": f[2]}
	for f in p._rows(data_dir + "/progression/body.txt", 5):
		var acts := {}
		for a in f[2].split(",", false):
			var q: PackedStringArray = str(a).split(":")
			acts[q[0]] = int(q[1])
		p.body[f[0]] = {"name": f[1], "activities": acts, "mods": parse_mods(f[3]), "description": f[4]}
	for f in p._rows(data_dir + "/progression/milestones.txt", 6):
		p.milestones.append({"hue": -1 if f[0] == "*" else HueDB.hue_index(f[0]), "from": int(f[1]),
				"to": int(f[2]), "step": maxi(1, int(f[3])), "points": int(f[4]), "talent": f[5] == "1"})
	for f in p._rows(data_dir + "/progression/talents.txt", 6):
		p.talents[f[0]] = {"id": f[0], "hue": HueDB.hue_index(f[1]), "min_mastery": int(f[2]),
				"name": f[3], "mods": parse_mods(f[4]), "description": f[5]}
	for f in p._rows(data_dir + "/progression/feats.txt", 9):
		p.feats[f[0]] = {"id": f[0], "hue": HueDB.hue_index(f[1]), "skill": int(f[2]), "modifier": int(f[3]),
				"min_conc": int(f[4]), "gear_tag": f[5], "cap_raise": int(f[6]), "name": f[7], "hint": f[8]}
	for f in p._rows(data_dir + "/hue/relations.txt", 4):
		p.relations[pair_key(HueDB.hue_index(f[0]), HueDB.hue_index(f[1]))] = {"relation": f[2], "pct": int(f[3])}
	for f in p._rows(data_dir + "/world/equipment.txt", 6):
		p.gear[int(f[0])] = {"slot": f[1], "tier": int(f[2]), "mods": parse_mods(f[3]),
				"sockets": int(f[4]), "tags": Array(f[5].split(",", false))}
	for f in p._rows(data_dir + "/world/gems.txt", 3):
		p.gems[int(f[0])] = {"mods": parse_mods(f[1]), "tags": Array(f[2].split(",", false))}
	for f in p._rows(data_dir + "/world/rarities.txt", 5):
		p.rarities.append({"name": f[1], "pct": int(f[2]), "sockets": int(f[3]), "up_chance": int(f[4])})
	for b in BANDS:
		if not p.bands.has(b):
			p.errors.append("bands.txt lacks band " + b)
	if p.rarities.is_empty():
		p.errors.append("no rarities")
	return p


func _rows(path: String, fields: int) -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot read " + path)
		return out
	var n := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		n += 1
		if line.is_empty() or line.begins_with("//"):
			continue
		var parts := line.split("|")
		if parts.size() != fields:
			errors.append("%s line %d: expected %d fields" % [path, n, fields])
			continue
		out.append(parts)
	return out


## "stat:+5,stat:-10%" -> [[stat, flat, pct], ...]
static func parse_mods(text: String) -> Array:
	var out := []
	for m in text.split(",", false):
		var q: PackedStringArray = str(m).strip_edges().split(":")
		if q.size() != 2:
			continue
		var v := q[1]
		if v.ends_with("%"):
			out.append([q[0], 0, int(v.trim_suffix("%"))])
		else:
			out.append([q[0], int(v), 0])
	return out


static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func mods_text(mods: Array) -> String:
	var parts := []
	for m in mods:
		parts.append("%s %s%d%s" % [m[0], "+" if (m[1] + m[2]) >= 0 else "", m[1] if m[1] else m[2], "%" if not m[1] else ""])
	return ", ".join(parts)


# --------------------------------------------------------------------------
# Character records

## Fill in any progression fields a character lacks (new or older saves).
func ensure(ch: Dictionary) -> void:
	if not ch.has("body"):
		ch.body = {}
	for s in body:
		if not ch.body.has(s):
			ch.body[s] = {"lvl": 0, "xp": 0}
	if not ch.has("progress"):
		ch.progress = {"seen": {}, "feats": [], "novel": []}
	if not ch.has("equipment"):
		ch.equipment = {}
	if not ch.has("anchors"):
		ch.anchors = {}
	if not ch.hue.has("techniques"):
		ch.hue.techniques = []
	for r in ch.hue.hues:
		for k in ["points", "granted", "picks"]:
			if not r.has(k):
				r[k] = 0
		if not r.has("talents"):
			r.talents = []


# --------------------------------------------------------------------------
# Modifiers

## Every modifier on a character: [stat, flat, pct, source].
func modifiers(ch: Dictionary) -> Array:
	var out := []
	for s in ch.get("body", {}):
		var lvl: int = ch.body[s].lvl
		if lvl > 0 and body.has(s):
			for m in body[s].mods:
				out.append([m[0], m[1] * lvl, m[2] * lvl, body[s].name])
	for i in ch.hue.hues.size():
		for t in ch.hue.hues[i].get("talents", []):
			if talents.has(t):
				for m in talents[t].mods:
					out.append([m[0], m[1], m[2], talents[t].name])
		var d := dissonance(ch, i)
		if d > 0:
			for k in ["capacity", "regen", "current"]:
				out.append(["%s.%s" % [HueDB.hue_name(i), k], 0, -d, "Dissonance"])
	for slot in ch.get("equipment", {}):
		var inst: Dictionary = ch.equipment[slot]
		out.append_array(gear_modifiers(inst))
	for c in ch.get("conditions", []):
		for m in c.mods:
			out.append([m[0], m[1], m[2], c.name])
	return out


## An equipment instance's modifiers: its base scaled by rarity, its gems
## and its enchants.
func gear_modifiers(inst: Dictionary) -> Array:
	var out := []
	var g: Dictionary = gear.get(int(inst.item), {})
	var rp: int = rarities[clampi(inst.get("rarity", 0), 0, rarities.size() - 1)].pct
	var label := "gear %d" % inst.item
	for m in g.get("mods", []):
		out.append([m[0], roundi(m[1] * rp / 100.0), roundi(m[2] * rp / 100.0), label])
	for gem in inst.get("sockets", []):
		if gem and gems.has(int(gem)):
			for m in gems[int(gem)].mods:
				out.append([m[0], m[1], m[2], "gem %d" % gem])
	for m in inst.get("enchants", []):
		out.append([m[0], m[1], m[2], "enchant"])
	return out


static func _applies(mod_key: String, key: String) -> bool:
	if mod_key == key:
		return true
	return mod_key.begins_with("*.") and key.ends_with(mod_key.substr(1))


## A derived stat: (base + flat) * (100 + pct) / 100, at least floor.
func stat(ch: Dictionary, key: String, base: int, floor_value := 0) -> int:
	return stat_from(modifiers(ch), key, base, floor_value)


static func stat_from(mods: Array, key: String, base: int, floor_value := 0) -> int:
	var flat := 0
	var pct := 0
	for m in mods:
		if _applies(m[0], key):
			flat += m[1]
			pct += m[2]
	return maxi(floor_value, (base + flat) * (100 + pct) / 100)


## Where a stat's value comes from, for the UI: [[source, flat, pct], ...]
func breakdown(ch: Dictionary, key: String) -> Array:
	var out := []
	for m in modifiers(ch):
		if _applies(m[0], key):
			out.append([m[3], m[1], m[2]])
	return out


# --------------------------------------------------------------------------
# Dissonance

func relation(a: int, b: int) -> Dictionary:
	return relations.get(pair_key(a, b), {"relation": "neutral", "pct": db.b("dissonance_neutral_pct", 8)})


## Percent by which the other hues a character holds weaken hue a.
func dissonance(ch: Dictionary, a: int) -> int:
	var ra: Dictionary = ch.hue.hues[a]
	if not ra.access:
		return 0
	var total := 0
	for b in ch.hue.hues.size():
		var rb: Dictionary = ch.hue.hues[b]
		if b == a or not rb.access:
			continue
		if ch.hue.get("techniques", []).has(pair_key(a, b)):
			continue
		var weight := mini(100, rb.mastery * 100 / maxi(ra.mastery, 1))
		total += relation(a, b).pct * weight / 100
	return mini(total, db.b("dissonance_max_pct", 40))


# --------------------------------------------------------------------------
# Body stats

func body_next(lvl: int) -> int:
	return db.b("body_xp_base", 25) * (lvl + 1)


## Train every body stat fed by an activity. Returns level-up messages.
func train(ch: Dictionary, activity: String, units: int) -> Array:
	var said := []
	if units <= 0:
		return said
	for s in body:
		var xp: int = body[s].activities.get(activity, 0)
		if xp <= 0:
			continue
		var rec: Dictionary = ch.body[s]
		rec.xp += xp * units
		while rec.xp >= body_next(rec.lvl):
			rec.xp -= body_next(rec.lvl)
			rec.lvl += 1
			said.append("Your %s rose to %d." % [body[s].name, rec.lvl])
	return said


## Record a visited cell; true the first time.
func explore(ch: Dictionary, map_name: String, cell: Vector2i, w: int, h: int) -> bool:
	var seen: Dictionary = ch.progress.seen
	var bits: PackedByteArray
	if seen.has(map_name):
		bits = Marshalls.base64_to_raw(seen[map_name])
	if bits.size() != (w * h + 7) / 8:
		bits = PackedByteArray()
		bits.resize((w * h + 7) / 8)
	var i := cell.x + cell.y * w
	if i < 0 or i >= w * h or bits[i >> 3] & (1 << (i & 7)):
		return false
	bits[i >> 3] |= 1 << (i & 7)
	seen[map_name] = Marshalls.raw_to_base64(bits)
	return true


# --------------------------------------------------------------------------
# Mastery: soft caps, milestones, talents

## The mastery a zone trains at full rate.
func training_limit(zone: Dictionary) -> int:
	return bands.get(zone.get("band", "edge"), {"limit": 10}).limit


func soft_cap(rec: Dictionary, zone: Dictionary) -> int:
	return mini(training_limit(zone), rec.cap)


## Mastery xp actually gained: halved for each level above the soft cap.
func mastery_gain(rec: Dictionary, zone: Dictionary, xp: int) -> int:
	var over: int = rec.mastery - soft_cap(rec, zone)
	if over < 0:
		return xp
	return xp >> mini(over + 1, 30)


## Grant milestones up to the hue's current mastery. Returns what was granted.
func grant_milestones(ch: Dictionary, hue: int) -> Dictionary:
	var r: Dictionary = ch.hue.hues[hue]
	var got := {"points": 0, "picks": 0}
	while r.granted < r.mastery:
		r.granted += 1
		var m: int = r.granted
		for ms in milestones:
			if ms.hue != -1 and ms.hue != hue:
				continue
			if m < ms.from or m > ms.to or (m - ms.from) % ms.step != 0:
				continue
			r.points += ms.points
			got.points += ms.points
			if ms.talent:
				r.picks += 1
				got.picks += 1
	return got


## Talents a hue may choose from now.
func talent_offers(ch: Dictionary, hue: int) -> Array:
	var r: Dictionary = ch.hue.hues[hue]
	var out := []
	for id in talents:
		var t: Dictionary = talents[id]
		if t.hue == hue and t.min_mastery <= r.mastery and not r.talents.has(id):
			out.append(id)
	out.sort()
	return out


## Pick a talent; "" or why not.
func pick_talent(ch: Dictionary, id: String) -> String:
	var t: Dictionary = talents.get(id, {})
	if t.is_empty():
		return "There is no such talent."
	var r: Dictionary = ch.hue.hues[t.hue]
	if r.picks <= 0:
		return "You have no %s talent pick to spend." % HueDB.hue_title(t.hue)
	if not talent_offers(ch, t.hue).has(id):
		return "%s is not open to you yet." % t.name
	r.picks -= 1
	r.talents.append(id)
	return ""


# --------------------------------------------------------------------------
# Feats

func gear_tags(ch: Dictionary) -> Array:
	var tags := []
	for slot in ch.get("equipment", {}):
		var inst: Dictionary = ch.equipment[slot]
		tags.append_array(gear.get(int(inst.item), {}).get("tags", []))
		for gem in inst.get("sockets", []):
			if gem and gems.has(int(gem)):
				tags.append_array(gems[int(gem)].tags)
	return tags


## After a meaningful success: authored feats and systemic novelty.
## conc is the hue's concentration where it happened. Returns messages.
func check_feats(ch: Dictionary, hue: int, skill: int, modifier: int, conc: int) -> Array:
	var said := []
	var r: Dictionary = ch.hue.hues[hue]
	var tags := gear_tags(ch)
	var top := db.b("mastery_max", 50)
	for id in feats:
		var f: Dictionary = feats[id]
		if ch.progress.feats.has(id) or f.hue != hue or f.skill != skill:
			continue
		if (f.modifier and f.modifier != modifier) or conc < f.min_conc:
			continue
		if f.gear_tag != "-" and not tags.has(f.gear_tag):
			continue
		ch.progress.feats.append(id)
		r.cap = mini(top, r.cap + f.cap_raise)
		said.append("Feat: %s! Your %s cap rose to %d." % [f.name, HueDB.hue_title(hue), r.cap])
	if conc >= db.b("novelty_min_conc", 40):
		tags.sort()
		var band := conc / 10
		var key := "%d:%d:%d:%d:%s" % [hue, skill, modifier, band, ",".join(tags)]
		if not ch.progress.novel.has(key):
			ch.progress.novel.append(key)
			r.cap = mini(top, r.cap + db.b("novelty_cap_raise", 1))
			said.append("Something new: your %s cap rose to %d." % [HueDB.hue_title(hue), r.cap])
	return said
