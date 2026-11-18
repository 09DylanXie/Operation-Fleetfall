extends Node2D
## Close-up of every ship class drawn by ShipArt: intact (left), damaged and burning
## (right, turrets trained to starboard). Saves a screenshot and quits.
##
## Run:  godot --path . --resolution 1600x900 res://tests/art_gallery.tscn -- --out=C:/some/folder

var _out_dir: String = "user://"
var _t: float = 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	var cam: Camera2D = Camera2D.new()
	cam.zoom = Vector2(1.85, 1.85)
	cam.position = Vector2(150.0, 232.0)
	add_child(cam)
	RenderingServer.set_default_clear_color(Color(0.07, 0.2, 0.31))
	_run.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var classes: Array[ShipStats.ShipClass] = GameData.all_classes()
	for i: int in classes.size():
		var stats: ShipStats = GameData.ship(classes[i])
		var y: float = 20.0 + float(i) * 42.0
		for damaged: int in 2:
			var x: float = 70.0 + float(damaged) * 170.0
			var turrets: PackedFloat32Array = PackedFloat32Array()
			for m: int in stats.gun_mounts:
				turrets.append(deg_to_rad(stats.mount_facings_deg[m]) + (deg_to_rad(70.0 if stats.mount_facings_deg[m] < 90.0 else -70.0) if damaged == 1 else 0.0))
			var sec: PackedFloat32Array = PackedFloat32Array()
			for m: int in stats.secondary_mounts:
				sec.append(deg_to_rad(stats.secondary_facings_deg[m]))
			draw_set_transform(Vector2(x, y), 0.0, Vector2.ONE)
			if damaged == 1:
				ShipArt.draw_wake(self, stats, 30.0, _t, Color.WHITE)
			ShipArt.draw(self, stats, Ship.TEAM_COLORS[i % 2], Color.WHITE, turrets, sec, 0.0,
				Transform2D(0.0, Vector2(x, y)))
			draw_set_transform(Vector2(x, y), 0.0, Vector2.ONE)
			if damaged == 1:
				ShipArt.draw_fires(self, stats, 0.7, _t, 0.0, i)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join("gallery.png")
	print("SHOT %s %s" % [path, image.save_png(path)])
	get_tree().quit()
