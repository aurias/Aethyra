extends SceneTree
## Render a map to a PNG (needs a display): godot --path game -s res://tools/map_shot.gd -- out.png [x y w h]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://map.png"
	var m := GameMap.load_named("gale-1")
	var vp := SubViewport.new()
	vp.size = Vector2i(m.w * 32, m.h * 32)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var objects := Node2D.new()
	objects.y_sort_enabled = true
	var view := MapView.new()
	vp.add_child(view)
	vp.add_child(objects)
	view.setup(m, objects)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if args.size() >= 5:
		img = img.get_region(Rect2i(int(args[1]) * 32, int(args[2]) * 32, int(args[3]) * 32, int(args[4]) * 32))
	img.save_png(out)
	print("saved ", out)
	quit()
