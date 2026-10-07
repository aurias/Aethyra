class_name Hud
extends CanvasLayer
## Everything drawn over the world: status, hue bars, hotbar, chat, toasts,
## dialogue and the Hues / Skills / Inventory windows. It shows the private
## state the host sends ("me"); every button sends a request.

signal skill_pressed(slot: int)

const HOTBAR := [HueDB.DASH, HueDB.GUST, HueDB.SCYTHE, HueDB.FEATHERFALL, HueDB.JUMP, HueDB.SPARK]
const HUE_COLOURS := [Color("7fd37a"), Color("5aa9e6"), Color("f08a3c"), Color("b58b52"),
		Color("4fb35d"), Color("f2e27a"), Color("8c6b9e"), Color("5b4b7a")]
const PANEL_BG := Color(0.13, 0.11, 0.08, 0.86)
const BORDER := Color(0.78, 0.66, 0.38, 0.9)

var game        # Game
var db: HueDB
var prog: Progression
var items := {}
var me := {}
var me_at := 0.0

var status: VBoxContainer
var name_label: Label
var hp_bar: ProgressBar
var exp_bar: ProgressBar
var hue_box: VBoxContainer
var hotbar: HBoxContainer
var slots := []
var chat_log: RichTextLabel
var chat_input: LineEdit
var toasts: VBoxContainer
var dialog: PanelContainer
var dialog_name: Label
var dialog_text: RichTextLabel
var dialog_buttons: VBoxContainer
var windows := {}
var help: PanelContainer
var prime_label: Label
var preview_label: Label
var _layout := []          # [control, anchor (0..1), offset, pivot (0..1)]


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)
	_build_status(root)
	_build_hotbar(root)
	_build_chat(root)
	_build_toasts(root)
	_build_dialog(root)
	windows.hues = _window(root, "Hues (H)", Vector2(360, 330), Vector2(20, 150))
	windows.skills = _window(root, "Skills (K)", Vector2(470, 470), Vector2(400, 90))
	windows.inventory = _window(root, "Pack (I)", Vector2(430, 470), Vector2(830, 90))
	windows.character = _window(root, "Character (C)", Vector2(400, 500), Vector2(400, 110))
	_build_help(root)


static func make_theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.border_color = BORDER
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = Color(0.32, 0.26, 0.16)
	button.border_color = BORDER
	button.set_border_width_all(1)
	button.set_corner_radius_all(4)
	button.set_content_margin_all(5)
	var hover := button.duplicate()
	hover.bg_color = Color(0.45, 0.36, 0.2)
	var pressed := button.duplicate()
	pressed.bg_color = Color(0.25, 0.4, 0.22)
	var disabled := button.duplicate()
	disabled.bg_color = Color(0.2, 0.18, 0.15)
	disabled.border_color = Color(0.4, 0.35, 0.25)
	t.set_stylebox("normal", "Button", button)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", Color("f3ead2"))
	t.set_color("font_color", "Button", Color("f3ead2"))
	t.set_color("font_disabled_color", "Button", Color("8f8673"))
	t.set_color("default_color", "RichTextLabel", Color("f3ead2"))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.55)
	bar_bg.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.05, 0.04, 0.03, 0.8)
	edit.border_color = BORDER
	edit.set_border_width_all(1)
	edit.set_content_margin_all(4)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit)
	t.set_default_font_size(14)
	return t


static func bar(colour: Color, height := 12) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	return p


func _build_status(root: Control) -> void:
	var p := _panel(root)
	p.position = Vector2(12, 12)
	p.custom_minimum_size = Vector2(280, 0)
	status = VBoxContainer.new()
	p.add_child(status)
	name_label = Label.new()
	status.add_child(name_label)
	hp_bar = bar(Color("d24b3c"), 14)
	status.add_child(hp_bar)
	var hp_text := Label.new()
	hp_text.name = "HpText"
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_bar.add_child(hp_text)
	hp_text.set_anchors_preset(Control.PRESET_CENTER)
	exp_bar = bar(Color("c9b458"), 5)
	status.add_child(exp_bar)
	hue_box = VBoxContainer.new()
	status.add_child(hue_box)


func _build_hotbar(root: Control) -> void:
	var p := _panel(root)
	_layout.append([p, Vector2(0.5, 1), Vector2(0, -10), Vector2(0.5, 1)])
	var v := VBoxContainer.new()
	p.add_child(v)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 6)
	v.add_child(hotbar)
	for i in HOTBAR.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(84, 50)
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): skill_pressed.emit(i))
		var cd := ColorRect.new()
		cd.color = Color(0, 0, 0, 0.55)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.name = "Cooldown"
		b.add_child(cd)
		hotbar.add_child(b)
		slots.append(b)
	var hints := HBoxContainer.new()
	v.add_child(hints)
	prime_label = Label.new()
	prime_label.add_theme_font_size_override("font_size", 12)
	hints.add_child(prime_label)
	preview_label = Label.new()
	preview_label.add_theme_font_size_override("font_size", 12)
	preview_label.add_theme_color_override("font_color", Color("cfe8c9"))
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hints.add_child(preview_label)


func _build_chat(root: Control) -> void:
	var p := _panel(root)
	_layout.append([p, Vector2(0, 1), Vector2(12, -12), Vector2(0, 1)])
	p.custom_minimum_size = Vector2(330, 170)
	p.self_modulate = Color(1, 1, 1, 0.8)
	var v := VBoxContainer.new()
	p.add_child(v)
	chat_log = RichTextLabel.new()
	chat_log.scroll_following = true
	chat_log.bbcode_enabled = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Enter to chat"
	chat_input.text_submitted.connect(_on_chat)
	v.add_child(chat_input)


func _build_toasts(root: Control) -> void:
	toasts = VBoxContainer.new()
	_layout.append([toasts, Vector2(0.5, 0), Vector2(0, 14), Vector2(0.5, 0)])
	toasts.custom_minimum_size = Vector2(600, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)


func _build_dialog(root: Control) -> void:
	dialog = _panel(root)
	_layout.append([dialog, Vector2(0.5, 1), Vector2(0, -110), Vector2(0.5, 1)])
	dialog.custom_minimum_size = Vector2(660, 0)
	dialog.visible = false
	var v := VBoxContainer.new()
	dialog.add_child(v)
	dialog_name = Label.new()
	dialog_name.add_theme_color_override("font_color", Color("ffd98a"))
	v.add_child(dialog_name)
	dialog_text = RichTextLabel.new()
	dialog_text.fit_content = true
	dialog_text.custom_minimum_size = Vector2(640, 60)
	v.add_child(dialog_text)
	dialog_buttons = VBoxContainer.new()
	v.add_child(dialog_buttons)


func _window(root: Control, title: String, size: Vector2, at: Vector2) -> Dictionary:
	var p := _panel(root)
	p.position = at
	p.custom_minimum_size = size
	p.visible = false
	var v := VBoxContainer.new()
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var l := Label.new()
	l.text = title
	l.add_theme_color_override("font_color", Color("ffd98a"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var x := Button.new()
	x.text = "x"
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): p.visible = false)
	head.add_child(x)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = size - Vector2(16, 50)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(size.x - 44, 0)
	scroll.add_child(body)
	return {"panel": p, "body": body}


func _build_help(root: Control) -> void:
	help = _panel(root)
	_layout.append([help, Vector2(1, 0), Vector2(-12, 12), Vector2(1, 0)])
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 12)
	l.text = """WASD / arrows: walk (and face)    Click: walk, attack, talk
1 Dash  2 Gust  3 Wind Scythe  4 Featherfall  5 Jump  6 Spark
Q: prime Spark to ride your next Gust    Shift + skill: accept overload risk
Tab: target nearest enemy    H Hues   K Skills   I Pack   C Character
Enter: chat (host: @ commands)    F1: this help    Esc: close / leave"""
	help.add_child(l)


func toggle(name: String) -> void:
	var p: PanelContainer = windows[name].panel
	p.visible = not p.visible
	if p.visible:
		help.visible = false
		refresh_windows()


func close_windows() -> bool:
	var any := false
	for w in windows.values():
		any = any or w.panel.visible
		w.panel.visible = false
	if dialog.visible:
		any = true
		_dialog_close()
	return any


# --------------------------------------------------------------------------
# State

func set_me(snapshot: Dictionary) -> void:
	me = snapshot
	me_at = Time.get_ticks_msec() / 1000.0
	name_label.text = "%s   %s (%s)" % [me.name, me.zone.name, me.zone.band]
	hp_bar.max_value = me.max_hp
	hp_bar.value = me.hp
	hp_bar.get_node("HpText").text = "%d / %d" % [me.hp, me.max_hp]
	exp_bar.visible = false
	_refresh_hues()
	_refresh_hotbar()
	refresh_windows()


func learned(id: int) -> int:
	var sk = me.get("hue", {}).get("skills", {}).get(str(id))
	return sk.rank if sk else 0


func capacity(i: int) -> int:
	return me.derived[i].get("capacity", 0) if i < me.derived.size() else 0


func _refresh_hues() -> void:
	for c in hue_box.get_children():
		c.queue_free()
	var hues: Array = me.hue.hues
	for i in hues.size():
		var r: Dictionary = hues[i]
		if not r.access:
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s %d" % [HueDB.hue_title(i), r.mastery]
		l.custom_minimum_size = Vector2(78, 0)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", HUE_COLOURS[i])
		row.add_child(l)
		var b := bar(HUE_COLOURS[i], 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.max_value = maxi(capacity(i), 1)
		b.value = r.energy
		b.tooltip_text = "%d / %d %s energy" % [r.energy, capacity(i), HueDB.hue_title(i)]
		row.add_child(b)
		var n := Label.new()
		n.text = "%d/%d" % [r.energy, capacity(i)]
		n.add_theme_font_size_override("font_size", 11)
		n.custom_minimum_size = Vector2(54, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(n)
		hue_box.add_child(row)
	var notes := []
	for i in hues.size():
		if hues[i].access and hues[i].get("points", 0) > 0:
			notes.append("%d %s point%s (K)" % [hues[i].points, HueDB.hue_title(i), "" if hues[i].points == 1 else "s"])
		if hues[i].access and hues[i].get("picks", 0) > 0:
			notes.append("%s talent to choose (H)" % HueDB.hue_title(i))
	if not notes.is_empty():
		var pts := Label.new()
		pts.text = ", ".join(notes)
		pts.add_theme_color_override("font_color", Color("ffd98a"))
		pts.add_theme_font_size_override("font_size", 12)
		hue_box.add_child(pts)


func _refresh_hotbar() -> void:
	for i in HOTBAR.size():
		var id: int = HOTBAR[i]
		var r := learned(id)
		var b: Button = slots[i]
		var def := db.rank(id, maxi(r, 1))
		b.text = "%d %s%s" % [i + 1, def.name if not def.is_empty() else "?", "" if r <= 1 else " " + "I".repeat(r)]
		b.disabled = r == 0
		b.tooltip_text = (def.description if r else "Not learned yet.") if not def.is_empty() else ""
		var hue_c: Color = HUE_COLOURS[def.hue] if not def.is_empty() else Color.WHITE
		b.add_theme_color_override("font_color", hue_c.lightened(0.3))
		b.add_theme_color_override("font_hover_color", hue_c.lightened(0.5))
	prime_label.text = "Spark primed: your next Gust carries fire (Q)" if game and game.primed else ""


func _process(_delta: float) -> void:
	var view := get_viewport().get_visible_rect().size
	for row in _layout:
		var c: Control = row[0]
		c.size = c.get_combined_minimum_size()
		c.position = (view * row[1] + row[2] - c.size * row[3]).round()
	if me.is_empty():
		return
	# Cooldown shading, counted down from the snapshot.
	var since := Time.get_ticks_msec() / 1000.0 - me_at
	for i in HOTBAR.size():
		var b: Button = slots[i]
		var cd: ColorRect = b.get_node("Cooldown")
		var left: float = me.ready.get(str(HOTBAR[i]), 0) / 1000.0 - since
		var def := db.rank(HOTBAR[i], maxi(learned(HOTBAR[i]), 1))
		var total: float = maxf(def.get("cooldown_ms", 1000) / 1000.0, 0.1)
		if left > 0.0:
			cd.visible = true
			cd.size = Vector2(b.size.x, b.size.y * clampf(left / total, 0.0, 1.0))
		else:
			cd.visible = false


func show_preview(text: String) -> void:
	preview_label.text = text


# --------------------------------------------------------------------------
# Messages

func toast(text: String, colour := Color("f3ead2")) -> void:
	if text.is_empty():
		return
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", colour)
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var t := create_tween()
	t.tween_interval(4.0)
	t.tween_property(p, "modulate:a", 0.0, 0.8)
	t.tween_callback(p.queue_free)
	log_line("[color=#bfb59a]%s[/color]" % text.replace("[", "[lb]"))


func log_line(bb: String) -> void:
	chat_log.append_text(bb + "\n")


func chat(from: String, text: String) -> void:
	var safe := text.replace("[", "[lb]")
	if from.is_empty():
		log_line("[color=#9fd3ff]%s[/color]" % safe)
	else:
		log_line("[color=#ffd98a]%s:[/color] %s" % [from.replace("[", "[lb]"), safe])


func _on_chat(text: String) -> void:
	chat_input.clear()
	chat_input.release_focus()
	if not text.strip_edges().is_empty():
		Net.request({"t": "chat", "text": text})


func focus_chat() -> void:
	chat_input.grab_focus()


func typing() -> bool:
	return chat_input.has_focus()


# --------------------------------------------------------------------------
# Dialogue

func show_dialog(ev: Dictionary) -> void:
	dialog.visible = true
	dialog_name.text = ev.name
	dialog_text.text = "\n".join(ev.lines).replace("[", "[lb]")
	for c in dialog_buttons.get_children():
		c.queue_free()
	var choices: Array = ev.choices
	if choices.is_empty():
		var b := Button.new()
		b.text = "Next" if ev.more else "Close"
		b.pressed.connect(func(): Net.request({"t": "choose", "index": 0}) if ev.more else _dialog_close())
		dialog_buttons.add_child(b)
	else:
		for i in choices.size():
			var b := Button.new()
			b.text = "%d. %s" % [i + 1, choices[i]]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func(): Net.request({"t": "choose", "index": i}))
			dialog_buttons.add_child(b)


func dialog_choose(n: int) -> bool:
	if not dialog.visible:
		return false
	var buttons := dialog_buttons.get_children()
	if n < buttons.size():
		(buttons[n] as Button).pressed.emit()
	return true


func _dialog_close() -> void:
	dialog.visible = false
	Net.request({"t": "close"})


func hide_dialog() -> void:
	dialog.visible = false


# --------------------------------------------------------------------------
# Windows

func refresh_windows() -> void:
	if me.is_empty():
		return
	if windows.hues.panel.visible:
		_fill_hues(windows.hues.body)
	if windows.skills.panel.visible:
		_fill_skills(windows.skills.body)
	if windows.inventory.panel.visible:
		_fill_inventory(windows.inventory.body)
	if windows.character.panel.visible:
		_fill_character(windows.character.body)


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()


func _label(box: Control, text: String, size := 13, colour := Color("f3ead2")) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	box.add_child(l)
	return l


func _fill_hues(box: Control) -> void:
	_clear(box)
	var hues: Array = me.hue.hues
	var any := false
	for i in hues.size():
		var r: Dictionary = hues[i]
		if not r.access:
			continue
		any = true
		var d: Dictionary = me.derived[i]
		var row := db.mastery_row(r.mastery)
		var flow: int = row.flow_pct
		for key in me.hue.skills:
			var def := db.rank(int(key), me.hue.skills[key].rank)
			if not def.is_empty() and def.kind == HueDB.FLOW and def.hue == i:
				flow += def.p1
		var active: int = me.active.filter(func(a): return a.hue == i).size()
		_label(box, "%s - mastery %d (personal cap %d, trains fully to %d here)" % [HueDB.hue_title(i), r.mastery, r.cap, d.soft_cap], 15, HUE_COLOURS[i])
		var xp := bar(HUE_COLOURS[i].darkened(0.3), 6)
		xp.max_value = maxi(r.mastery, 1) * db.b("mastery_xp_per_level", 20)
		xp.value = r.xp
		box.add_child(xp)
		var text := "Energy %d / %d, regaining %d per second here (concentration %d)\nChannel: %d current safely; vessels +%d%% flow\nAllowance: %d of %d sustained actions   Points: %d" % [
				r.energy, d.capacity, d.regen, d.conc, d.channel, flow, active, row.allowance, r.points]
		if d.dissonance:
			text += "\nDissonance: -%d%% from the other hues you hold" % d.dissonance
		_label(box, text, 12)
		for t in r.get("talents", []):
			if prog.talents.has(t):
				_label(box, "  Talent: %s - %s" % [prog.talents[t].name, prog.talents[t].description], 11, Color("cfe8c9"))
		if r.get("picks", 0) > 0:
			_label(box, "Choose a talent (%d to pick):" % r.picks, 12, Color("ffd98a"))
			for id in d.offers:
				var t: Dictionary = prog.talents[id]
				var b := Button.new()
				b.text = "%s: %s" % [t.name, t.description]
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.focus_mode = Control.FOCUS_NONE
				b.pressed.connect(func(): Net.request({"t": "talent", "id": id}))
				box.add_child(b)
	if not any:
		_label(box, "You cannot manipulate any hue yet.")
	_label(box, "\nMastery trains fully up to the lower of your personal cap and what this place allows; beyond, each level halves the gain. Feats - new things done where a hue runs strong - raise your cap.", 11, Color("bfb59a"))


func _fill_skills(box: Control) -> void:
	_clear(box)
	var pts := []
	for i in me.hue.hues.size():
		if me.hue.hues[i].access:
			pts.append("%s %d" % [HueDB.hue_title(i), me.hue.hues[i].points])
	_label(box, "Skill points: " + ", ".join(pts) + "  (from mastery milestones)", 13, Color("ffd98a"))
	var ids := db.skills.keys()
	ids.sort()
	for id in ids:
		var r := learned(id)
		var top := db.max_rank(id)
		var cur := db.rank(id, maxi(r, 1))
		var hue_i: int = cur.hue
		if not me.hue.hues[hue_i].access and r == 0:
			continue
		var head := HBoxContainer.new()
		box.add_child(head)
		var l := Label.new()
		l.text = "%s  %s" % [cur.name, ("rank %d/%d" % [r, top]) if r else "not learned"]
		l.add_theme_color_override("font_color", HUE_COLOURS[hue_i])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
		var next := db.rank(id, r + 1)
		if not next.is_empty():
			var b := Button.new()
			b.text = "Learn" if r == 0 else "Rank up"
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func(): Net.request({"t": "learn", "skill": id}))
			head.add_child(b)
		_label(box, cur.description, 12)
		var sk = me.hue.skills.get(str(id))
		var info := ""
		if r:
			info = "%d energy, %d current, %.1f s recovery" % [cur.energy, cur.current, cur.cooldown_ms / 1000.0] if cur.kind != HueDB.FLOW else "Always in effect."
			if cur.prof_cap:
				info += "   Proficiency %d / %d" % [sk.prof, cur.prof_cap]
		if not next.is_empty():
			info += "\nNext rank: %d %s points, mastery %d, proficiency %d. %s" % [next.cost,
					HueDB.hue_title(next.hue), next.req_mastery, next.req_prof, next.description]
		_label(box, info.strip_edges(), 11, Color("bfb59a"))
		box.add_child(HSeparator.new())


func _fill_inventory(box: Control) -> void:
	_clear(box)
	var inv: Array = me.inventory
	var any := false
	for i in inv.size():
		var lot = inv[i]
		if lot == null:
			continue
		any = true
		var it: Dictionary = items.get(lot.item, {"name": "item %d" % lot.item, "kind": "misc", "description": ""})
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := Label.new()
		l.text = "%s x%d" % [it.name, lot.amount]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = it.description
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		if it.kind == "gear" or it.kind == "gem":
			var rar: int = lot.get("rarity", 0)
			if it.kind == "gear":
				l.text = "%s %s" % [prog.rarities[rar].name, it.name]
			var info: Array = prog.gear_modifiers(lot) if it.kind == "gear" else prog.gems.get(lot.item, {}).get("mods", [])
			l.tooltip_text = "%s\n%s" % [it.description, Progression.mods_text(info)]
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			if it.kind == "gear":
				b.text = "Wear"
				b.pressed.connect(func(): Net.request({"t": "equip", "index": i}))
			else:
				b.text = "Set in gear"
				var slot := ""
				for sl in me.equipment:
					if me.equipment[sl].sockets.has(0):
						slot = sl
						break
				b.disabled = slot == ""
				b.pressed.connect(func(): Net.request({"t": "socket", "slot": slot, "index": i}))
			row.add_child(b)
			_label(box, "  " + Progression.mods_text(info), 11, Color("bfb59a"))
		if it.kind == "use" or it.kind == "kit":
			var b := Button.new()
			b.text = "Use"
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func(): Net.request({"t": "use", "index": i}))
			row.add_child(b)
		var v: Dictionary = db.vessels.get(lot.item, {})
		if not v.is_empty() and lot.get("init", false):
			var order: int = me.hue.supply.find(i) + 1
			var b := Button.new()
			b.text = "Supply #%d" % order if order else "Use as supply"
			b.toggle_mode = true
			b.button_pressed = order > 0
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func(): Net.request({"t": "supply", "index": i, "on": 0 if order else 1}))
			row.add_child(b)
			var per_unit: float = lot.charge / 1000.0
			_label(box, "  %s vessel, grade %d: %.1f / %d energy each (%d in the stack), safe current %d, condition %d / %d" % [
					HueDB.hue_title(v.hue), v.grade, per_unit, v.capacity, int(lot.charge) * int(lot.amount) / 1000,
					v.safe_current, lot.condition, v.max_condition], 11, Color("bfb59a"))
	if not any:
		_label(box, "Your pack is empty. Wind Scythe (3) harvests grass, herbs and flowers.")


func _fill_character(box: Control) -> void:
	_clear(box)
	_label(box, "Body (trained by what you do)", 14, Color("ffd98a"))
	for st in prog.body:
		var rec: Dictionary = me.body.get(st, {"lvl": 0, "xp": 0})
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := Label.new()
		l.text = "%s %d" % [prog.body[st].name, rec.lvl]
		l.custom_minimum_size = Vector2(120, 0)
		l.tooltip_text = prog.body[st].description
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		var b := bar(Color("c9b458"), 8)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.max_value = prog.body_next(rec.lvl)
		b.value = rec.xp
		b.tooltip_text = prog.body[st].description
		row.add_child(b)
	var s: Dictionary = me.stats
	_label(box, "Health %d   Attack +%d   Defense %d   Step %d ms   Noticed at %d%%   Yield %d%%" % [
			me.max_hp, s.attack, s.defense, s.move_ms, s.notice, s.yield], 12)
	_label(box, "\nEquipment", 14, Color("ffd98a"))
	for slot in Progression.SLOTS:
		if not me.equipment.has(slot):
			continue
		var inst: Dictionary = me.equipment[slot]
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := Label.new()
		var gems := []
		for g in inst.sockets:
			gems.append(items[g].name if g and items.has(g) else "empty")
		l.text = "%s: %s %s [%s]" % [slot, prog.rarities[inst.get("rarity", 0)].name,
				items.get(inst.item, {"name": "?"}).name, ", ".join(gems)]
		l.tooltip_text = Progression.mods_text(prog.gear_modifiers(inst))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		if me.zone.band in ["core", "altar"]:
			var up := Button.new()
			up.text = "Raise"
			up.tooltip_text = "Offer this place's energy to raise its rarity (may fail)."
			up.focus_mode = Control.FOCUS_NONE
			up.pressed.connect(func(): Net.request({"t": "altar", "slot": slot}))
			row.add_child(up)
		var off := Button.new()
		off.text = "Remove"
		off.focus_mode = Control.FOCUS_NONE
		off.pressed.connect(func(): Net.request({"t": "unequip", "slot": slot}))
		row.add_child(off)
	if me.equipment.is_empty():
		_label(box, "Nothing worn. Ama can sew you a vest from hopper hide.", 12)
	_label(box, "\nFeats: %s" % (", ".join(me.feats.map(func(f): return prog.feats[f].name if prog.feats.has(f) else f)) if not me.feats.is_empty() else "none yet"), 12)
	var camp: Dictionary = me.anchors.get(game.map.name if game and game.map else "", {})
	_label(box, "Camp: %s" % ("at %d,%d (wards %d)" % [camp.x, camp.y, camp.protection] if not camp.is_empty() else "none - use a Camp Kit beyond the meadow"), 12)
