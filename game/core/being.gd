class_name Being
extends RefCounted
## Anything that stands on the map: a player, a monster (or plant) or an NPC.
## Only the host's World changes these; clients mirror what they are told.

enum { PLAYER, MOB, NPC, CACHE }

const VEGETATION_FIRST := 1100
const VEGETATION_LAST := 1199

var id := 0
var kind := MOB
var cls := 0                    # monster id; 0 for players and NPCs
var key := ""                   # NPC dialogue key
var name := ""
var pos := Vector2i.ZERO
var facing := Vector2i(0, 1)
var hp := 1
var max_hp := 1
var dead := false

# Movement and combat.
var path: Array[Vector2i] = []
var next_step := 0              # world ms when the next path step may happen
var step_ms := 150
var target := 0                 # being id being attacked/chased
var next_attack := 0
var can_move_at := 0
var attackable_at := 0
var burn := {}

# Players.
var peer := 0
var ch := {}                    # the saved character
var session := {}               # hue session state, never saved
var respawn_at := 0
var safe_until := 0             # monsters ignore a newly woken player
var dialog := {}                # open NPC conversation

# Monsters.
var mob := {}                   # its mobs.txt row
var group := -1                 # spawn group index
var next_wander := 0


func is_vegetation() -> bool:
	return kind == MOB and cls >= VEGETATION_FIRST and cls <= VEGETATION_LAST


func new_session() -> void:
	session = {"ready": {}, "active": [], "awards": {}, "last_request": 0,
			"rng": randi() | 1, "forced": -1, "debug": false}


## What every client may know about this being.
func public() -> Dictionary:
	return {"id": id, "kind": kind, "cls": cls, "key": key, "name": name,
			"x": pos.x, "y": pos.y, "fx": facing.x, "fy": facing.y,
			"hp": hp, "max_hp": max_hp, "dead": dead,
			"level": mob.get("level", 0)}
