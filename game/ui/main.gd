extends Node
## Root of the game: the host/join menu, then the world.

const SETTINGS := "user://settings.json"
const VERSION := "0.3.0 (Godot parity pass)"

var menu: Control
var game: Game
var status: Label
var fields := {}


func _ready() -> void:
	Net.joined.connect(_on_joined)
	Net.failed.connect(func(why): _back_to_menu(why))
	Net.closed.connect(func(why): _back_to_menu(why))
	_build_menu()
	# Automation: --host <world> <name> or --join <address> <name>, then
	# optionally --shot <png> <seconds> [--do <chat or key script>].
	var args := OS.get_cmdline_user_args()
	var shot := args.find("--shot")
	if shot >= 0 and args.size() > shot + 2:
		_screenshot_later(args[shot + 1], float(args[shot + 2]))
	var quit_after := args.find("--quit-after")
	if quit_after >= 0 and args.size() > quit_after + 1:
		get_tree().create_timer(float(args[quit_after + 1])).timeout.connect(func():
			Net.stop()
			get_tree().quit())
	if args.has("--log-events"):
		Net.event.connect(func(ev): print("EVENT ", JSON.stringify(ev)))
	var script := args.find("--do")
	if script >= 0 and args.size() > script + 1:
		_run_script(args[script + 1])
	var port := args.find("--port")
	if port >= 0 and args.size() > port + 1:
		fields.port.text = args[port + 1]
		fields.join_port.text = args[port + 1]
	if args.size() >= 3 and args[0] == "--host":
		fields.world.text = args[1]
		fields.name.text = args[2]
		_host()
	elif args.size() >= 3 and args[0] == "--join":
		fields.address.text = args[1]
		fields.name.text = args[2]
		_join()


func _screenshot_later(path: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path)
	Net.stop()
	get_tree().quit()


## A tiny automation script for visual checks: steps separated by ';',
## each "wait <s>", "key <name>", "hold <name> <s>", "say <text>" or
## "click <x> <y>" (cells).
func _run_script(text: String) -> void:
	for step in text.split(";", false):
		var p := step.strip_edges().split(" ", false, 1)
		var arg := p[1] if p.size() > 1 else ""
		match p[0]:
			"wait":
				await get_tree().create_timer(float(arg)).timeout
			"key", "hold":
				var a := arg.split(" ")
				var ev := InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(a[0])
				ev.physical_keycode = ev.keycode
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().create_timer(float(a[1]) if a.size() > 1 else 0.05).timeout
				var up := ev.duplicate()
				up.pressed = false
				Input.parse_input_event(up)
			"say":
				Net.request({"t": "chat", "text": arg})
			"click":
				var a := arg.split(" ")
				if game:
					Net.request({"t": "walk", "x": int(a[0]), "y": int(a[1])})
		await get_tree().process_frame


func _settings() -> Dictionary:
	var s = Save.read_json(SETTINGS)
	return s if typeof(s) == TYPE_DICTIONARY else {}


func _save_settings() -> void:
	var s := {}
	for k in fields:
		if fields[k] is LineEdit and k != "password" and k != "join_password":
			s[k] = fields[k].text
	Save.write_json(SETTINGS, s)


func _build_menu() -> void:
	var s := _settings()
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.theme = Hud.make_theme()
	add_child(menu)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/avalon/grass.png")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.scale = Vector2(2, 2)
	menu.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Aethyra"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("ffd98a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "The Windswept Meadow - hue demo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	fields.name = _field(v, "Your character", s.get("name", ""), "a name, 2-20 letters")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 210)
	v.add_child(tabs)

	var host := VBoxContainer.new()
	host.name = "Host a world"
	tabs.add_child(host)
	fields.world = _field(host, "World name", s.get("world", "Meadow"), "")
	fields.password = _field(host, "Password for friends (optional)", "", "")
	fields.port = _field(host, "Port", s.get("port", str(Net.DEFAULT_PORT)), "")
	var hb := Button.new()
	hb.text = "Host and play"
	hb.pressed.connect(_host)
	host.add_child(hb)

	var join := VBoxContainer.new()
	join.name = "Join a friend"
	tabs.add_child(join)
	fields.address = _field(join, "Host address", s.get("address", "127.0.0.1"), "IP or host name")
	fields.join_port = _field(join, "Port", s.get("join_port", str(Net.DEFAULT_PORT)), "")
	fields.join_password = _field(join, "World password", "", "")
	var jb := Button.new()
	jb.text = "Join"
	jb.pressed.connect(_join)
	join.add_child(jb)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("ffc3a8"))
	v.add_child(status)
	var credit := Label.new()
	credit.text = "v%s.  Tiles: \"Whispers of Avalon\" by Leonard Pabin (barrel after Crush), CC-BY 3.0, OpenGameArt.org" % VERSION
	credit.add_theme_font_size_override("font_size", 10)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.add_theme_color_override("font_color", Color("bfb59a"))
	v.add_child(credit)


func _field(parent: Control, label: String, value: String, hint: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = hint
	parent.add_child(e)
	return e


func _host() -> void:
	_save_settings()
	status.text = "Opening the world..."
	var why := Net.host(fields.world.text.strip_edges(), fields.password.text, int(fields.port.text), fields.name.text.strip_edges())
	if why != "":
		status.text = why


func _join() -> void:
	_save_settings()
	status.text = "Connecting..."
	var why := Net.join(fields.address.text.strip_edges(), int(fields.join_port.text), fields.join_password.text, fields.name.text.strip_edges())
	if why != "":
		status.text = why


func _on_joined(map_name: String) -> void:
	if game:
		return
	menu.visible = false
	game = Game.new()
	game.leave_requested.connect(_confirm_leave)
	add_child(game)
	game.load_map(map_name)
	status.text = ""


func _confirm_leave() -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = "Leave the world?" + (" Friends in it will be disconnected." if Net.is_host else "")
	d.confirmed.connect(func(): Net.stop(); _back_to_menu(""))
	add_child(d)
	d.popup_centered()


func _back_to_menu(why: String) -> void:
	if game:
		game.queue_free()
		game = null
	menu.visible = true
	status.text = why
