class_name Effect
extends Node2D
## A short-lived visual: skill effects, damage numbers, loot text.

var kind := ""
var dir := Vector2.DOWN
var text := ""
var colour := Color.WHITE
var life := 0.5
var age := 0.0
var seed_ := 0.0


static func make(kind_: String, at: Vector2, dir_ := Vector2.DOWN, text_ := "", colour_ := Color.WHITE) -> Effect:
	var e := Effect.new()
	e.kind = kind_
	e.position = at
	e.dir = dir_.normalized() if dir_ != Vector2.ZERO else Vector2.DOWN
	e.text = text_
	e.colour = colour_
	e.seed_ = randf() * 100.0
	e.life = {"text": 1.1, "gust": 0.45, "scythe": 0.3, "dash": 0.35, "spark": 0.35, "fire": 0.4,
			"burn": 0.5, "featherfall": 0.9, "jump": 0.5, "level": 1.4}.get(kind_, 0.5)
	e.z_index = 5
	return e


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := age / life
	var fade := 1.0 - k
	match kind:
		"text":
			var font := ThemeDB.fallback_font
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var p := Vector2(-w / 2, -40 - k * 26)
			draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, fade * 0.8))
			draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(colour, fade))
		"gust":
			# A widening fan of wind in front.
			var base := dir.angle()
			for i in 5:
				var a := base + (i - 2) * 0.32
				var r := 14.0 + k * 70.0 + i % 2 * 8
				draw_arc(Vector2(0, -12), r, a - 0.35, a + 0.35, 10, Color(0.9, 1, 0.95, fade * 0.8), 2.0)
		"scythe":
			var base := dir.angle()
			draw_arc(Vector2(0, -12), 28.0, base - 1.4 + k * 1.2, base + 0.2 + k * 1.2, 16, Color(0.85, 1, 0.8, fade), 4.0)
			draw_arc(Vector2(0, -12), 22.0, base - 1.2 + k * 1.2, base + 0.1 + k * 1.2, 16, Color(1, 1, 1, fade * 0.6), 2.0)
		"dash":
			for i in 4:
				var off := Vector2(-dir.y, dir.x) * (i - 1.5) * 5.0
				draw_line(off + Vector2(0, -12), off + Vector2(0, -12) - dir * (20 + 30 * fade), Color(0.85, 1, 0.9, fade * 0.7), 2.0)
		"spark", "fire":
			for i in 10:
				var a := i * TAU / 10 + seed_
				var r := 4.0 + k * 22.0
				draw_line(Vector2(0, -12) + Vector2(cos(a), sin(a)) * r * 0.4, Vector2(0, -12) + Vector2(cos(a), sin(a)) * r,
						Color(1, 0.6 + 0.3 * sin(i), 0.15, fade), 2.0)
			draw_circle(Vector2(0, -12), 6.0 * fade, Color(1, 0.9, 0.5, fade))
		"burn":
			draw_circle(Vector2(0, -14 - k * 10), 3.0 * fade, Color(1, 0.5, 0.1, fade))
		"featherfall":
			for i in 6:
				var a := seed_ + i
				var p := Vector2(sin(a * 3.1 + k * 4) * 16, -30 + k * 30 + (i * 7) % 20)
				draw_line(p, p + Vector2(4, 2), Color(0.8, 1, 0.7, fade), 2.0)
		"jump":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.4))
			draw_arc(Vector2.ZERO, 6 + k * 22, 0, TAU, 20, Color(0.95, 0.9, 0.75, fade), 2.0)
		"level":
			for i in 12:
				var a := i * TAU / 12 + k * 2.0
				draw_circle(Vector2(cos(a), sin(a) * 0.5) * (10 + k * 20) + Vector2(0, -20 - k * 20), 2.0, Color(1, 0.95, 0.5, fade))
