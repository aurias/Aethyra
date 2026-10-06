class_name Game
extends Node2D
## The world as this player sees it. It mirrors what the host reports
## (events from Net), turns input into requests, and previews where a
## featherfall or jump would land using the same terrain rules as the host.

signal leave_requested

const SKILL_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
const STEP_SECONDS := 0.15

var db: HueDB
var items := {}
var map: GameMap
var map_view: MapView
var objects: Node2D
var effects: Node2D
var preview: Node2D
var cam: Camera2D
var hud: Hud

var views := {}            # id -> BeingView
var my_id := 0
var me := {}
var primed := 0
var target := 0
var request := 0
var _next_step := 0.0
var _preview := {}         # {cell, ok, text}


func _ready() -> void:
	db = HueDB.load_from("res://data/hue")
	items = World.read_items("res://data/world/items.txt")
	Net.event.connect(_on_event)
	cam = Camera2D.new()
	cam.zoom = Vector2(2, 2)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	map_view = MapView.new()
	add_child(map_view)
	objects = Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	preview = Node2D.new()
	preview.z_index = 3
	preview.draw.connect(_draw_preview)
	add_child(preview)
	effects = Node2D.new()
	effects.z_index = 4
	add_child(effects)
	hud = Hud.new()
	hud.game = self
	hud.db = db
	hud.items = items
	hud.skill_pressed.connect(func(i): use_skill(i))
	add_child(hud)


func load_map(map_name: String) -> void:
	map = GameMap.load_named(map_name)
	map_view.setup(map, objects)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = map.w * MapView.CELL
	cam.limit_bottom = map.h * MapView.CELL


func mine() -> BeingView:
	return views.get(my_id)


# --------------------------------------------------------------------------
# Events from the host

func _on_event(ev: Dictionary) -> void:
	match ev.t:
		"welcome":
			my_id = ev.id
			if map == null or map.name != ev.map:
				load_map(ev.map)
		"spawn":
			var d: Dictionary = ev.being
			var v: BeingView = views.get(d.id)
			if v:
				v.revive(d)
			else:
				v = BeingView.new()
				v.setup(d)
				v.is_me = d.id == my_id
				objects.add_child(v)
				views[d.id] = v
			if d.id == my_id:
				cam.position = v.position
				cam.reset_smoothing()
		"despawn":
			var v: BeingView = views.get(ev.id)
			if v:
				views.erase(ev.id)
				v.queue_free()
			if target == ev.id:
				target = 0
		"move":
			var v: BeingView = views.get(ev.id)
			if v:
				v.move_to(Vector2i(ev.x, ev.y), ev.ms)
		"face":
			var v: BeingView = views.get(ev.id)
			if v:
				v.facing = Vector2i(ev.fx, ev.fy)
		"slide":
			var v: BeingView = views.get(ev.id)
			if v:
				var from := v.position
				v.slide(Vector2i(ev.x, ev.y), ev.kind)
				if ev.kind == 3:
					_effect("jump", from)
				elif ev.kind == 2:
					_effect("featherfall", v.position, Vector2.ZERO, v)
		"damage":
			var v: BeingView = views.get(ev.id)
			if v:
				v.hurt(ev.hp, ev.kind)
				var colour := Color("ffb347") if ev.kind in ["fire", "burn"] else Color("ff6b5b") if ev.id == my_id else Color.WHITE
				_effect("text", v.position, Vector2.ZERO, null, str(ev.amount), colour)
		"heal":
			var v: BeingView = views.get(ev.id)
			if v:
				v.hp = ev.hp
		"die":
			var v: BeingView = views.get(ev.id)
			if v:
				v.die()
			if target == ev.id:
				_select(0)
		"attack":
			var v: BeingView = views.get(ev.id)
			var t: BeingView = views.get(ev.target)
			if v and t:
				v.facing = (t.cell - v.cell).sign()
		"effect":
			var v: BeingView = views.get(ev.id)
			if v:
				_effect(ev.name, v.position, Vector2(v.facing), v)
		"level":
			var v: BeingView = views.get(ev.id)
			if v:
				v.max_hp = ev.max_hp
				v.hp = ev.hp
				_effect("level", v.position)
		"me":
			me = ev
			hud.set_me(ev)
			var v := mine()
			if v:
				v.hp = ev.hp
				v.max_hp = ev.max_hp
		"result":
			var colour := Color("f3ead2")
			if ev.outcome == HueRules.Outcome.REJECTED:
				colour = Color("ffc3a8")
			elif ev.outcome == HueRules.Outcome.FAILED:
				colour = Color("ff9d7a")
			hud.toast(Describe.result(db, items, ev), colour)
			if ev.outcome == HueRules.Outcome.REJECTED and ev.reason == HueRules.R.OVERLOAD_RISK:
				hud.toast("(Shift + %d to accept the risk.)" % (Hud.HOTBAR.find(ev.skill) + 1), Color("ffd98a"))
		"msg":
			hud.toast(ev.text)
		"chat":
			hud.chat(ev.from, ev.text)
			var v: BeingView = views.get(ev.get("id", 0))
			if v and ev.from != "":
				_effect("text", v.position + Vector2(0, -16), Vector2.ZERO, null, ev.text.left(40), Color("fff8e0"))
		"loot":
			var v := mine()
			if v:
				_effect("text", v.position + Vector2(0, -14), Vector2.ZERO, null,
						"+%d %s" % [ev.amount, Describe.item_label(items, ev.item, 1)], Color("c8f7c5"))
		"dialog":
			hud.show_dialog(ev)
		"dialog_close":
			hud.hide_dialog()


func _effect(kind: String, at: Vector2, dir := Vector2.ZERO, follow: BeingView = null, text := "", colour := Color.WHITE) -> void:
	var e := Effect.make(kind, at, dir, text, colour)
	effects.add_child(e)


# --------------------------------------------------------------------------
# Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if hud.dialog.visible and k >= KEY_1 and k <= KEY_9:
			hud.dialog_choose(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
		var slot := SKILL_KEYS.find(k)
		if slot >= 0:
			use_skill(slot, event.shift_pressed)
		elif k == KEY_Q:
			if hud.learned(HueDB.SPARK):
				primed = 0 if primed else HueDB.SPARK
				hud.set_me(me)
		elif k == KEY_TAB:
			_target_nearest()
		elif k == KEY_H:
			hud.toggle("hues")
		elif k == KEY_K:
			hud.toggle("skills")
		elif k == KEY_I:
			hud.toggle("inventory")
		elif k == KEY_F1:
			hud.help.visible = not hud.help.visible
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			hud.focus_chat()
		elif k == KEY_ESCAPE:
			if not hud.close_windows():
				leave_requested.emit()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = Vector2.ONE * minf(cam.zoom.x + 1, 3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = Vector2.ONE * maxf(cam.zoom.x - 1, 1)


func _process(_delta: float) -> void:
	var v := mine()
	if v == null:
		return
	cam.position = v.position
	if not hud.typing():
		var d := Vector2i(int(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
				- int(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
				int(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
				- int(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		var t := Time.get_ticks_msec() / 1000.0
		if d != Vector2i.ZERO and t >= _next_step:
			_next_step = t + STEP_SECONDS
			v.facing = d
			Net.request({"t": "step", "dx": d.x, "dy": d.y})
	_update_preview(v)


func _click(at: Vector2) -> void:
	var c := MapView.to_cell(at)
	# Beings are tall: a click on the cell above one also picks it.
	var hit: BeingView = null
	for v in views.values():
		if v.dead or v.id == my_id:
			continue
		if v.cell == c or v.cell == c + Vector2i(0, 1):
			if hit == null or v.cell == c:
				hit = v
	if hit:
		match hit.kind:
			Being.NPC:
				Net.request({"t": "talk", "id": hit.id})
				return
			Being.MOB:
				_select(hit.id)
				if hit.cls < Being.VEGETATION_FIRST:
					Net.request({"t": "attack", "id": hit.id})
					return
	if map and map.inside(c.x, c.y):
		Net.request({"t": "walk", "x": c.x, "y": c.y})


func _select(id: int) -> void:
	var old: BeingView = views.get(target)
	if old:
		old.selected = false
	target = id
	var v: BeingView = views.get(id)
	if v:
		v.selected = true


func _target_nearest() -> void:
	var me_v := mine()
	var best := 0
	var best_d := 1e9
	for v in views.values():
		if v.kind == Being.MOB and not v.dead and v.cls < Being.VEGETATION_FIRST and v.id != target:
			var d: float = (v.position - me_v.position).length()
			if d < best_d:
				best_d = d
				best = v.id
	_select(best)


func use_skill(slot: int, risk := false) -> void:
	var v := mine()
	if v == null:
		return
	var skill: int = Hud.HOTBAR[slot]
	var modifier := 0
	if primed and not db.combo(skill, primed).is_empty():
		modifier = primed
		primed = 0
		hud.set_me(me)
	var t := target if views.has(target) and not views[target].dead else 0
	if skill == HueDB.SPARK and t:
		v.facing = (views[t].cell - v.cell).sign()
	request += 1
	Net.request({"t": "hue", "skill": skill, "dx": v.facing.x, "dy": v.facing.y,
			"flags": HueRules.ACCEPT_RISK if (risk or Input.is_key_pressed(KEY_SHIFT)) else 0,
			"request": request, "target": t, "modifier": modifier})


# --------------------------------------------------------------------------
# Landing preview: where Featherfall / Upward Jump would take you from here.

func _update_preview(v: BeingView) -> void:
	var p := {}
	var ff := hud.learned(HueDB.FEATHERFALL)
	var jp := hud.learned(HueDB.JUMP)
	if map and (ff or jp) and v.lift == 0.0:
		var down := map.leap(v.cell, v.facing, -1, 99, 99)
		if down.result != GameMap.Leap.NOT_AT_EDGE:
			var going_up: bool = down.result == GameMap.Leap.WRONG_WAY and down.levels > 0
			var id := HueDB.JUMP if going_up else HueDB.FEATHERFALL
			var r := jp if going_up else ff
			var key := 5 if going_up else 4
			var name := Describe.skill_name(db, id)
			if r == 0:
				p = {"cell": down.at, "ok": false, "text": "%s: you have not learned it (Wren on the terrace teaches it)." % name}
			else:
				var def := db.rank(id, r)
				var l := map.leap(v.cell, v.facing, 1 if going_up else -1, def.p1, def.p2)
				if l.result == GameMap.Leap.OK:
					var busy := false
					for o in views.values():
						if o != v and o.cell == l.at and not o.dead and not (o.kind == Being.MOB and o.cls >= Being.VEGETATION_FIRST):
							busy = true
					p = {"cell": l.at, "ok": not busy, "text": ("%d: %s here" % [key, name]) if not busy
							else Describe.leap(name, HueRules.R.LANDING_OCCUPIED, 0)}
				else:
					var reason: int = {GameMap.Leap.TOO_FAR: HueRules.R.TOO_FAR, GameMap.Leap.NO_LANDING: HueRules.R.NO_LANDING,
							GameMap.Leap.OBSTRUCTED: HueRules.R.OBSTRUCTED, GameMap.Leap.WRONG_WAY: HueRules.R.WRONG_WAY,
							GameMap.Leap.TOO_HIGH: HueRules.R.TOO_HIGH}.get(l.result, HueRules.R.NOT_AT_EDGE)
					var detail: int = absi(l.levels) if l.result == GameMap.Leap.TOO_HIGH else l.span if l.result == GameMap.Leap.TOO_FAR else 0
					p = {"cell": l.at if l.at != v.cell else v.cell + v.facing, "ok": false, "text": Describe.leap(name, reason, detail)}
	if p.hash() != _preview.hash():
		_preview = p
		hud.show_preview(p.get("text", ""))
		preview.queue_redraw()


func _draw_preview() -> void:
	if _preview.is_empty():
		return
	var c := MapView.cell_center(_preview.cell)
	if _preview.ok:
		preview.draw_set_transform(c + Vector2(0, 8), 0.0, Vector2(1, 0.5))
		preview.draw_arc(Vector2.ZERO, 12, 0, TAU, 24, Color(0.6, 1, 0.6, 0.9), 2.5)
		preview.draw_circle(Vector2.ZERO, 4, Color(0.6, 1, 0.6, 0.6))
	else:
		preview.draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), Color(1, 0.4, 0.3, 0.9), 3)
		preview.draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), Color(1, 0.4, 0.3, 0.9), 3)
