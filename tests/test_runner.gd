extends Node
## Headless rule tests. Every test builds a real Match on a hand-made map and
## advances real physics frames, so raycasts, vision ticks and timers all run
## exactly as they do in play.
##
## Run:  godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## Optional:  -- --only=<substring>

const MAIN_SCENE: String = "res://scenes/main.tscn"
const NONE: int = Match.ControlType.NONE
const HUMAN: int = Match.ControlType.HUMAN
const DD: ShipStats.ShipClass = ShipStats.ShipClass.DD
const SS: ShipStats.ShipClass = ShipStats.ShipClass.SS
const CL: ShipStats.ShipClass = ShipStats.ShipClass.CL
const CA: ShipStats.ShipClass = ShipStats.ShipClass.CA
const BB: ShipStats.ShipClass = ShipStats.ShipClass.BB
const CV: ShipStats.ShipClass = ShipStats.ShipClass.CV

var _checks: int = 0
var _failures: Array[String] = []
var _current: String = ""
var _match: Match = null


func _ready() -> void:
	await get_tree().process_frame
	var only: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var names: Array[String] = []
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and (only == "" or method_name.contains(only)):
			names.append(method_name)
	names.sort()
	for test_name: String in names:
		_current = test_name
		var before: int = _failures.size()
		await call(test_name)
		await _cleanup()
		print("[%s] %s" % ["PASS" if _failures.size() == before else "FAIL", test_name])
	print("")
	print("%d tests, %d checks, %d failures" % [names.size(), _checks, _failures.size()])
	for failure: String in _failures:
		print("  FAILED: " + failure)
	print("RESULT: " + ("ALL TESTS PASSED" if _failures.is_empty() else "TESTS FAILED"))
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Helpers ----------------------------------------------------------------

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current, message])


func check_near(actual: float, expected: float, message: String, tolerance: float = 0.01) -> void:
	check(absf(actual - expected) <= tolerance, "%s (expected %s, got %s)" % [message, expected, actual])


func frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func seconds(duration: float) -> void:
	await frames(int(ceil(duration * 60.0)))


func open_map(size: Vector2 = Vector2(4000.0, 2400.0)) -> MapData:
	var map: MapData = MapData.new()
	map.size = size
	map.base_positions = [Vector2(200.0, size.y * 0.5), Vector2(size.x - 200.0, size.y * 0.5)]
	return map


func add_island(map: MapData, kind: int, at: Vector2, radius: float) -> void:
	var shallow: float = 330.0 if kind == MapData.KIND_MINOR else 0.0
	map.add_island(kind, at, radius, shallow, MapData.circle_polygon(radius))


func start(map: MapData, control: Array[int] = [NONE, NONE], ui: bool = false, levels: Array[int] = []) -> Match:
	var m: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	m.map_override = map
	m.ai_difficulty = levels
	m.map_seed = 4242
	m.team_control = control
	m.create_ui = ui
	m.enable_weather = false
	add_child(m)
	_match = m
	await frames(2)
	return m


func _cleanup() -> void:
	if _match != null:
		_match.queue_free()
		_match = null
	await frames(2)


## A hull under construction: targetable, never fires, never spots. Ideal test target.
func hull(m: Match, cls: ShipStats.ShipClass, team: int, at: Vector2) -> Ship:
	return m.spawn_ship(cls, team, at, 0.0, true)


## A passive observer: a Submarine hull (never auto-fires, hard to spot) given eyes.
## Real Submarines have no spotting range at all.
func spotter(m: Match, team: int, at: Vector2, spotting: float = 520.0) -> Ship:
	var ship: Ship = m.spawn_ship(SS, team, at)
	ship.stats = ship.stats.duplicate() as ShipStats
	ship.stats.spotting_range = spotting
	return ship


func count_projectiles(m: Match, script_class: String) -> int:
	var total: int = 0
	for node: Node in m.projectiles():
		if node.is_queued_for_deletion():
			continue
		if (script_class == "Shell" and node is Shell) or (script_class == "Torpedo" and node is Torpedo) \
				or (script_class == "PlaneSquadron" and node is PlaneSquadron):
			total += 1
	return total


# --- Data & scenes ----------------------------------------------------------

func test_01_roster_matches_design_doc() -> void:
	# code: [gold, steel, build, speed, armor, fire rate, required tier]
	var expected: Dictionary = {
		DD: ["DD", 100, 50, 15.0, 1.0, 0.0, 4.0, 1],
		SS: ["SS", 150, 75, 20.0, 0.5, 0.0, 20.0, 1],
		CL: ["CL", 250, 150, 30.0, 0.7, 0.05, 4.0, 2],
		CA: ["CA", 400, 250, 45.0, 0.5, 0.15, 5.333, 2],
		BB: ["BB", 800, 600, 90.0, 0.3, 0.25, 8.0, 3],
		CV: ["CV", 1000, 400, 120.0, 0.9, 0.0, 10.0, 3],
	}
	for cls: ShipStats.ShipClass in GameData.all_classes():
		var s: ShipStats = GameData.ship(cls)
		var row: Array = expected[cls]
		check(s != null, "stats resource loads for class %d" % cls)
		check(s.ship_class == cls, "%s ship_class field" % row[0])
		check(s.code == row[0], "%s code" % row[0])
		check(s.gold_cost == row[1], "%s gold cost" % row[0])
		check(s.steel_cost == row[2], "%s steel cost" % row[0])
		check_near(s.build_time, row[3], "%s build time" % row[0])
		check_near(s.speed_factor, row[4], "%s speed" % row[0])
		check_near(s.base_armor, row[5], "%s armor" % row[0])
		check_near(s.fire_interval, row[6], "%s fire rate" % row[0])
		check(s.required_shipyard_tier == row[7], "%s shipyard tier" % row[0])
		check(s.mount_offsets.size() == s.gun_mounts, "%s mount offsets match mount count" % row[0])
		check(s.mount_facings_deg.size() == s.gun_mounts, "%s mount facings match mount count" % row[0])
	var dd: ShipStats = GameData.ship(DD)
	var ss: ShipStats = GameData.ship(SS)
	var cl: ShipStats = GameData.ship(CL)
	var ca: ShipStats = GameData.ship(CA)
	var bb: ShipStats = GameData.ship(BB)
	var cv: ShipStats = GameData.ship(CV)
	check_near(cl.fire_interval, dd.fire_interval, "CL guns reload as fast as a destroyer's")
	check_near(ca.fire_interval, 8.0 / 1.5, "CA guns fire 1.5x as often as they used to", 0.001)
	check_near(bb.fire_interval, 8.0, "BB guns reload in half the time they used to")
	check_near(dd.spotting_range, 720.0, "DD spotting range")
	check_near(cl.spotting_range, dd.spotting_range / 2.0, "CL spots half as far as a DD")
	check_near(ca.spotting_range, dd.spotting_range / 2.0, "CA spots half as far as a DD")
	check_near(bb.spotting_range, cl.spotting_range * 2.0 / 3.0, "BB spots 2/3 as far as a cruiser")
	check_near(cv.spotting_range, bb.spotting_range / 3.0, "CV spots 1/3 as far as a BB")
	check_near(ss.spotting_range, 0.0, "SS spots nothing")
	check(dd.gun_mounts == 2 and dd.shells_per_mount == 1, "DD 2x single")
	check(cl.gun_mounts == 3 and cl.shells_per_mount == 3, "CL 3x triple")
	check(ca.gun_mounts == 4 and ca.shells_per_mount == 2, "CA 4x double")
	check(bb.gun_mounts == 3 and bb.shells_per_mount == 2, "BB 3x double")
	check(not ss.has_guns() and ss.torpedo_mode == ShipStats.TorpedoMode.MANUAL_BOW_STERN, "SS torpedoes only, manual")
	check_near(ss.torpedo_interval, 20.0, "SS torpedo reload")
	check(dd.torpedo_mode == ShipStats.TorpedoMode.AUTO_BROADSIDE, "DD auto broadside torpedoes")
	check_near(dd.torpedo_interval, 30.0, "DD torpedo cooldown")
	check(not cv.has_guns() and cv.torpedo_mode == ShipStats.TorpedoMode.NONE and cv.has_planes(), "CV planes only")
	check_near(cv.plane_interval, 10.0, "CV sends a squadron every 10s")
	check(cv.max_squadrons == 5 and cv.squadrons_per_launch == 1, "CV keeps up to 5 squadrons airborne")
	check_near(dd.torpedo_speed_scale, 0.5, "DD torpedoes run at half the standard torpedo speed")
	check_near(ss.torpedo_speed_scale, 1.0, "SS torpedoes run at the standard torpedo speed")
	for cls: ShipStats.ShipClass in [CL, CA, BB]:
		check_near(GameData.ship(cls).aa_kill_chance, 0.2, "%s anti-air downs 1 squadron in 5" % GameData.ship(cls).code)
	for cls: ShipStats.ShipClass in [DD, SS, CV]:
		check_near(GameData.ship(cls).aa_kill_chance, 0.0, "%s has no anti-air" % GameData.ship(cls).code)
	# Cruisers must out-gun destroyers ship for ship and for the same money.
	check(cl.gun_dps() > dd.gun_dps() * 3.0 and ca.gun_dps() > cl.gun_dps(), "cruiser gun damage is well above a destroyer's")
	check(cl.gun_dps() / float(cl.gold_cost) > dd.gun_dps() / float(dd.gold_cost),
		"a CL does more gun damage per gold than a DD")
	check(ca.gun_dps() / float(ca.gold_cost) > dd.gun_dps() / float(dd.gold_cost),
		"a CA does more gun damage per gold than a DD")
	check(dd.shallow_draft and ss.shallow_draft, "DD and SS are shallow draft")
	check(not cl.shallow_draft and not ca.shallow_draft and not bb.shallow_draft and not cv.shallow_draft,
		"cruisers and capital ships are deep draft")
	check(dd.salvo_damage() < cl.salvo_damage() and ca.salvo_damage() < bb.salvo_damage(), "salvo damage ordering")
	check(dd.shell_speed < cl.shell_speed and cl.shell_speed < ca.shell_speed and ca.shell_speed < bb.shell_speed,
		"shell speed scales with caliber")
	check_near(GameData.torpedo_damage(), 1.3 * bb.shell_damage, "torpedo = 1.3x one BB shell")
	check(GameData.torpedo_speed() < bb.shell_speed and GameData.torpedo_speed() > bb.shell_speed * 0.8,
		"torpedo slightly slower than BB shell")
	check_near(GameData.plane_speed(), 0.5 * GameData.torpedo_speed(), "planes at 50% torpedo speed")
	var b: GameBalance = GameData.balance()
	check(GameData.bomb_damage() > 0.0 and is_equal_approx(GameData.bomb_damage(), b.bomb_damage), "bomb damage comes from balance data")
	check_near(b.bomb_interval, 3.0, "squadrons bomb every 3s")
	check_near(b.capture_time, 30.0, "islands take 30s to capture")
	check(b.fleet_cap == 30, "fleet cap 30")
	check_near(b.tick_interval, 15.0, "15s economy tick")
	check(b.home_gold == 50 and b.home_steel == 20, "home base income")
	check(b.minor_gold == 30 and b.minor_steel == 10, "minor island income")
	check(b.major_gold == 20 and b.major_steel == 50, "major island income")
	check_near(b.armor_strip_per_attacker, 0.05, "armor strip 5%")
	check_near(b.sub_homing_time, 2.0, "homing ping 2s")
	check_near(b.sub_reveal_time, 15.0, "reveal penalty 15s")
	check(b.major_shipyard_max_tier == 3 and b.minor_shipyard_max_tier < 3 and b.home_shipyard_max_tier < 3,
		"tier 3 only on major islands")


func _collect(dir_path: String, extension: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), extension, out)
	for file: String in dir.get_files():
		if file.ends_with(extension):
			out.append(dir_path.path_join(file))


func test_02_every_scene_script_and_resource_loads() -> void:
	var scenes: Array[String] = []
	_collect("res://scenes", ".tscn", scenes)
	check(scenes.size() >= 9, "found all scenes (%d)" % scenes.size())
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		check(packed != null, "scene loads: " + path)
		if packed != null:
			var node: Node = packed.instantiate()
			check(node != null and node.get_script() != null, "scene instantiates with its script: " + path)
			if node != null:
				node.free()
	var scripts: Array[String] = []
	_collect("res://scripts", ".gd", scripts)
	for path: String in scripts:
		var script: GDScript = load(path) as GDScript
		check(script != null and script.can_instantiate(), "script compiles: " + path)
	var resources: Array[String] = []
	_collect("res://data", ".tres", resources)
	check(resources.size() == 10, "found all data resources (%d)" % resources.size())
	for path: String in resources:
		check(load(path) != null, "resource loads: " + path)
	check(load("res://assets/shaders/fog.gdshader") != null, "fog shader loads")


# --- Combat rules -----------------------------------------------------------

func test_03_focus_fire_armor_stripping() -> void:
	check_near(Combatant.compute_effective_armor(0.25, 3, 0.05), 0.15, "GDD example: BB under 3 attackers")
	check_near(Combatant.compute_effective_armor(0.25, 1, 0.05), 0.25, "single attacker strips nothing")
	check_near(Combatant.compute_effective_armor(0.25, 0, 0.05), 0.25, "no attackers")
	check_near(Combatant.compute_effective_armor(0.05, 6, 0.05), 0.0, "armor floors at zero")
	var m: Match = await start(open_map())
	var bb: Ship = m.spawn_ship(BB, 1, Vector2(2000.0, 1200.0))
	var cruisers: Array[Ship] = []
	for i: int in 3:
		cruisers.append(m.spawn_ship(CL, 0, Vector2(1500.0, 1000.0 + 200.0 * float(i)), 0.0))
	spotter(m, 0, Vector2(2000.0, 1500.0))
	await seconds(3.0)
	check(bb.active_attacker_count() == 3, "three cruisers register as active attackers (got %d)" % bb.active_attacker_count())
	check_near(bb.effective_armor(), 0.15, "live BB armor stripped to 15%")
	var hp_before: float = bb.hp
	var dealt: float = bb.apply_damage(100.0, false, false)
	check_near(dealt, 85.0, "100 damage through 15% armor")
	check_near(hp_before - bb.hp, 85.0, "hp reduced by dealt amount")
	for ship: Ship in cruisers:
		ship.kill()
	await seconds(9.0)
	check(bb.active_attacker_count() == 0, "attackers expire once they stop firing")
	check_near(bb.effective_armor(), 0.25, "armor returns to base")


func test_04_island_blocks_vision_shells_and_torpedoes() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1600.0, 1200.0), 120.0)
	var m: Match = await start(map)
	var observer: Ship = spotter(m, 0, Vector2(1350.0, 1200.0))
	var hidden: Ship = hull(m, CL, 1, Vector2(1850.0, 1200.0))
	var exposed: Ship = hull(m, CL, 1, Vector2(1350.0, 800.0))
	await seconds(1.0)
	check(not m.has_los(observer.position, hidden.position), "island breaks line of sight")
	check(m.has_los(observer.position, exposed.position), "open water has line of sight")
	check(not hidden.spotted_by[0], "ship behind an island is not spotted even inside spotting range")
	check(exposed.spotted_by[0], "ship in the open is spotted")
	var hidden_hp: float = hidden.hp
	var exposed_hp: float = exposed.hp
	m.spawn_shell(observer, observer.position, 0.0, 100.0, 300.0, 1200.0, 1)
	m.spawn_torpedo(observer, observer.position, 0.0, 1200.0, null, 0.0)
	m.spawn_shell(observer, observer.position, -PI * 0.5, 100.0, 300.0, 1200.0, 1)
	await seconds(4.0)
	check_near(hidden.hp, hidden_hp, "shell and torpedo are stopped by the island")
	check_near(exposed_hp - exposed.hp, 95.0, "unobstructed shell hits (100 dmg through 5% armor)")
	check(m.projectile_count() == 0, "blocked projectiles are destroyed")


func test_05_per_turret_arcs_and_line_of_sight() -> void:
	var map: MapData = open_map()
	# Small rock that masks only the aft turret's line to the target.
	add_island(map, MapData.KIND_COVER, Vector2(950.0, 1150.0), 40.0)
	var m: Match = await start(map)
	var bb: Ship = m.spawn_ship(BB, 0, Vector2(1000.0, 1000.0), 0.0)
	var target: Ship = hull(m, BB, 1, Vector2(1000.0, 1400.0))
	spotter(m, 0, Vector2(1250.0, 1450.0))
	check(bb.mount_bears_on(0, target.position) and bb.mount_bears_on(2, target.position), "broadside: all turrets bear")
	check(m.has_los(bb.mount_position(0), target.position), "fore turret has LOS")
	check(not m.has_los(bb.mount_position(2), target.position), "aft turret LOS is masked by the rock")
	var shells: int = 0
	for i: int in 90:
		await frames(1)
		shells = count_projectiles(m, "Shell")
		if shells > 0:
			break
	check(shells == 2, "only the two turrets with LOS fire (got %d)" % shells)
	# Arcs: a target dead ahead cannot be engaged by the aft turret.
	var bow_on: Ship = m.spawn_ship(BB, 0, Vector2(2400.0, 600.0), 0.0)
	var ahead: Vector2 = Vector2(3000.0, 600.0)
	check(bow_on.mount_bears_on(0, ahead) and bow_on.mount_bears_on(1, ahead), "fore turrets bear ahead")
	check(not bow_on.mount_bears_on(2, ahead), "aft turret cannot train dead ahead")


func test_06_priority_target_obeys_range_and_spotting() -> void:
	var m: Match = await start(open_map())
	var cl: Ship = m.spawn_ship(CL, 0, Vector2(1000.0, 1200.0), PI * 0.5)
	var near: Ship = hull(m, CA, 1, Vector2(1300.0, 1200.0))
	var far: Ship = hull(m, CA, 1, Vector2(1500.0, 1200.0))
	var distant: Ship = hull(m, CA, 1, Vector2(2300.0, 1200.0))
	spotter(m, 0, Vector2(2300.0, 1500.0))
	spotter(m, 0, Vector2(1400.0, 1400.0))
	await seconds(1.0)
	check(cl.gun_target == near, "auto-engagement picks the nearest spotted target")
	check(cl.order_attack(far), "attack order accepted")
	await seconds(0.5)
	check(cl.gun_target == far, "priority target overrides nearest")
	check(distant.spotted_by[0], "distant target is spotted by a scout")
	cl.order_attack(distant)
	await seconds(1.0)
	check(cl.gun_target != distant, "out-of-range priority target is not fired on")
	check(cl.gun_target == near, "falls back to auto-engagement while closing")
	check(cl.has_destination(), "ship closes on an out-of-range priority target")
	var unseen: Ship = hull(m, CA, 1, Vector2(1000.0, 1700.0))
	unseen.spotted_by[0] = false
	check(not cl._target_valid(unseen, 9999.0, false), "unspotted targets are never valid")


func test_07_shells_fly_straight_at_caliber_speed() -> void:
	var m: Match = await start(open_map())
	var base: HomeBase = m.bases[1]
	m.spawn_ship(DD, 0, base.position + Vector2(-400.0, -150.0), 0.0)
	m.spawn_ship(BB, 0, base.position + Vector2(-700.0, 200.0), PI * 0.5)
	var speeds: Dictionary[int, bool] = {}
	for i: int in 120:
		await frames(1)
		for node: Node in m.projectiles():
			if node is Shell:
				speeds[int((node as Shell).speed)] = true
	check(speeds.has(300), "DD shells travel at baseline speed")
	check(speeds.has(440), "BB shells travel faster")
	check(base.hp < base.max_hp, "surface artillery damages the Home Base")
	var shooter: Ship = m.spawn_ship(SS, 0, Vector2(600.0, 400.0))
	var shell: Shell = m.spawn_shell(shooter, Vector2(600.0, 400.0), 0.3, 10.0, 300.0, 5000.0, 1)
	var dir: Vector2 = shell.direction
	await frames(60)
	check(shell.direction.is_equal_approx(dir), "shell never changes course")
	check_near(shell.position.distance_to(Vector2(600.0, 400.0)), 300.0, "shell covers speed x time", 6.0)
	check_near((shell.position - Vector2(600.0, 400.0)).angle(), 0.3, "shell stays on its launch bearing", 0.001)


# --- Destroyers -------------------------------------------------------------

func test_08_destroyer_torpedoes_broadside_only() -> void:
	var m: Match = await start(open_map())
	var base: HomeBase = m.bases[1]
	var dd: Ship = m.spawn_ship(DD, 0, base.position + Vector2(-450.0, 0.0), 0.0)
	await seconds(5.0)
	check(dd.salvos_fired > 0, "guns engage a target dead ahead")
	check(dd.torpedoes_launched == 0, "no torpedoes while the target is off the bow")
	check(dd.torpedo_ready(), "cooldown is not spent while no broadside solution exists")
	check(not dd.in_broadside_arc(base.position), "bow-on target is outside the broadside arc")
	dd.rotation = PI * 0.5
	check(dd.in_broadside_arc(base.position), "beam-on target is inside the broadside arc")
	await seconds(0.6)
	check(dd.torpedoes_launched == 2, "torpedoes launch automatically once broadside (got %d)" % dd.torpedoes_launched)
	check(dd.torpedo_cooldown() > 29.0, "30s cooldown starts")
	var hp_mid: float = base.hp
	var torpedo: Torpedo = null
	for node: Node in m.projectiles():
		if node is Torpedo and not node.is_queued_for_deletion():
			torpedo = node as Torpedo
	check(torpedo != null, "the spread is in the water")
	if torpedo != null:
		check_near(torpedo.speed, 0.5 * GameData.torpedo_speed(), "destroyer torpedoes run at half the standard speed")
		var from: Vector2 = torpedo.position
		await seconds(0.5)
		check(is_instance_valid(torpedo), "half a second later the torpedo is still running")
		if is_instance_valid(torpedo):
			check_near(torpedo.position.distance_to(from), 0.25 * GameData.torpedo_speed(), "and really covers half the distance", 4.0)
	await seconds(27.5)
	check(dd.torpedoes_launched == 2, "no second launch inside 30s")
	await seconds(2.5)
	check(dd.torpedoes_launched == 4, "second launch after 30s (got %d)" % dd.torpedoes_launched)
	check(base.hp < hp_mid, "destroyer torpedoes damage the base")


func test_08b_destroyer_fires_torpedoes_while_sailing_past() -> void:
	# No attack order at all: a destroyer on a move order launches by itself the moment
	# an enemy comes onto its beam.
	var m: Match = await start(open_map())
	var target: Ship = hull(m, CA, 1, Vector2(2000.0, 900.0))
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(1450.0, 1250.0), 0.0)
	dd.order_move(Vector2(2800.0, 1250.0))
	await seconds(1.0)
	check(target.spotted_by[0], "the destroyer sees the target")
	check(dd.torpedoes_launched == 0, "nothing launches while the target is still off the bow (got %d)" % dd.torpedoes_launched)
	var hp_start: float = target.hp
	var launch_bearing: float = -1.0
	for i: int in 80:
		await seconds(0.25)
		if dd.torpedoes_launched > 0:
			launch_bearing = absf(rad_to_deg(dd.relative_bearing(target.position)))
			break
	check(dd.torpedoes_launched == 2, "the spread launches automatically on the way past (got %d)" % dd.torpedoes_launched)
	check(launch_bearing >= 49.0 and launch_bearing <= 131.0, "launched with the target on the beam (bearing %.0f deg)" % launch_bearing)
	check(dd.has_destination() and dd.priority_target == null, "the destroyer never had an attack order and keeps sailing")
	check(count_projectiles(m, "Torpedo") == 2, "both torpedoes are in the water")
	await seconds(6.0)
	check(target.hp < hp_start, "the target is hurt on the way past")


# --- Submarines -------------------------------------------------------------

func test_09_submarine_stealth_and_detection() -> void:
	var m: Match = await start(open_map())
	var sub: Ship = m.spawn_ship(SS, 0, Vector2(1600.0, 1200.0))
	var cruiser: Ship = hull(m, CL, 1, Vector2(1900.0, 1200.0))
	cruiser.complete_construction()
	await seconds(1.0)
	check(not cruiser.spotted_by[0], "a submarine sees nothing by itself")
	check(not sub.spotted_by[1], "cruiser 300px away cannot see a submerged submarine")
	check(cruiser.salvos_fired == 0, "cruiser cannot fire at what it cannot see")
	var dd: Ship = m.spawn_ship(DD, 1, Vector2(1600.0, 1450.0))
	await seconds(0.5)
	check(sub.spotted_by[1], "enemy destroyer within detection range reveals the submarine")
	dd.kill()
	cruiser.kill()
	await seconds(0.5)
	check(not sub.spotted_by[1], "submarine hides again once the destroyer is gone")
	var enemy_base: HomeBase = m.bases[1]
	var near_yard: Ship = m.spawn_ship(SS, 0, enemy_base.position + Vector2(-300.0, 0.0))
	var off_yard: Ship = m.spawn_ship(SS, 0, enemy_base.position + Vector2(-560.0, 0.0))
	await seconds(0.5)
	check(near_yard.spotted_by[1], "enemy shipyard detects a submarine that comes too close")
	check(not off_yard.spotted_by[1], "submarine inside base spotting range but outside detection range stays hidden")


func test_09b_destroyer_depth_charges_kill_submarines() -> void:
	var dd_stats: ShipStats = GameData.ship(DD)
	check(dd_stats.has_depth_charges(), "destroyers carry depth charges")
	for cls: ShipStats.ShipClass in [SS, CL, CA, BB, CV]:
		check(not GameData.ship(cls).has_depth_charges(), "%s carries none" % GameData.ship(cls).code)
	check(dd_stats.depth_charge_range <= GameData.balance().sub_detection_range, "a destroyer detects every boat it can depth-charge")
	var m: Match = await start(open_map())
	# Rotated away so neither guns nor tubes matter: a DD's guns cannot be told apart otherwise.
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(1500.0, 1200.0), 0.0)
	dd.stats = dd.stats.duplicate() as ShipStats
	dd.stats.gun_mounts = 0
	dd.stats.torpedo_mode = ShipStats.TorpedoMode.NONE
	var far_sub: Ship = m.spawn_ship(SS, 1, Vector2(1500.0, 1200.0 + dd_stats.depth_charge_range + 60.0))
	var slip_sub: Ship = hull(m, SS, 1, Vector2(1500.0, 1100.0))
	var cruiser: Ship = hull(m, CL, 1, Vector2(1560.0, 1200.0))
	var friend: Ship = m.spawn_ship(SS, 0, Vector2(1450.0, 1200.0))
	await seconds(6.0)
	check(far_sub.spotted_by[0], "the far submarine is detected")
	check(dd.depth_charges_dropped == 0, "no depth charges outside their range (got %d)" % dd.depth_charges_dropped)
	check_near(far_sub.hp, far_sub.max_hp, "a detected submarine out of reach is unharmed")
	check_near(friend.hp, friend.max_hp, "friendly submarines are never depth-charged")
	check_near(cruiser.hp, cruiser.max_hp * 0.2, "surface ships are never depth-charged")
	check_near(slip_sub.hp, slip_sub.max_hp * 0.2, "a submarine hull on the slip is not a depth-charge target")
	var sub: Ship = m.spawn_ship(SS, 1, Vector2(1500.0, 1320.0))
	var waited: int = 0
	while dd.depth_charges_dropped == 0 and waited < 60:
		await frames(1)
		waited += 1
	check(dd.depth_charges_dropped == 1, "a submarine that comes close is depth-charged at once")
	check_near(sub.max_hp - sub.hp, dd_stats.depth_charge_damage, "one pattern does its full damage")
	await seconds(dd_stats.depth_charge_interval - 0.4)
	check(dd.depth_charges_dropped == 1, "patterns are spaced by the reload")
	var kill_time: float = dd_stats.depth_charge_interval * ceilf(sub.max_hp / dd_stats.depth_charge_damage)
	await seconds(kill_time)
	check(not sub.is_alive(), "the destroyer sinks the submarine with depth charges alone")
	check(far_sub.is_alive() and is_equal_approx(far_sub.hp, far_sub.max_hp), "the boat out of reach is still untouched")
	# An attack order on a submarine runs the destroyer in over the boat.
	check(dd.order_attack(far_sub), "attack order on a detected submarine")
	await seconds(12.0)
	check(not far_sub.is_alive(), "the destroyer hunts the submarine down")


func test_10_submarine_manual_fire_homing_and_reveal() -> void:
	var m: Match = await start(open_map())
	var sub: Ship = m.spawn_ship(SS, 0, Vector2(1000.0, 1000.0), 0.0)
	var target: Ship = hull(m, BB, 1, Vector2(1400.0, 1300.0))
	await seconds(1.0)
	check(not target.spotted_by[0], "a submarine cannot spot its own targets")
	spotter(m, 0, Vector2(1400.0, 1700.0))
	spotter(m, 0, Vector2(600.0, 1400.0))
	await seconds(2.0)
	check(target.spotted_by[0], "target is spotted by another ship")
	check(sub.torpedoes_launched == 0, "submarines never auto-engage")
	check(not sub.order_attack(m.bases[1]), "attack order on the Home Base is refused")
	check(not sub.order_torpedo(m.bases[1]), "torpedo order on the Home Base is refused")
	check(sub.order_attack(target), "manual torpedo order accepted")
	await frames(2)
	check(sub.torpedoes_launched == 2, "torpedoes launch on command (got %d)" % sub.torpedoes_launched)
	check_near(sub.reveal_timer, 15.0, "reveal penalty starts at 15s", 0.1)
	check(sub.torpedo_order == null, "one salvo per order")
	check_near(sub.torpedo_cooldown(), 20.0, "20s reload", 0.1)
	var torpedo: Torpedo = null
	for node: Node in m.projectiles():
		if node is Torpedo:
			torpedo = node as Torpedo
	check(torpedo != null and torpedo.is_homing() and torpedo.from_submarine, "torpedo is homing and flagged as submarine-launched")
	if torpedo != null:
		check(absf(angle_difference(torpedo.direction.angle(), 0.0)) < 0.2, "launched from the bow tube along the hull axis")
	var hp_before: float = target.hp
	await seconds(0.5)
	check(sub.spotted_by[1], "firing reveals the submarine to the whole enemy team")
	await seconds(2.0)
	check(target.hp < hp_before, "homing torpedoes curve onto an off-axis target")
	await seconds(12.0)
	check(sub.reveal_timer > 0.0 and sub.spotted_by[1], "still revealed just before 15s")
	await seconds(1.0)
	check(sub.reveal_timer <= 0.0, "reveal expires after 15s")
	check(not sub.spotted_by[1], "submarine is hidden again")
	# Stern tube: a target astern launches from the rear.
	var astern: Ship = hull(m, BB, 1, Vector2(600.0, 1000.0))
	await seconds(5.0)
	check(sub.torpedo_ready(), "reloaded after 20s")
	sub.order_torpedo(astern)
	await frames(2)
	var stern_shot: Torpedo = null
	for node: Node in m.projectiles():
		if node is Torpedo:
			stern_shot = node as Torpedo
	check(stern_shot != null and absf(angle_difference(stern_shot.direction.angle(), PI)) < 0.2,
		"astern target is engaged from the stern tube")
	# Homing lasts exactly 2s, then the course locks.
	var runner: Ship = m.spawn_ship(SS, 0, Vector2(2000.0, 300.0))
	var decoy: Ship = hull(m, BB, 1, Vector2(1000.0, 2100.0))
	var free_run: Torpedo = m.spawn_torpedo(runner, Vector2(2000.0, 300.0), 0.0, 6000.0, decoy,
		GameData.balance().sub_homing_time)
	var start_dir: Vector2 = free_run.direction
	await seconds(1.0)
	check(free_run.is_homing() and not free_run.direction.is_equal_approx(start_dir), "steers during the homing ping")
	await seconds(1.1)
	check(not free_run.is_homing(), "homing ends after 2s")
	var locked: Vector2 = free_run.direction
	await seconds(1.0)
	check(is_instance_valid(free_run) and free_run.direction.is_equal_approx(locked), "course is locked after the ping")


func test_11_submarines_cannot_hurt_the_home_base() -> void:
	var m: Match = await start(open_map())
	var base: HomeBase = m.bases[1]
	var sub: Ship = m.spawn_ship(SS, 0, Vector2(600.0, 300.0))
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(600.0, 500.0))
	check_near(base.apply_damage(500.0, false, true), 0.0, "submarine damage to a base is rejected")
	m.spawn_torpedo(sub, base.position + Vector2(-300.0, 0.0), 0.0, 1000.0, null, 0.0)
	await seconds(2.0)
	check_near(base.hp, base.max_hp, "a submarine torpedo crossing the base does nothing")
	check(count_projectiles(m, "Torpedo") == 0, "the torpedo is spent")
	m.spawn_torpedo(dd, base.position + Vector2(-300.0, 0.0), 0.0, 1000.0, null, 0.0)
	await seconds(2.0)
	check_near(base.max_hp - base.hp, GameData.torpedo_damage(), "a destroyer torpedo does full damage to the base")


# --- Carriers ---------------------------------------------------------------

func squadrons_of(m: Match) -> Array[PlaneSquadron]:
	var result: Array[PlaneSquadron] = []
	for node: Node in m.projectiles():
		if node is PlaneSquadron and not node.is_queued_for_deletion():
			result.append(node as PlaneSquadron)
	return result


func test_12_carrier_launches_on_its_own_and_takes_orders() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1500.0, 1200.0), 120.0)
	var m: Match = await start(map)
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	var target: Ship = hull(m, BB, 1, Vector2(2000.0, 1200.0))
	target.max_hp = 100000.0
	target.hp = 100000.0
	var other: Ship = hull(m, BB, 1, Vector2(2000.0, 1500.0))
	other.max_hp = 100000.0
	other.hp = 100000.0
	var scout: Ship = spotter(m, 0, Vector2(1750.0, 1200.0))
	var bomb: float = GameData.bomb_damage()
	check(cv.squadrons_launched == 0, "nothing is in the air before the enemy is spotted")
	var waited: int = 0
	while cv.squadrons_launched == 0 and waited < 60:
		await frames(1)
		waited += 1
	var launched_at: float = m.sim_time
	check(target.spotted_by[0] and other.spotted_by[0] and cv.range_to(target) < cv.stats.plane_range,
		"spotted enemies sit inside plane range")
	check(cv.squadrons_launched == 1 and cv.airborne_squadrons() == 1,
		"the first squadron goes up by itself as soon as an enemy is spotted (got %d)" % cv.squadrons_launched)
	check(cv.strike_target == null and cv.air_target() == target, "the air wing picked the nearest enemy without an order")
	check(not m.has_los(cv.position, target.position), "an island sits between carrier and target")
	check(not cv.has_destination(), "the carrier holds position")
	var first: PlaneSquadron = null
	for squadron: PlaneSquadron in squadrons_of(m):
		first = squadron
	check(first != null, "a plane squadron is airborne")
	if first == null:
		return
	check_near(first.speed, 0.5 * GameData.torpedo_speed(), "squadron flies at 50% torpedo speed")
	check_near(target.base_armor, 0.25, "target has 25% armor")
	waited = 0
	while first.bombs_dropped == 0 and waited < 600:
		await frames(1)
		waited += 1
	check(first.bombs_dropped == 1, "the squadron flies over the island and bombs on arrival")
	check_near(100000.0 - target.hp, bomb, "a bomb run ignores armor entirely", 0.01)
	check(first.position.distance_to(target.position) < 220.0, "the squadron is over its target")
	await seconds(2.8)
	check(first.bombs_dropped == 1, "no second bomb run inside 3s")
	await seconds(0.4)
	check(first.bombs_dropped == 2, "the same squadron bombs again after 3s (got %d)" % first.bombs_dropped)
	# A new squadron every 10 seconds, up to five in the air.
	var launch_times: Array[float] = [launched_at]
	var first_bombs_at_six: int = -1
	waited = 0
	while cv.squadrons_launched < 5 and waited < 3600:
		await frames(1)
		waited += 1
		if cv.squadrons_launched > launch_times.size():
			launch_times.append(m.sim_time)
		if waited == 360:
			first_bombs_at_six = first.bombs_dropped
	check(first_bombs_at_six == 4, "and keeps bombing every 3s while it hovers (got %d)" % first_bombs_at_six)
	check(first.position.distance_to(target.position) < 220.0, "the squadron stays on station over the target")
	check(cv.squadrons_launched == 5 and launch_times.size() == 5, "five squadrons are sent up (got %d)" % cv.squadrons_launched)
	for i: int in range(1, launch_times.size()):
		check_near(launch_times[i] - launch_times[i - 1], 10.0, "squadron %d follows 10s after the one before" % (i + 1), 0.1)
	await seconds(25.0)
	check(cv.squadrons_launched == 5 and cv.airborne_squadrons() == 5 and count_projectiles(m, "PlaneSquadron") == 5,
		"no more than five squadrons fly at once (launched %d)" % cv.squadrons_launched)
	var bombs: int = 0
	for squadron: PlaneSquadron in squadrons_of(m):
		bombs += squadron.bombs_dropped
		check(squadron.position.distance_to(target.position) < 220.0, "every squadron circles the target")
	check(bombs >= 25, "five squadrons keep up continuous bombing (%d runs)" % bombs)
	check_near(100000.0 - target.hp, float(bombs) * bomb, "all damage is bomb runs x bomb damage", 0.01)
	check_near(other.hp, 100000.0, "the air wing stays on the target it chose")
	check(cv.salvos_fired == 0 and cv.torpedoes_launched == 0, "carriers fire no shells or torpedoes")
	check(cv.squadrons_lost == 0, "a hull under construction has no anti-air")
	# An order points the whole air wing at one specific ship.
	check(cv.order_attack(other) and cv.strike_target == other and cv.air_target() == other,
		"right-click attack picks the air wing's target")
	await seconds(6.0)
	check(other.hp < 100000.0, "the squadrons switch to the ordered target")
	var hp_left_alone: float = target.hp
	var hp_before_move: float = other.hp
	cv.order_move(Vector2(900.0, 1300.0))
	check(cv.strike_target == other and cv.priority_target == null, "a move order keeps the ordered strike")
	await seconds(4.0)
	check(other.hp < hp_before_move, "squadrons keep bombing while the carrier repositions")
	check(is_equal_approx(target.hp, hp_left_alone), "the first target is left alone meanwhile")
	# Stop drops the order; the air wing goes back to choosing for itself.
	cv.order_stop()
	check(cv.strike_target == null, "stop drops the ordered strike")
	await seconds(8.0)
	check(cv.air_target() == target and target.hp < hp_left_alone, "the air wing returns to its own choice of target")
	check(cv.airborne_squadrons() == 5, "and the squadrons stay up")
	# With nothing left to see, the squadrons come home.
	scout.kill()
	await seconds(1.0)
	check(cv.air_target() == null, "no target once contact is lost")
	var hp_unseen: float = target.hp
	await seconds(14.0)
	check(cv.airborne_squadrons() == 0 and count_projectiles(m, "PlaneSquadron") == 0,
		"squadrons with nothing to attack fly home and land (still up: %d)" % cv.airborne_squadrons())
	check(is_equal_approx(target.hp, hp_unseen), "no bombs fall on a target nobody sees")
	check(cv.squadrons_lost == 0, "landing is not a loss")


func test_12b_anti_air_shoots_squadrons_down() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	var cruiser: Ship = m.spawn_ship(CA, 1, Vector2(1900.0, 1200.0))
	spotter(m, 0, Vector2(1900.0, 1650.0))
	var ca_stats: ShipStats = GameData.ship(CA)
	var original: float = ca_stats.aa_kill_chance
	check_near(cruiser.aa_kill_chance(), 0.2, "a heavy cruiser shoots down 1 squadron in 5")
	check_near(hull(m, CA, 1, Vector2(3000.0, 400.0)).aa_kill_chance(), 0.0, "a hull under construction has no anti-air")
	check_near(m.bases[1].aa_kill_chance(), 0.0, "the Home Base has no anti-air")
	check_near(m.spawn_ship(DD, 1, Vector2(3000.0, 2000.0)).aa_kill_chance(), 0.0, "destroyers have no anti-air")
	await seconds(1.0)
	check(cruiser.spotted_by[0], "the cruiser is spotted")
	# Certain anti-air: every squadron is lost on its first bomb run - after dropping.
	ca_stats.aa_kill_chance = 1.0
	check(cv.order_strike(cruiser), "strike ordered")
	await seconds(8.0)
	check(cv.squadrons_launched == 1 and cv.squadrons_lost == 1, "the squadron is shot down (lost %d)" % cv.squadrons_lost)
	check(cv.airborne_squadrons() == 0 and count_projectiles(m, "PlaneSquadron") == 0, "a downed squadron is gone")
	check_near(cruiser.max_hp - cruiser.hp, GameData.bomb_damage(), "its bombs still landed, ignoring armor", 0.01)
	await seconds(10.0)
	check(cv.squadrons_launched == 2 and cv.squadrons_lost == 2, "the replacement launched 10s later is lost too (lost %d)" % cv.squadrons_lost)
	check_near(cruiser.max_hp - cruiser.hp, 2.0 * GameData.bomb_damage(), "two bomb runs landed", 0.01)
	# No anti-air: squadrons survive.
	ca_stats.aa_kill_chance = 0.0
	await seconds(14.0)
	check(cv.squadrons_lost == 2 and cv.airborne_squadrons() >= 1, "without anti-air the squadrons survive their runs")
	ca_stats.aa_kill_chance = original
	# The real 1-in-5 chance: count shoot-downs over many bomb runs.
	cruiser.max_hp = 1000000.0
	cruiser.hp = 1000000.0
	var lost_before: int = cv.squadrons_lost
	await seconds(150.0)
	var runs: int = int(round((1000000.0 - cruiser.hp) / GameData.bomb_damage()))
	var downed: int = cv.squadrons_lost - lost_before
	check(runs >= 40, "plenty of bomb runs were flown (%d)" % runs)
	check(downed >= 2 and float(downed) / float(runs) > 0.05 and float(downed) / float(runs) < 0.45,
		"about 1 run in 5 costs a squadron (%d lost in %d runs)" % [downed, runs])
	check(cv.strike_target == cruiser, "the strike continues until told otherwise")


func test_12c_air_strike_ends_with_contact_reach_or_carrier() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	var target: Ship = hull(m, BB, 1, Vector2(1900.0, 1200.0))
	target.max_hp = 100000.0
	target.hp = 100000.0
	var far: Ship = hull(m, BB, 1, Vector2(2900.0, 1900.0))
	far.max_hp = 100000.0
	far.hp = 100000.0
	var scout: Ship = spotter(m, 0, Vector2(1650.0, 1200.0))
	spotter(m, 0, Vector2(2700.0, 1900.0))
	await seconds(1.0)
	check(target.spotted_by[0] and far.spotted_by[0], "both targets are spotted")
	# A strike order alone never moves the carrier, so a target out of reach is refused.
	check(cv.range_to(far) > cv.stats.plane_range * Ship.STRIKE_LEASH, "the far target is beyond plane reach")
	cv.order_strike(far)
	await frames(3)
	check(cv.strike_target == null and cv.air_target() == target, "an ordered strike beyond plane reach is called off")
	check(cv.order_strike(target), "strike ordered on the near target")
	check(not cv.has_destination() and cv.priority_target == null, "a strike order does not move the carrier")
	await seconds(8.0)
	check(cv.airborne_squadrons() == 1 and target.hp < 100000.0, "the squadron is bombing")
	# Lost contact: no blind bombing, no new launches, strike dropped after 10s.
	scout.kill()
	await seconds(1.0)
	check(not target.spotted_by[0], "contact is lost")
	var hp_unseen: float = target.hp
	await seconds(Ship.STRIKE_LOST_TIME - 3.0)
	check(cv.strike_target == target, "the strike holds for a few seconds without contact")
	check(is_equal_approx(target.hp, hp_unseen), "squadrons do not bomb a target nobody can see")
	check(cv.squadrons_launched == 1, "no squadron launches at an unseen target")
	await seconds(4.0)
	check(cv.strike_target == null and cv.air_target() == null, "the strike is called off after 10s without contact")
	await seconds(12.0)
	check(cv.airborne_squadrons() == 0 and count_projectiles(m, "PlaneSquadron") == 0, "the squadron returns and lands")
	# An attack order sails the carrier into reach, then the strike starts.
	check(cv.order_attack(far) and cv.strike_target == far, "attack order on the far target is accepted")
	await seconds(1.0)
	check(cv.has_destination(), "the carrier closes on a target outside plane range")
	var launched_before: int = cv.squadrons_launched
	var waited: int = 0
	while cv.squadrons_launched == launched_before and waited < 3600:
		await frames(1)
		waited += 1
	check(cv.squadrons_launched > launched_before, "squadrons launch once the carrier is in range")
	check(cv.range_to(far) <= cv.stats.plane_range + 5.0, "and not before (range %.0f)" % cv.range_to(far))
	await seconds(9.0)
	check(far.hp < 100000.0 and count_projectiles(m, "PlaneSquadron") >= 1, "the far target is being bombed")
	# A sunk carrier takes its air wing with it.
	var hp_at_loss: float = far.hp
	cv.kill()
	await frames(4)
	check(count_projectiles(m, "PlaneSquadron") == 0, "squadrons are lost with their carrier")
	await seconds(4.0)
	check(is_equal_approx(far.hp, hp_at_loss), "no bombs fall once the carrier is gone")


# --- Vision -----------------------------------------------------------------

func test_13_weather_cuts_spotting_range() -> void:
	var m: Match = await start(open_map())
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(1000.0, 1200.0), 0.0)
	var target: Ship = hull(m, CL, 1, Vector2(1500.0, 1200.0))
	await seconds(0.5)
	check(target.spotted_by[0], "target 500px away is spotted in clear weather")
	var front: WeatherFront = (load(Match.WEATHER_SCENE) as PackedScene).instantiate() as WeatherFront
	front.setup(m, dd.position, 420.0, 0.0)
	m.add_child(front)
	m.fronts.append(front)
	check_near(m.spotting_multiplier_at(dd.position), GameData.balance().weather_spotting_multiplier, "ship is inside the front")
	await seconds(0.5)
	check(not target.spotted_by[0], "inside a cyclone the same target is no longer spotted")
	m.fronts.erase(front)
	front.queue_free()
	await seconds(0.5)
	check(target.spotted_by[0], "spotting recovers once the weather passes")
	check(not m.vision.is_point_in_vision(0, Vector2(3000.0, 300.0)), "unscouted water stays in fog")


# --- Economy, capture, production ------------------------------------------

func test_14_economy_tick_every_15_seconds() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MINOR, Vector2(1400.0, 600.0), 80.0)
	add_island(map, MapData.KIND_MAJOR, Vector2(2600.0, 1800.0), 130.0)
	var m: Match = await start(map)
	m.islands[0].set_owner_team(0)
	m.islands[1].set_owner_team(0)
	var gold0: int = m.economy.gold[0]
	var steel0: int = m.economy.steel[0]
	var gold1: int = m.economy.gold[1]
	var steel1: int = m.economy.steel[1]
	check(m.economy.income_for(0) == Vector2i(100, 80), "home + minor + major income")
	check(m.economy.income_for(1) == Vector2i(50, 20), "home-only income")
	await seconds(14.5)
	check(m.economy.gold[0] == gold0 and m.economy.ticks_paid == 0, "nothing is paid before 15s")
	await seconds(0.6)
	check(m.economy.ticks_paid == 1, "first deposit at 15s")
	check(m.economy.gold[0] - gold0 == 100 and m.economy.steel[0] - steel0 == 80, "team 0 deposit")
	check(m.economy.gold[1] - gold1 == 50 and m.economy.steel[1] - steel1 == 20, "team 1 deposit")
	await seconds(15.0)
	check(m.economy.ticks_paid == 2 and m.economy.gold[0] - gold0 == 200, "second deposit at 30s")
	var before_move: int = m.economy.gold[0]
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(600.0, 300.0))
	dd.order_move(Vector2(1200.0, 300.0))
	await seconds(3.0)
	check(m.economy.gold[0] == before_move, "movement costs nothing")


func test_15_island_capture_and_contest() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MINOR, Vector2(1400.0, 1200.0), 80.0)
	add_island(map, MapData.KIND_MINOR, Vector2(2600.0, 1200.0), 80.0)
	var m: Match = await start(map)
	var a: Island = m.islands[0]
	var b: Island = m.islands[1]
	var capturer: Ship = m.spawn_ship(DD, 0, a.position + Vector2(0.0, 180.0))
	m.spawn_ship(SS, 0, b.position + Vector2(0.0, 180.0))
	m.spawn_ship(SS, 1, b.position + Vector2(0.0, -180.0))
	var capture_time: float = GameData.balance().capture_time
	check_near(capture_time, 30.0, "capture takes 30s")
	await seconds(capture_time - 1.0)
	check(a.owner_team == -1 and a.capture_progress > capture_time - 2.0, "still neutral just before the capture time is up")
	await seconds(1.6)
	check(a.owner_team == 0, "island captured after 30s uncontested")
	check(a.shipyard.team == 0 and a.shipyard.tier == 0, "captured island offers an empty shipyard site")
	check(b.contested and b.owner_team == -1, "island with both teams present is contested and not captured")
	# Recapture wipes the previous owner's shipyard.
	m.economy.set_bank(0, 5000, 5000)
	check(a.shipyard.enqueue_upgrade(), "shipyard construction queued")
	await seconds(20.5)
	check(a.shipyard.tier == 1, "tier 1 shipyard built")
	capturer.kill()
	# An owned island is fortified: sitting on it no longer captures it.
	m.spawn_ship(SS, 1, a.position + Vector2(0.0, -180.0), PI)
	await seconds(capture_time + 3.0)
	check(a.owner_team == 0, "an owned island is not captured by sitting on it")
	check(a.capturing_team == -1 and is_zero_approx(a.capture_progress), "no capture progress builds on an owned island")
	check(a.shipyard.tier == 1, "its shipyard is untouched")


func test_15b_owned_islands_are_fortified() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MINOR, Vector2(1400.0, 1200.0), 80.0)
	add_island(map, MapData.KIND_MAJOR, Vector2(2700.0, 1200.0), 130.0)
	var m: Match = await start(map)
	var balance: GameBalance = GameData.balance()
	var a: Island = m.islands[0]
	var fort: IslandGarrison = a.garrison
	check(fort != null and m.islands[1].garrison != null, "every capturable island has a garrison")
	check(not fort.is_alive(), "a neutral island has no garrison to shoot at")
	check_near(fort.max_hp, balance.minor_garrison_hp, "minor island garrison HP")
	check_near(m.islands[1].garrison.max_hp, balance.major_garrison_hp, "major island garrison HP")
	check(balance.major_garrison_hp > balance.minor_garrison_hp, "major islands are tougher")
	a.set_owner_team(1)
	check(fort.is_alive() and fort.team == 1 and is_equal_approx(fort.hp, fort.max_hp), "captured island gets a full garrison")
	check(fort.is_structure() and not fort.is_home_base(), "a garrison is a structure but not the Home Base")
	m.economy.set_bank(1, 5000, 5000)
	check(a.shipyard.enqueue_upgrade(), "owner builds a shipyard")
	await seconds(20.5)
	check(a.shipyard.tier == 1, "shipyard built")
	var slip_hull: Ship = null
	# Submarines can neither target nor hurt it, like the Home Base.
	var sub: Ship = m.spawn_ship(SS, 0, a.position + Vector2(-500.0, 0.0))
	check(not sub.order_attack(fort), "submarine refuses to attack a garrison")
	check(is_zero_approx(fort.apply_damage(500.0, false, true)), "submarine weapons do no damage to a garrison")
	sub.kill()
	# Unseen it is not fired on; an attack order closes in on it anyway.
	check(not fort.spotted_by[0], "garrison starts unspotted")
	var cl: Ship = m.spawn_ship(CL, 0, a.position + Vector2(0.0, 1100.0), -PI * 0.5)
	check(cl.order_attack(fort), "attack order on an unspotted garrison is accepted")
	var fell_to: int = -2
	var saw_bar_damage: bool = false
	for i: int in 90:
		await seconds(1.0)
		if fort.is_alive() and fort.hp < 600.0 and slip_hull == null:
			# Lay a hull down late enough that it is still on the slip when the island falls.
			if a.shipyard.hull == null:
				a.shipyard.enqueue_ship(DD)
			else:
				slip_hull = a.shipyard.hull
		if fort.is_alive() and fort.hp < fort.max_hp:
			saw_bar_damage = true
			check(a.owner_team == 1, "island stays with its owner while the garrison holds")
		if a.owner_team != 1:
			fell_to = a.owner_team
			break
	check(saw_bar_damage, "shells landing on the island wear the garrison down")
	check(fell_to == -1, "island falls neutral (not to the attacker) when the garrison dies (got %d)" % fell_to)
	check(a.times_fallen == 1 and not fort.is_alive(), "garrison is gone")
	check(a.shipyard.tier == 0 and a.shipyard.queue.is_empty(), "shipyard and queue are lost with the garrison")
	check(slip_hull != null and not slip_hull.is_alive(), "hull on the slip is lost with the garrison")
	check(cl.priority_target == null, "attack order ends when the garrison falls")
	# Now the usual 30 second hold takes it.
	var dd: Ship = m.spawn_ship(DD, 0, a.position + Vector2(0.0, 180.0))
	await seconds(balance.capture_time + 1.0)
	check(a.owner_team == 0, "neutral island is captured with the usual hold")
	check(fort.is_alive() and fort.team == 0 and is_equal_approx(fort.hp, fort.max_hp), "new owner gets a fresh garrison")
	await seconds(6.0)
	check(is_equal_approx(fort.hp, fort.max_hp), "own ships do not shell their own garrison")
	check(dd.is_alive() and cl.is_alive(), "garrisons do not shoot back")
	# Bombs hurt it as well.
	var before: float = fort.hp
	a.set_owner_team(1)
	check(is_equal_approx(fort.apply_damage(balance.bomb_damage, true, false), balance.bomb_damage), "bombs damage a garrison")
	check(before > fort.hp, "garrison HP dropped")


func test_15c_battleships_cannot_target_submarines() -> void:
	check_near(GameData.balance().bomb_damage, 150.0, "squadron bombs do 150 damage")
	check(not GameData.ship(BB).can_target_submarines, "BB data: cannot target submarines")
	for cls: ShipStats.ShipClass in [DD, CL, CA, CV, SS]:
		check(GameData.ship(cls).can_target_submarines, "%s can target submarines" % GameData.ship(cls).display_name)
	var m: Match = await start(open_map())
	var boat: Ship = hull(m, SS, 1, Vector2(1600.0, 1200.0))
	var escort: Ship = hull(m, DD, 1, Vector2(1600.0, 1500.0))
	m.spawn_ship(DD, 0, Vector2(1500.0, 1000.0))
	var bb: Ship = m.spawn_ship(BB, 0, Vector2(1000.0, 1200.0))
	var cl: Ship = m.spawn_ship(CL, 0, Vector2(1200.0, 900.0))
	await seconds(0.5)
	check(boat.spotted_by[0], "the submarine is spotted")
	check(not bb.can_engage(boat) and cl.can_engage(boat), "battleship cannot engage a submarine, a cruiser can")
	check(not bb.order_attack(boat), "battleship refuses an attack order on a submarine")
	check(bb.priority_target == null, "no priority target is set")
	check(bb.order_attack(escort), "battleship still takes orders on surface ships")
	bb.order_stop()
	escort.kill()
	await seconds(0.2)
	check(bb._pick_target(bb.stats.gun_range, true) == null, "battleship guns never pick the submarine")
	check(cl._pick_target(cl.stats.gun_range, true) == boat, "cruiser guns do pick it")


func test_16_shallow_water_restricts_deep_draft_hulls() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MINOR, Vector2(1600.0, 1200.0), 80.0)
	var m: Match = await start(map)
	var island: Island = m.islands[0]
	var inside: Vector2 = island.position + Vector2(0.0, 190.0)
	check(m.nav.is_blocked(inside, false), "shallow water blocks deep-draft navigation")
	check(not m.nav.is_blocked(inside, true), "shallow water is open to DD/SS")
	check(m.nav.is_shallow_water(inside), "nav grid marks the zone as shallow")
	var cl: Ship = m.spawn_ship(CL, 0, Vector2(900.0, 1200.0))
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(900.0, 1300.0))
	var sub: Ship = m.spawn_ship(SS, 0, Vector2(1100.0, 1350.0))
	cl.order_move(inside)
	dd.order_move(inside)
	sub.order_move(inside)
	var cl_closest: float = INF
	# Long enough to sail there and sit out the full capture time.
	for i: int in int(GameData.balance().capture_time) + 14:
		await seconds(1.0)
		cl_closest = minf(cl_closest, cl.position.distance_to(island.position))
	check(cl_closest > island.capture_radius() + 40.0, "cruiser never enters the shallows (closest %.0f)" % cl_closest)
	check(dd.position.distance_to(inside) < 40.0, "destroyer reaches the island")
	check(sub.position.distance_to(inside) < 60.0, "submarine reaches the island")
	check(island.owner_team == 0, "shallow-draft ships capture the Minor island")
	# A route through the shallows is available to a DD but forces a CL to detour.
	var far_side: Vector2 = island.position + Vector2(700.0, 0.0)
	var dd_path: PackedVector2Array = m.nav.find_path(Vector2(900.0, 1200.0), far_side, true)
	var cl_path: PackedVector2Array = m.nav.find_path(Vector2(900.0, 1200.0), far_side, false)
	check(cl_path.size() > dd_path.size(), "cruiser must route around the shallows")


func test_17_shipyard_tiers_gate_ship_classes() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MINOR, Vector2(1400.0, 600.0), 80.0)
	add_island(map, MapData.KIND_MAJOR, Vector2(1800.0, 1700.0), 130.0)
	var m: Match = await start(map)
	m.economy.set_bank(0, 50000, 50000)
	var home: Shipyard = m.bases[0].shipyard
	var minor: Shipyard = m.islands[0].shipyard
	var major: Shipyard = m.islands[1].shipyard
	check(home.tier == 1, "home base starts with a tier 1 yard")
	check(home.can_build_class(DD) and home.can_build_class(SS), "tier 1 builds DD and SS")
	check(home.try_enqueue_ship(CL).contains("Tier 2"), "CL refused at tier 1")
	check(home.try_enqueue_ship(BB).contains("Tier 3"), "BB refused at tier 1")
	check(major.try_enqueue_ship(DD) != "" and major.try_enqueue_upgrade() != "", "neutral island cannot build")
	m.islands[0].set_owner_team(0)
	m.islands[1].set_owner_team(0)
	check(home.enqueue_upgrade(), "home upgrade queued")
	check(minor.enqueue_upgrade(), "minor yard queued")
	check(major.enqueue_upgrade(), "major yard queued")
	await seconds(30.5)
	check(home.tier == 2 and home.can_build_class(CL) and home.can_build_class(CA), "tier 2 unlocks cruisers")
	check(home.try_enqueue_upgrade() != "", "home base cannot reach tier 3")
	check(minor.tier == 1 and not minor.can_upgrade(), "minor island yard caps at tier 1")
	check(major.tier == 1, "major yard at tier 1 after 20s")
	check(major.enqueue_upgrade(), "major tier 2 queued")
	await seconds(30.5)
	check(major.enqueue_upgrade(), "major tier 3 queued")
	await seconds(45.5)
	check(major.tier == 3, "tier 3 shipyard on the deep-water island")
	check(not home.can_build_class(BB) and not home.can_build_class(CV), "capital ships still unavailable at home")
	var gold_before: int = m.economy.gold[0]
	check(major.enqueue_ship(BB), "battleship queued at tier 3")
	check(gold_before == m.economy.gold[0], "nothing is charged when the order is queued")
	await frames(3)
	check(gold_before - m.economy.gold[0] == 800, "battleship cost deducted when the keel is laid")
	check(major.hull != null and major.hull.stats.ship_class == BB, "battleship hull laid down")
	check(not m.nav.is_blocked(major.slip_position, false), "slip is in deep water")
	check(major.cancel_last() == false, "the hull being built cannot be cancelled")
	check(major.enqueue_ship(CV), "carrier queued behind it")
	var gold_mid: int = m.economy.gold[0]
	check(m.economy.gold[0] == gold_mid, "an order waiting in the queue has cost nothing yet")
	check(major.cancel_last() and m.economy.gold[0] == gold_mid and major.queue.size() == 1,
		"a queued order that has not started cancels at no cost")


func test_17b_build_queue_pays_on_start_and_never_idles() -> void:
	var m: Match = await start(open_map())
	var yard: Shipyard = m.bases[0].shipyard
	m.economy.set_bank(0, 150, 75)
	check(yard.enqueue_ship(DD) and yard.enqueue_ship(DD) and yard.enqueue_ship(SS),
		"three ships can be queued with money for only one")
	check(m.economy.gold[0] == 150 and m.economy.steel[0] == 75, "queueing costs nothing")
	check(yard.unpaid_cost() == Vector2i(350, 175), "the yard knows what its queue will cost")
	check(m.fleet_count(0) == 3, "unpaid orders still count toward the fleet cap")
	await frames(2)
	check(yard.hull != null and yard.hull.under_construction and yard.queue[0].paid, "the first hull is laid down at once")
	check(m.economy.gold[0] == 50 and m.economy.steel[0] == 25, "and paid for at that moment")
	check(yard.unpaid_cost() == Vector2i(250, 125) and not yard.waiting_for_resources, "the rest of the queue is unpaid")
	check(yard.can_cancel() and yard.cancel_last() and yard.queue.size() == 2, "an order that has not started can be cancelled")
	check(m.economy.gold[0] == 50 and m.economy.steel[0] == 25, "cancelling it moves no money")
	# First destroyer launches at 15s. The 15s income (50 G / 20 S) leaves 100 G / 45 S:
	# not enough steel for the second, so the yard waits instead of dropping the order.
	await seconds(16.0)
	check(m.ships_of(0).size() == 1, "the first destroyer has launched")
	check(yard.queue.size() == 1 and not yard.queue[0].paid and yard.hull == null, "the second order is still queued")
	check(yard.waiting_for_resources, "the yard reports that it is waiting for resources")
	check(m.economy.gold[0] == 100 and m.economy.steel[0] == 45, "nothing is charged while it waits (%d / %d)" % [
		m.economy.gold[0], m.economy.steel[0]])
	# The 30s income covers it: construction starts by itself.
	await seconds(15.0)
	check(yard.hull != null and yard.queue[0].paid and not yard.waiting_for_resources,
		"construction starts by itself as soon as the bank can cover it")
	check(m.economy.gold[0] == 50 and m.economy.steel[0] == 15, "and is paid for then (%d / %d)" % [
		m.economy.gold[0], m.economy.steel[0]])
	check(yard.queue[0].progress() > 0.02 and yard.queue[0].progress() < 0.12, "it began right after the 30s deposit")
	check(not yard.can_cancel() and not yard.cancel_last(), "a hull that is being built cannot be cancelled")
	# With money in the bank the next keel is laid in the same tick the previous ship launches.
	m.economy.set_bank(0, 5000, 5000)
	check(yard.enqueue_ship(DD), "third destroyer queued behind the one on the slip")
	var handoff: Array[bool] = []
	yard.ship_launched.connect(func(ship: Ship) -> void: handoff.append(
		yard.hull != null and yard.hull != ship and yard.hull.under_construction and yard.queue[0].paid))
	var gold_before: int = m.economy.gold[0]
	await seconds(15.0)
	check(handoff.size() == 1 and handoff[0], "the next hull is on the slip the instant the previous ship launches")
	check(m.ships_of(0).size() == 2, "the second destroyer has launched")
	check(m.economy.gold[0] == gold_before + 50 - 100, "the third destroyer was paid for when it started")
	# Upgrades follow the same rule.
	var bank: Vector2i = Vector2i(m.economy.gold[0], m.economy.steel[0])
	check(yard.enqueue_upgrade(), "upgrade queued behind the hull")
	check(Vector2i(m.economy.gold[0], m.economy.steel[0]) == bank, "an upgrade is not charged when queued")
	check(yard.unpaid_cost() == yard.upgrade_cost(), "its cost is still owed")
	await seconds(15.0)
	check(m.ships_of(0).size() == 3 and yard.queue.size() == 1 and yard.queue[0].is_upgrade and yard.queue[0].paid,
		"the upgrade starts when the ship ahead of it launches")
	check(m.economy.gold[0] == bank.x + 50 - yard.upgrade_cost().x, "and is paid for then")


func test_18_fleet_cap_counts_hulls_and_queue() -> void:
	var m: Match = await start(open_map())
	m.economy.set_bank(0, 99999, 99999)
	for i: int in 28:
		m.spawn_ship(DD, 0, Vector2(600.0 + 90.0 * float(i % 10), 400.0 + 90.0 * float(i / 10)))
	check(m.fleet_count(0) == 28, "28 ships afloat")
	var yard: Shipyard = m.bases[0].shipyard
	check(yard.enqueue_ship(DD), "29th ship queued")
	check(yard.enqueue_ship(DD), "30th ship queued")
	check(m.fleet_count(0) == 30, "queued orders count toward the cap")
	check(yard.try_enqueue_ship(DD).contains("Fleet cap"), "31st ship refused")
	await frames(3)
	check(yard.hull != null and yard.hull.under_construction, "first order has a hull on the slip")
	check(m.fleet_count(0) == 30, "hull under construction + queued order still total 30")
	check(yard.try_enqueue_ship(SS).contains("Fleet cap"), "cap holds while building")
	await seconds(31.0)
	check(m.ships_of(0).size() == 30 and m.fleet_count(0) == 30, "30 combat-ready ships after construction")
	check(not yard.enqueue_ship(DD), "cap holds at 30")
	m.ships_of(0)[0].kill()
	await frames(2)
	check(m.fleet_count(0) == 29 and yard.enqueue_ship(DD), "a loss frees a slot")
	check(m.fleet_count(1) == 0, "the cap is tracked per player")


func test_19_hull_under_construction_is_defenseless() -> void:
	var m: Match = await start(open_map())
	m.economy.set_bank(0, 5000, 5000)
	var yard: Shipyard = m.bases[0].shipyard
	check(yard.enqueue_ship(DD), "destroyer queued")
	await frames(3)
	var slip_hull: Ship = yard.hull
	check(slip_hull != null and slip_hull.under_construction, "hull exists on the map while building")
	var raider: Ship = m.spawn_ship(CL, 1, slip_hull.position + Vector2(330.0, 0.0), PI * 0.5)
	await seconds(8.0)
	check(raider.salvos_fired > 0, "enemy engages the hull on the slip")
	check(slip_hull.salvos_fired == 0 and slip_hull.torpedoes_launched == 0, "hull under construction never returns fire")
	check(slip_hull.position.distance_to(yard.slip_position) < 1.0, "hull under construction cannot move")
	check(raider.hp == raider.max_hp, "raider takes no damage from the hull")
	var expected_hp: float = slip_hull.max_hp * (0.2 + 0.8 * slip_hull.build_progress)
	check(not slip_hull.is_alive() or slip_hull.hp < expected_hp - 20.0, "hull takes damage while defenseless")
	raider.kill()
	await seconds(9.0)
	if slip_hull.is_alive():
		check(not slip_hull.under_construction, "construction completes after the build time")
		await seconds(5.0)
		check(slip_hull.position.distance_to(yard.slip_position) > 30.0, "finished ship clears the slip toward the rally point")
	else:
		check(yard.queue.is_empty() and yard.hull == null, "a hull sunk on the slip forfeits the order")


func test_19b_docks_repair_friendly_ships() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MAJOR, Vector2(1400.0, 600.0), 130.0)
	var m: Match = await start(map, [HUMAN, NONE], true)
	var b: GameBalance = GameData.balance()
	m.economy.set_bank(0, 0, 0)
	var yard: Shipyard = m.bases[0].shipyard
	var dock: Vector2 = yard.dock_point()
	check(yard.slip_position.distance_to(m.bases[0].position) > m.bases[0].radius, "the dock sits in the water off the base")
	check(dock.distance_to(yard.slip_position) < b.dock_radius, "ships sent to the dock gather inside its repair zone")
	var dd: Ship = m.spawn_ship(DD, 0, dock)
	var outside: Ship = m.spawn_ship(DD, 0, yard.slip_position + Vector2(b.dock_radius + 60.0, 0.0))
	var cl: Ship = m.spawn_ship(CL, 0, dock + Vector2(0.0, 80.0))
	var foe: Ship = m.spawn_ship(SS, 1, dock + Vector2(0.0, -80.0))
	for ship: Ship in [dd, outside, cl, foe]:
		ship.hp = ship.max_hp * 0.5
	check(yard.tier == 1 and yard.in_dock(dd) and yard.in_dock(cl) and not yard.in_dock(outside) and not yard.in_dock(foe),
		"dock membership: friendly ships near the slip")
	await seconds(2.0)
	check_near(dd.hp - dd.max_hp * 0.5, 2.0 * b.repair_rate * dd.max_hp, "a docked destroyer regains 2% of its hull per second", 1.0)
	check_near(outside.hp, outside.max_hp * 0.5, "a ship outside the dock is not repaired")
	check_near(cl.hp, cl.max_hp * 0.5, "a Tier 1 yard cannot repair a cruiser it could not build")
	check(yard.repair_block_reason(cl).contains("Tier 2"), "and says why (%s)" % yard.repair_block_reason(cl))
	check(not yard.can_repair(foe), "enemy ships are never repaired")
	check(yard.repairing == 1, "the yard reports one ship under repair (got %d)" % yard.repairing)
	# An order that cannot be paid for does not occupy the yard.
	check(yard.enqueue_ship(DD), "destroyer queued with an empty bank")
	await seconds(1.0)
	check(not yard.is_building() and yard.waiting_for_resources, "the unpaid order has not started")
	var hp_waiting: float = dd.hp
	await seconds(1.0)
	check(dd.hp > hp_waiting, "repairs carry on while the yard only waits for resources")
	# Building stops all repairs.
	m.economy.set_bank(0, 100, 50)
	await frames(3)
	check(yard.is_building() and yard.hull != null, "the yard is now building")
	var hp_building: float = dd.hp
	await seconds(3.0)
	check_near(dd.hp, hp_building, "no repairs while the shipyard is building")
	check(yard.repair_block_reason(dd).contains("building") and yard.repairing == 0, "and the yard says so")
	await seconds(GameData.ship(DD).build_time - 2.0)
	check(not yard.is_building() and yard.queue.is_empty(), "the new destroyer has launched")
	var hp_free: float = dd.hp
	await seconds(1.0)
	check(dd.hp > hp_free, "repairs resume as soon as the slip is free")
	# An upgrade occupies the yard too.
	m.economy.set_bank(0, 5000, 5000)
	check(yard.enqueue_upgrade(), "upgrade queued")
	await frames(3)
	var hp_upgrade: float = dd.hp
	await seconds(1.0)
	check(yard.is_building() and is_equal_approx(dd.hp, hp_upgrade), "no repairs while the yard is being upgraded")
	yard.queue.clear()
	yard.tier = 2
	var bb: Ship = m.spawn_ship(BB, 0, dock + Vector2(80.0, 0.0))
	bb.hp = bb.max_hp * 0.5
	await seconds(2.0)
	check(cl.hp > cl.max_hp * 0.5, "a Tier 2 yard repairs cruisers")
	check_near(bb.hp, bb.max_hp * 0.5, "a battleship in a Tier 2 dock is not repaired")
	check(yard.repair_block_reason(bb).contains("Tier 3"), "and says why (%s)" % yard.repair_block_reason(bb))
	dd.hp = dd.max_hp - 1.0
	await seconds(1.0)
	check_near(dd.hp, dd.max_hp, "repairs stop at full health")
	# Island docks: nothing until a shipyard is built there, then by tier.
	var island: Island = m.islands[0]
	island.set_owner_team(0)
	var island_yard: Shipyard = island.shipyard
	var bb2: Ship = m.spawn_ship(BB, 0, island_yard.dock_point())
	bb2.hp = bb2.max_hp * 0.5
	await seconds(1.0)
	check(island_yard.in_dock(bb2) and is_equal_approx(bb2.hp, bb2.max_hp * 0.5), "an island with no shipyard repairs nothing")
	island_yard.tier = 3
	await seconds(2.0)
	check_near(bb2.hp - bb2.max_hp * 0.5, 2.0 * b.repair_rate * bb2.max_hp, "a Tier 3 dock repairs a battleship", 5.0)
	island.set_owner_team(1)
	await frames(2)
	var hp_lost_island: float = bb2.hp
	await seconds(1.0)
	check_near(bb2.hp, hp_lost_island, "a dock that changed hands repairs nothing for its old owner")
	bb2.kill()
	# Right-click on the dock (or the base itself) sends the selection there.
	var far: Ship = m.spawn_ship(DD, 0, Vector2(1500.0, 1700.0))
	far.hp = far.max_hp * 0.4
	m.camera.position = Vector2(900.0, 1300.0)
	m.camera.zoom = Vector2(0.6, 0.6)
	await seconds(0.3)
	await get_tree().process_frame
	m.player.set_selected_ships([far])
	_click(m, MOUSE_BUTTON_RIGHT, yard.slip_position, true)
	check(far.has_destination() and far.destination().distance_to(yard.slip_position) < b.dock_radius,
		"right-click on the dock sends the ship into it (dest %s)" % far.destination().round())
	check(m.hud.last_notice().contains("Docking at Home Base for repairs"), "HUD confirms (%s)" % m.hud.last_notice())
	far.order_stop()
	_click(m, MOUSE_BUTTON_RIGHT, m.bases[0].position, true)
	check(far.has_destination() and far.destination().distance_to(yard.slip_position) < b.dock_radius,
		"right-click on the base itself docks too")
	m.player.set_selected_ships([bb])
	_click(m, MOUSE_BUTTON_RIGHT, yard.slip_position, true)
	check(m.hud.last_notice().contains("Tier 3"), "HUD warns when the dock cannot repair that ship (%s)" % m.hud.last_notice())
	m.player.set_selected_ships([far])
	await seconds(22.0)
	check(yard.in_dock(far) and far.hp > far.max_hp * 0.4, "the ship arrives and is repaired")
	await get_tree().process_frame
	check(m.hud._info_label.text.contains("In dock at Home Base: repairing +12 HP/s"),
		"HUD shows the repair (%s)" % m.hud._info_label.text.replace("\n", " | "))


# --- Movement ---------------------------------------------------------------

func test_20_pathfinding_routes_around_islands() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1600.0, 1200.0), 160.0)
	add_island(map, MapData.KIND_COVER, Vector2(1600.0, 800.0), 140.0)
	var m: Match = await start(map)
	var goal: Vector2 = Vector2(2400.0, 1200.0)
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(800.0, 1200.0))
	var ca: Ship = m.spawn_ship(CA, 0, Vector2(800.0, 1000.0))
	dd.order_move(goal)
	ca.order_move(goal + Vector2(0.0, -120.0))
	var grounded: bool = false
	for i: int in 45:
		await seconds(1.0)
		for ship: Ship in [dd, ca]:
			for island: Island in m.islands:
				if ship.position.distance_to(island.position) < island.radius:
					grounded = true
	check(not grounded, "ships never cross land")
	check(dd.position.distance_to(goal) < 20.0, "destroyer arrives (%.0f px away)" % dd.position.distance_to(goal))
	check(ca.position.distance_to(goal + Vector2(0.0, -120.0)) < 20.0, "heavy cruiser arrives")
	check(not dd.has_destination(), "ship stops at its destination")
	check_near(GameData.ship_speed(GameData.ship(BB)), 0.3 * GameData.ship_speed(GameData.ship(DD)), "BB at 30% of DD speed")
	# Ordering a move into land resolves to the nearest water.
	dd.order_move(m.islands[0].position)
	await seconds(12.0)
	check(dd.position.distance_to(m.islands[0].position) > m.islands[0].radius, "move order onto land stops at the shore")


func test_21_procedural_maps_are_valid_and_seeded() -> void:
	var cfg: MapConfig = GameData.map_config()
	var layouts: Dictionary[String, bool] = {}
	for seed_value: int in range(1, 13):
		var map: MapData = MapGenerator.generate(seed_value, cfg, GameData.balance().home_base_radius)
		check(MapGenerator.validate(map), "seed %d produces a fully reachable map" % seed_value)
		var minors: int = 0
		var majors: int = 0
		for def: MapData.IslandDef in map.islands:
			if def.kind == MapData.KIND_MINOR:
				minors += 1
			elif def.kind == MapData.KIND_MAJOR:
				majors += 1
			for base_pos: Vector2 in map.base_positions:
				check(def.position.distance_to(base_pos) > def.radius + map.base_radius + 100.0,
					"seed %d keeps islands clear of the bases" % seed_value)
		check(minors == cfg.minor_per_side * 2, "seed %d has %d minor islands" % [seed_value, minors])
		check(majors == cfg.major_per_side * 2 + 1, "seed %d has %d major islands" % [seed_value, majors])
		check(map.base_positions[1].is_equal_approx(map.size - map.base_positions[0]), "bases are mirrored")
		layouts[str(map.islands[1].position) + str(map.base_positions[0])] = true
	check(layouts.size() >= 11, "different seeds give different layouts (%d unique)" % layouts.size())
	check(GameData.map_config_for(MapConfig.Size.MEDIUM) == cfg, "the medium map is the original map")
	check(GameSettings.map_size == MapConfig.Size.MEDIUM, "medium is the default size")
	var first: MapData = MapGenerator.generate(5, cfg, 80.0)
	var second: MapData = MapGenerator.generate(5, cfg, 80.0)
	var same: bool = first.islands.size() == second.islands.size()
	for i: int in mini(first.islands.size(), second.islands.size()):
		same = same and first.islands[i].position.is_equal_approx(second.islands[i].position)
	check(same, "the same seed reproduces the same map")


func test_21b_small_medium_and_large_maps() -> void:
	var small: MapConfig = GameData.map_config_for(MapConfig.Size.SMALL)
	var medium: MapConfig = GameData.map_config_for(MapConfig.Size.MEDIUM)
	var large: MapConfig = GameData.map_config_for(MapConfig.Size.LARGE)
	check(small.map_size.x < medium.map_size.x and medium.map_size.x < large.map_size.x
		and small.map_size.y < medium.map_size.y and medium.map_size.y < large.map_size.y, "small < medium < large")
	check(small.capturable_islands() < medium.capturable_islands() and medium.capturable_islands() < large.capturable_islands(),
		"bigger maps have more islands to capture (%d / %d / %d)" % [small.capturable_islands(),
		medium.capturable_islands(), large.capturable_islands()])
	check(GameSettings.size_from_name("small") == MapConfig.Size.SMALL and GameSettings.size_from_name("LARGE") == MapConfig.Size.LARGE
		and GameSettings.size_from_name("nonsense") == MapConfig.Size.MEDIUM, "size names parse")
	for size: MapConfig.Size in [MapConfig.Size.SMALL, MapConfig.Size.LARGE]:
		var cfg: MapConfig = GameData.map_config_for(size)
		var label: String = GameSettings.size_name(size)
		var short_of_cover: int = 0
		for seed_value: int in range(1, 21):
			var map: MapData = MapGenerator.generate(seed_value, cfg, GameData.balance().home_base_radius)
			check(map.size == cfg.map_size, "%s seed %d has the preset's dimensions" % [label, seed_value])
			check(MapGenerator.validate(map), "%s seed %d produces a fully reachable map" % [label, seed_value])
			var minors: int = 0
			var majors: int = 0
			var covers: int = 0
			for def: MapData.IslandDef in map.islands:
				if def.kind == MapData.KIND_MINOR:
					minors += 1
				elif def.kind == MapData.KIND_MAJOR:
					majors += 1
				else:
					covers += 1
				check(def.position.x > 0.0 and def.position.y > 0.0 and def.position.x < map.size.x and def.position.y < map.size.y,
					"%s seed %d keeps islands on the map" % [label, seed_value])
			# The full island count also proves the generator's emergency fallback map was not used.
			check(minors == cfg.minor_per_side * 2 and majors == cfg.major_per_side * 2 + 1,
				"%s seed %d has every capturable island (%d minor, %d major)" % [label, seed_value, minors, majors])
			if covers < cfg.cover_per_side * 2 - 2:
				short_of_cover += 1
		check(short_of_cover <= 4, "%s maps nearly always fit their cover islands (%d of 20 short)" % [label, short_of_cover])
	# A match on each size boots, and the yards and docks sit in open water.
	for size: MapConfig.Size in [MapConfig.Size.SMALL, MapConfig.Size.LARGE]:
		GameSettings.map_size = size
		var m: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
		m.map_seed = 3
		m.team_control = [NONE, NONE]
		m.create_ui = false
		add_child(m)
		_match = m
		await frames(3)
		check(m.map_data.size == GameData.map_config_for(size).map_size, "the match uses the chosen map size")
		for yard: Shipyard in m.yards:
			check(not m.nav.is_blocked(yard.slip_position, true), "every dock is in the water")
		await _cleanup()
	GameSettings.map_size = MapConfig.Size.MEDIUM


# --- Player input and match flow -------------------------------------------

func _click(m: Match, button: MouseButton, world: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = m.player.world_to_screen(world)
	event.global_position = event.position
	get_viewport().push_input(event, true)


func _drag_to(m: Match, world: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = m.player.world_to_screen(world)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	get_viewport().push_input(event, true)


func test_22_player_input_select_move_attack_build() -> void:
	var m: Match = await start(open_map(), [HUMAN, NONE], true)
	check(m.hud != null and m.player != null and m.camera != null and m.fog != null, "UI is created for a human player")
	var squad: Array[Ship] = []
	for i: int in 3:
		squad.append(m.spawn_ship(DD, 0, Vector2(1500.0 + 60.0 * float(i), 1100.0)))
	var loner: Ship = m.spawn_ship(DD, 0, Vector2(1560.0, 1500.0))
	var carrier: Ship = m.spawn_ship(CV, 0, Vector2(1250.0, 1350.0))
	var enemy: Ship = hull(m, CA, 1, Vector2(1900.0, 1000.0))
	m.camera.position = Vector2(1600.0, 1100.0)
	m.camera.zoom = Vector2.ONE
	await seconds(0.5)
	await get_tree().process_frame
	check(m.player.world_to_screen(Vector2(1600.0, 1100.0)).distance_to(get_viewport().get_visible_rect().size * 0.5) < 2.0,
		"camera centres the requested point")
	# Drag-select the three destroyers.
	_click(m, MOUSE_BUTTON_LEFT, Vector2(1440.0, 1040.0), true)
	_drag_to(m, Vector2(1600.0, 1100.0))
	check(m.player.dragging, "drag box is active while the button is held")
	_drag_to(m, Vector2(1700.0, 1160.0))
	_click(m, MOUSE_BUTTON_LEFT, Vector2(1700.0, 1160.0), false)
	check(m.player.selected_ships.size() == 3, "drag-select picks the ships in the box (got %d)" % m.player.selected_ships.size())
	check(not m.player.selected_ships.has(loner), "ships outside the box are not selected")
	# Right-click water: move.
	_click(m, MOUSE_BUTTON_RIGHT, Vector2(1650.0, 1300.0), true)
	var moving: int = 0
	for ship: Ship in squad:
		if ship.has_destination() and ship.destination().distance_to(Vector2(1650.0, 1300.0)) < 120.0:
			moving += 1
	check(moving == 3, "right-click on water issues a formation move (got %d)" % moving)
	# Right-click a spotted enemy: focus fire.
	check(enemy.spotted_by[0], "enemy is spotted")
	_click(m, MOUSE_BUTTON_RIGHT, enemy.position, true)
	var focused: int = 0
	for ship: Ship in squad:
		if ship.priority_target == enemy:
			focused += 1
	check(focused == 3, "right-click on an enemy sets the priority target (got %d)" % focused)
	# Stop key.
	_key(KEY_X)
	check(squad[0].priority_target == null and not squad[0].has_destination(), "X stops the selection")
	# Single click selects one ship; clicking empty water clears.
	_click(m, MOUSE_BUTTON_LEFT, loner.position, true)
	_click(m, MOUSE_BUTTON_LEFT, loner.position, false)
	check(m.player.selected_ships.size() == 1 and m.player.selected_ships[0] == loner, "click selects a single ship")
	check(loner.selected and not squad[0].selected, "selection flags follow the selection")
	# Enemy ships can never be selected.
	_click(m, MOUSE_BUTTON_LEFT, enemy.position, true)
	_click(m, MOUSE_BUTTON_LEFT, enemy.position, false)
	check(m.player.selected_ships.is_empty(), "enemy ships cannot be selected")
	# Range rings: selected own ships only, or the whole fleet with the top-bar toggle. Never enemies.
	var rival: Ship = m.spawn_ship(DD, 1, Vector2(3600.0, 2000.0))
	check(not m.show_all_ranges and m.hud._ranges_toggle != null and not m.hud._ranges_toggle.button_pressed,
		"the range toggle starts off")
	check(not squad[0].shows_range_rings() and not loner.shows_range_rings(), "unselected ships show no range rings")
	_click(m, MOUSE_BUTTON_LEFT, loner.position, true)
	_click(m, MOUSE_BUTTON_LEFT, loner.position, false)
	check(loner.shows_range_rings() and not squad[0].shows_range_rings(), "a selected ship shows its range rings")
	check(loner.range_rings() == PackedVector2Array([Vector2(480.0, 0.0), Vector2(620.0, 1.0)]),
		"a destroyer has a gun ring and a torpedo ring (%s)" % loner.range_rings())
	check(carrier.range_rings() == PackedVector2Array([Vector2(1300.0, 2.0)]), "a carrier has a plane-range ring")
	check(GameData.ship(SS).gun_mounts == 0 and m.spawn_ship(SS, 0, Vector2(900.0, 700.0)).range_rings()
		== PackedVector2Array([Vector2(900.0, 1.0)]), "a submarine has a torpedo ring only")
	m.hud._ranges_toggle.button_pressed = true
	check(m.show_all_ranges, "the top-bar toggle switches to all ships")
	check(squad[0].shows_range_rings() and carrier.shows_range_rings() and loner.shows_range_rings(),
		"every own ship shows its rings with the toggle on")
	check(not rival.shows_range_rings() and not enemy.shows_range_rings(), "enemy ships never show range rings")
	_key(KEY_R)
	check(not m.show_all_ranges and not squad[0].shows_range_rings() and loner.shows_range_rings(),
		"R switches back to selected ships only")
	await seconds(0.2)
	await get_tree().process_frame
	check(not m.hud._ranges_toggle.button_pressed, "the toggle follows the hotkey")
	rival.kill()
	m.player.clear_selection()
	# Carrier: it launches by itself; select it and right-click an enemy to pick its target.
	check(carrier.squadrons_launched == 1 and carrier.strike_target == null and carrier.air_target() == enemy,
		"the carrier launched by itself (got %d)" % carrier.squadrons_launched)
	var decoy: Ship = hull(m, CA, 1, Vector2(1900.0, 1250.0))
	await seconds(0.4)
	check(decoy.spotted_by[0] and carrier.air_target() == enemy, "the air wing sticks to its target")
	_click(m, MOUSE_BUTTON_LEFT, carrier.position, true)
	_click(m, MOUSE_BUTTON_LEFT, carrier.position, false)
	check(m.player.selected_ships.size() == 1 and m.player.selected_ships[0] == carrier, "click selects the carrier")
	_click(m, MOUSE_BUTTON_RIGHT, decoy.position, true)
	check(carrier.strike_target == decoy and carrier.air_target() == decoy, "right-click on an enemy points the air wing at it")
	await seconds(0.4)
	await get_tree().process_frame
	check(m.hud._info_label.text.contains("Squadrons airborne 1 / 5") and m.hud._info_label.text.contains("Air strike on your target"),
		"HUD shows the air wing (%s)" % m.hud._info_label.text.replace("\n", " | "))
	_key(KEY_X)
	check(carrier.strike_target == null, "X hands the air wing back")
	decoy.kill()
	# Shipyard: select the base, build with the hotkey and with the HUD button.
	_key(KEY_H)
	await get_tree().process_frame
	check(m.player.selected_yard == m.bases[0].shipyard, "H selects the Home Base")
	var gold: int = m.economy.gold[0]
	_key(KEY_1)
	check(m.bases[0].shipyard.queue.size() == 1 and gold == m.economy.gold[0], "hotkey 1 queues a destroyer")
	await frames(2)
	check(gold - m.economy.gold[0] == 100 and m.bases[0].shipyard.hull != null, "it is paid for as its hull is laid down")
	m.hud._on_build_pressed(SS)
	check(m.bases[0].shipyard.queue.size() == 2, "HUD build button queues a submarine")
	m.hud._on_build_pressed(BB)
	check(m.hud.last_notice().contains("Tier 3"), "HUD explains why a build was refused")
	_click(m, MOUSE_BUTTON_RIGHT, Vector2(1000.0, 1200.0), true)
	check(m.bases[0].shipyard.rally_point.distance_to(Vector2(1000.0, 1200.0)) < 40.0, "right-click with a yard selected sets the rally point")
	await seconds(0.3)
	check(m.hud._gold_label.text.contains(str(m.economy.gold[0])), "HUD shows the current bank")
	check(m.hud._fleet_label.text.contains("/ 30"), "HUD shows the fleet cap")
	# Layout regression: the minimap and the selection panel must be fully on screen.
	var screen: Rect2 = get_viewport().get_visible_rect()
	var mini_rect: Rect2 = m.hud._minimap.get_global_rect()
	check(screen.encloses(mini_rect) and mini_rect.size.x > 200.0, "minimap is on screen (%s)" % mini_rect)
	check(mini_rect.end.distance_to(screen.end) < 30.0, "minimap sits in the bottom-right corner")
	var panel_rect: Rect2 = (m.hud._info_label.get_parent().get_parent() as Control).get_global_rect()
	check(screen.encloses(panel_rect), "selection panel is on screen (%s)" % panel_rect)
	check(not panel_rect.intersects(mini_rect), "panel and minimap do not overlap")
	# Clicking the minimap moves the camera to that part of the map.
	var mini_click: InputEventMouseButton = InputEventMouseButton.new()
	mini_click.button_index = MOUSE_BUTTON_LEFT
	mini_click.pressed = true
	mini_click.position = mini_rect.position + mini_rect.size * Vector2(0.75, 0.25)
	mini_click.global_position = mini_click.position
	get_viewport().push_input(mini_click, true)
	var expected_cam: Vector2 = m.map_data.size * Vector2(0.75, 0.25)
	check(m.camera.position.distance_to(expected_cam) < 40.0, "minimap click moves the camera (%s)" % m.camera.position)
	mini_click = mini_click.duplicate() as InputEventMouseButton
	mini_click.pressed = false
	get_viewport().push_input(mini_click, true)
	check(not m.player.dragging, "a minimap click does not start a drag-select")
	m.camera.position = Vector2(1600.0, 1100.0)
	await get_tree().process_frame
	# Fog: the unspotted enemy base is hidden from the local player, own ships are visible.
	check(not m.is_point_visible_to_local(m.bases[1].position, 1), "enemy territory is fogged")
	check(squad[0].visible, "own ships are always drawn")
	var lurker: Ship = m.spawn_ship(DD, 1, Vector2(3600.0, 400.0))
	await seconds(0.5)
	await get_tree().process_frame
	check(not lurker.visible, "unspotted enemy ships are not drawn")


func test_23_destroying_the_home_base_wins() -> void:
	var m: Match = await start(open_map())
	var results: Array[int] = []
	m.match_ended.connect(func(winning_team: int) -> void: results.append(winning_team))
	var base: HomeBase = m.bases[1]
	var bb: Ship = m.spawn_ship(BB, 0, base.position + Vector2(-300.0, 0.0), PI * 0.5)
	base.hp = 3000.0
	await seconds(1.0)
	check(not m.is_over, "match continues while the base stands")
	await seconds(20.0)
	check(not base.is_alive(), "battleship gunfire destroys the base")
	check(m.is_over and m.winner == 0, "destroying the enemy Home Base wins the match")
	check(results.size() == 1 and results[0] == 0, "match_ended is emitted exactly once")
	var salvos: int = bb.salvos_fired
	var time_at_end: float = m.sim_time
	await seconds(20.0)
	check(bb.salvos_fired == salvos and is_equal_approx(m.sim_time, time_at_end), "the simulation stops when the match is over")


func test_24_attack_order_on_an_unspotted_home_base() -> void:
	# Regression: the enemy base starts in fog. Ordering an attack on it must sail the
	# ship there (both sides know where the bases are), not to a bogus last-known point.
	var m: Match = await start(open_map())
	var base: HomeBase = m.bases[1]
	var dd: Ship = m.spawn_ship(DD, 0, base.position + Vector2(-1600.0, 300.0), 0.0)
	var bb: Ship = m.spawn_ship(BB, 0, base.position + Vector2(-1300.0, -300.0), 0.0)
	await seconds(0.5)
	check(not base.spotted_by[0], "enemy base starts unspotted")
	check(dd.order_attack(base) and bb.order_attack(base), "attack order on the known base location is accepted")
	await seconds(2.0)
	check(dd.has_destination() and dd.destination().distance_to(base.position) < 200.0,
		"destroyer heads for the base, not the map origin (dest %s)" % dd.destination().round())
	await seconds(22.0)
	check(base.spotted_by[0], "base is spotted on approach")
	check(dd.salvos_fired > 0, "destroyer opens fire once in range")
	check(base.hp < base.max_hp, "base takes damage")
	check(dd.range_to(base) <= dd.stats.gun_range, "destroyer holds inside gun range")
	dd.kill()
	await seconds(30.0)
	check(bb.salvos_fired > 0, "a lone battleship closes until it can see and shell the base")

func test_25_ai_difficulty_levels() -> void:
	check(GameSettings.difficulty_from_name("easy") == GameSettings.Difficulty.EASY
		and GameSettings.difficulty_from_name("Medium") == GameSettings.Difficulty.MEDIUM
		and GameSettings.difficulty_from_name("hard") == GameSettings.Difficulty.HARD, "difficulty names parse")
	check(GameSettings.ai_difficulty == GameSettings.Difficulty.HARD, "headless default is Hard (the original AI)")
	var easy: int = int(GameSettings.Difficulty.EASY)
	var medium: int = int(GameSettings.Difficulty.MEDIUM)
	var hard: int = int(GameSettings.Difficulty.HARD)
	for pairing: Array in [[medium, easy], [hard, hard]]:
		var levels: Array[int] = [pairing[0], pairing[1]]
		var m: Match = await start(open_map(), [Match.ControlType.AI, Match.ControlType.AI], false, levels)
		check(m.ai_controllers.size() == 2, "two AI controllers")
		for ai: AIController in m.ai_controllers:
			check(int(ai.difficulty) == levels[ai.team], "team %d plays at the requested difficulty" % ai.team)
			check(ai.is_limited() == (levels[ai.team] != hard), "only Easy and Medium are limited")
		var fleets: Array = [[], []]
		for team: int in 2:
			var home: Vector2 = m.bases[team].position
			for i: int in 6:
				fleets[team].append(m.spawn_ship(DD, team, home + Vector2(300.0 if team == 0 else -300.0, -250.0 + 100.0 * float(i))))
		var seen: Array[int] = [0, 0]
		var last_at: Array[float] = [-1000.0, -1000.0]
		var max_in_frame: Array[int] = [0, 0]
		var min_gap: Array[float] = [INF, INF]
		for frame: int in 60 * 40:
			await get_tree().physics_frame
			for ai: AIController in m.ai_controllers:
				var sent: int = ai.orders_sent - seen[ai.team]
				if sent <= 0:
					continue
				seen[ai.team] = ai.orders_sent
				max_in_frame[ai.team] = maxi(max_in_frame[ai.team], sent)
				min_gap[ai.team] = minf(min_gap[ai.team], m.sim_time - last_at[ai.team])
				last_at[ai.team] = m.sim_time
		for ai: AIController in m.ai_controllers:
			var name: String = GameSettings.difficulty_name(ai.difficulty)
			check(seen[ai.team] > 0, "%s AI gives orders (%d)" % [name, seen[ai.team]])
			if ai.is_limited():
				check(max_in_frame[ai.team] == 1, "%s AI orders one ship at a time" % name)
				check(min_gap[ai.team] >= ai.order_interval() - 0.05,
					"%s AI waits %.0fs between ship orders (min gap %.2fs)" % [name, ai.order_interval(), min_gap[ai.team]])
				var reached: int = 0
				for ship: Ship in fleets[ai.team]:
					if ai._last_ordered.has(ship):
						reached += 1
				check(reached == 6, "%s AI gets round to every ship (%d / 6)" % [name, reached])
			else:
				check(max_in_frame[ai.team] >= 6, "Hard AI orders its whole fleet at once (%d in one think)" % max_in_frame[ai.team])
		await _cleanup()
