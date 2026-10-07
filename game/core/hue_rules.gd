class_name HueRules
extends RefCounted
## Hue rules: what a character knows, the energy it holds, which supplies an
## action draws on, the overload rolls, item loss and progression. Ported
## from the tmwa-based server (hue.cpp) and run only by the host; clients
## get results and state.
##
## An action resolves in five steps (framework section 5.3):
##   1. validate: learned skill, hue access, cooldown, activation allowance,
##      target; nothing is spent when this fails;
##   2. plan the supply: the character's own reserve first (up to the
##      current it can channel), then the selected vessel stacks in order,
##      each up to its safe current;
##   3. check energy, then current; when only overloading a vessel stack
##      could deliver the current, the player must accept the risk;
##   4. roll for the action's success and, per overloaded stack, its
##      destruction;
##   5. commit spending, wear, destruction, effects and awards together,
##      then tell the client the outcome.

## Why an action or request had the outcome it did (shared with the UI).
enum R {
	OK, UNKNOWN_SKILL, NOT_LEARNED, NO_ACCESS, DEAD, COOLDOWN, ALLOWANCE,
	CEILING, BLOCKED, NO_ENERGY, CURRENT_LIMITED, OVERLOAD_RISK,
	OVERLOAD_LIMIT, PERMANENT, NO_POINTS, NEEDS_LEVEL, NEEDS_MASTERY,
	NEEDS_PROFICIENCY, MAX_RANK, NOT_A_VESSEL, SUPPLY_FULL, OVERLOAD_FAILED,
	NOT_AT_EDGE, TOO_FAR, NO_LANDING, OBSTRUCTED, WRONG_WAY, TOO_HIGH,
	LANDING_OCCUPIED, NO_TARGET, INCOMPATIBLE,
}
enum Outcome { REJECTED, SUCCEEDED, FAILED, LEARNED, SUPPLY }
enum Fate { SAFE, STRAINED, DESTROYED }
## Slide kinds (animations): dash, knockback, featherfall, jump, fall.
enum Slide { DASH, KNOCKBACK, FEATHERFALL, JUMP, FALL }

const ACCEPT_RISK := 1
const MAX_SUPPLY := 3
const EFFECTS := {1: "dash", 2: "gust", 3: "scythe", 4: "featherfall", 5: "jump", 6: "spark"}

var world   # World
var db: HueDB
var prog: Progression


func _init(w, hue_db: HueDB, progression: Progression) -> void:
	world = w
	db = hue_db
	prog = progression


# --------------------------------------------------------------------------
# State access

static func record(ch: Dictionary, hue: int) -> Dictionary:
	return ch.hue.hues[hue]


## A hue's energy capacity, after talents, gear, body and dissonance.
func capacity(ch: Dictionary, hue: int) -> int:
	var r := record(ch, hue)
	if not r.access:
		return 0
	return prog.stat(ch, HueDB.hue_name(hue) + ".capacity", db.mastery_row(r.mastery).capacity, 1)


## The current a character channels safely in a hue, after modifiers.
func channel(ch: Dictionary, hue: int) -> int:
	return prog.stat(ch, HueDB.hue_name(hue) + ".current", db.mastery_row(record(ch, hue).mastery).current, 1)


## Regeneration per interval: mastery row, local concentration, modifiers.
func regen_amount(ch: Dictionary, hue: int, conc: int) -> int:
	var pct := db.b("regen_base_pct", 50) + conc * db.b("regen_per_conc_pct", 250) / 100
	var base: int = db.mastery_row(record(ch, hue).mastery).regen * pct / 100
	return prog.stat(ch, HueDB.hue_name(hue) + ".regen", base)


func learned_rank(ch: Dictionary, id: int) -> int:
	var sk = ch.hue.skills.get(str(id))
	return sk.rank if sk else 0


func flow_pct(ch: Dictionary, hue: int) -> int:
	var pct: int = db.mastery_row(record(ch, hue).mastery).flow_pct
	for key in ch.hue.skills:
		var def := db.rank(int(key), ch.hue.skills[key].rank)
		if not def.is_empty() and def.kind == HueDB.FLOW and def.hue == hue:
			pct += def.p1
	return pct


func mastery_next(mastery: int) -> int:
	return maxi(mastery, 1) * db.b("mastery_xp_per_level", 20)


func active_count(p: Being, hue: int) -> int:
	var n := 0
	for a in p.session.active:
		if a.hue == hue:
			n += 1
	return n


func prune_activations(p: Being) -> void:
	var now: int = world.now
	p.session.active = p.session.active.filter(func(a): return a.until > now)


func next_random(p: Being) -> int:
	var x: int = p.session.rng
	x ^= (x << 13) & 0xffffffff
	x ^= x >> 17
	x ^= (x << 5) & 0xffffffff
	p.session.rng = x
	return x


func roll(p: Being, pct: int) -> bool:
	return next_random(p) % 100 < pct


func debug(p: Being, text: String) -> void:
	if p.session.debug:
		world.tell(p, text)


# --------------------------------------------------------------------------
# Vessel lots

func vessel_at(ch: Dictionary, i: int) -> Dictionary:
	if i < 0 or i >= ch.inventory.size():
		return {}
	var lot = ch.inventory[i]
	if lot == null or lot.amount <= 0 or not lot.get("init", false):
		return {}
	return db.vessels.get(int(lot.item), {})


static func lot_energy(lot: Dictionary) -> int:
	return int(lot.charge) * int(lot.amount) / 1000


func supply_order(ch: Dictionary, i: int) -> int:
	var k: int = ch.hue.supply.find(i)
	return k + 1


func remove_supply(ch: Dictionary, i: int) -> void:
	ch.hue.supply.erase(i)


## Give a newly added item its vessel lot state if it has none yet.
func init_lot(lot: Dictionary) -> void:
	if lot.get("init", false):
		return
	var v: Dictionary = db.vessels.get(int(lot.item), {})
	if v.is_empty():
		return
	# Provisional policy: vessels arrive precharged (recharge undecided).
	lot.charge = v.initial_charge * 1000
	lot.condition = v.max_condition
	lot.init = true


## Called whenever an inventory slot changes item or empties.
func slot_changed(ch: Dictionary, i: int) -> void:
	if vessel_at(ch, i).is_empty() and supply_order(ch, i):
		remove_supply(ch, i)


# --------------------------------------------------------------------------
# Characters

## Reset the hue state to an origin or profile grant.
func apply_grant(ch: Dictionary, g: Dictionary) -> void:
	var st: Dictionary = ch.hue
	st.hues = []
	for i in HueDB.HUES.size():
		st.hues.append({"access": false, "mastery": 0, "cap": 0, "xp": 0, "energy": 0,
				"points": 0, "granted": 0, "picks": 0, "talents": []})
	st.skills = {}
	st.techniques = []
	var r: Dictionary = st.hues[g.hue]
	r.access = true
	r.mastery = g.mastery
	r.cap = maxi(g.mastery_cap, db.b("personal_cap_start", 15))
	r.granted = g.mastery
	r.points = g.skill_points
	r.energy = capacity(ch, g.hue)
	for pair in g.skills:
		# A granted rank counts as practised up to what it required.
		var def := db.rank(pair[0], pair[1])
		st.skills[str(pair[0])] = {"rank": pair[1], "prof": def.req_prof if not def.is_empty() else 0}


## New characters start from their origin.
func init_character(ch: Dictionary, origin := 1) -> void:
	var g: Dictionary = db.origins.get(origin, db.origins[1])
	ch.hue = {"version": 2, "origin": origin, "supply": []}
	apply_grant(ch, g)


## On load: repair anything the definitions no longer allow.
func repair(ch: Dictionary) -> void:
	var st: Dictionary = ch.hue
	prog.ensure(ch)
	for key in st.skills.keys():
		var top := db.max_rank(int(key))
		if top > 0:
			st.skills[key].rank = mini(st.skills[key].rank, top)
	for i in st.hues.size():
		st.hues[i].energy = clampi(st.hues[i].energy, 0, capacity(ch, i))
		if st.hues[i].access:
			prog.grant_milestones(ch, i)
	for lot in ch.inventory:
		if lot != null:
			init_lot(lot)
	st.supply = st.supply.filter(func(i): return not vessel_at(ch, i).is_empty())


## Energy regeneration and activation expiry, once per regen interval.
func regen(p: Being) -> bool:
	if p.dead:
		return false
	var changed := false
	for i in HueDB.HUES.size():
		var r: Dictionary = p.ch.hue.hues[i]
		if not r.access:
			continue
		var cap := capacity(p.ch, i)
		var gain := regen_amount(p.ch, i, world.map.concentration(p.pos, i))
		var e := mini(clampi(r.energy + gain, 0, maxi(cap, r.energy)), cap)
		if e != r.energy:
			r.energy = e
			changed = true
	var before: int = p.session.active.size()
	prune_activations(p)
	return changed or before != p.session.active.size()


func restore(p: Being, hue: int, amount: int) -> int:
	var r := record(p.ch, hue)
	if not r.access or amount <= 0:
		return 0
	var before: int = r.energy
	r.energy = mini(r.energy + amount, capacity(p.ch, hue))
	return r.energy - before


# --------------------------------------------------------------------------
# Awards

## Percent of a full award for another award of this skill now.
func award_pct(p: Being, skill: int) -> int:
	var now: int = world.now
	var window := db.b("award_window_ms", 60000)
	var recent: Array = p.session.awards.get(skill, [])
	recent = recent.filter(func(t): return t + window > now)
	var pct := maxi(db.b("award_floor_pct", 25), 100 - db.b("award_decay_pct", 15) * recent.size())
	recent.append(now)
	p.session.awards[skill] = recent
	return pct


## Mastery progress, slowed above the soft cap (the lower of where you are
## training and your personal cap); milestones are granted as it rises.
func add_mastery_xp(p: Being, hue: int, xp: int) -> void:
	var r := record(p.ch, hue)
	var top := db.b("mastery_max", 50)
	var zone: Dictionary = world.map.zone_at(p.pos)
	while xp > 0 and r.mastery < top:
		var gain := prog.mastery_gain(r, zone, xp)
		if gain <= 0:
			break
		var need: int = mastery_next(r.mastery) - r.xp
		if gain < need:
			r.xp += gain
			break
		# Spend what this level needed, at this level's rate.
		xp -= need * xp / gain
		r.xp = 0
		r.mastery += 1
		world.tell(p, "Your %s mastery rose to %d." % [HueDB.hue_title(hue), r.mastery])
	var got := prog.grant_milestones(p.ch, hue)
	if got.points:
		world.tell(p, "+%d %s skill point%s." % [got.points, HueDB.hue_title(hue), "" if got.points == 1 else "s"])
	if got.picks:
		world.tell(p, "A %s talent is ready to choose (C)." % HueDB.hue_title(hue))
	r.energy = mini(r.energy, capacity(p.ch, hue))


## Award proficiency, mastery progress and experience for an action that
## resolved with a meaningful result (units of it).
func award(p: Being, def: Dictionary, units: int) -> void:
	if units <= 0:
		return
	var pct := award_pct(p, def.id)
	var sk = p.ch.hue.skills.get(str(def.id))
	if sk and def.prof_award:
		sk.prof = mini(def.prof_cap, sk.prof + def.prof_award * units)
	if def.mastery_award:
		add_mastery_xp(p, def.hue, def.mastery_award * units * pct / 100)


# --------------------------------------------------------------------------
# Results

func _result(request: int, skill: int, modifier := 0) -> Dictionary:
	return {"t": "result", "request": request, "skill": skill,
			"outcome": Outcome.REJECTED, "reason": R.OK, "energy": 0,
			"current": 0, "channel": 0, "personal": 0, "vessel": 0,
			"detail": 0, "modifier": modifier, "mod_personal": 0,
			"mod_vessel": 0, "mod_detail": 0, "vessels": []}


func _reject(p: Being, res: Dictionary, reason: int, detail := 0) -> Dictionary:
	res.outcome = Outcome.REJECTED
	res.reason = reason
	res.detail = detail
	world.send(p, res)
	return res


# --------------------------------------------------------------------------
# Actions

## Steps 1 (hue, cooldown, allowance) and 2-3 (supply, energy, current) for
## one part of an action. Returns [reason, detail].
func plan_part(p: Being, part: Dictionary, activations_before: int, flags: int) -> Array:
	var ch := p.ch
	var h := record(ch, part.hue)
	if not h.access:
		return [R.NO_ACCESS, 0]
	var ready: int = p.session.ready.get(part.skill, 0)
	if world.now < ready:
		return [R.COOLDOWN, ready - world.now]
	var row := db.mastery_row(h.mastery)
	if active_count(p, part.hue) >= row.allowance:
		var holder := 0
		for a in p.session.active:
			if a.hue == part.hue:
				holder = a.skill
		return [R.ALLOWANCE, holder]
	if activations_before >= db.b("activation_ceiling", 3):
		var last: int = part.skill if p.session.active.is_empty() else p.session.active.back().skill
		return [R.CEILING, last]

	# Own reserve first, then the selected stacks of this hue in order.
	var E: int = part.E
	var I: int = part.I
	var safe := channel(ch, part.hue)
	var own := {"index": -1, "available": h.energy, "safe": safe, "energy": 0}
	own.current = mini(mini(I, safe), h.energy * I / maxi(E, 1))
	part.sources = [own]
	var flow := flow_pct(ch, part.hue)
	var remaining: int = I - own.current
	for i in ch.hue.supply:
		var v := vessel_at(ch, i)
		if v.is_empty() or v.hue != part.hue:
			continue
		var src := {"index": i, "vessel": v, "available": lot_energy(ch.inventory[i]),
				"safe": v.safe_current * (100 + flow) / 100, "energy": 0}
		src.current = mini(mini(remaining, src.safe), src.available * I / maxi(E, 1))
		remaining -= src.current
		part.sources.append(src)

	var total := 0
	for src in part.sources:
		total += src.available
	if total < E:
		return [R.NO_ENERGY, mini(total, 0xffff)]
	part.safe_channel = 0
	for src in part.sources:
		part.safe_channel += src.safe

	part.worst = 0
	part.risky = false
	if remaining > 0:
		# Only by pushing vessel stacks past their safe current.
		for k in range(1, part.sources.size()):
			if remaining <= 0:
				break
			var src: Dictionary = part.sources[k]
			var room: int = mini(src.available * I / maxi(E, 1), 0xffff) - src.current
			var extra := maxi(0, mini(remaining, room))
			src.current += extra
			remaining -= extra
		if remaining > 0:
			return [R.CURRENT_LIMITED, part.safe_channel]
		for k in range(1, part.sources.size()):
			var src: Dictionary = part.sources[k]
			if src.current > src.safe:
				part.worst = maxi(part.worst, src.current * 100 / src.safe)
		if part.worst > db.b("overload_max_ratio_pct", 300):
			return [R.OVERLOAD_LIMIT, part.worst]
		if not (flags & ACCEPT_RISK):
			return [R.OVERLOAD_RISK, part.worst]
		part.risky = true

	# Energy follows each source's share of the current; rounding leftovers
	# go to whichever sources still hold energy.
	var drawn := 0
	for src in part.sources:
		src.energy = src.current * E / I if I else 0
		drawn += src.energy
	for src in part.sources:
		var extra := mini(E - drawn, src.available - src.energy)
		if extra > 0:
			src.energy += extra
			drawn += extra
	part.destroyed = []
	part.destroyed.resize(part.sources.size())
	part.destroyed.fill(false)
	return [R.OK, 0]


## Step 4 for one part: roll success and each overloaded stack's fate.
func roll_part(p: Being, part: Dictionary) -> bool:
	if not part.risky:
		return true
	var m: int = record(p.ch, part.hue).mastery
	var forced: int = p.session.forced
	var p_success := clampi(db.b("success_base_pct") - db.b("success_slope_pct") * (part.worst - 100) / 100
			+ db.b("success_mastery_pct") * m, 2, 100)
	var success: bool = bool(forced & 1) if forced >= 0 else roll(p, p_success)
	for k in range(1, part.sources.size()):
		var src: Dictionary = part.sources[k]
		if src.current <= src.safe:
			continue
		var load: int = src.current * 100 / src.safe
		var p_destroy := clampi(db.b("destroy_base_pct") + db.b("destroy_slope_pct") * (load - 100) / 100
				- db.b("destroy_mastery_pct") * m, 0, 98)
		part.destroyed[k] = bool(forced & 2) if forced >= 0 else roll(p, p_destroy)
		debug(p, "[hue] stack %d load %d%%: destroy chance %d%% -> %s" % [src.index, load,
				p_destroy, "destroyed" if part.destroyed[k] else "survives"])
	debug(p, "[hue] %s worst load %d%%: success chance %d%% -> %s%s" % [part.def.name,
			part.worst, p_success, "success" if success else "failure",
			" (forced)" if forced >= 0 else ""])
	return success


## Step 5 for one part's supply: spend, wear and destroy.
func commit_part(p: Being, part: Dictionary, reports: Array) -> void:
	var ch := p.ch
	var h := record(ch, part.hue)
	h.energy -= part.sources[0].energy
	part.personal_spent = part.sources[0].energy
	part.vessel_spent = 0
	for k in range(1, part.sources.size()):
		var src: Dictionary = part.sources[k]
		if not src.current and not src.energy:
			continue
		var lot: Dictionary = ch.inventory[src.index]
		var rep := {"index": src.index, "item": lot.item, "amount": lot.amount,
				"spent": src.energy, "load": src.current * 100 / src.safe, "fate": Fate.SAFE}
		part.vessel_spent += src.energy
		# Every unit of the stack shares the draw.
		var per_unit: int = (src.energy * 1000 + lot.amount - 1) / lot.amount
		lot.charge -= mini(lot.charge, per_unit)
		if src.current > src.safe and not part.destroyed[k]:
			var wear := maxi(1, db.b("overload_wear", 40) * (rep.load - 100) / 100)
			rep.fate = Fate.STRAINED
			if lot.condition <= wear:
				part.destroyed[k] = true
			else:
				lot.condition -= wear
		if part.destroyed[k]:
			# The whole participating stack disintegrates with what it held.
			rep.fate = Fate.DESTROYED
			world.remove_item_at(p, src.index, lot.amount)
		reports.append(rep)


func _leap_reason(result: int) -> int:
	match result:
		GameMap.Leap.NOT_AT_EDGE: return R.NOT_AT_EDGE
		GameMap.Leap.TOO_FAR: return R.TOO_FAR
		GameMap.Leap.NO_LANDING: return R.NO_LANDING
		GameMap.Leap.OBSTRUCTED: return R.OBSTRUCTED
		GameMap.Leap.WRONG_WAY: return R.WRONG_WAY
		GameMap.Leap.TOO_HIGH: return R.TOO_HIGH
	return R.OK


## Use a skill facing d. flags: ACCEPT_RISK. Repeated request numbers are
## ignored. target: the selected being (0: targeted skills pick the nearest
## in front). modifier: a skill applied live to this one (0: none); it must
## be a registered combination and pays its own way.
func action(p: Being, skill: int, d: Vector2i, flags: int, request: int, target: int, modifier: int) -> Dictionary:
	if request and request <= p.session.last_request:
		return {}   # a repeated request: already resolved once
	if request:
		p.session.last_request = request
	var res := _result(request, skill, modifier)
	var ch := p.ch

	# 1. Validate. Nothing is spent on any rejection below.
	if db.max_rank(skill) == 0:
		return _reject(p, res, R.UNKNOWN_SKILL)
	var def := db.rank(skill, learned_rank(ch, skill))
	if def.is_empty():
		return _reject(p, res, R.NOT_LEARNED)
	res.energy = def.energy
	res.current = def.current
	if def.kind == HueDB.FLOW:
		return _reject(p, res, R.PERMANENT)
	if p.dead:
		return _reject(p, res, R.DEAD)
	if d == Vector2i.ZERO:
		d = p.facing

	var parts := [{"skill": skill, "def": def, "hue": def.hue, "E": def.energy, "I": def.current}]
	var combo := {}
	if modifier:
		combo = db.combo(skill, modifier)
		if combo.is_empty():
			return _reject(p, res, R.INCOMPATIBLE, modifier)
		var mod := db.rank(modifier, learned_rank(ch, modifier))
		if mod.is_empty():
			res.skill = modifier
			return _reject(p, res, R.NOT_LEARNED)
		parts.append({"skill": modifier, "def": mod, "hue": mod.hue,
				"E": mod.energy * combo.energy_pct / 100,
				"I": maxi(1, mod.current * combo.current_pct / 100)})

	prune_activations(p)
	for k in parts.size():
		var why := plan_part(p, parts[k], p.session.active.size() + k, flags)
		if why[0] != R.OK:
			# Name the part that is short: the modifier's own hue may be.
			res.skill = parts[k].skill
			res.energy = parts[k].E
			res.current = parts[k].I
			res.channel = parts[k].get("safe_channel", 0)
			if not res.channel:
				res.channel = channel(ch, parts[k].hue)
			return _reject(p, res, why[0], why[1])
	res.channel = parts[0].safe_channel

	# Targets and landings, also before anything is spent.
	var to := p.pos
	var steps := 0
	var spark: Being = null
	var m: GameMap = world.map
	match def.kind:
		HueDB.DASH:
			to = m.travel(p.pos, d, def.p1)
			steps = maxi(absi(to.x - p.pos.x), absi(to.y - p.pos.y))
			if steps == 0:
				world.set_facing(p, d)
				return _reject(p, res, R.BLOCKED)
		HueDB.FEATHERFALL, HueDB.JUMP:
			var way := 1 if def.kind == HueDB.JUMP else -1
			var leap := m.leap(p.pos, d, way, def.p1, def.p2)
			world.set_facing(p, d)
			if leap.result != GameMap.Leap.OK:
				var detail := 0
				match leap.result:
					GameMap.Leap.TOO_HIGH: detail = absi(leap.levels)
					GameMap.Leap.TOO_FAR: detail = leap.span
					GameMap.Leap.WRONG_WAY: detail = 1 if leap.levels > 0 else 2
				return _reject(p, res, _leap_reason(leap.result), detail)
			if world.occupied(leap.at, p):
				return _reject(p, res, R.LANDING_OCCUPIED)
			to = leap.at
		HueDB.SPARK:
			spark = spark_target(p, target, d, def.p1)
			if spark == null:
				return _reject(p, res, R.NO_TARGET, def.p1)

	# 4. Roll each part. Any part failing makes the whole action fizzle.
	var success := true
	for part in parts:
		success = roll_part(p, part) and success

	# 5. Commit: effects, then spending, wear and destruction.
	if spark:
		var toward := (spark.pos - p.pos).sign()
		if toward != Vector2i.ZERO:
			d = toward
	world.set_facing(p, d)
	var units := 0
	var mod_units := 0
	if success:
		match def.kind:
			HueDB.DASH, HueDB.FEATHERFALL, HueDB.JUMP:
				var kind: int = {HueDB.DASH: Slide.DASH, HueDB.FEATHERFALL: Slide.FEATHERFALL,
						HueDB.JUMP: Slide.JUMP}[def.kind]
				world.slide(p, to, kind)
				units = maxi(0, steps - 2) if def.kind == HueDB.DASH else 1
			HueDB.GUST:
				var hits := []
				for b in world.beings_near(p.pos, def.p1):
					var hit := gust_push(p, b, d, def)
					if hit:
						hits.append(b)
				units = hits.size()
				if not combo.is_empty() and combo.effect == "ignite":
					# The gust carries the spark: everyone it moved is hit.
					var mod: Dictionary = parts[1].def
					for b in hits:
						if world.alive(b):
							ignite(p, b, mod.p2 * combo.effect_pct / 100, mod.p3)
							mod_units += 1
			HueDB.SCYTHE:
				for b in world.beings_near(p.pos, def.p1):
					if b.is_vegetation() and not b.dead and in_front(p.pos, d, b.pos, def.p1):
						world.kill(b, p)
						units += 1
			HueDB.SPARK:
				ignite(p, spark, def.p2, def.p3)
				units = 1
		world.effect(p, EFFECTS.get(def.kind, ""))

	var reports := []
	for part in parts:
		commit_part(p, part, reports)
		p.session.active.append({"until": world.now + part.def.exec_ms, "skill": part.skill, "hue": part.hue})
		p.session.ready[part.skill] = world.now + part.def.cooldown_ms

	if success:
		award(p, def, units)
		if parts.size() > 1:
			award(p, parts[1].def, mod_units)
		# Feats: meaningful successes where the hue runs strong.
		if units > 0:
			for line in prog.check_feats(ch, def.hue, skill, modifier, world.map.concentration(p.pos, def.hue)):
				world.tell(p, line)

	res.outcome = Outcome.SUCCEEDED if success else Outcome.FAILED
	res.reason = R.OK if success else R.OVERLOAD_FAILED
	res.detail = units
	res.personal = parts[0].personal_spent
	res.vessel = parts[0].vessel_spent
	res.vessels = reports
	if parts.size() > 1:
		res.mod_personal = parts[1].personal_spent
		res.mod_vessel = parts[1].vessel_spent
		res.mod_detail = mod_units
	world.send(p, res)
	world.private_changed(p)

	var extra := ""
	if parts.size() > 1:
		extra = "; + %s: %d own, %d vessels" % [parts[1].def.name, parts[1].personal_spent, parts[1].vessel_spent]
	debug(p, "[hue] %s r%d: demand %d energy at %d current; own %d, vessels %d%s" % [def.name,
			def.rank, parts[0].E, parts[0].I, parts[0].personal_spent, parts[0].vessel_spent, extra])
	return res


## Whether c is in front of (or right next to) a being at from facing d,
## within radius.
static func in_front(from: Vector2i, d: Vector2i, c: Vector2i, radius: int) -> bool:
	var r := c - from
	var dist := maxi(absi(r.x), absi(r.y))
	if dist > radius:
		return false
	if dist <= 1:
		return true
	return r.x * d.x + r.y * d.y > 0


## Push one enemy away; returns whether it moved.
func gust_push(p: Being, b: Being, d: Vector2i, def: Dictionary) -> bool:
	if b.kind != Being.MOB or b.dead or b.is_vegetation():
		return false
	if not in_front(p.pos, d, b.pos, def.p1):
		return false
	# Wind does not blow through a cliff: only beings on the caster's level.
	var m: GameMap = world.map
	if not m.same_level(p.pos, b.pos):
		return false
	# Away from the caster; straight ahead if standing on the same tile.
	var push := (b.pos - p.pos).sign()
	if push == Vector2i.ZERO:
		push = d
	var to := m.travel(b.pos, push, def.p2)
	var pushed := maxi(absi(to.x - b.pos.x), absi(to.y - b.pos.y))
	var fell := false
	if pushed < def.p2:
		# Blown against a ledge with push to spare: over it, if a free
		# landing lies below within reach. Otherwise it stops at the edge.
		var leap := m.leap(to, push, -1, db.b("ledge_fall_max_levels", 3), db.b("ledge_fall_max_span", 3))
		if leap.result == GameMap.Leap.OK and not world.occupied(leap.at, b):
			to = leap.at
			fell = true
	var stagger: int = def.p3 + (db.b("fall_stagger_ms", 2000) if fell else 0)
	world.stagger(b, stagger)
	if to == b.pos:
		return false
	world.slide(b, to, Slide.FALL if fell else Slide.KNOCKBACK)
	# Gust itself never harms; a fall may, if the policy says so.
	if fell and db.b("fall_damage_pct") > 0:
		var dmg: int = b.max_hp * db.b("fall_damage_pct") / 100
		if dmg > 0:
			world.damage(b, dmg, null, "fall")
	return true


func spark_target_ok(p: Being, b: Being, range: int) -> bool:
	if b == null or b.kind != Being.MOB or b.dead or b.is_vegetation():
		return false
	var dist := maxi(absi(b.pos.x - p.pos.x), absi(b.pos.y - p.pos.y))
	return dist <= range and world.map.same_level(p.pos, b.pos)


## The selected target, or else the nearest enemy in front.
func spark_target(p: Being, target: int, d: Vector2i, range: int) -> Being:
	if target:
		var b: Being = world.beings.get(target)
		return b if spark_target_ok(p, b, range) else null
	var best: Being = null
	var best_dist := range + 1
	for b in world.beings_near(p.pos, range):
		if not spark_target_ok(p, b, range) or not in_front(p.pos, d, b.pos, range):
			continue
		var dist := maxi(absi(b.pos.x - p.pos.x), absi(b.pos.y - p.pos.y))
		if dist < best_dist:
			best = b
			best_dist = dist
	return best


## Fire damage and a chance to set the enemy burning (a new burn restarts
## an existing one). Returns whether it now burns.
func ignite(p: Being, b: Being, dmg: int, burn_pct: int) -> bool:
	world.effect(b, "fire")
	if dmg > 0:
		world.damage(b, dmg, p, "fire")
	if not world.alive(b):
		return false
	if not roll(p, burn_pct):
		return false
	b.burn = {"owner": p.id, "ticks": db.b("burn_ticks", 3), "damage": db.b("burn_tick_damage", 2),
			"next": world.now + maxi(db.b("burn_tick_ms", 1000), 100)}
	return true


## Burning enemies take damage on the burn clock.
func burn_tick(b: Being) -> void:
	if b.burn.is_empty() or b.dead or world.now < b.burn.next:
		return
	var owner: Being = world.beings.get(b.burn.owner)
	world.effect(b, "burn")
	b.burn.ticks -= 1
	b.burn.next = world.now + maxi(db.b("burn_tick_ms", 1000), 100)
	var dmg: int = b.burn.damage
	if b.burn.ticks <= 0:
		b.burn = {}
	world.damage(b, dmg, owner, "burn")


# --------------------------------------------------------------------------
# Learning and supply

func learn(p: Being, skill: int) -> Dictionary:
	var ch := p.ch
	var res := _result(0, skill)
	if db.max_rank(skill) == 0:
		return _reject(p, res, R.UNKNOWN_SKILL)
	var r := learned_rank(ch, skill)
	var next := db.rank(skill, r + 1)
	if next.is_empty():
		return _reject(p, res, R.MAX_RANK, r)
	var h := record(ch, next.hue)
	var sk = ch.hue.skills.get(str(skill))
	if not h.access:
		return _reject(p, res, R.NO_ACCESS)
	if h.points < next.cost:
		return _reject(p, res, R.NO_POINTS, next.cost)
	if h.mastery < next.req_mastery:
		return _reject(p, res, R.NEEDS_MASTERY, next.req_mastery)
	if (sk.prof if sk else 0) < next.req_prof:
		return _reject(p, res, R.NEEDS_PROFICIENCY, next.req_prof)
	if not sk:
		sk = {"rank": 0, "prof": 0}
		ch.hue.skills[str(skill)] = sk
	h.points -= next.cost
	sk.rank += 1
	res.outcome = Outcome.LEARNED
	res.detail = sk.rank
	world.send(p, res)
	world.private_changed(p)
	return res


func select_supply(p: Being, i: int, on: bool) -> Dictionary:
	var ch := p.ch
	var res := _result(0, 0)
	if vessel_at(ch, i).is_empty():
		return _reject(p, res, R.NOT_A_VESSEL)
	if on and not supply_order(ch, i):
		if ch.hue.supply.size() >= MAX_SUPPLY:
			return _reject(p, res, R.SUPPLY_FULL, MAX_SUPPLY)
		ch.hue.supply.append(i)
	elif not on:
		remove_supply(ch, i)
	res.outcome = Outcome.SUPPLY
	res.detail = supply_order(ch, i)
	world.send(p, res)
	world.private_changed(p)
	return res


# --------------------------------------------------------------------------
# Teaching and developer fixtures

## Grant hue access (mastery 1, homeland cap, full energy).
func grant_access(p: Being, hue: int) -> bool:
	var r := record(p.ch, hue)
	if r.access:
		return false
	r.access = true
	r.mastery = 1
	r.cap = maxi(r.cap, db.b("personal_cap_start", 15))
	r.xp = 0
	r.granted = maxi(r.granted, 1)
	r.energy = capacity(p.ch, hue)
	world.private_changed(p)
	return true


## Grant a skill rank (teaching NPCs). False if known at that rank already.
func grant_skill(p: Being, skill: int, rank: int) -> bool:
	var def := db.rank(skill, rank)
	if def.is_empty():
		return false
	var sk = p.ch.hue.skills.get(str(skill))
	if sk and sk.rank >= rank:
		return false
	if not sk:
		sk = {"rank": 0, "prof": 0}
		p.ch.hue.skills[str(skill)] = sk
	sk.rank = rank
	sk.prof = maxi(sk.prof, def.req_prof)
	world.private_changed(p)
	return true


func apply_profile(p: Being, profile: String) -> bool:
	var g: Dictionary = db.profiles.get(profile, {})
	if g.is_empty():
		return false
	apply_grant(p.ch, g)
	p.ch.hue.supply = []
	p.session.active = []
	p.session.ready = {}
	world.private_changed(p)
	return true


## Force the next overload resolutions: -1 clears; otherwise bit 0 = the
## action succeeds, bit 1 = participating stacks are destroyed.
func force_outcome(p: Being, outcome: int) -> void:
	p.session.forced = -1 if outcome < 0 else outcome & 3


func seed(p: Being, value: int) -> void:
	p.session.rng = value & 0xffffffff if value else 0x2545f491


func set_energy(p: Being, hue: int, energy: int) -> void:
	var r := record(p.ch, hue)
	r.energy = clampi(energy, 0, capacity(p.ch, hue))
	world.private_changed(p)


func set_mastery(p: Being, hue: int, mastery: int) -> void:
	var r := record(p.ch, hue)
	if not r.access:
		r.access = true
		r.cap = maxi(r.cap, db.b("personal_cap_start", 15))
	r.cap = maxi(r.cap, clampi(mastery, 1, 50))
	r.mastery = clampi(mastery, 1, r.cap)
	r.xp = 0
	prog.grant_milestones(p.ch, hue)
	r.energy = mini(r.energy, capacity(p.ch, hue))
	world.private_changed(p)


func set_proficiency(p: Being, skill: int, value: int) -> bool:
	var sk = p.ch.hue.skills.get(str(skill))
	var def := db.rank(skill, sk.rank) if sk else {}
	if def.is_empty():
		return false
	sk.prof = clampi(value, 0, def.prof_cap)
	world.private_changed(p)
	return true


## Refill (per_unit < 0) or set the charge of every vessel stack carried.
func charge_vessels(p: Being, per_unit: int) -> void:
	for i in p.ch.inventory.size():
		var v := vessel_at(p.ch, i)
		if v.is_empty():
			continue
		var units: int = v.capacity if per_unit < 0 else mini(per_unit, v.capacity)
		p.ch.inventory[i].charge = units * 1000
	world.private_changed(p)
