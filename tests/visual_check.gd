extends Node
## Windowed smoke/performance check. Boots the real game scene, takes screenshots
## of the opening view, the shipyard panel, a 30-vs-30 fleet battle and the fog,
## and logs frame cost while the battle is running.
##
## Run:  godot --path . --resolution 1600x900 res://tests/visual_check.tscn -- --out=C:/some/folder

const MAIN_SCENE: String = "res://scenes/main.tscn"
const FLEET: Array[int] = [7, 3, 5, 4, 3, 3, 2, 3]  # DD, SS, CL, CA, BC, BB, SBB, CV = 30 hulls

var _out_dir: String = "user://"
var _match: Match = null
var _frame_usec: PackedInt64Array = PackedInt64Array()
var _measuring: bool = false
var _last_tick: int = 0
var _physics_ms: Array[float] = []


func _ready() -> void:
	var seed_value: int = 7
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	_match.map_seed = seed_value
	_match.team_control = [Match.ControlType.HUMAN, Match.ControlType.AI]
	add_child(_match)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _measuring:
		return
	var now: int = Time.get_ticks_usec()
	if _last_tick != 0:
		_frame_usec.append(now - _last_tick)
	_last_tick = now
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _wait(duration: float) -> void:
	await get_tree().create_timer(duration, true, true).timeout


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join(file_name)
	var err: Error = image.save_png(path)
	print("SHOT %s %dx%d %s" % [path, image.get_width(), image.get_height(), "ok" if err == OK else "ERROR %d" % err])


func _spawn_fleet(team: int, center: Vector2, heading: float) -> Array[Ship]:
	var fleet: Array[Ship] = []
	var classes: Array[ShipStats.ShipClass] = GameData.all_classes()
	var index: int = 0
	for class_index: int in FLEET.size():
		for n: int in FLEET[class_index]:
			var col: int = index % 6
			var row: int = floori(float(index) / 6.0)
			var offset: Vector2 = Vector2(float(row) * 95.0 - 190.0, float(col) * 110.0 - 275.0)
			var at: Vector2 = _match.nav.nearest_free(center + offset, false)
			fleet.append(_match.spawn_ship(classes[class_index], team, at, heading))
			index += 1
	return fleet


func _run() -> void:
	await _wait(1.5)
	print("VISUAL renderer=%s viewport=%s" % [RenderingServer.get_video_adapter_name(), get_viewport().get_visible_rect().size])
	await _shot("01_start.png")

	# A damaged destroyer in the Home Base dock: range rings, dock art and the repair badge.
	var yard: Shipyard = _match.bases[0].shipyard
	var patient: Ship = _match.spawn_ship(ShipStats.ShipClass.DD, 0, yard.dock_point(), 0.0)
	patient.hp = patient.max_hp * 0.4
	_match.player.set_selected_ships([patient] as Array[Ship])
	_match.camera.position = yard.dock_point()
	_match.camera.zoom = Vector2(1.0, 1.0)
	await _wait(2.0)
	print("VISUAL dock repairing=%d hp=%.0f/%.0f" % [yard.repairing, patient.hp, patient.max_hp])
	await _shot("01b_dock_repair.png")

	_match.player.select_yard(_match.bases[0].shipyard)
	_match.player.request_build(ShipStats.ShipClass.DD)
	_match.player.request_build(ShipStats.ShipClass.SS)
	await _wait(1.0)
	await _shot("02_shipyard_panel.png")

	# A fortified enemy island under fire: the garrison HP bar and a smaller island dock.
	var fort_island: Island = null
	for island: Island in _match.islands:
		if island.is_capturable() and island.kind == Island.Kind.MAJOR:
			fort_island = island
			break
	if fort_island != null:
		fort_island.set_owner_team(1)
		fort_island.shipyard.tier = 3
		fort_island.garrison.hp = fort_island.garrison.max_hp * 0.55
		var gunner: Ship = _match.spawn_ship(ShipStats.ShipClass.CL, 0,
			_match.nav.nearest_free(fort_island.position + Vector2(0.0, fort_island.radius + 380.0), false), -PI * 0.5)
		gunner.order_attack(fort_island.garrison)
		_match.player.select_yard(fort_island.shipyard)
		_match.camera.position = fort_island.position + Vector2(0.0, 150.0)
		_match.camera.zoom = Vector2(0.8, 0.8)
		await _wait(4.0)
		print("VISUAL garrison hp=%.0f/%.0f owner=%d" % [fort_island.garrison.hp, fort_island.garrison.max_hp, fort_island.owner_team])
		await _shot("02c_fortified_island.png")
		gunner.kill()
		_match.player.clear_selection()

	# A lone submarine (spots nothing) and a lone carrier (spots almost nothing), away from
	# everything else: both must be drawn clear of the fog, ringed, and on the minimap.
	var lonely: Vector2 = _match.nav.nearest_free(_match.bases[0].position + Vector2(300.0, -1100.0), false)
	var sub: Ship = _match.spawn_ship(ShipStats.ShipClass.SS, 0, lonely, 0.0)
	var flattop: Ship = _match.spawn_ship(ShipStats.ShipClass.CV, 0,
		_match.nav.nearest_free(lonely + Vector2(420.0, 60.0), false), 0.0)
	_match.player.set_selected_ships([sub, flattop] as Array[Ship])
	_match.camera.position = lonely + Vector2(210.0, 0.0)
	_match.camera.zoom = Vector2(0.45, 0.45)
	await _wait(1.0)
	await _shot("02b_lone_sub_and_carrier.png")
	sub.kill()
	flattop.kill()

	# 30 v 30 in open water near the middle of the map.
	var center: Vector2 = _match.nav.nearest_free(_match.map_data.center() + Vector2(0.0, -500.0), false)
	var mine: Array[Ship] = _spawn_fleet(0, center + Vector2(-520.0, 0.0), 0.0)
	var theirs: Array[Ship] = _spawn_fleet(1, center + Vector2(520.0, 0.0), PI)
	_match.camera.position = center
	_match.camera.zoom = Vector2(0.62, 0.62)
	_match.player.set_selected_ships(mine)
	_match.order_group_move(mine, center + Vector2(-150.0, 0.0))
	_match.order_group_move(theirs, center + Vector2(150.0, 0.0))
	await _wait(2.0)
	# Carriers launch on their own; nothing to order.
	await _wait(3.0)
	_measuring = true
	await _wait(4.0)
	await _shot("03_battle_30v30.png")
	await _wait(8.0)
	_measuring = false
	await _shot("04_battle_later.png")
	_report(mine.size() + theirs.size())
	# "Ranges: all my ships" toggle with nothing selected: every own ship ringed, no enemy.
	_match.player.clear_selection()
	_match.show_all_ranges = true
	await _wait(0.6)
	await _shot("04b_all_ranges.png")
	_match.show_all_ranges = false

	# Fog of war: the enemy home waters should be dark, the minimap should not show their fleet.
	_match.player.clear_selection()
	_match.camera.position = _match.bases[1].position
	_match.camera.zoom = Vector2(0.5, 0.5)
	await _wait(1.0)
	await _shot("05_enemy_base_in_fog.png")

	# A Resource Ship mining the island nearest our base (gold marker).
	var home: Vector2 = _match.bases[0].position
	var near: Island = _match.islands[0]
	for island: Island in _match.islands:
		if island.position.distance_to(home) < near.position.distance_to(home):
			near = island
	var dir: Vector2 = (home - near.position).normalized()
	_match.spawn_ship(ShipStats.ShipClass.RS, 0, near.position + dir * (near.radius + 60.0), dir.angle() + PI * 0.5)
	_match.camera.position = near.position + dir * (near.radius * 0.5)
	_match.camera.zoom = Vector2(1.6, 1.6)
	await _wait(2.0)
	await _shot("05b_resource_ship_mining.png")

	# The pause screen.
	_match.hud.set_paused(true)
	for i: int in 20:
		await get_tree().process_frame
	await _shot("05c_paused.png")
	_match.hud.set_paused(false)

	# The start menu.
	_match.queue_free()
	await _wait(0.3)
	GameSettings.menu_shown = true  # keep --size= from auto-starting a match out of this shot
	var menu: Node = (load(GameSettings.MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await _wait(0.6)
	await _shot("06_start_menu.png")
	menu.queue_free()
	await _wait(0.2)
	# The title screen the game opens on.
	GameSettings.menu_shown = false
	add_child((load(GameSettings.MENU_SCENE) as PackedScene).instantiate())
	await _wait(0.8)
	await _shot("07_title_screen.png")
	get_tree().quit(0)


func _report(ship_count: int) -> void:
	var sorted: Array[int] = []
	var total: int = 0
	for value: int in _frame_usec:
		sorted.append(value)
		total += value
	sorted.sort()
	if sorted.is_empty():
		print("PERF no samples")
		return
	var avg_ms: float = float(total) / float(sorted.size()) / 1000.0
	var p95_ms: float = float(sorted[int(float(sorted.size() - 1) * 0.95)]) / 1000.0
	var p99_ms: float = float(sorted[int(float(sorted.size() - 1) * 0.99)]) / 1000.0
	var max_ms: float = float(sorted[sorted.size() - 1]) / 1000.0
	var phys: float = 0.0
	var phys_max: float = 0.0
	for value: float in _physics_ms:
		phys += value
		phys_max = maxf(phys_max, value)
	print("PERF ships_spawned=%d alive=%d projectiles=%d frames=%d" % [ship_count, _match.ships_of(0).size() + _match.ships_of(1).size(),
		_match.projectile_count(), sorted.size()])
	print("PERF frame avg=%.2fms (%.0f fps) p95=%.2fms p99=%.2fms max=%.2fms" % [avg_ms, 1000.0 / avg_ms, p95_ms, p99_ms, max_ms])
	print("PERF simulation (physics) tick avg=%.2fms max=%.2fms (budget 16.67ms at 60 Hz)" % [
		phys / float(_physics_ms.size()), phys_max])
