class_name Describe
extends RefCounted
## Player-facing explanations of hue results, ported from the old client
## (src/eathena/huestate.cpp). The host decides; this only explains.

const R := HueRules.R
const O := HueRules.Outcome
const F := HueRules.Fate


static func skill_name(db: HueDB, id: int) -> String:
	var r := db.rank(id, 1)
	return r.name if not r.is_empty() else "Skill %d" % id


static func item_label(items: Dictionary, item: int, amount: int) -> String:
	var label: String = items[item].name if items.has(item) else "item %d" % item
	return label if amount == 1 else "%s stack (x%d)" % [label, amount]


static func result(db: HueDB, items: Dictionary, r: Dictionary) -> String:
	var skill := skill_name(db, r.skill)
	var def := db.rank(r.skill, 1)
	var hue := HueDB.hue_title(def.hue if not def.is_empty() else 0)
	match r.outcome:
		O.LEARNED:
			return "You learned %s rank %d." % [skill, r.detail]
		O.SUPPLY:
			return "Vessel stack selected as supply #%d." % r.detail if r.detail \
					else "Vessel stack removed from your supply."
		O.SUCCEEDED, O.FAILED:
			var text := ""
			if r.modifier:
				var mod := db.rank(r.modifier, 1)
				text = "%s + %s %s: %d %s and %d %s energy." % [skill, skill_name(db, r.modifier),
						"fizzled" if r.outcome == O.FAILED else "together", r.personal + r.vessel, hue,
						r.mod_personal + r.mod_vessel, HueDB.hue_title(mod.hue if not mod.is_empty() else 0)]
				if r.outcome == O.SUCCEEDED and r.mod_detail:
					text += " %d set alight." % r.mod_detail
			elif r.outcome == O.FAILED:
				text = "%s fizzled under the overload; %d %s energy was spent." % [skill, r.personal + r.vessel, hue]
			elif r.vessel:
				text = "%s drew %d %s energy: %d your own, %d from vessels." % [skill, r.personal + r.vessel,
						hue, r.personal, r.vessel]
			for v in r.vessels:
				var what := item_label(items, v.item, v.amount)
				if v.fate == F.DESTROYED:
					text += " Your %s disintegrated at %d%% load." % [what, v.load]
				elif v.fate == F.STRAINED:
					text += " Your %s strained at %d%% load and wore down." % [what, v.load]
			return text.strip_edges()

	match r.reason:
		R.UNKNOWN_SKILL: return "That skill does not exist."
		R.NOT_LEARNED: return "You have not learned %s." % skill
		R.NO_ACCESS: return "You cannot manipulate %s yet." % hue
		R.DEAD: return "You cannot do that now."
		R.COOLDOWN: return "%s is still recovering (%.1f s)." % [skill, r.detail / 1000.0]
		R.ALLOWANCE: return "%s cannot start: your %s allowance is held by %s." % [skill, hue, skill_name(db, r.detail)]
		R.CEILING: return "%s cannot start: you are already sustaining all you can." % skill
		R.BLOCKED: return "%s: there is no room to move that way." % skill
		R.NO_ENERGY: return "%s needs %d %s energy; you can draw on %d." % [skill, r.energy, hue, r.detail]
		R.CURRENT_LIMITED:
			return "%s needs %d current; you can deliver %d safely. Mark a vessel stack as supply in your pack (I) or train your mastery." % [skill, r.current, r.detail]
		R.OVERLOAD_RISK:
			return "%s would push your vessels to %d%% load and they may disintegrate. Hold Shift and use it again to risk it." % [skill, r.detail]
		R.OVERLOAD_LIMIT: return "%s would need %d%% load from your vessels: far beyond what they can take." % [skill, r.detail]
		R.PERMANENT: return "%s is permanent; it is always in effect." % skill
		R.NO_POINTS: return "%s needs %d %s skill points. Mastery milestones in %s give them." % [skill, r.detail, hue, hue]
		R.NEEDS_LEVEL: return "That needs character level %d." % r.detail
		R.NEEDS_MASTERY: return "That needs %s mastery %d." % [hue, r.detail]
		R.NEEDS_PROFICIENCY: return "That needs %d proficiency with %s: use it to good effect." % [r.detail, skill]
		R.MAX_RANK: return "%s is already at its highest rank." % skill
		R.NOT_A_VESSEL: return "That item cannot supply hue energy."
		R.SUPPLY_FULL: return "You can draw on at most %d vessel stacks." % r.detail
		R.INCOMPATIBLE: return "%s cannot be combined with %s." % [skill_name(db, r.detail), skill]
	return leap(skill, r.reason, r.detail)


## Also used by the landing preview.
static func leap(skill: String, reason: int, detail: int) -> String:
	match reason:
		R.NOT_AT_EDGE: return "%s: face a cliff edge first." % skill
		R.TOO_FAR: return "%s: that cliff is %d cells across, too wide for you yet." % [skill, detail]
		R.NO_LANDING: return "%s: there is nowhere to land beyond that cliff." % skill
		R.OBSTRUCTED: return "%s: something is in the way at the corner." % skill
		R.WRONG_WAY:
			return "%s: that ledge is above you - jump instead." % skill if detail == 1 \
					else "%s: that ledge is below you - featherfall instead." % skill
		R.TOO_HIGH: return "%s: that is %d levels, more than you can manage yet." % [skill, detail]
		R.LANDING_OCCUPIED: return "%s: someone is standing where you would land." % skill
		R.NO_TARGET: return "%s: no enemy in reach (%d tiles, on your level)." % [skill, detail]
	return "The host refused that (reason %d)." % reason
