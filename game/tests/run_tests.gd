extends SceneTree
## Headless rules tests: godot --headless --path game -s res://tests/run_tests.gd
##
## Ported from server/tools/worldtest.py (scenarios pass1, pass2, spark and
## the baseline's save checks), driving the World directly with its own
## clock, so they are fast and deterministic.

const DASH := 1
const GUST := 2
const SCYTHE := 3
const FEATHERFALL := 4
const JUMP := 5
const SPARK := 6
const REED := 701
const HERB := 703
const PETAL := 704
const TEMPERED := 706
const TONIC := 710
const HOPPER := 1010
const GALE := 0
const EMBER := 2

const R := HueRules.R
const O := HueRules.Outcome
const F := HueRules.Fate

var failures: Array[String] = []
var passed := 0
var w: World
var a: Being
var events: Array = []
var request := 0


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	for scenario in ["data", "terrain", "pass1", "pass2", "spark", "world", "saves"]:
		if only.is_empty() or only.has(scenario):
			print("== ", scenario)
			call("t_" + scenario)
	print("%d passed, %d failed" % [passed, failures.size()])
	for f in failures:
		print("  FAILED: ", f)
	quit(1 if failures.size() else 0)


func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  ok   ", what)
	else:
		failures.append(what)
		print("  FAIL ", what)


# --------------------------------------------------------------------------
# Helpers

## A fresh world without monsters, with one GM player at a cell.
func fresh(at := Vector2i(14, 20)) -> void:
	w = World.new()
	w.gm_everyone = true
	w.rng.seed = 1
	for b in w.beings.values():
		if b.kind == Being.MOB:
			w.beings.erase(b.id)
	w._groups.clear()
	if not w.errors.is_empty():
		check(false, "world loads (%s)" % ", ".join(w.errors))
	w.join(1, "Wanderer", "secret-a")
	a = w.players[1]
	a.session.rng = 12345
	warp(a, at)
	pump()


func pump(ms := 0) -> void:
	if ms:
		w.tick(ms)
	events.append_array(w.drain())


func mark() -> void:
	pump()
	events.clear()


func gm(p: Being, text: String) -> void:
	w.handle(p.peer, {"t": "chat", "text": text})
	pump()


func warp(p: Being, at: Vector2i) -> void:
	w.slide(p, at, 0)
	p.path.clear()


func act(skill: int, d: Vector2i, flags := 0, target := 0, modifier := 0, p: Being = null) -> Dictionary:
	p = p if p else a
	request += 1
	mark()
	w.handle(p.peer, {"t": "hue", "skill": skill, "dx": d.x, "dy": d.y, "flags": flags,
			"request": request, "target": target, "modifier": modifier})
	pump()
	return last_result(p)


func last_result(p: Being = null) -> Dictionary:
	p = p if p else a
	for k in range(events.size() - 1, -1, -1):
		if events[k].t == "result" and events[k].get("to") == p.peer:
			return events[k]
	return {}


func learn(skill: int) -> Dictionary:
	mark()
	w.handle(1, {"t": "learn", "skill": skill})
	pump()
	return last_result()


func select(index: int, on := true) -> Dictionary:
	mark()
	w.handle(1, {"t": "supply", "index": index, "on": 1 if on else 0})
	pump()
	return last_result()


func gale(p: Being = null) -> Dictionary:
	return (p if p else a).ch.hue.hues[GALE]


func clear_mobs() -> void:
	for b in w.beings.values():
		if b.kind == Being.MOB:
			w.beings.erase(b.id)


func hopper_at(at: Vector2i) -> Being:
	return w.spawn_at(HOPPER, at)


## Full energy in every hue and skills off cooldown.
func ready() -> void:
	for h in [GALE, EMBER]:
		if a.ch.hue.hues[h].access:
			w.hue.set_energy(a, h, 999)
	w.tick(1600)
	a.hp = a.max_hp
	for h in [GALE, EMBER]:
		if a.ch.hue.hues[h].access:
			w.hue.set_energy(a, h, 999)
	mark()


func slides_of(b: Being) -> Array:
	return events.filter(func(e): return e.t == "slide" and e.id == b.id)


func damage_to(b: Being) -> Array:
	return events.filter(func(e): return e.t == "damage" and e.id == b.id).map(func(e): return e.amount)


## Gust right at a hopper standing right of the player.
func gust(flags := 0) -> Array:
	clear_mobs()
	a.hp = a.max_hp
	var hop := hopper_at(a.pos + Vector2i(1, 0))
	ready()
	var r := act(GUST, Vector2i(1, 0), flags)
	return [r, slides_of(hop)]


func index_of(item: int) -> int:
	for i in a.ch.inventory.size():
		var lot = a.ch.inventory[i]
		if lot != null and lot.item == item:
			return i
	return -1


func lot(i: int) -> Dictionary:
	return a.ch.inventory[i] if i >= 0 and i < a.ch.inventory.size() and a.ch.inventory[i] != null else {}


func reed_stacks() -> Array:
	var out := []
	for i in a.ch.inventory.size():
		if lot(i).get("item") == REED:
			out.append(i)
	return out


func summary(r: Dictionary) -> String:
	if r.is_empty():
		return "no result"
	return "outcome %d reason %d detail %d own %d vessels %d %s" % [r.outcome, r.reason,
			r.detail, r.personal, r.vessel, r.vessels]


# --------------------------------------------------------------------------
# Scenarios

func t_data() -> void:
	var db := HueDB.load_from("res://data/hue")
	check(db.errors.is_empty(), "hue definitions load without errors %s" % [db.errors])
	check(db.max_rank(GUST) == 3 and db.rank(GUST, 2).current == 9, "Gust has 3 ranks; rank 2 needs 9 current")
	check(db.vessels[REED].safe_current == 4 and db.vessels[TEMPERED].capacity == 40, "vessel definitions")
	check(not db.combo(GUST, SPARK).is_empty() and db.combo(DASH, SPARK).is_empty(), "Gust+Spark is the one combination")
	check(db.region_pct("gale-1", EMBER) == 50 and db.region_pct("gale-1", GALE) == 100, "regional regen")
	check(db.mastery_row(6).current == 8 and db.mastery_row(20).current == 16, "mastery rows")
	var m := GameMap.load_named("gale-1")
	check(m.errors.is_empty() and m.w == 44 and m.h == 34, "the meadow map loads %s" % [m.errors])
	check(m.npcs.size() == 2 and m.spawns.size() == 6, "two NPCs and six spawn groups")


func t_terrain() -> void:
	var m := GameMap.load_named("gale-1")
	var down := Vector2i(0, 1)
	var up := Vector2i(0, -1)
	check(m.level(20, 10) == 1 and m.level(20, 13) == 0 and m.cliff(20, 11) and m.stair(9, 11), "levels, cliffs, stairs")
	check(not m.ground_step(Vector2i(20, 10), down), "no walking off the terrace edge")
	check(m.ground_step(Vector2i(9, 10), down) and m.ground_step(Vector2i(9, 12), down), "stairs join the levels")
	var l := m.leap(Vector2i(20, 10), down, -1, 1, 2)
	check(l.result == GameMap.Leap.OK and l.at == Vector2i(20, 13) and l.levels == -1 and l.span == 2, "featherfall off the terrace")
	l = m.leap(Vector2i(20, 13), up, 1, 1, 1)
	check(l.result == GameMap.Leap.TOO_FAR and l.span == 2, "the terrace face is too tall for a rank 1 jump")
	l = m.leap(Vector2i(20, 13), up, -1, 1, 2)
	check(l.result == GameMap.Leap.WRONG_WAY and l.levels == 1, "featherfall facing up the face is the wrong way")
	l = m.leap(Vector2i(25, 3), Vector2i(1, 0), 1, 1, 1)
	check(l.result == GameMap.Leap.OK and l.at == Vector2i(27, 3), "a rank 1 jump onto the lookout")
	l = m.leap(Vector2i(40, 10), down, -1, 1, 2)
	check(l.result == GameMap.Leap.TOO_HIGH and l.levels == -2, "the spur is two levels up")
	l = m.leap(Vector2i(2, 10), Vector2i(-1, 1), -1, 1, 3)
	check(l.result == GameMap.Leap.OBSTRUCTED, "a diagonal leap past the forest edge is obstructed")
	l = m.leap(Vector2i(20, 20), Vector2i(1, 0), -1, 1, 2)
	check(l.result == GameMap.Leap.NOT_AT_EDGE, "no cliff ahead")
	l = m.leap(Vector2i(9, 11), down, -1, 1, 2)
	check(l.result == GameMap.Leap.NOT_AT_EDGE, "no leaping from stairs")


func t_pass1() -> void:
	fresh(Vector2i(2, 20))
	var g := gale()
	var row := w.db.mastery_row(g.mastery)
	check(g.mastery == 1 and g.cap == 10 and g.energy == 60 and w.hue.capacity_of(g) == 60
			and row.current == 6 and row.allowance == 1, "Gale record: mastery 1/10, energy 60/60, channel 6, allowance 1")
	var skills: Dictionary = a.ch.hue.skills
	check(skills.size() == 3 and skills["1"].rank == 1 and skills["2"].rank == 1 and skills["3"].rank == 1
			and a.ch.hue.skill_points == 0, "starting skills Dash/Gust/Wind Scythe rank 1, 0 points")

	ready()
	var r := act(DASH, Vector2i(1, 0))
	var d1 := a.pos.x - 2
	check(r.outcome == O.SUCCEEDED and d1 == 6, "Dash rank 1 travels 6 tiles (%d)" % d1)

	warp(a, Vector2i(14, 20))
	var res := gust()
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.personal == 15 and r.vessel == 0 and not res[1].is_empty(),
			"Gust rank 1 from personal reserve: %s" % summary(r))

	gm(a, "@hueset energy gale 5")
	w.tick(1600)
	w.hue.set_energy(a, GALE, 5)
	r = act(GUST, Vector2i(1, 0))
	check(r.outcome == O.REJECTED and r.reason == R.NO_ENERGY and r.personal == 0 and a.ch.hue.hues[GALE].energy == 5,
			"insufficient energy rejects Gust: %s" % summary(r))

	ready()
	request += 1
	for k in 2:
		w.handle(1, {"t": "hue", "skill": SCYTHE, "dx": 1, "dy": 0, "request": request})
	pump()
	var same := events.filter(func(e): return e.t == "result" and e.request == request)
	check(same.size() == 1 and same[0].personal == 4, "a duplicated request resolves once (%d results)" % same.size())

	var prof0: int = skills["2"].prof
	var xp0: int = gale().xp
	res = gust()
	check(not res[1].is_empty() and skills["2"].prof == prof0 + 5 and gale().xp > xp0,
			"displacing an enemy advances Gust proficiency and mastery progress")
	var prof1: int = skills["2"].prof
	var xp1: int = gale().xp
	clear_mobs()
	ready()
	r = act(GUST, Vector2i(1, 0))
	check(r.outcome == O.SUCCEEDED and skills["2"].prof == prof1 and gale().xp == xp1,
			"a gust into empty air costs energy but awards nothing")

	r = learn(GUST)
	check(r.reason == R.NO_POINTS, "upgrade without points: reason %d" % r.reason)
	gm(a, "@hueset points 1")
	r = learn(GUST)
	check(r.reason == R.NEEDS_LEVEL and r.detail == 2, "upgrade needs level 2: %s" % summary(r))
	gm(a, "@level 4")
	check(a.ch.hue.skill_points == 4, "levels 2-4 grant 3 skill points (%d)" % a.ch.hue.skill_points)
	r = learn(GUST)
	check(r.reason == R.NEEDS_MASTERY and r.detail == 3, "upgrade needs mastery 3: %s" % summary(r))
	gm(a, "@hueset mastery gale 6")
	r = learn(GUST)
	check(r.reason == R.NEEDS_PROFICIENCY and r.detail == 50, "upgrade needs proficiency 50: %s" % summary(r))
	gm(a, "@hueset prof 2 50")
	r = learn(GUST)
	check(r.outcome == O.LEARNED and skills["2"].rank == 2 and a.ch.hue.skill_points == 3,
			"Gust upgraded to rank 2 for one point: %s" % summary(r))

	ready()
	var energy: int = gale().energy
	r = act(GUST, Vector2i(1, 0))
	check(r.reason == R.CURRENT_LIMITED and r.detail == 8 and r.personal == 0 and energy >= 18,
			"Gust rank 2 is current-limited with %d energy: %s" % [energy, summary(r)])

	gm(a, "@item 701 10")
	gm(a, "@item 703 2")
	gm(a, "@item 706 1")
	var reeds := index_of(REED)
	var temp := index_of(TEMPERED)
	var herbs := w.count_item(a, HERB)
	check(lot(reeds).charge == 20000 and lot(reeds).condition == 100 and lot(temp).charge == 40000,
			"vessels arrive precharged")
	ready()
	act(SCYTHE, Vector2i(1, 0))
	check(lot(reeds).charge == 20000, "unselected vessels are never drawn on")
	r = select(reeds)
	check(r.outcome == O.SUPPLY and w.hue.supply_order(a.ch, reeds) == 1, "Breeze Reeds selected as supply 1")
	res = gust()
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.vessels.size() == 1 and r.vessels[0].fate == F.SAFE
			and r.personal + r.vessel == 18 and not res[1].is_empty(), "Gust rank 2 succeeds safely with reeds: %s" % summary(r))
	check(lot(reeds).charge == 20000 - (r.vessel * 1000 + 9) / 10 and w.count_item(a, REED) == 10,
			"the reed stack pays its share and stays (charge %d)" % lot(reeds).charge)
	res = gust()
	check(res[0].outcome == O.SUCCEEDED and w.count_item(a, REED) == 10, "the reeds are reusable for rated use")

	gm(a, "@hueset prof 2 150")
	r = learn(GUST)
	check(r.outcome == O.LEARNED and skills["2"].rank == 3, "Gust upgraded to rank 3")
	ready()
	var charge: int = lot(reeds).charge
	r = act(GUST, Vector2i(1, 0))
	check(r.reason == R.OVERLOAD_RISK and r.detail == 150 and r.vessel == 0 and lot(reeds).charge == charge,
			"rank 3 would overload the reeds (150%%): asks first, spends nothing: %s" % summary(r))
	gm(a, "@huecharge")
	gm(a, "@item 701 10")
	check(w.count_item(a, REED) == 20 and reed_stacks().size() == 1, "full reeds merge into one stack of 20")
	ready()
	r = act(GUST, Vector2i(1, 0))
	check(r.reason == R.OVERLOAD_RISK and r.detail == 150, "twice the reeds deliver no more safe current: %s" % summary(r))

	gm(a, "@hueforce 1")
	res = gust(1)
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.vessels.size() and r.vessels[0].fate == F.STRAINED and not res[1].is_empty()
			and lot(reeds).condition == 80, "forced success, stack survives strained (condition %d)" % lot(reeds).get("condition", -1))
	gm(a, "@hueforce 0")
	res = gust(1)
	r = res[0]
	check(r.outcome == O.FAILED and r.reason == R.OVERLOAD_FAILED and r.personal > 0 and res[1].is_empty(),
			"forced failure: energy spent, nobody pushed: %s" % summary(r))
	gm(a, "@item 701 2")
	var others := reed_stacks().filter(func(i): return i != reeds)
	check(others.size() == 1 and w.count_item(a, REED) == 22, "new reeds form their own stack beside the worn one")
	gm(a, "@hueforce 3")
	res = gust(1)
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.vessels.size() and r.vessels[0].fate == F.DESTROYED and w.count_item(a, REED) == 2
			and w.count_item(a, HERB) == herbs and w.count_item(a, TEMPERED) == 1 and lot(temp).charge == 40000,
			"forced destruction removes exactly the selected stack: %s" % summary(r))
	check(w.hue.supply_order(a.ch, others[0]) == 0 and a.ch.hue.supply.is_empty(), "the destroyed stack left the supply; the other was never in it")
	select(others[0])
	gm(a, "@hueforce 2")
	res = gust(1)
	r = res[0]
	check(r.outcome == O.FAILED and r.vessels.size() and r.vessels[0].fate == F.DESTROYED and w.count_item(a, REED) == 0
			and res[1].is_empty(), "forced failure with destruction: %s" % summary(r))

	gm(a, "@hueforce -1")
	var outcomes := []
	for k in 2:
		gm(a, "@item 701 5")
		select(reed_stacks()[0])
		gm(a, "@hueseed 7")
		r = gust(1)[0]
		outcomes.append([r.outcome, r.vessels.map(func(v): return v.fate)])
		for i in reed_stacks():
			w.remove_item_at(a, i, lot(i).amount)
	check(outcomes[0] == outcomes[1], "the same seed gives the same overload outcome %s" % [outcomes])

	select(temp)
	res = gust()
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.vessels.size() and r.vessels[0].fate == F.SAFE and not res[1].is_empty(),
			"the Tempered Reed (test grade) carries rank 3 safely: %s" % summary(r))

	gm(a, "@hueprofile advanced")
	res = gust()
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.vessel == 0 and not res[1].is_empty(), "mastery 20 casts rank 3 from the personal reserve: %s" % summary(r))
	warp(a, Vector2i(2, 20))
	ready()
	act(DASH, Vector2i(1, 0))
	check(a.pos.x - 2 > d1, "Dash rank 3 goes further than rank 1 (%d > %d)" % [a.pos.x - 2, d1])
	warp(a, Vector2i(14, 20))

	gm(a, "@hueset mastery gale 6")
	gm(a, "@item 701 4")
	select(index_of(REED))
	res = gust()
	r = res[0]
	check(r.outcome == O.SUCCEEDED and r.vessels.size() and r.vessels[0].fate == F.SAFE and r.vessels[0].load == 100,
			"Steady Flow makes the same reeds safe at 100%% load: %s" % summary(r))

	w.gm_everyone = false
	w.join(2, "Breezy", "secret-b")
	var b: Being = w.players[2]
	pump()
	for c in ["@hueforce 3", "@hueset mastery gale 50", "@hueprofile advanced", "@hueset energy gale 0"]:
		gm(b, c)
	check(gale(b).mastery == 1 and gale(b).energy > 0 and b.ch.hue.skills["2"].rank == 1 and b.session.forced == -1,
			"non-host players cannot change hue state or rolls")


func t_pass2() -> void:
	fresh(Vector2i(9, 14))
	var wren: Being = null
	for b in w.beings.values():
		if b.kind == Being.NPC and b.key == "wren":
			wren = b
	check(wren != null and w.map.level(wren.pos.x, wren.pos.y) == 1, "Wren the Ridge-runner is on the terrace")

	w.walk_to(a, Vector2i(9, 9))
	pump(4000)
	check(a.pos == Vector2i(9, 9), "walking up the stairs reaches the terrace (%s)" % a.pos)
	mark()
	w.handle(1, {"t": "talk", "id": wren.id})
	pump()
	w.handle(1, {"t": "choose", "index": 0})
	pump()
	check(w.hue.learned_rank(a.ch, FEATHERFALL) == 1 and w.hue.learned_rank(a.ch, JUMP) == 1,
			"Wren teaches Featherfall and Upward Jump")
	check(events.any(func(e): return e.t == "dialog" and str(e.lines).contains("Featherfall")), "Wren explains the keys")

	warp(a, Vector2i(20, 10))
	ready()
	var r := act(FEATHERFALL, Vector2i(0, 1))
	var mine := slides_of(a)
	check(r.outcome == O.SUCCEEDED and a.pos == Vector2i(20, 13) and mine.size() == 1 and mine[0].kind == HueRules.Slide.FEATHERFALL,
			"Featherfall drifts down the terrace face: %s" % summary(r))
	ready()
	r = act(FEATHERFALL, Vector2i(0, -1))
	check(r.reason == R.WRONG_WAY and r.detail == 1 and r.personal == 0, "Featherfall up a face: wrong way, nothing spent")
	r = act(JUMP, Vector2i(0, -1))
	check(r.reason == R.TOO_FAR and r.detail == 2, "the terrace face is too tall for Jump rank 1: %s" % summary(r))
	r = act(FEATHERFALL, Vector2i(1, 0))
	check(r.reason == R.NOT_AT_EDGE, "no cliff ahead: %s" % summary(r))

	warp(a, Vector2i(25, 3))
	ready()
	r = act(JUMP, Vector2i(1, 0))
	check(r.outcome == O.SUCCEEDED and a.pos == Vector2i(27, 3) and slides_of(a)[0].kind == HueRules.Slide.JUMP,
			"Upward Jump onto the lookout: %s" % summary(r))
	var gave := false
	clear_mobs()
	var reed := w.spawn_at(1104, Vector2i(28, 3))
	ready()
	var before := w.count_item(a, REED)
	act(SCYTHE, Vector2i(1, 0))
	check(reed.dead and w.count_item(a, REED) > before, "Skyreeds on the lookout give Breeze Reeds")

	warp(a, Vector2i(40, 10))
	ready()
	r = act(FEATHERFALL, Vector2i(0, 1))
	check(r.reason == R.TOO_HIGH and r.detail == 2, "the spur is too high for Featherfall rank 1: %s" % summary(r))
	warp(a, Vector2i(2, 10))
	ready()
	r = act(FEATHERFALL, Vector2i(-1, 1))
	check(r.reason == R.OBSTRUCTED, "a corner obstructs a diagonal drift: %s" % summary(r))
	warp(a, Vector2i(30, 4))
	ready()
	r = act(FEATHERFALL, Vector2i(0, 1))
	check(r.outcome == O.SUCCEEDED and a.pos == Vector2i(30, 7), "Featherfall from the lookout onto the terrace")

	warp(a, Vector2i(20, 10))
	clear_mobs()
	var blocker := hopper_at(Vector2i(20, 13))
	w.stagger(blocker, 60000)
	ready()
	r = act(FEATHERFALL, Vector2i(0, 1))
	check(r.reason == R.LANDING_OCCUPIED and a.pos == Vector2i(20, 10), "an enemy on the landing blocks it")

	# Gust a hopper off the terrace edge.
	clear_mobs()
	warp(a, Vector2i(20, 9))
	var hop := hopper_at(Vector2i(20, 10))
	ready()
	r = act(GUST, Vector2i(0, 1))
	var falls := slides_of(hop)
	check(r.outcome == O.SUCCEEDED and falls.size() == 1 and falls[0].kind == HueRules.Slide.FALL and hop.pos == Vector2i(20, 13)
			and damage_to(hop).is_empty(), "Gust sends a hopper over the ledge, unharmed (%s)" % hop.pos)
	mark()
	a.hp = a.max_hp
	warp(a, Vector2i(20, 10))
	pump(8000)
	check(damage_to(a).is_empty(), "the fallen hopper cannot attack across the cliff")
	mark()
	w.handle(1, {"t": "attack", "id": hop.id})
	pump(500)
	check(damage_to(hop).is_empty() and a.target == hop.id and not a.path.is_empty(),
			"attacking it from above means walking round by the stairs")


func t_spark() -> void:
	fresh(Vector2i(14, 20))
	var hop := hopper_at(Vector2i(16, 20))
	w.stagger(hop, 600000)
	ready()
	var r := act(SPARK, Vector2i(1, 0))
	check(r.reason == R.NOT_LEARNED, "Spark unknown at first")
	gm(a, "@huegrant skill 6 1")
	r = act(SPARK, Vector2i(1, 0))
	check(r.reason == R.NO_ACCESS, "Spark needs Ember access")
	gm(a, "@huegrant access ember")
	var ember: Dictionary = a.ch.hue.hues[EMBER]
	check(ember.mastery == 1 and ember.energy > 0, "Ember access: mastery 1, energy %d" % ember.energy)
	ready()
	var e0: int = ember.energy
	var g0: int = gale().energy
	r = act(SPARK, Vector2i(1, 0))
	check(r.outcome == O.SUCCEEDED and r.personal == 12 and damage_to(hop) == [8],
			"Spark: 12 Ember energy, 8 fire damage: %s" % summary(r))
	check(ember.energy < e0 and gale().energy == g0, "Spark draws on Ember, not Gale")

	var burned := false
	for k in 12:
		hop.hp = hop.max_hp
		ready()
		r = act(SPARK, Vector2i(1, 0))
		if not hop.burn.is_empty():
			mark()
			pump(3500)
			var ticks := events.filter(func(e): return e.t == "damage" and e.id == hop.id and e.kind == "burn")
			burned = ticks.size() == 3 and ticks.all(func(e): return e.amount == 2)
			break
	check(burned, "sometimes it burns: 3 ticks of 2 damage")

	clear_mobs()
	ready()
	r = act(SPARK, Vector2i(1, 0))
	check(r.reason == R.NO_TARGET and r.detail == 4, "no enemy in reach: %s" % summary(r))
	warp(a, Vector2i(20, 10))
	var below := hopper_at(Vector2i(20, 13))
	w.stagger(below, 600000)
	ready()
	r = act(SPARK, Vector2i(0, 1), 0, below.id)
	check(r.reason == R.NO_TARGET, "Spark cannot reach across a cliff")

	# Gust carries Spark's fire.
	warp(a, Vector2i(14, 20))
	clear_mobs()
	hop = hopper_at(Vector2i(15, 20))
	ready()
	e0 = ember.energy
	g0 = gale().energy
	r = act(GUST, Vector2i(1, 0), 0, 0, SPARK)
	check(r.outcome == O.SUCCEEDED and r.modifier == SPARK and r.mod_detail == 1 and not slides_of(hop).is_empty(),
			"Gust + Spark ignites what it pushes: %s" % summary(r))
	check(gale().energy < g0 and ember.energy < e0 and r.mod_personal == 9, "each hue pays its share (Ember %d)" % r.mod_personal)
	check(damage_to(hop).slice(0, 1) == [8], "the pushed hopper takes Spark's fire (%s)" % [damage_to(hop)])
	r = act(GUST, Vector2i(1, 0), 0, 0, SPARK)
	check(r.reason == R.COOLDOWN, "both parts take their cooldowns")
	ready()
	r = act(DASH, Vector2i(1, 0), 0, 0, SPARK)
	check(r.reason == R.INCOMPATIBLE and r.detail == SPARK, "Dash + Spark is not a combination")
	w.hue.set_energy(a, EMBER, 2)
	r = act(GUST, Vector2i(1, 0), 0, 0, SPARK)
	check(r.reason == R.NO_ENERGY and r.skill == SPARK and gale().energy == w.hue.capacity_of(gale()),
			"Ember short: names Spark, spends no Gale: %s" % summary(r))
	a.ch.hue.skills.erase("6")
	ready()
	r = act(GUST, Vector2i(1, 0), 0, 0, SPARK)
	check(r.reason == R.NOT_LEARNED and r.skill == SPARK, "an unlearned modifier is refused")


func t_world() -> void:
	fresh(Vector2i(14, 26))
	var ama: Being = null
	for b in w.beings.values():
		if b.kind == Being.NPC and b.key == "ama":
			ama = b
	check(ama != null, "Windkeeper Ama is in the clearing")
	mark()
	w.handle(1, {"t": "talk", "id": ama.id})
	pump()
	w.handle(1, {"t": "choose", "index": 1})
	pump()
	check(w.count_item(a, TONIC) == 0 and events.any(func(e): return e.t == "dialog" and str(e.lines).contains("three Meadow Herbs")),
			"Ama asks for herbs and petals first")
	gm(a, "@item 703 4")
	gm(a, "@item 704 3")
	w.handle(1, {"t": "talk", "id": ama.id})
	w.handle(1, {"t": "choose", "index": 1})
	pump()
	check(w.count_item(a, TONIC) == 1 and w.count_item(a, HERB) == 1 and w.count_item(a, PETAL) == 0, "Ama brews a Gale Tonic")
	a.hp = 10
	w.hue.set_energy(a, GALE, 0)
	mark()
	w.handle(1, {"t": "use", "index": index_of(TONIC)})
	pump()
	check(a.hp == a.max_hp and gale().energy == 60 and w.count_item(a, TONIC) == 0, "the tonic heals and restores Gale (%d HP)" % a.hp)

	# Harvest with Wind Scythe.
	clear_mobs()
	for x in [15, 16]:
		w.spawn_at(1101, Vector2i(x, 26))
	ready()
	var r := act(SCYTHE, Vector2i(1, 0))
	check(r.outcome == O.SUCCEEDED and r.detail == 2 and w.count_item(a, 702) == 2, "Wind Scythe harvests grass: %s" % summary(r))

	# Fight a hopper to the end.
	clear_mobs()
	var hop := hopper_at(Vector2i(17, 26))
	var exp0: int = a.ch.exp + a.ch.level * 1000
	mark()
	w.handle(1, {"t": "attack", "id": hop.id})
	pump(20000)
	check(hop.dead and a.ch.exp + a.ch.level * 1000 > exp0, "a hopper dies to basic attacks and gives experience")
	check(events.any(func(e): return e.t == "damage" and e.id == a.id), "it fought back")

	# Death and the cozy respawn.
	clear_mobs()
	pump(4000)
	warp(a, Vector2i(14, 26))
	a.safe_until = 0
	var bite := hopper_at(Vector2i(15, 26))
	a.hp = 1
	pump(5000)
	check(events.any(func(e): return e.t == "die" and e.id == a.id), "a player can fall")
	pump(4000)
	check(not a.dead and a.hp == a.max_hp and a.pos == w.map.spawn, "and wakes in the clearing, healed")
	mark()
	pump(3000)
	check(damage_to(a).is_empty(), "monsters leave a newly woken player be for a moment")

	# Monsters come back.
	w = World.new()
	var count := w.beings.values().filter(func(b): return b.cls == 1101).size()
	check(count == 22, "22 Meadow Grass grow at start (%d)" % count)
	w.join(1, "Cutter", "x")
	var p: Being = w.players[1]
	var grass: Being = w.beings.values().filter(func(b): return b.cls == 1101)[0]
	w.kill(grass, p)
	w.tick(40000)
	count = w.beings.values().filter(func(b): return b.cls == 1101 and not b.dead).size()
	check(count == 22, "harvested grass regrows (%d)" % count)


func t_saves() -> void:
	var dir := "user://test-world-%d" % Time.get_ticks_usec()
	w = World.new()
	w.save_dir = dir
	w.gm_everyone = true
	check(w.join(1, "Wanderer", "secret-a") == "", "a new character joins")
	a = w.players[1]
	gm(a, "@item 701 7")
	gm(a, "@item 703 2")
	gm(a, "@hueprofile advanced")
	select(index_of(REED))
	warp(a, Vector2i(15, 22))
	var snapshot: Dictionary = a.ch.duplicate(true)
	check(w.join(2, "Wanderer", "secret-a") != "", "the same character cannot be in twice")
	w.leave(1)
	check(w.join(3, "wanderer", "wrong") != "", "someone else cannot take the name")
	check(w.join(3, "Wanderer", "secret-a") == "", "rejoining with the right secret works")
	a = w.players[3]
	check(a.pos == Vector2i(15, 22), "rejoin keeps the position")
	w.save_all()

	w = World.new()
	w.save_dir = dir
	check(w.join(1, "Wanderer", "secret-a") == "", "after a host restart the character loads")
	a = w.players[1]
	var keep := ["level", "inventory", "hue"]
	var same := true
	for k in keep:
		same = same and JSON.stringify(a.ch[k]) == JSON.stringify(snapshot[k])
	check(same and a.pos == Vector2i(15, 22), "inventory, vessel lots, supply, hue state and position survive a restart")
	check(a.ch.hue.supply.size() == 1 and w.hue.supply_order(a.ch, index_of(REED)) == 1, "the supply selection survives")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/characters/wanderer.json"))
