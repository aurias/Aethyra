class_name MapView
extends Node2D
## Draws a GameMap with the Whispers of Avalon pieces (game/assets/avalon,
## cut by tools/art/cut_avalon.py). Ground, water and cliff faces are drawn
## here; trees, bushes and rocks become y-sorted sprites under `objects`
## so beings walk behind and in front of them.

const CELL := 32
const ART := "res://assets/avalon/"

## Cliff face kinds, worked out per cliff cell from the levels around it.
enum Face { NONE, SOUTH_TOP, SOUTH_LOW, WEST, EAST, CORNER_SW_TOP, CORNER_SW_LOW,
		CORNER_SE_TOP, CORNER_SE_LOW }

## Obstacle sprites: texture, and the pixel of the texture that stands on
## the bottom middle of its cell.
const OBJECTS := {
	"T": ["tree_round", Vector2(62, 162)],
	"t": ["tree_bright", Vector2(62, 162)],
	"O": ["tree_old", Vector2(76, 162)],
	"D": ["tree_dead", Vector2(54, 162)],
	"u": ["stump", Vector2(44, 158)],
	"B": ["bush", Vector2(48, 90)],
	"b": ["bush_small", Vector2(32, 62)],
	"r": ["rock_wide", Vector2(16, 30)],
}

var map: GameMap
var objects: Node2D        # y-sorted layer shared with beings
var tex := {}
var faces := PackedInt32Array()


func setup(m: GameMap, object_layer: Node2D) -> void:
	map = m
	objects = object_layer
	for n in ["grass", "sand", "sand_edges", "water", "water_edges", "plateau", "stairs",
			"flowers", "flower", "tree_round", "tree_bright", "tree_old", "tree_dead", "stump",
			"bush", "bush_small", "bush_big", "rock_wide", "rock", "rock_mossy"]:
		tex[n] = load(ART + n + ".png")
	_classify_faces()
	_place_objects()
	queue_redraw()


func _classify_faces() -> void:
	faces.resize(map.w * map.h)
	faces.fill(Face.NONE)
	for y in map.h:
		for x in map.w:
			if not map.cliff(x, y):
				continue
			var f := Face.NONE
			var above := faces[x + (y - 1) * map.w] if y > 0 else Face.NONE
			if y > 0 and not map.cliff(x, y - 1) and _higher_than_below(x, y):
				f = Face.SOUTH_TOP
			elif above == Face.SOUTH_TOP:
				f = Face.SOUTH_LOW
			elif above == Face.CORNER_SW_TOP:
				f = Face.CORNER_SW_LOW
			elif above == Face.CORNER_SE_TOP:
				f = Face.CORNER_SE_LOW
			elif above in [Face.WEST, Face.EAST] and x > 0 and faces[x - 1 + y * map.w] == Face.SOUTH_TOP:
				f = Face.SOUTH_TOP      # a south face running past a side face
			elif above == Face.WEST and map.cliff(x + 1, y):
				f = Face.CORNER_SW_TOP
			elif above == Face.EAST and map.cliff(x - 1, y):
				f = Face.CORNER_SE_TOP
			elif not map.cliff(x + 1, y) and map.level(x + 1, y) > map.level(x - 1, y):
				f = Face.WEST
			elif not map.cliff(x - 1, y) and map.level(x - 1, y) > map.level(x + 1, y):
				f = Face.EAST
			else:
				f = Face.SOUTH_LOW
			faces[x + y * map.w] = f


func _higher_than_below(x: int, y: int) -> bool:
	var top := map.level(x, y - 1)
	for k in range(1, 4):
		if not map.cliff(x, y + k) and map.inside(x, y + k):
			return top > map.level(x, y + k)
	return true


func _place_objects() -> void:
	for y in map.h:
		for x in map.w:
			var c := map.ground_at(x, y)
			if c == "=":
				_sprite(["bush_small", Vector2(32, 54)], x, y)
			elif c == "#":
				# The forest edge: alternate bushes and trees, sparsely.
				if (x * 7 + y * 13) % 5 == 0:
					_sprite(["tree_round", Vector2(62, 162)] if (x + y) % 3 else ["tree_old", Vector2(76, 162)], x, y)
				else:
					_sprite(["bush", Vector2(48, 90)], x, y)
			elif OBJECTS.has(c):
				_sprite(OBJECTS[c], x, y)


func _sprite(def: Array, x: int, y: int) -> void:
	var s := Sprite2D.new()
	s.texture = tex[def[0]]
	s.centered = false
	s.offset = -def[1]
	s.position = Vector2(x * CELL + CELL / 2, y * CELL + CELL)
	objects.add_child(s)


func _draw() -> void:
	if map == null:
		return
	for y in map.h:
		for x in map.w:
			_draw_ground(x, y)
	for y in map.h:
		for x in map.w:
			_draw_shade(x, y)
	for y in map.h:
		for x in map.w:
			if map.cliff(x, y):
				_draw_face(x, y)
			elif map.stair(x, y):
				_draw_stair(x, y)
			elif map.ground_at(x, y) == "f":
				draw_texture(tex.flowers if (x + y) % 2 else tex.flower, Vector2(x, y) * CELL)


## Ground at the foot of a cliff lies in its shadow.
func _draw_shade(x: int, y: int) -> void:
	if map.cliff(x, y) or map.stair(x, y):
		return
	var r := Rect2(x * CELL, y * CELL, CELL, CELL)
	var dark := Color(0.1, 0.12, 0.05, 0.28)
	var clear := Color(dark, 0.0)
	if map.cliff(x, y - 1):
		draw_polygon([r.position, r.position + Vector2(CELL, 0), r.end, r.position + Vector2(0, CELL)],
				[dark, dark, clear, clear])
	if map.cliff(x - 1, y) and faces[x - 1 + y * map.w] == Face.WEST:
		draw_polygon([r.position, r.position + Vector2(CELL * 0.6, 0), r.position + Vector2(CELL * 0.6, CELL), r.position + Vector2(0, CELL)],
				[dark, clear, clear, dark])
	if map.cliff(x + 1, y) and faces[x + 1 + y * map.w] == Face.EAST:
		draw_polygon([r.position + Vector2(CELL * 0.4, 0), r.position + Vector2(CELL, 0), r.end, r.position + Vector2(CELL * 0.4, CELL)],
				[clear, dark, dark, clear])


func _region(t: Texture2D, col: int, row: int, x: int, y: int) -> void:
	draw_texture_rect_region(t, Rect2(x * CELL, y * CELL, CELL, CELL), Rect2(col * CELL, row * CELL, CELL, CELL))


func _is(x: int, y: int, c: String) -> bool:
	return map.ground_at(x, y) == c or (not map.inside(x, y))


func _draw_ground(x: int, y: int) -> void:
	var c := map.ground_at(x, y)
	var lvl := map.level(x, y) if not map.cliff(x, y) else map.level(x, y + 2)
	if map.cliff(x, y) or c == "#" or c == "=":
		_region(tex.grass, posmod(x, 2), posmod(y, 2), x, y)
	elif lvl >= 1 and not map.stair(x, y):
		# Raised ground: the brighter plateau-top grass.
		var pick: Array = [[2, 1], [3, 1], [1, 2], [4, 2]][posmod(x * 3 + y * 5, 4)]
		_region(tex.plateau, pick[0], pick[1], x, y)
		if lvl >= 2:
			draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), Color(1.0, 0.95, 0.6, 0.12))
	else:
		_region(tex.grass, posmod(x, 2), posmod(y, 2), x, y)
	if c == ":":
		_draw_border(x, y, ":", tex.sand_edges, tex.sand, 3)
	elif c == "~":
		_draw_border(x, y, "~", tex.water_edges, tex.water, 1)


## A 3x3 border template (centre empty) around a patch of c.
func _draw_border(x: int, y: int, c: String, edges: Texture2D, fill: Texture2D, fill_cells: int) -> void:
	var col := 0 if not _is(x - 1, y, c) else 2 if not _is(x + 1, y, c) else 1
	var row := 0 if not _is(x, y - 1, c) else 2 if not _is(x, y + 1, c) else 1
	if col == 1 and row == 1:
		# Inner corners: the border template has none, so fill.
		_region(fill, posmod(x, fill_cells), posmod(y, fill_cells), x, y)
	else:
		_region(edges, col, row, x, y)


func _draw_face(x: int, y: int) -> void:
	var f := faces[x + y * map.w]
	var left_end := not map.cliff(x - 1, y) and not map.stair(x - 1, y)
	var right_end := not map.cliff(x + 1, y) and not map.stair(x + 1, y)
	var mid := 1 + posmod(x, 4)
	match f:
		Face.SOUTH_TOP, Face.SOUTH_LOW:
			var row := 5 if f == Face.SOUTH_TOP else 6
			_region(tex.plateau, 0 if left_end else 5 if right_end else mid, row, x, y)
		Face.CORNER_SW_TOP: _region(tex.plateau, 0, 5, x, y)
		Face.CORNER_SW_LOW: _region(tex.plateau, 0, 6, x, y)
		Face.CORNER_SE_TOP: _region(tex.plateau, 5, 5, x, y)
		Face.CORNER_SE_LOW: _region(tex.plateau, 5, 6, x, y)
		# The art's side rims are thin; stretch their rocks across the cell.
		Face.WEST:
			draw_texture_rect_region(tex.plateau, Rect2(x * CELL, y * CELL, CELL, CELL),
					Rect2(8, (2 + posmod(y, 2)) * CELL, 18, CELL))
		Face.EAST:
			draw_texture_rect_region(tex.plateau, Rect2(x * CELL, y * CELL, CELL, CELL),
					Rect2(5 * CELL + 6, (2 + posmod(y, 2)) * CELL, 18, CELL))


func _draw_stair(x: int, y: int) -> void:
	var left := x
	while map.stair(left - 1, y):
		left -= 1
	var top := y
	while map.stair(x, top - 1):
		top -= 1
	_region(tex.stairs, clampi(x - left, 0, 2), clampi(1 + y - top, 1, 2), x, y)


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2, c.y * CELL + CELL / 2)


static func cell_feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2, c.y * CELL + CELL - 4)


static func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))
