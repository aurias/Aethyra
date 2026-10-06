class_name BeingView
extends Node2D
## One being as the client sees it: drawn procedurally (the Avalon set has
## no characters), moved and animated from the host's events.

const CELL := MapView.CELL
const SKIN := Color("f2c9a0")
const OUTLINE := Color(0.12, 0.1, 0.08, 0.85)

var id := 0
var kind := Being.MOB
var cls := 0
var key := ""
var display_name := ""
var level := 0
var hp := 1
var max_hp := 1
var dead := false
var cell := Vector2i.ZERO
var facing := Vector2i(0, 1)
var is_me := false
var selected := false
var lift := 0.0                 # height above the ground, for jumps
var spin := 0.0
var walk_phase := 0.0
var moving_until := 0.0
var flash := 0.0
var burning_until := 0.0
var show_hp_until := 0.0
var colour := Color.WHITE
var _tween: Tween


func setup(d: Dictionary) -> void:
	id = d.id
	kind = d.kind
	cls = d.cls
	key = d.key
	display_name = d.name
	level = d.get("level", 0)
	hp = d.hp
	max_hp = maxi(d.max_hp, 1)
	dead = d.dead
	facing = Vector2i(d.fx, d.fy)
	cell = Vector2i(d.x, d.y)
	position = MapView.cell_feet(cell)
	modulate.a = 0.35 if dead else 1.0
	# A stable colour per player name.
	var h := float(hash(display_name) % 1000) / 1000.0
	colour = Color.from_hsv(h, 0.45, 0.75)
	queue_redraw()


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func move_to(c: Vector2i, ms: int) -> void:
	_face_towards(c)
	cell = c
	moving_until = now() + ms / 1000.0
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "position", MapView.cell_feet(c), ms / 1000.0)


## Skill movement: 0 dash, 1 knockback, 2 featherfall, 3 jump, 4 fall.
func slide(c: Vector2i, kind_: int) -> void:
	var to := MapView.cell_feet(c)
	if kind_ in [0, 2, 3]:
		_face_towards(c)
	cell = c
	_kill_tween()
	_tween = create_tween()
	match kind_:
		0:  # dash: a quick rush
			_tween.tween_property(self, "position", to, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		1:  # knockback: shoved, skidding to a stop
			_tween.tween_property(self, "position", to, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		2:  # featherfall: rise a little, then drift down
			_tween.set_parallel(true)
			_tween.tween_property(self, "position", to, 0.75).set_trans(Tween.TRANS_SINE)
			_tween.tween_method(func(t): lift = sin(t * PI) * 18.0 + (1.0 - t) * 6.0, 0.0, 1.0, 0.75)
		3:  # jump: a high arc
			_tween.set_parallel(true)
			_tween.tween_property(self, "position", to, 0.45)
			_tween.tween_method(func(t): lift = sin(t * PI) * 44.0, 0.0, 1.0, 0.45)
		4:  # fall: tumble over the edge
			_tween.set_parallel(true)
			_tween.tween_property(self, "position", to, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_tween.tween_method(func(t): lift = sin(t * PI) * 10.0; spin = t * TAU, 0.0, 1.0, 0.5)
		_:
			position = to
	_tween.chain().tween_callback(func(): lift = 0.0; spin = 0.0; queue_redraw())


## Teleport (respawns, warps).
func place(c: Vector2i) -> void:
	_kill_tween()
	cell = c
	position = MapView.cell_feet(c)
	lift = 0.0
	spin = 0.0


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	lift = 0.0
	spin = 0.0


func _face_towards(c: Vector2i) -> void:
	var d := (c - cell).sign()
	if d != Vector2i.ZERO:
		facing = d


func hurt(new_hp: int, kind_: String) -> void:
	hp = new_hp
	flash = 0.25
	show_hp_until = now() + 4.0
	if kind_ == "burn" or kind_ == "fire":
		burning_until = now() + 1.2


func die() -> void:
	dead = true
	hp = 0
	create_tween().tween_property(self, "modulate:a", 0.0 if kind == Being.MOB else 0.35, 0.8)


func revive(d: Dictionary) -> void:
	setup(d)
	modulate.a = 1.0
	place(cell)


func _process(delta: float) -> void:
	var moving := now() < moving_until
	if moving:
		walk_phase += delta * 14.0
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
	z_index = 2 if lift > 1.0 else 0
	queue_redraw()


# --------------------------------------------------------------------------
# Drawing

func _draw() -> void:
	var t := now()
	# Shadow stays on the ground.
	var sw := 10.0 if kind != Being.MOB or cls >= 1100 else 9.0
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, sw * (1.0 - clampf(lift / 80.0, 0.0, 0.5)), Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2(0, -lift), spin, Vector2.ONE)
	if selected:
		draw_set_transform(Vector2(0, 0), 0.0, Vector2(1, 0.45))
		draw_arc(Vector2.ZERO, 15.0, 0, TAU, 32, Color(1, 0.85, 0.3, 0.9), 2.0)
		draw_set_transform(Vector2(0, -lift), spin, Vector2.ONE)
	var bob := sin(walk_phase) * 1.5 if now() < moving_until else 0.0
	match kind:
		Being.PLAYER:
			_draw_person(bob, colour, Color("3f7d4a"), Color("5a3b22"))
		Being.NPC:
			if key == "ama":
				_draw_person(bob, Color("2f7f86"), Color("e8e3d0"), Color("dfe3e8"), true)
			else:
				_draw_person(bob, Color("b06a2c"), Color("6b4a2a"), Color("3b2a1a"), false, true)
		_:
			match cls:
				1010: _draw_hopper(t, bob)
				1101: _draw_grass(t)
				1102: _draw_herb(t)
				1103: _draw_windflower(t)
				1104: _draw_skyreed(t)
				_: draw_circle(Vector2(0, -8), 7, Color.MAGENTA)
	if flash > 0.0:
		draw_circle(Vector2(0, -12), 12, Color(1, 0.2, 0.1, flash * 1.6))
	if t < burning_until:
		_draw_flames(t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_overhead(t)


func _draw_person(bob: float, cloak: Color, scarf: Color, hair: Color, robe := false, hat := false) -> void:
	var y := -bob
	var side := facing.x
	# Legs
	var step := sin(walk_phase) * 2.5 if now() < moving_until else 0.0
	if not robe:
		draw_rect(Rect2(-5, -9 + y, 4, 9 + step * 0.4), Color("3b3328"))
		draw_rect(Rect2(1, -9 + y, 4, 9 - step * 0.4), Color("3b3328"))
	# Body
	var top := -26.0 + y
	var bottom := -6.0 + y if not robe else 0.0
	var body := PackedVector2Array([Vector2(-6, top), Vector2(6, top), Vector2(9, bottom), Vector2(-9, bottom)])
	draw_colored_polygon(body, cloak)
	draw_polyline(body + PackedVector2Array([body[0]]), OUTLINE, 1.0)
	# Arms
	draw_line(Vector2(-7, top + 3), Vector2(-9, top + 13 + step), cloak.darkened(0.25), 3.0)
	draw_line(Vector2(7, top + 3), Vector2(9, top + 13 - step), cloak.darkened(0.25), 3.0)
	# Scarf / collar in the hue colour
	draw_rect(Rect2(-6, top, 12, 3), scarf)
	# Head
	var head := Vector2(side * 1.0, top - 6)
	draw_circle(head, 6.5, SKIN)
	draw_arc(head, 6.5, 0, TAU, 20, OUTLINE, 1.0)
	# Hair, and a face unless facing away
	if facing.y < 0:
		draw_circle(head, 6.6, hair)
	else:
		draw_arc(head + Vector2(0, -1), 6.2, PI, TAU, 12, hair, 4.0)
		var e := Vector2(side * 2.0, 0)
		if side == 0:
			draw_circle(head + Vector2(-2.3, 0.5), 0.9, OUTLINE)
			draw_circle(head + Vector2(2.3, 0.5), 0.9, OUTLINE)
		else:
			draw_circle(head + e + Vector2(side * 0.8, 0.5), 0.9, OUTLINE)
	if hat:
		draw_colored_polygon(PackedVector2Array([head + Vector2(-9, -3), head + Vector2(9, -3),
				head + Vector2(3, -12), head + Vector2(-3, -12)]), Color("5b3d22"))


func _draw_hopper(t: float, bob: float) -> void:
	var hop := absf(sin(t * 5.0 + id)) * 3.0 if now() < moving_until else absf(sin(t * 2.0 + id)) * 1.0
	var c := Color("a9c79a")
	var body := Vector2(0, -8 - hop)
	draw_set_transform(Vector2(0, -lift) + body, spin, Vector2(1.25, 1.0))
	draw_circle(Vector2.ZERO, 8, c)
	draw_arc(Vector2.ZERO, 8, 0, TAU, 20, OUTLINE, 1.0)
	draw_set_transform(Vector2(0, -lift), spin, Vector2.ONE)
	# Ears
	var ex := facing.x * 2.0
	for s in [-1, 1]:
		var base := body + Vector2(s * 4 + ex, -6)
		draw_line(base, base + Vector2(s * 3, -9), c.darkened(0.15), 4.0)
		draw_line(base, base + Vector2(s * 3, -9), Color("f0d0c8"), 1.5)
	# Face
	if facing.y >= 0 or facing.x != 0:
		draw_circle(body + Vector2(facing.x * 4 - 2.5 * absf(facing.y), -1), 1.3, OUTLINE)
		draw_circle(body + Vector2(facing.x * 4 + 2.5 * absf(facing.y), -1), 1.3, OUTLINE)
	# Feet
	draw_circle(Vector2(-5, -1), 2.5, c.darkened(0.2))
	draw_circle(Vector2(5, -1), 2.5, c.darkened(0.2))
	# Wind tuft
	draw_arc(body + Vector2(-9 * (1 if facing.x <= 0 else -1), 0), 4, -PI / 2, PI / 2, 6, Color(1, 1, 1, 0.6), 1.5)


func _sway(t: float, k: float) -> float:
	return sin(t * 1.7 + id * 0.7 + k) * 2.0


func _draw_grass(t: float) -> void:
	for k in 7:
		var x := -8.0 + k * 2.6
		var h := 10.0 + (k * 37 + id) % 7
		draw_line(Vector2(x, 0), Vector2(x + _sway(t, k) + (k - 3) * 0.8, -h), Color("5d8f3a").lerp(Color("9cc65a"), k / 7.0), 2.0)


func _draw_herb(t: float) -> void:
	for k in 5:
		var a := -PI / 2 + (k - 2) * 0.55 + _sway(t, k) * 0.04
		var tip := Vector2(cos(a), sin(a)) * 11.0 + Vector2(0, -3)
		draw_line(Vector2(0, -2), tip, Color("4e7d34"), 3.0)
		draw_circle(tip, 2.2, Color("6ea548"))
	for k in 3:
		draw_circle(Vector2(-4 + k * 4, -12 - (k % 2) * 3), 1.6, Color("f4f4ea"))


func _draw_windflower(t: float) -> void:
	var top := Vector2(_sway(t, 0), -15)
	draw_line(Vector2(0, 0), top, Color("4e8a3a"), 2.0)
	draw_line(Vector2(0, -5), Vector2(-5, -9), Color("5f9a44"), 2.0)
	for k in 5:
		var a := k * TAU / 5 + t * 0.5
		draw_circle(top + Vector2(cos(a), sin(a)) * 3.5, 2.6, Color("e58fb4"))
	draw_circle(top, 2.0, Color("f7e27a"))


func _draw_skyreed(t: float) -> void:
	for k in 4:
		var x := -5.0 + k * 3.3
		var tip := Vector2(x + _sway(t, k) * 1.5, -24 - (k % 2) * 4)
		draw_line(Vector2(x, 0), tip, Color("9fb7c4"), 2.0)
		draw_line(tip, tip + Vector2(2, -5), Color("e6eef2"), 3.0)


func _draw_flames(t: float) -> void:
	for k in 3:
		var x := -6.0 + k * 6.0
		var h := 8.0 + sin(t * 18.0 + k * 2.0) * 3.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 3, -10), Vector2(x + 3, -10), Vector2(x, -10 - h)]),
				Color(1.0, 0.55 + 0.2 * sin(t * 9 + k), 0.1, 0.85))


func _draw_overhead(t: float) -> void:
	var top := -46.0 - lift
	if kind == Being.MOB and cls >= Being.VEGETATION_FIRST:
		top = -30.0
	elif kind == Being.MOB:
		top = -32.0 - lift
	var font := ThemeDB.fallback_font
	if kind != Being.MOB or selected:
		var label := display_name
		var size := 11
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
		var col := Color("fff3c4") if kind == Being.NPC else Color.WHITE if not is_me else Color("c8f7c5")
		draw_string_outline(font, Vector2(-w / 2, top), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(-w / 2, top), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		top -= 12
	if kind != Being.NPC and not dead and (t < show_hp_until or selected or (is_me and hp < max_hp)):
		var r := Rect2(-12, top + 4, 24, 3)
		draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.position, Vector2(r.size.x * hp / max_hp, r.size.y)),
				Color("e04a3a") if kind == Being.MOB else Color("58c858"))
