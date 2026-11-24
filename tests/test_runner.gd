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
const BC: ShipStats.ShipClass = ShipStats.ShipClass.BC
const SBB: ShipStats.ShipClass = ShipStats.ShipClass.SBB
const RS: ShipStats.ShipClass = ShipStats.ShipClass.RS
const RD: ShipStats.ShipClass = ShipStats.ShipClass.RD
const LCV: ShipStats.ShipClass = ShipStats.ShipClass.LCV
const CLAA: ShipStats.ShipClass = ShipStats.ShipClass.CLAA

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


func start(map: MapData, control: Array[int] = [NONE, NONE], ui: bool = false, levels: Array[int] = [],
		alliances: Array[int] = []) -> Match:
	var m: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	m.map_override = map
	m.alliance = alliances
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
		# Build times are half the original roster's; CA through SBB sail 1.5x faster, then
		# CA -15% and BC / BB / SBB -5%.
		DD: ["DD", 100, 50, 7.5, 1.0, 0.0, 4.0, 1],
		SS: ["SS", 150, 75, 10.0, 0.5, 0.0, 20.0, 1],
		CL: ["CL", 250, 150, 15.0, 0.7, 0.05, 4.0, 2],
		CA: ["CA", 400, 250, 22.5, 0.6375, 0.15, 5.333, 2],
		BB: ["BB", 800, 600, 45.0, 0.4275, 0.25, 8.0, 3],
		CV: ["SCV", 1500, 600, 60.0, 0.9, 0.0, 10.0, 3],
		BC: ["BC", 650, 450, 37.5, 0.513, 0.2, 8.0, 3],
		SBB: ["SBB", 1040, 780, 58.5, 0.38475, 0.3, 11.0, 3],
		RS: ["RS", 250, 150, 15.0, 0.5, 0.0, 4.0, 1],
		RD: ["RD", 150, 75, 10.0, 0.8, 0.0, 4.0, 1],
		LCV: ["LCV", 500, 200, 30.0, 0.9, 0.0, 10.0, 2],
		CLAA: ["CLAA", 400, 250, 15.0, 0.7, 0.05, 4.0, 2],
	}
	check(GameData.all_classes().size() == expected.size(), "every class is in the roster")
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
	check(dd.gun_mounts == 4 and dd.shells_per_mount == 1, "DD 4x single (Benson layout)")
	check(cl.gun_mounts == 3 and cl.shells_per_mount == 3, "CL 3x triple")
	check(ca.gun_mounts == 4 and ca.shells_per_mount == 2, "CA 4x double")
	check(bb.gun_mounts == 3 and bb.shells_per_mount == 2, "BB 3x double")
	check(not ss.has_guns() and ss.torpedo_mode == ShipStats.TorpedoMode.MANUAL_BOW_STERN, "SS torpedoes only, manual")
	check_near(ss.torpedo_interval, 20.0, "SS torpedo reload")
	check(dd.torpedo_mode == ShipStats.TorpedoMode.AUTO_BROADSIDE, "DD auto broadside torpedoes")
	check_near(dd.torpedo_interval, 30.0, "DD torpedo cooldown")
	check(not cv.has_guns() and cv.torpedo_mode == ShipStats.TorpedoMode.NONE and cv.has_planes(), "CV planes only")
	check_near(cv.plane_interval, 3.333, "Supercarrier sends a dive-bomber squadron every 3.3s (5s cut by a third)", 0.01)
	check_near(cv.bomb_damage_multiplier, 1.1, "Supercarrier bombs hit 10% harder")
	check(cv.torpedo_flights_per_launch == 3 and cv.torpedo_flights_per_target == 3, "Supercarrier sends 3 torpedo flights, up to 3 per target")
	check(cv.squadrons_per_target == 5 and cv.max_total_squadrons == 0 and cv.squadrons_per_launch == 1,
		"Supercarrier stacks up to 5 dive-bomber squadrons on each target, with no overall cap")
	var lcv: ShipStats = GameData.ship(LCV)
	check_near(lcv.plane_interval, 5.0, "Light Carrier keeps 5s dive bombers")
	check(lcv.torpedo_flights_per_launch == 1 and lcv.max_torpedo_bombers == 1, "Light Carrier: one torpedo flight at a time")
	check_near(lcv.bomb_damage_multiplier, 1.0, "Light Carrier bombs are standard")
	check(lcv.max_total_squadrons == 5 and lcv.max_squadrons == 5, "Light Carrier has at most 5 squadrons up")
	check_near(lcv.plane_range, cv.plane_range * 0.5, "Light Carrier plane range is half the Supercarrier's")
	check(lcv.has_torpedo_bombers() and lcv.has_depth_bombers(), "Light Carrier flies all three roles")
	check(not ShipStats.is_capital_class(LCV), "torpedo bombers do not go after a Light Carrier")
	check(cv.has_torpedo_bombers() and absf(cv.torpedo_bomber_interval - 6.667) < 0.01, "CV torpedo bombers every 6.7s")
	check(cv.has_depth_bombers() and is_equal_approx(cv.depth_bomber_interval, 2.0), "CV depth-charge bombers every 2s")
	check_near(cv.plane_range, 1300.0 * 1.3 * 1.2, "Supercarrier plane range: +30%, then +20%")
	check(ss.torpedoes_per_launch == 3, "SS launches 3 torpedoes")
	for cls: ShipStats.ShipClass in [BC, BB, SBB, CV]:
		check(ShipStats.is_capital_class(cls), "%s may be attacked by torpedo bombers" % GameData.ship(cls).code)
	for cls: ShipStats.ShipClass in [DD, SS, CL, CA, RS, RD]:
		check(not ShipStats.is_capital_class(cls), "%s is too small for torpedo bombers" % GameData.ship(cls).code)
	var rs: ShipStats = GameData.ship(RS)
	var rd: ShipStats = GameData.ship(RD)
	check(rs.is_support() and rd.is_support() and rs.mines_islands and not rd.mines_islands, "RS and RD are unarmed support hulls")
	check(rs.gold_cost == cl.gold_cost and rs.steel_cost == cl.steel_cost, "a Resource Ship costs as much as a CL")
	check(rs.max_hp <= 100.0, "a Resource Ship has almost no HP")
	check(rd.gold_cost == ss.gold_cost and rd.steel_cost == ss.steel_cost, "a Radar Ship costs as much as a SS")
	check_near(rd.spotting_range, dd.spotting_range * 1.5, "a Radar Ship spots 1.5x as far as a DD")
	check_near(rd.max_hp, dd.max_hp * 0.5, "a Radar Ship has half a DD's HP")
	check(not rd.detects_submarines, "Radar Ships spot surface ships only")
	check(GameData.ship(CV).display_name == "Supercarrier", "the heavy carrier is the Supercarrier (SCV)")
	# AA Cruiser: a Light Cruiser with its guns traded for flak, at a Heavy Cruiser's price.
	var claa: ShipStats = GameData.ship(CLAA)
	check(not claa.has_guns() and not claa.has_planes() and not claa.is_support(), "AA Cruiser: no guns, but a warship")
	check(claa.max_hp == cl.max_hp and claa.speed_factor == cl.speed_factor and claa.base_armor == cl.base_armor \
		and claa.spotting_range == cl.spotting_range and claa.hull_length == cl.hull_length, "AA Cruiser has a CL's stats")
	check(claa.gold_cost == ca.gold_cost and claa.steel_cost == ca.steel_cost, "an AA Cruiser costs as much as a CA")
	check_near(claa.periodic_aa_chance, 1.0 / 3.0, "AA Cruiser flak downs a squadron 1 time in 3", 0.001)
	check_near(claa.periodic_aa_interval, 3.0, "AA Cruiser flak every 3s")
	check_near(claa.periodic_aa_range, cl.gun_range * 0.5, "AA Cruiser flak reaches half a CL's gun range")
	check(not ShipStats.is_capital_class(CLAA), "torpedo bombers ignore AA Cruisers")
	# Shop and hotkey order: smallest hulls first, radar / resource ships / destroyers at the
	# small end, carriers at the big end.
	var order: Array[ShipStats.ShipClass] = GameData.all_classes()
	check(order.slice(0, 3) == [RD, RS, DD], "the shop starts with RD, RS, DD (%s)" % [order])
	check(order.slice(order.size() - 2) == [LCV, CV], "the shop ends with the carriers")
	check(order.size() == PlayerController.BUILD_KEYS.size(), "every class has a build hotkey")
	check_near(dd.torpedo_speed_scale, 0.5, "DD torpedoes run at half the standard torpedo speed")
	check_near(ss.torpedo_speed_scale, 1.0, "SS torpedoes run at the standard torpedo speed")
	for cls: ShipStats.ShipClass in [CL, CA, BB, BC, SBB]:
		check_near(GameData.ship(cls).aa_kill_chance, 0.2, "%s anti-air downs 1 squadron in 5" % GameData.ship(cls).code)
	for cls: ShipStats.ShipClass in [DD, SS, CV]:
		check_near(GameData.ship(cls).aa_kill_chance, 0.0, "%s has no anti-air" % GameData.ship(cls).code)
	# Cruisers must out-gun destroyers ship for ship and for the same money.
	check(cl.gun_dps() > dd.gun_dps() * 3.0 and ca.gun_dps() > cl.gun_dps(), "cruiser gun damage is well above a destroyer's")
	check(cl.gun_dps() / float(cl.gold_cost) > dd.gun_dps() / float(dd.gold_cost),
		"a CL does more gun damage per gold than a DD")
	check(ca.gun_dps() > dd.gun_dps() * 3.0, "a CA out-guns three destroyers")
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
	# Super Battleship and Battlecruiser are defined relative to the Battleship.
	var sbb: ShipStats = GameData.ship(SBB)
	var bc: ShipStats = GameData.ship(BC)
	check_near(sbb.speed_factor, bb.speed_factor * 0.9, "SBB is 10% slower than a BB")
	check_near(sbb.shell_damage, bb.shell_damage * 1.3, "SBB shells hit 30% harder")
	check_near(sbb.fire_interval, bb.fire_interval + 3.0, "SBB reloads 3s slower than a BB")
	check_near(sbb.base_armor, 0.3, "SBB armor 30%")
	check(sbb.gold_cost == roundi(bb.gold_cost * 1.3) and sbb.steel_cost == roundi(bb.steel_cost * 1.3), "SBB costs 30% more than a BB")
	check_near(sbb.max_hp, bb.max_hp * 1.1, "SBB has 10% more HP")
	check_near(sbb.periodic_aa_chance, 0.4, "SBB flak downs a squadron 2 times in 5")
	check_near(sbb.periodic_aa_interval, 10.0, "SBB flak fires every 10s")
	check(not sbb.can_target_submarines and not bc.can_target_submarines, "SBB and BC cannot target submarines")
	check_near(bc.base_armor, 0.2, "BC armor 20%")
	check_near(bc.speed_factor, bb.speed_factor * 1.2, "BC is 20% faster than a BB")
	check_near(bc.fire_interval, bb.fire_interval, "BC reloads like a BB")
	check(bc.gun_mounts == 4 and bc.shells_per_mount == 4, "BC 4x quad")
	check_near(bc.shell_damage, bb.shell_damage * 0.4, "BC shells do 60% less damage than a BB's")
	check_near(bc.max_hp, bb.max_hp * 0.8, "BC has 20% less HP")
	for cls: ShipStats.ShipClass in [DD, SS, CL, CA, BB, BC, CV]:
		check(not GameData.ship(cls).has_periodic_aa(), "%s has no flak barrage" % GameData.ship(cls).code)
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
	check(resources.size() == 16, "found all data resources (%d)" % resources.size())
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
	# Main turrets only: the target is inside secondary range (test_31 covers secondaries).
	bb.stats = bb.stats.duplicate() as ShipStats
	bb.stats.secondary_mounts = 0
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
	check(sub.torpedoes_launched == 3, "three torpedoes launch on command (got %d)" % sub.torpedoes_launched)
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
	# Homing lasts exactly 2s against anything but a battleship, then the course locks.
	var runner: Ship = m.spawn_ship(SS, 0, Vector2(2000.0, 300.0))
	var decoy: Ship = hull(m, CA, 1, Vector2(1000.0, 2100.0))
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
	# Against Battleships and Super Battleships the torpedoes track far more closely.
	var b: GameBalance = GameData.balance()
	for cls: ShipStats.ShipClass in [BB, SBB]:
		var big: Ship = hull(m, cls, 1, Vector2(1000.0, 2100.0))
		var tracker: Torpedo = m.spawn_torpedo(runner, Vector2(2000.0, 300.0), 0.0, 6000.0, big, b.sub_homing_time)
		check_near(tracker.homing_time_left, b.sub_battleship_homing_time, "%s: torpedoes home for longer" % big.stats.code)
		check_near(tracker.homing_turn_rate, deg_to_rad(b.sub_battleship_homing_turn_deg), "%s: and turn harder" % big.stats.code)
		tracker.queue_free()
		big.kill()
	var bc_target: Ship = hull(m, BC, 1, Vector2(1000.0, 2000.0))
	var bc_shot: Torpedo = m.spawn_torpedo(runner, Vector2(2000.0, 300.0), 0.0, 6000.0, bc_target, b.sub_homing_time)
	check_near(bc_shot.homing_time_left, b.sub_homing_time, "a Battlecruiser gets the normal homing ping")
	check_near(bc_shot.homing_turn_rate, deg_to_rad(b.torpedo_homing_turn_deg), "and the normal turn rate")
	bc_shot.queue_free()
	bc_target.kill()
	# A battleship steaming across the torpedo's path is followed; a heavy cruiser is missed.
	var dodger: Ship = m.spawn_ship(BB, 1, Vector2(2600.0, 1300.0), 0.0)
	var dodger_ca: Ship = m.spawn_ship(CA, 1, Vector2(1400.0, 1300.0), 0.0)
	for ship: Ship in [dodger, dodger_ca]:
		ship.max_hp = 100000.0
		ship.hp = 100000.0
	var at_bb: Torpedo = m.spawn_torpedo(runner, Vector2(2600.0, 700.0), PI * 0.5, 3000.0, dodger, b.sub_homing_time)
	var at_ca: Torpedo = m.spawn_torpedo(runner, Vector2(1400.0, 700.0), PI * 0.5, 3000.0, dodger_ca, b.sub_homing_time)
	at_bb.damage = 1.0
	at_ca.damage = 1.0
	dodger.order_move(Vector2(3600.0, 1300.0))
	dodger_ca.order_move(Vector2(2400.0, 1300.0))
	await seconds(10.0)
	check(dodger.hp < 100000.0, "a torpedo follows a battleship that steams across its path")
	check(is_equal_approx(dodger_ca.hp, 100000.0), "a heavy cruiser doing the same is missed")


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

## Turns a carrier's torpedo and depth-charge bombers off (or back on) so a test can count
## dive-bomber squadrons alone.
func dive_bombers_only(only: bool) -> void:
	for cls: ShipStats.ShipClass in [CV, LCV]:
		var cv: ShipStats = GameData.ship(cls)
		cv.torpedo_bomber_interval = 0.0 if only else (6.667 if cls == CV else 10.0)
		cv.depth_bomber_interval = 0.0 if only else (2.0 if cls == CV else 3.0)


func squadrons_of(m: Match) -> Array[PlaneSquadron]:
	var result: Array[PlaneSquadron] = []
	for node: Node in m.projectiles():
		if node is PlaneSquadron and not node.is_queued_for_deletion():
			result.append(node as PlaneSquadron)
	return result


func test_12_carrier_launches_on_its_own_and_takes_orders() -> void:
	dive_bombers_only(true)
	await _carrier_dive_bombers()
	dive_bombers_only(false)


## Light Carrier: at most 5 squadrons in the air, so the whole wing works one target.
func _carrier_dive_bombers() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1350.0, 1200.0), 100.0)
	var m: Match = await start(map)
	var cv: Ship = m.spawn_ship(LCV, 0, Vector2(1000.0, 1200.0))
	var target: Ship = hull(m, BB, 1, Vector2(1800.0, 1200.0))
	target.max_hp = 100000.0
	target.hp = 100000.0
	var other: Ship = hull(m, BB, 1, Vector2(1800.0, 1450.0))
	other.max_hp = 100000.0
	other.hp = 100000.0
	var scout: Ship = spotter(m, 0, Vector2(1600.0, 1200.0))
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
	# A new squadron every 5 seconds, up to five in the air.
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
	# The fifth goes up 4 x 5s after the first (the loop sees that launch on its frame).
	check_near(launch_times[launch_times.size() - 1] - launched_at, 20.0, "a squadron follows every 5s", 0.1)
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
	# Stop drops the order; the air wing goes back to choosing for itself (squadrons on a
	# live target in reach stay on it).
	cv.order_stop()
	check(cv.strike_target == null, "stop drops the ordered strike")
	var hp_after_stop: float = other.hp
	await seconds(8.0)
	check(cv.air_target() == target, "the air wing goes back to its own choice of target")
	check(other.hp < hp_after_stop, "squadrons already on a live target keep at it")
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
	var cv: Ship = m.spawn_ship(LCV, 0, Vector2(1000.0, 1200.0))
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
	var waited: int = 0
	while cv.squadrons_lost < 1 and waited < 600:
		await frames(1)
		waited += 1
	check(cv.squadrons_launched == 1 and cv.squadrons_lost == 1, "the squadron is shot down (lost %d)" % cv.squadrons_lost)
	check(cv.airborne_squadrons() == 0 and count_projectiles(m, "PlaneSquadron") == 0, "a downed squadron is gone")
	check_near(cruiser.max_hp - cruiser.hp, GameData.bomb_damage(), "its bombs still landed, ignoring armor", 0.01)
	waited = 0
	while cv.squadrons_lost < 2 and waited < 600:
		await frames(1)
		waited += 1
	check(cv.squadrons_launched == 2 and cv.squadrons_lost == 2, "the replacement launched 5s later is lost too (lost %d)" % cv.squadrons_lost)
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
	dive_bombers_only(true)
	await _carrier_strike_limits()
	dive_bombers_only(false)


func _carrier_strike_limits() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	var target: Ship = hull(m, BB, 1, Vector2(1900.0, 1200.0))
	target.max_hp = 100000.0
	target.hp = 100000.0
	var far: Ship = hull(m, BB, 1, Vector2(3700.0, 2100.0))
	far.max_hp = 100000.0
	far.hp = 100000.0
	var scout: Ship = spotter(m, 0, Vector2(1650.0, 1200.0))
	spotter(m, 0, Vector2(3500.0, 2100.0))
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
	check(cv.airborne_squadrons() >= 1 and target.hp < 100000.0, "the squadrons are bombing")
	# Lost contact: no blind bombing, no new launches, strike dropped after 10s.
	scout.kill()
	await seconds(1.0)
	check(not target.spotted_by[0], "contact is lost")
	var launched_unseen: int = cv.squadrons_launched
	var hp_unseen: float = target.hp
	await seconds(Ship.STRIKE_LOST_TIME - 3.0)
	check(cv.strike_target == target, "the strike holds for a few seconds without contact")
	check(is_equal_approx(target.hp, hp_unseen), "squadrons do not bomb a target nobody can see")
	check(cv.squadrons_launched == launched_unseen, "no squadron launches at an unseen target")
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
	waited = 0
	while far.hp >= 100000.0 and waited < 60 * 40:
		await frames(1)
		waited += 1
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
		if fort.is_alive() and fort.hp < 350.0 and slip_hull == null:
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
	check(gold_before - m.economy.gold[0] == 800, "the full cost is charged when the order is queued")
	await frames(3)
	check(major.hull != null and major.hull.stats.ship_class == BB, "battleship hull laid down")
	check(not m.nav.is_blocked(major.slip_position, false), "slip is in deep water")
	check(major.enqueue_ship(CV), "carrier queued behind it")
	var gold_mid: int = m.economy.gold[0]
	check(major.cancel_last() and m.economy.gold[0] == gold_mid + 1500 and major.queue.size() == 1,
		"cancelling a queued order refunds its full cost")


func test_17b_build_queue_pays_when_queued_and_never_idles() -> void:
	var m: Match = await start(open_map())
	var yard: Shipyard = m.bases[0].shipyard
	m.economy.set_bank(0, 250, 125)
	check(yard.enqueue_ship(DD) and yard.enqueue_ship(SS), "two ships queued with the money for both")
	check(m.economy.gold[0] == 0 and m.economy.steel[0] == 0, "both are paid for in full when queued")
	check(yard.try_enqueue_ship(DD).contains("Not enough"), "an order the bank cannot cover is refused")
	check(yard.queue.size() == 2 and m.fleet_count(0) == 2, "only the paid orders are queued")
	check(yard.hull != null and yard.hull.under_construction and yard.queue[0].paid, "the first hull is laid down at once")
	check(yard.unpaid_cost() == Vector2i.ZERO and not yard.waiting_for_resources, "nothing is owed")
	check(yard.can_cancel() and yard.cancel_last() and yard.queue.size() == 1, "the last order can be cancelled")
	check(m.economy.gold[0] == 150 and m.economy.steel[0] == 75, "and is refunded in full")
	# The next keel is laid in the same tick the previous ship launches.
	check(yard.enqueue_ship(SS), "submarine queued behind the destroyer on the slip")
	var handoff: Array[bool] = []
	yard.ship_launched.connect(func(ship: Ship) -> void: handoff.append(
		yard.hull != null and yard.hull != ship and yard.hull.under_construction and yard.queue[0].paid))
	await seconds(GameData.ship(DD).build_time + 0.5)
	check(m.ships_of(0).size() == 1, "the destroyer launched after its (halved) build time")
	check(handoff.size() == 1 and handoff[0], "the next hull is on the slip the instant the previous ship launches")
	# Upgrades are paid when queued and refunded when cancelled, too.
	m.economy.set_bank(0, 5000, 5000)
	var cost: Vector2i = yard.upgrade_cost()
	check(yard.enqueue_upgrade(), "upgrade queued behind the hull")
	check(m.economy.gold[0] == 5000 - cost.x and m.economy.steel[0] == 5000 - cost.y, "the upgrade is charged when queued")
	var gold_before: int = m.economy.gold[0]
	check(yard.cancel_last() and m.economy.gold[0] == gold_before + cost.x and yard.queue.size() == 1,
		"a cancelled upgrade is refunded")
	# Cancelling the order under construction scraps its hull and refunds it.
	var slip_hull: Ship = yard.hull
	gold_before = m.economy.gold[0]
	check(yard.cancel_last() and yard.queue.is_empty() and yard.hull == null, "the hull being built can be cancelled")
	check(m.economy.gold[0] == gold_before + GameData.ship(SS).gold_cost, "and its full cost comes back")
	check(not slip_hull.is_alive() and not m.ships.has(slip_hull), "the unfinished hull is removed from the sea")


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
	# An order that cannot be paid for is refused and does not occupy the yard.
	check(not yard.enqueue_ship(DD), "a destroyer cannot be queued with an empty bank")
	var hp_waiting: float = dd.hp
	await seconds(1.0)
	check(not yard.is_building() and dd.hp > hp_waiting, "repairs carry on while the yard is idle")
	# Building stops all repairs.
	m.economy.set_bank(0, 100, 50)
	check(yard.enqueue_ship(DD), "destroyer queued once it can be paid for")
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
	# Arrival radius plus the few pixels the swell rocks a ship about.
	check(dd.position.distance_to(goal) < 32.0, "destroyer arrives (%.0f px away)" % dd.position.distance_to(goal))
	check(ca.position.distance_to(goal + Vector2(0.0, -120.0)) < 20.0, "heavy cruiser arrives")
	check(not dd.has_destination(), "ship stops at its destination")
	check_near(GameData.ship_speed(GameData.ship(BB)), 0.4275 * GameData.ship_speed(GameData.ship(DD)), "BB at 42.75% of DD speed")
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


func test_21c_maps_for_three_and_four_players() -> void:
	var base_radius: float = GameData.balance().home_base_radius
	for size: MapConfig.Size in [MapConfig.Size.SMALL, MapConfig.Size.MEDIUM, MapConfig.Size.LARGE]:
		var cfg: MapConfig = GameData.map_config_for(size)
		var label: String = GameSettings.size_name(size)
		check(cfg.size_for(2).x < cfg.size_for(3).x and cfg.size_for(3).x < cfg.size_for(4).x,
			"%s: the sea grows with the number of players" % label)
		for players: int in [3, 4]:
			for seed_value: int in range(1, 5):
				var map: MapData = MapGenerator.generate(seed_value, cfg, base_radius, players)
				var tag: String = "%s, %d players, seed %d" % [label, players, seed_value]
				check(map.circular and map.size == cfg.size_for(players), "%s: round sea of the right size" % tag)
				check(map.base_positions.size() == players, "%s: one Home Base per player" % tag)
				check(MapGenerator.validate(map), "%s: everything is reachable" % tag)
				var step: float = TAU / float(players)
				var arm: Vector2 = map.base_positions[0] - map.center()
				var minors: int = 0
				var majors: int = 0
				for i: int in map.base_positions.size():
					check(map.base_positions[i].distance_to(map.center() + arm.rotated(step * float(i))) < 1.0,
						"%s: bases are spaced evenly round the rim" % tag)
				for def: MapData.IslandDef in map.islands:
					if def.kind == MapData.KIND_MINOR:
						minors += 1
					elif def.kind == MapData.KIND_MAJOR:
						majors += 1
					check(map.contains(def.position, def.radius), "%s: islands lie inside the sea" % tag)
					for base_pos: Vector2 in map.base_positions:
						check(def.position.distance_to(base_pos) > def.radius + map.base_radius + 100.0,
							"%s: islands keep clear of the bases" % tag)
				check(minors == cfg.minor_per_side * players and majors == cfg.major_per_side * players + 1,
					"%s: every player gets the same islands (%d minor, %d major)" % [tag, minors, majors])
	# A four-sided match boots with a base, a bank and a dock for everyone.
	var m: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	m.map_seed = 3
	m.team_control = [NONE, NONE, NONE, NONE]
	m.create_ui = false
	add_child(m)
	_match = m
	await frames(3)
	check(m.team_count == 4 and m.bases.size() == 4, "four sides, four Home Bases")
	for team: int in 4:
		check(m.bases[team].team == team and m.economy.gold[team] == GameData.balance().start_gold,
			"side %d has its own base and starting bank" % team)
		check(not m.nav.is_blocked(m.bases[team].shipyard.slip_position, true), "side %d's dock is in the water" % team)


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
			check(map.size == cfg.size_for(2) and map.circular, "%s seed %d has the preset's dimensions" % [label, seed_value])
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
				check(map.contains(def.position, def.radius), "%s seed %d keeps islands on the map" % [label, seed_value])
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
		check(m.map_data.size == GameData.map_config_for(size).size_for(2), "the match uses the chosen map size")
		check(m.nav.is_blocked(Vector2(40.0, 40.0), true) and not m.nav.is_blocked(m.map_data.center() + Vector2(0.0, 300.0), true),
			"the corners outside the round sea are closed to ships")
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
	check(m.order_feedback != null and m.order_feedback.active_count() == 1, "a move order shows an impact ripple")
	var water_screen: Vector2 = m.player.world_to_screen(Vector2(1650.0, 1300.0))
	check(m.player.wanted_cursor(water_screen) == PlayerController.CursorMode.MOVE,
		"with ships selected the cursor is the move arrow over water")
	check(m.player.wanted_cursor(m.player.world_to_screen(enemy.position)) == PlayerController.CursorMode.ATTACK,
		"and a crosshair over a spotted enemy")
	# Right-click a spotted enemy: focus fire.
	check(enemy.spotted_by[0], "enemy is spotted")
	_click(m, MOUSE_BUTTON_RIGHT, enemy.position, true)
	var focused: int = 0
	for ship: Ship in squad:
		if ship.priority_target == enemy:
			focused += 1
	check(focused == 3, "right-click on an enemy sets the priority target (got %d)" % focused)
	check(m.order_feedback.active_count() == 2, "an attack order briefly brackets the enemy")
	m.order_feedback._process(OrderFeedback.LOCK_TIME + 0.1)
	check(m.order_feedback.active_count() == 0, "order markers fade out")
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
	check(carrier.range_rings() == PackedVector2Array([Vector2(2028.0, 2.0)]), "a carrier has a plane-range ring")
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
	check(m.hud._info_label.text.contains("Squadrons airborne") and m.hud._info_label.text.contains("Air strike on your target"),
		"HUD shows the air wing (%s)" % m.hud._info_label.text.replace("\n", " | "))
	_key(KEY_X)
	check(carrier.strike_target == null, "X hands the air wing back")
	decoy.kill()
	# Shipyard: select the base, build with the hotkey and with the HUD button.
	_key(KEY_H)
	await get_tree().process_frame
	check(m.player.selected_yard == m.bases[0].shipyard, "H selects the Home Base")
	var gold: int = m.economy.gold[0]
	_key(KEY_3)
	check(m.bases[0].shipyard.queue.size() == 1 and gold - m.economy.gold[0] == 100, "hotkey 3 queues and pays for a destroyer")
	await frames(2)
	check(m.bases[0].shipyard.hull != null, "its hull is laid down at once")
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

func three_base_map() -> MapData:
	var map: MapData = open_map()
	map.base_positions.append(Vector2(2000.0, 200.0))
	return map


func test_26_three_sides_fight_until_one_is_left() -> void:
	var map: MapData = three_base_map()
	add_island(map, MapData.KIND_MAJOR, Vector2(2000.0, 900.0), 110.0)
	var m: Match = await start(map, [NONE, NONE, NONE])
	check(m.team_count == 3 and m.bases.size() == 3, "three sides, three Home Bases")
	check(m.economy.gold[2] == GameData.balance().start_gold, "the third side has a bank")
	check(m.are_enemies(0, 1) and m.are_enemies(1, 2) and m.are_enemies(0, 2) and not m.are_allies(0, 2),
		"with no alliances everybody is everybody's enemy")
	var island: Island = m.islands[0]
	island.set_owner_team(2)
	var target0: Ship = hull(m, BB, 0, Vector2(1800.0, 1700.0))
	var target1: Ship = hull(m, BB, 1, Vector2(2200.0, 1700.0))
	var gunner: Ship = m.spawn_ship(CL, 2, Vector2(2000.0, 1500.0), PI * 0.5)
	var hull_hp: float = target0.hp
	await seconds(8.0)
	check(target0.spotted_by[2] and target1.spotted_by[2], "the third side spots both of the others")
	check(target0.hp < hull_hp or target1.hp < hull_hp, "and shoots at them")
	check(island.garrison.spotted_by[0] == false and island.garrison.is_enemy_of(0) and island.garrison.is_enemy_of(1),
		"its island is hostile to both")
	var income_before: Vector2i = m.economy.income_for(2)
	var lost: Array[int] = []
	m.team_eliminated.connect(func(team: int) -> void: lost.append(team))
	m.bases[2].kill()
	await frames(3)
	check(not m.is_over and m.eliminated[2] and lost == [2], "losing a base knocks that side out but the match goes on")
	check(not gunner.is_alive() and m.ships_of(2, false).is_empty(), "its fleet goes down with it")
	check(island.owner_team == -1 and m.yards_of(2).is_empty(), "its islands and shipyards are abandoned")
	check(income_before.x > 0 and m.economy.income_for(2) == Vector2i.ZERO, "and it earns nothing more")
	check(target0.is_alive() and target1.is_alive(), "the other fleets are untouched")
	m.bases[1].kill()
	await frames(3)
	check(m.is_over and m.winner == 0, "the last side standing wins")


func test_27_allies_share_vision_and_victory() -> void:
	var m: Match = await start(three_base_map(), [HUMAN, NONE, NONE], false, [], [7, 7, 9])
	check(m.are_allies(0, 1) and not m.are_enemies(0, 1) and m.are_enemies(0, 2) and m.are_enemies(1, 2),
		"sides 0 and 1 are allies against side 2")
	check(m.local_team == 0, "the human plays side 0")
	var friend: Ship = hull(m, BB, 1, Vector2(1000.0, 1500.0))
	var gunner: Ship = m.spawn_ship(CL, 0, Vector2(1000.0, 1200.0), PI * 0.5)
	check(not gunner.can_engage(friend) and not gunner.order_attack(friend), "an ally cannot be attacked")
	var friend_hp: float = friend.hp
	# An enemy far from side 0, seen only by the ally's scout.
	var enemy: Ship = hull(m, BB, 2, Vector2(3000.0, 600.0))
	var scout: Ship = spotter(m, 1, Vector2(3000.0, 900.0))
	await seconds(8.0)
	check(friend.hp == friend_hp, "allied ships do not shoot each other")
	check(enemy.spotted_by[1] and enemy.spotted_by[0], "what an ally sees, the whole alliance sees")
	check(m.is_combatant_visible_to_local(scout) and m.is_combatant_visible_to_local(friend), "allied ships are always visible")
	check(m.vision.spotted_enemies(0).has(enemy) and not m.vision.spotted_enemies(0).has(friend),
		"only real enemies are on the target list")
	# A shell fired through an ally passes it by and hits the enemy behind.
	var ally_wall: Ship = hull(m, BB, 1, Vector2(2500.0, 2000.0))
	var foe: Ship = hull(m, BB, 2, Vector2(2700.0, 2000.0))
	var hit: Dictionary = m.cast_projectile(Vector2(2300.0, 2000.0), Vector2(2900.0, 2000.0), 0)
	check(not hit.is_empty() and hit["collider"] == foe, "shells pass allied hulls and strike the enemy")
	check(ally_wall.is_alive(), "the ally is unharmed")
	m.bases[1].kill()
	await frames(3)
	check(not m.is_over and m.eliminated[1], "losing an ally does not end the match")
	m.bases[2].kill()
	await frames(3)
	check(m.is_over and m.are_allies(m.winner, 0), "the alliance wins when the last enemy base falls")
	await _cleanup()
	# The offline rule: when the local player's own alliance is out, the match is over.
	var solo: Match = await start(three_base_map(), [HUMAN, NONE, NONE])
	solo.bases[0].kill()
	await frames(3)
	check(solo.is_over and solo.winner != 0, "the match ends when the local player is knocked out")


func test_28_commands_are_checked_before_they_run() -> void:
	var m: Match = await start(three_base_map(), [HUMAN, NONE, NONE])
	var mine: Ship = m.spawn_ship(CL, 0, Vector2(1000.0, 1500.0))
	var theirs: Ship = m.spawn_ship(CL, 1, Vector2(3000.0, 600.0))
	var yard0: int = m.yards.find(m.bases[0].shipyard)
	var yard1: int = m.yards.find(m.bases[1].shipyard)
	check(mine.net_id > 0 and theirs.net_id != mine.net_id and m.ships_by_id[mine.net_id] == mine,
		"every ship has its own id")
	for who: Combatant in [mine, m.bases[1], m.bases[2]]:
		check(m.combatant_from_ref(m.combatant_ref(who)) == who, "combatant refs round-trip")
	check(m.combatant_ref(null) == 0 and m.combatant_from_ref(0) == null and m.combatant_from_ref(999999) == null,
		"unknown refs name nothing")
	# Valid commands of the side's own.
	check(m.execute_command(0, {"type": "move", "ships": [mine.net_id], "x": 1400.0, "y": 1500.0}) == ""
		and mine.has_destination(), "a side moves its own ships")
	m.execute_command(0, {"type": "stop", "ships": [mine.net_id]})
	check(not mine.has_destination(), "and stops them")
	check(m.execute_command(0, {"type": "build", "yard": yard0, "cls": int(DD)}) == ""
		and m.bases[0].shipyard.queue.size() == 1, "a side builds at its own yard")
	m.execute_command(0, {"type": "cancel", "yard": yard0})
	check(m.bases[0].shipyard.queue.is_empty(), "and cancels the order")
	m.execute_command(0, {"type": "rally", "yard": yard0, "x": 900.0, "y": 1400.0})
	check(m.bases[0].shipyard.rally_point.distance_to(Vector2(900.0, 1400.0)) < 60.0, "and moves its rally point")
	check(m.execute_command(0, {"type": "build", "yard": yard0, "cls": int(BB)}) != "",
		"a refused order comes back as a notice for the player")
	# Forged commands: other sides' ships and yards are out of reach.
	m.execute_command(0, {"type": "move", "ships": [theirs.net_id], "x": 100.0, "y": 100.0})
	check(not theirs.has_destination(), "a side cannot move another side's ships")
	m.execute_command(0, {"type": "build", "yard": yard1, "cls": int(DD)})
	m.execute_command(0, {"type": "upgrade", "yard": yard1})
	check(m.bases[1].shipyard.queue.is_empty(), "nor build at another side's yard")
	var rally1: Vector2 = m.bases[1].shipyard.rally_point
	m.execute_command(0, {"type": "rally", "yard": yard1, "x": 100.0, "y": 100.0})
	check(m.bases[1].shipyard.rally_point == rally1, "nor move its rally point")
	# An enemy the side cannot see cannot be ordered attacked.
	m.execute_command(0, {"type": "attack", "ships": [mine.net_id], "target": theirs.net_id})
	check(mine.priority_target == null, "an unseen enemy cannot be targeted")
	# Malformed commands do nothing (and do not crash).
	var bad: Array[Dictionary] = [{}, {"type": 5}, {"type": "launch"}, {"type": "move"},
		{"type": "move", "ships": "all", "x": 1.0, "y": 2.0},
		{"type": "move", "ships": [mine.net_id], "x": NAN, "y": 0.0},
		{"type": "move", "ships": [mine.net_id], "x": "1", "y": 0.0},
		{"type": "build", "yard": 999, "cls": 0}, {"type": "build", "yard": -1, "cls": 0},
		{"type": "build", "yard": yard0, "cls": 99}, {"type": "build", "yard": "0", "cls": 0},
		{"type": "attack", "ships": [mine.net_id], "target": "base"},
		{"type": "attack", "ships": [mine.net_id], "target": -1}]
	for cmd: Dictionary in bad:
		check(m.execute_command(0, cmd) == "", "malformed command %s is ignored" % str(cmd))
	check(not mine.has_destination() and mine.priority_target == null and m.bases[0].shipyard.queue.is_empty(),
		"malformed commands change nothing")
	var many: Array[int] = []
	for i: int in Match.MAX_COMMAND_SHIPS + 1:
		many.append(mine.net_id)
	m.execute_command(0, {"type": "move", "ships": many, "x": 1400.0, "y": 1500.0})
	check(not mine.has_destination(), "an oversized ship list is refused")
	check(m.execute_command(-1, {"type": "stop", "ships": [mine.net_id]}) == ""
		and m.execute_command(7, {"type": "stop", "ships": [mine.net_id]}) == "", "unknown sides are refused")
	# A spotted enemy can be attacked, and class rules still apply (a Submarine cannot hit a base).
	var scout: Ship = spotter(m, 0, Vector2(3000.0, 900.0))
	await seconds(1.0)
	m.execute_command(0, {"type": "attack", "ships": [mine.net_id], "target": theirs.net_id})
	check(mine.priority_target == theirs, "a spotted enemy can be ordered attacked")
	check(m.execute_command(0, {"type": "attack", "ships": [scout.net_id], "target": m.combatant_ref(m.bases[1])})
		in ["Submarines cannot attack the Home Base", ""], "order rules are those of the ships themselves")
	# The local player's commands go through the same door.
	check(m.command({"type": "move", "ships": [mine.net_id], "x": 1300.0, "y": 1500.0}) == "" and mine.has_destination(),
		"Match.command runs the local side's orders")
	# Knocked-out sides give no more orders.
	var lost: Ship = m.spawn_ship(CL, 2, Vector2(2000.0, 500.0))
	m.bases[2].kill()
	await frames(3)
	check(m.execute_command(2, {"type": "build", "yard": m.yards.find(m.bases[2].shipyard), "cls": int(DD)}) == ""
		and m.bases[2].shipyard.queue.is_empty() and not lost.is_alive(), "an eliminated side is ignored")


func test_29_a_replica_mirrors_the_host_exactly() -> void:
	var host: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	host.map_seed = 5
	host.team_control = [Match.ControlType.AI, Match.ControlType.AI, Match.ControlType.AI]
	host.create_ui = false
	host.record_effects = true
	add_child(host)
	_match = host
	await seconds(150.0)
	check(host.ships.size() > 4 and host.projectile_count() > 0, "the host has a battle going (%d ships, %d projectiles)" % [
		host.ships.size(), host.projectile_count()])
	# The replica lives in its own 2D world so the two matches cannot collide.
	var view: SubViewport = SubViewport.new()
	add_child(view)
	var rep: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	rep.map_seed = 5
	rep.team_control = [NONE, NONE, NONE]
	rep.replica = true
	rep.create_ui = false
	view.add_child(rep)
	await frames(2)
	check(rep.islands.size() == host.islands.size() and rep.yards.size() == host.yards.size(),
		"the same seed builds the same map on the client")
	var snap: Dictionary = NetSync.build(host)
	NetSync.apply(rep, snap)
	var diff: Array[String] = NetSync.differences(snap, NetSync.build(rep))
	check(diff.is_empty(), "after one snapshot the replica holds exactly the host's state (differs: %s)" % str(diff))
	check(rep.ships.size() == host.ships_by_id.size() and rep.net_projectiles.size() > 0, "ships and projectiles are mirrored")
	# Sandbox mode (Shift+E) is a command the host runs for the sender's side, and is synced.
	check(host.execute_command(1, {"type": "sandbox"}).contains("ON") and host.economy.infinite[1], "the host toggles sandbox for a client's side")
	NetSync.apply(rep, NetSync.build(host))
	check(rep.economy.infinite[1] and not rep.economy.infinite[0], "the client sees its infinite resources")
	host.execute_command(1, {"type": "sandbox"})
	NetSync.apply(rep, NetSync.build(host))
	check(not rep.economy.infinite[1], "and sees it switched off")
	var bytes: int = var_to_bytes(snap).size()
	print("    snapshot: %d bytes, %d ships, %d projectiles" % [bytes, rep.ships.size(), rep.net_projectiles.size()])
	check(bytes < 60000, "a snapshot stays small enough for LAN (%d bytes)" % bytes)
	await seconds(5.0)
	diff = NetSync.differences(snap, NetSync.build(rep))
	check(diff.is_empty(), "left alone, the replica changes nothing by itself (differs: %s)" % str(diff))
	var worst: Array[String] = []
	for i: int in 300:
		await frames(4)
		snap = NetSync.build(host)
		NetSync.apply(rep, snap)
		diff = NetSync.differences(snap, NetSync.build(rep))
		if not diff.is_empty() and worst.is_empty():
			worst = diff
	check(worst.is_empty(), "the replica follows the host through 20 s of battle (differs: %s)" % str(worst))
	var sunk: int = 0
	for ship: Ship in rep.ships:
		if not host.ships_by_id.has(ship.net_id):
			sunk += 1
	check(sunk == 0, "ships sunk on the host are gone on the replica")
	# Knock-outs and the end of the match reach the client as well.
	var out: Array[int] = []
	var ended: Array[int] = []
	rep.team_eliminated.connect(func(team: int) -> void: out.append(team))
	rep.match_ended.connect(func(team: int) -> void: ended.append(team))
	host.bases[2].kill()
	await frames(3)
	NetSync.apply(rep, NetSync.build(host))
	check(rep.eliminated[2] and out == [2] and not rep.bases[2].is_alive() and not rep.is_over,
		"a side knocked out on the host is knocked out on the replica")
	check(rep.ships_of(2, false).is_empty() and rep.yards_of(2).is_empty(), "its fleet and yards are gone there too")
	host.bases[1].kill()
	await frames(3)
	NetSync.apply(rep, NetSync.build(host))
	check(rep.is_over and rep.winner == host.winner and ended == [host.winner], "the replica sees the match end with the same winner")
	var sent: Array[Dictionary] = []
	rep.command_sink = func(cmd: Dictionary) -> void: sent.append(cmd)
	rep.command({"type": "stop", "ships": []})
	check(sent.size() == 1 and rep.execute_command(0, {"type": "stop", "ships": []}) == "",
		"a replica sends its commands away instead of running them")
	view.queue_free()


func test_30_menu_opponent_count_adds_ai_fleets() -> void:
	var shown: bool = GameSettings.menu_shown
	var opponents: int = GameSettings.ai_opponents
	GameSettings.menu_shown = true
	GameSettings.ai_opponents = 3
	var m: Match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	m.map_seed = 2
	m.create_ui = false
	add_child(m)
	_match = m
	await frames(3)
	GameSettings.menu_shown = shown
	GameSettings.ai_opponents = opponents
	check(m.team_count == 4 and m.bases.size() == 4 and m.local_team == 0, "three AI opponents make a four-fleet match")
	check(m.ai_controllers.size() == 3 and m.are_enemies(1, 2) and m.are_enemies(0, 3),
		"each AI fleet fights everybody else")


func test_32_super_battleship_flak() -> void:
	var m: Match = await start(open_map(Vector2(3000.0, 2400.0)))
	var sbb: Ship = m.spawn_ship(SBB, 0, Vector2(1500.0, 1200.0))
	sbb.max_hp = 1000000.0
	sbb.hp = sbb.max_hp
	var cv: Ship = m.spawn_ship(CV, 1, Vector2(1500.0, 1700.0))
	m.spawn_ship(DD, 1, Vector2(1500.0, 1600.0))
	await seconds(90.0)
	check(cv.squadrons_launched >= 3, "the carrier sends squadrons at the super battleship (%d)" % cv.squadrons_launched)
	check(sbb.flak_barrages >= 2, "the super battleship fires flak barrages (%d)" % sbb.flak_barrages)
	check(sbb.flak_kills >= 1 and cv.squadrons_lost >= sbb.flak_kills, "flak brings squadrons down (%d)" % sbb.flak_kills)
	check(float(sbb.flak_barrages) <= 90.0 / GameData.ship(SBB).periodic_aa_interval + 1.0,
		"barrages are at least %.0fs apart" % GameData.ship(SBB).periodic_aa_interval)


func test_45_aa_cruiser_flak_shreds_squadrons() -> void:
	var m: Match = await start(open_map(Vector2(3000.0, 2400.0)))
	var stats: ShipStats = GameData.ship(CLAA)
	var claa: Ship = m.spawn_ship(CLAA, 0, Vector2(1500.0, 1200.0))
	claa.max_hp = 1000000.0
	claa.hp = claa.max_hp
	var cv: Ship = m.spawn_ship(CV, 1, Vector2(1500.0, 1900.0))
	m.spawn_ship(DD, 1, Vector2(1500.0, 1600.0))
	check(claa.range_rings().has(Vector2(stats.periodic_aa_range, 4.0)), "the AA Cruiser shows its flak ring")
	await seconds(60.0)
	check(claa.salvos_fired == 0, "no gun salvos from an AA Cruiser")
	check(cv.squadrons_launched >= 3, "the carrier sends squadrons at the AA Cruiser (%d)" % cv.squadrons_launched)
	check(claa.flak_barrages >= 5, "the AA Cruiser fires flak barrages (%d)" % claa.flak_barrages)
	check(claa.flak_kills >= 2 and cv.squadrons_lost >= claa.flak_kills, "flak brings squadrons down (%d)" % claa.flak_kills)
	check(float(claa.flak_barrages) <= 60.0 / stats.periodic_aa_interval + 1.0,
		"barrages are at least %.0fs apart" % stats.periodic_aa_interval)


func test_46_major_islands_raise_the_fleet_cap() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MAJOR, Vector2(1500.0, 700.0), 120.0)
	add_island(map, MapData.KIND_MAJOR, Vector2(2500.0, 1700.0), 120.0)
	add_island(map, MapData.KIND_MINOR, Vector2(2000.0, 1200.0), 80.0)
	var m: Match = await start(map)
	var b: GameBalance = GameData.balance()
	check(b.major_island_fleet_bonus == 3, "+3 fleet cap per Major island")
	check(m.fleet_cap(0) == 30, "base fleet cap 30")
	m.islands[2].set_owner_team(0)
	check(m.fleet_cap(0) == 30, "a Minor island adds nothing")
	m.islands[0].set_owner_team(0)
	check(m.fleet_cap(0) == 33 and m.islands[0].shipyard.tier == 0, "a Major island adds 3 with no shipyard built")
	m.islands[1].set_owner_team(0)
	check(m.fleet_cap(0) == 36 and m.fleet_cap(1) == 30, "two Majors add 6, for their owner only")
	m.economy.set_bank(0, 999999, 999999)
	for i: int in 33:
		m.spawn_ship(DD, 0, Vector2(600.0 + 90.0 * float(i % 10), 1500.0 + 90.0 * float(i / 10)))
	var yard: Shipyard = m.bases[0].shipyard
	check(yard.enqueue_ship(DD), "ship 34 fits under the raised cap")
	m.islands[1].set_owner_team(-1)
	check(yard.try_enqueue_ship(DD).contains("Fleet cap reached (33"), "losing a Major lowers the cap again")


func test_47_supercarrier_and_super_battleship_limits() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MAJOR, Vector2(1500.0, 700.0), 120.0)
	var m: Match = await start(map)
	m.islands[0].set_owner_team(0)
	var yard: Shipyard = m.islands[0].shipyard
	yard.tier = 3
	m.economy.set_bank(0, 999999, 999999)
	check(GameData.ship(CV).max_active == 2 and GameData.ship(CV).max_per_game == 4, "SCV: 2 at a time, 4 per game")
	check(GameData.ship(SBB).max_active == 3 and GameData.ship(SBB).max_per_game == 0, "SBB: 3 at a time")
	# Super Battleships: three at once, counting afloat and queued.
	m.spawn_ship(SBB, 0, Vector2(800.0, 1500.0))
	check(yard.enqueue_ship(SBB) and yard.enqueue_ship(SBB), "two more SBB queue up")
	check(yard.try_enqueue_ship(SBB).contains("At most 3"), "a fourth SBB is refused")
	check(m.class_count(0, SBB) == Vector2i(3, 2), "one afloat, two unfinished")
	yard.cancel_last()
	check(yard.enqueue_ship(SBB), "cancelling frees the slot")
	while not yard.queue.is_empty():
		yard.cancel_last()
	# Supercarriers: two at once.
	check(yard.enqueue_ship(CV) and yard.enqueue_ship(CV), "two SCV queue up")
	check(yard.try_enqueue_ship(CV).contains("At most 2"), "a third SCV is refused")
	yard.cancel_last()
	# A real launch counts toward the per-game limit.
	await seconds(GameData.ship(CV).build_time + 0.5)
	check(m.launched_count(0, CV) == 1, "a launched SCV is counted (%d)" % m.launched_count(0, CV))
	check(m.launched_count(1, CV) == 0, "per side")
	# Lose it and two more, then only one is left for the game.
	m.record_launch(0, CV)
	m.record_launch(0, CV)
	for ship: Ship in m.ships_of(0):
		if ship.stats.ship_class == CV:
			ship.kill()
	await frames(2)
	check(m.class_count(0, CV).x == 0 and m.launched_count(0, CV) == 3, "three launched, none left afloat")
	check(yard.enqueue_ship(CV), "a fourth SCV may still be built")
	check(yard.try_enqueue_ship(CV).contains("per game"), "but not a fifth while the fourth is on order")
	yard.cancel_last()
	m.record_launch(0, CV)
	check(yard.try_enqueue_ship(CV).contains("per game"), "after four launches SCVs are gone for good")
	check(m.class_limit_reason(1, CV) == "", "the other side still has all of its own")


func test_48_sandbox_infinite_resources() -> void:
	var m: Match = await start(open_map(), [HUMAN, NONE], true)
	var yard: Shipyard = m.bases[0].shipyard
	m.economy.set_bank(0, 0, 0)
	check(yard.try_enqueue_ship(DD).begins_with("Not enough"), "an empty bank cannot build")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_E
	key.shift_pressed = true
	key.pressed = true
	m.hud._unhandled_key_input(key)
	check(m.economy.infinite[0] and not m.economy.infinite[1], "Shift+E gives the local side infinite resources")
	check(m.hud.last_notice().contains("infinite resources ON"), "the HUD confirms it (%s)" % m.hud.last_notice())
	check(yard.enqueue_ship(DD) and m.economy.gold[0] == 0, "orders are free")
	yard.cancel_last()
	check(m.economy.gold[0] == 0 and m.economy.steel[0] == 0, "and refund nothing")
	m.hud._refresh_all()
	check(m.hud._gold_label.text == "∞", "the bank shows infinity")
	m.hud.toggle_sandbox()
	check(not m.economy.infinite[0] and yard.try_enqueue_ship(DD).begins_with("Not enough"), "Shift+E again turns it off")


func test_49_defeated_player_may_spectate_or_leave() -> void:
	var map: MapData = open_map()
	map.base_positions.append(Vector2(2000.0, 2200.0))
	# Three sides: you and an ally against one enemy, so the match goes on after you fall.
	var m: Match = await start(map, [HUMAN, NONE, NONE], true, [], [1, 1, 2])
	check(m.team_count == 3 and not m.spectator and m.fog.visible, "three sides, you play under fog")
	check(not m.hud.defeat_panel_shown(), "no defeat panel while you are in the game")
	m.bases[0].kill()
	await frames(3)
	check(m.eliminated[0] and not m.is_over, "you are out, the match goes on")
	check(m.hud.defeat_panel_shown(), "the defeat panel offers to spectate or leave")
	var panel: Control = m.hud.find_child("DefeatPanel", true, false) as Control
	check(panel != null and panel.find_child("Spectate", true, false) is Button
		and panel.find_child("Leave", true, false) is Button, "with a Spectate and a Leave button")
	check(not m.spectator, "still under fog until you choose")
	m.hud.spectate_match()
	check(m.spectator and not m.fog.visible and not m.hud.defeat_panel_shown(), "Spectate lifts the fog and closes the panel")
	var enemy: Ship = m.spawn_ship(DD, 2, Vector2(3600.0, 300.0))
	check(m.is_combatant_visible_to_local(enemy), "a spectator sees every ship")
	check(m.hud.last_notice().contains("Spectating"), "the HUD confirms (%s)" % m.hud.last_notice())


func test_50_lobby_spectators() -> void:
	check(Net.host_game(NetSession.DEFAULT_PORT + 31) == "", "host a LAN game")
	Net.slots[1] = {"kind": NetSession.Slot.HUMAN, "peer": 77, "name": "Ann", "team": 2}
	var beacon: Dictionary = Net._beacon()
	check(not bool(beacon["in_match"]) and int(beacon["watch"]) == NetSession.MAX_SPECTATORS, "the beacon offers spectator places")
	Net._set_spectating(77, true)
	check(Net.is_spectator(77) and Net.slot_of(77) < 0 and int(Net.slots[1]["kind"]) == NetSession.Slot.OPEN,
		"a player can give up their seat to spectate")
	check(Net._lobby_state()["spectators"].size() == 1, "spectators are in the lobby state")
	Net._set_spectating(77, false)
	check(not Net.is_spectator(77) and Net.slot_of(77) >= 0, "and take an open seat back")
	Net._set_spectating(1, true)
	check(not Net.is_spectator(1) and Net.slot_of(1) == 0, "the host always plays")
	for i: int in range(1, Net.slots.size()):
		Net.slots[i] = {"kind": NetSession.Slot.HUMAN, "peer": 80 + i, "name": "P%d" % i, "team": i + 1}
	Net._set_spectating(81, true)
	Net._set_spectating(90, false)
	Net.spectators.append({"peer": 90, "name": "Late"})
	Net._set_spectating(90, false)
	check(Net.slot_of(90) >= 0, "a spectator takes the seat that was freed")
	Net.leave()
	check(Net.spectators.is_empty() and not Net.is_online(), "leaving clears the spectators")


func test_33_swell_rocks_ships_without_carrying_them_off() -> void:
	var m: Match = await start(open_map(Vector2(3000.0, 2400.0)))
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(1500.0, 1200.0))
	var bb: Ship = m.spawn_ship(BB, 0, Vector2(1500.0, 900.0))
	var dd_start: Vector2 = dd.position
	var bb_start: Vector2 = bb.position
	var dd_most: float = 0.0
	var bb_most: float = 0.0
	for i: int in 120:
		await seconds(0.5)
		dd_most = maxf(dd_most, dd.position.distance_to(dd_start))
		bb_most = maxf(bb_most, bb.position.distance_to(bb_start))
	check(dd_most > 2.0, "an idle destroyer is moved by the waves (%.1f px)" % dd_most)
	check(dd_most < 20.0 and bb_most < 20.0, "the swell never carries a ship away (%.1f / %.1f px)" % [dd_most, bb_most])
	check(bb_most < dd_most, "big hulls are rocked less than small ones (%.1f < %.1f)" % [bb_most, dd_most])


func test_31_battleship_secondaries() -> void:
	var bb_stats: ShipStats = GameData.ship(BB)
	var dd_stats: ShipStats = GameData.ship(DD)
	check(bb_stats.secondary_mounts == 4 and is_equal_approx(bb_stats.secondary_shell_damage, dd_stats.shell_damage),
		"battleships carry four destroyer-calibre secondary guns")
	check(is_equal_approx(bb_stats.secondary_interval, dd_stats.fire_interval * 2.0),
		"secondaries fire at half a destroyer gun's rate")
	check(is_equal_approx(bb_stats.secondary_range, bb_stats.gun_range * 0.5), "secondary range is half the main-gun range")
	for cls: ShipStats.ShipClass in [DD, SS, CL, CA, CV]:
		check(not GameData.ship(cls).has_secondaries(), "%s has no secondaries" % GameData.ship(cls).code)
	var m: Match = await start(open_map(Vector2(6400.0, 2400.0)))
	# A hull abeam inside secondary range: main turrets and secondaries both fire.
	var bb: Ship = m.spawn_ship(BB, 0, Vector2(1000.0, 1200.0))
	var near: Ship = hull(m, DD, 1, Vector2(1000.0, 1500.0))
	near.max_hp = 1000000.0
	near.hp = near.max_hp
	spotter(m, 0, Vector2(900.0, 1300.0))
	# A hull past secondary range but inside main-gun range: only the main battery fires.
	var bb2: Ship = m.spawn_ship(BB, 0, Vector2(3000.0, 1200.0))
	var far: Ship = hull(m, DD, 1, Vector2(3000.0, 1900.0))
	far.max_hp = 1000000.0
	far.hp = far.max_hp
	spotter(m, 0, Vector2(3000.0, 1300.0), 900.0)
	# A spotted submarine close aboard: battleship secondaries leave it alone too.
	var bb3: Ship = m.spawn_ship(BB, 0, Vector2(4700.0, 1200.0))
	var boat: Ship = hull(m, SS, 1, Vector2(4700.0, 1400.0))
	m.spawn_ship(DD, 0, Vector2(4900.0, 1000.0))
	await seconds(3.0)
	check(boat.spotted_by[0], "the submarine is spotted")
	check(bb.secondary_salvos >= 1 and bb.salvos_fired >= 1, "secondaries and main guns both engage a close target (%d / %d)" % [
		bb.secondary_salvos, bb.salvos_fired])
	check(bb2.salvos_fired >= 1 and bb2.secondary_salvos == 0, "a target past secondary range draws only main-gun fire (%d / %d)" % [
		bb2.secondary_salvos, bb2.salvos_fired])
	check(bb3.secondary_salvos == 0 and bb3.salvos_fired == 0, "battleship secondaries never fire at submarines")
	var before: int = bb.secondary_salvos
	await seconds(bb_stats.secondary_interval * 2.0)
	check(bb.secondary_salvos - before == 2, "secondaries reload every %.0fs (%d salvos in %.0fs)" % [
		bb_stats.secondary_interval, bb.secondary_salvos - before, bb_stats.secondary_interval * 2.0])
	check(bb.range_rings().has(Vector2(bb_stats.secondary_range, 3.0)), "a battleship shows a secondary range ring")


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


# --- Air wing roles, island defenses, support ships --------------------------

func _squadrons_with_role(m: Match, role: PlaneSquadron.Role) -> Array[PlaneSquadron]:
	var result: Array[PlaneSquadron] = []
	for squadron: PlaneSquadron in squadrons_of(m):
		if squadron.role == role:
			result.append(squadron)
	return result


func test_12d_torpedo_bombers_hit_capital_ships_broadside() -> void:
	var m: Match = await start(open_map())
	# A Light Carrier sends one torpedo flight at a time.
	var cv: Ship = m.spawn_ship(LCV, 0, Vector2(1100.0, 1200.0))
	# A heavy cruiser alone: too small for torpedo bombers.
	var cruiser: Ship = hull(m, CA, 1, Vector2(1900.0, 900.0))
	cruiser.max_hp = 100000.0
	cruiser.hp = 100000.0
	spotter(m, 0, Vector2(1900.0, 1300.0))
	await seconds(3.0)
	check(cruiser.spotted_by[0], "the cruiser is spotted")
	check(_squadrons_with_role(m, PlaneSquadron.Role.TORPEDO).is_empty(), "no torpedo bombers go after a cruiser")
	check(not Ship.torpedo_bomber_can_target(cruiser), "a cruiser is not a torpedo-bomber target")
	# A battleship (a hull on the slip, heading east): torpedo bombers launch for it.
	var bb: Ship = hull(m, BB, 1, Vector2(1900.0, 1500.0))
	bb.max_hp = 100000.0
	bb.hp = 100000.0
	var waited: int = 0
	while _squadrons_with_role(m, PlaneSquadron.Role.TORPEDO).is_empty() and waited < 600:
		await frames(1)
		waited += 1
	var flight: Array[PlaneSquadron] = _squadrons_with_role(m, PlaneSquadron.Role.TORPEDO)
	check(flight.size() == 1 and flight[0].mission_target == bb, "a torpedo bomber flight is sent at the battleship")
	if flight.is_empty():
		return
	var bomber: PlaneSquadron = flight[0]
	waited = 0
	while is_instance_valid(bomber) and not bomber.payload_dropped and waited < 900:
		await frames(1)
		waited += 1
	check(is_instance_valid(bomber) and bomber.payload_dropped, "the bombers reach the battleship and drop")
	var torpedoes: Array[Torpedo] = []
	for node: Node in m.projectiles():
		if node is Torpedo and not node.is_queued_for_deletion():
			torpedoes.append(node as Torpedo)
	check(torpedoes.size() == 2, "two torpedoes are dropped (got %d)" % torpedoes.size())
	if torpedoes.size() == 2:
		check(absf(angle_difference(torpedoes[0].rotation, torpedoes[1].rotation)) < 0.01, "they run side by side")
		var across: float = absf(angle_difference(torpedoes[0].rotation, bb.rotation))
		check(absf(across - PI * 0.5) < 0.05, "aimed straight across the battleship's beam")
		var off: float = absf((torpedoes[0].position - bb.position).dot(Vector2.from_angle(bb.rotation).orthogonal()))
		check(off > 60.0 and off < 120.0, "dropped just off its broadside (%.0f px)" % off)
		check(torpedoes[0].position.distance_to(torpedoes[1].position) > 8.0, "a little apart")
	await seconds(1.5)
	check_near(100000.0 - bb.hp, 2.0 * GameData.torpedo_damage() * (1.0 - bb.effective_armor()),
		"both torpedoes hit for torpedo damage (less armor)", 0.5)
	waited = 0
	while is_instance_valid(bomber) and not bomber.is_queued_for_deletion() and waited < 900:
		await frames(1)
		waited += 1
	check(not is_instance_valid(bomber) or bomber.is_queued_for_deletion(), "the flight flies home and lands")
	check(cv.squadrons_lost == 0, "landing is not a loss")


func test_12e_depth_charge_bombers_hunt_submarines() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	# Dive bombers off, so only depth charges hit the boat.
	cv.stats = cv.stats.duplicate() as ShipStats
	cv.stats.max_squadrons = 0
	var boat: Ship = m.spawn_ship(SS, 1, Vector2(1700.0, 1200.0))
	boat.max_hp = 100000.0
	boat.hp = 100000.0
	await seconds(1.0)
	check(not boat.spotted_by[0], "a submerged boat is not seen")
	check(_squadrons_with_role(m, PlaneSquadron.Role.DEPTH).is_empty(), "no depth-charge bombers for an unseen boat")
	boat.reveal_timer = 30.0
	await seconds(0.5)
	check(boat.spotted_by[0], "the boat is revealed")
	var flights: Array[PlaneSquadron] = _squadrons_with_role(m, PlaneSquadron.Role.DEPTH)
	check(flights.size() == 1 and flights[0].mission_target == boat, "a depth-charge bomber flight goes after it")
	await seconds(2.1)
	check(cv.squadrons_launched >= 2 and _squadrons_with_role(m, PlaneSquadron.Role.DEPTH).size() == 2,
		"another follows 2s later")
	var waited: int = 0
	while boat.hp >= 100000.0 and waited < 900:
		await frames(1)
		waited += 1
	check(boat.hp < 100000.0 and fmod(100000.0 - boat.hp, GameData.ship(DD).depth_charge_damage) < 0.5,
		"depth charges hit the boat for full damage, ignoring armor (%.0f)" % (100000.0 - boat.hp))
	var most: int = 0
	for i: int in 20:
		await seconds(1.0)
		most = maxi(most, _squadrons_with_role(m, PlaneSquadron.Role.DEPTH).size())
	check(most <= cv.stats.max_depth_bombers, "no more than %d depth-charge flights in the air (%d)" % [
		cv.stats.max_depth_bombers, most])
	check(_squadrons_with_role(m, PlaneSquadron.Role.TORPEDO).is_empty(), "torpedo bombers never go after a submarine")


func test_15c_major_island_air_base_and_radar() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MAJOR, Vector2(2400.0, 1200.0), 130.0)
	var m: Match = await start(map)
	var b: GameBalance = GameData.balance()
	var island: Island = m.islands[0]
	var fort: IslandGarrison = island.garrison
	island.set_owner_team(1)
	m.economy.set_bank(1, 50000, 50000)
	check(not island.has_air_base(), "no air base before a Tier 3 shipyard")
	check(island.try_buy_radar(1).contains("Tier 3"), "radar needs a Tier 3 shipyard")
	check_near(island.spotting_range(), b.island_spotting, "plain island spotting")
	island.shipyard.tier = 3
	check(island.has_air_base(), "a Tier 3 Major island runs an air base")
	check(island.try_buy_radar(0) != "", "only the owner can buy radar")
	var gold: int = m.economy.gold[1]
	check(island.try_buy_radar(1) == "" and island.has_radar, "radar bought")
	check(gold - m.economy.gold[1] == b.radar_gold_cost, "radar is paid for")
	check_near(island.spotting_range(), GameData.ship(DD).spotting_range, "radar gives the island a destroyer's spotting", 1.0)
	check(island.try_buy_radar(1) != "", "radar is bought once")
	# A ship that does not fire on the island is left alone.
	var passer: Ship = m.spawn_ship(RD, 0, island.position + Vector2(-500.0, 300.0))
	await seconds(4.0)
	check(passer.spotted_by[1], "the island sees the passer-by")
	check(fort.airborne_squadrons() == 0, "no bombers for a ship that is not attacking")
	# A destroyer (no anti-air) shelling the island draws the bombers.
	var cl: Ship = m.spawn_ship(DD, 0, island.position + Vector2(-650.0, 0.0))
	cl.max_hp = 100000.0
	cl.hp = 100000.0
	cl.order_attack(fort)
	var waited: int = 0
	while fort.squadrons_launched == 0 and waited < 900:
		await frames(1)
		waited += 1
	check(fort.squadrons_launched == 1 and fort.air_target() == cl, "the air base launches at the ship firing on it")
	await seconds(b.air_base_interval * 2.0 + 6.0)
	check(fort.squadrons_launched == b.air_base_squadrons and fort.airborne_squadrons() == b.air_base_squadrons,
		"up to %d squadrons, one every %ds (launched %d)" % [b.air_base_squadrons, int(b.air_base_interval), fort.squadrons_launched])
	await seconds(b.air_base_interval + 1.0)
	check(fort.squadrons_launched == b.air_base_squadrons, "and no more while they are all up")
	check(cl.hp < 100000.0, "the bombers hit the cruiser")
	check_near(passer.hp, passer.max_hp, "the passer-by is still left alone")
	# The island falls: radar and the air wing are lost.
	fort.kill()
	await frames(3)
	check(not island.has_radar and not island.has_air_base(), "radar and air base are lost with the island")
	check(count_projectiles(m, "PlaneSquadron") == 0, "the base's squadrons are lost with it")


func test_16c_resource_ship_mines_islands() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1500.0, 800.0), 100.0)
	add_island(map, MapData.KIND_MINOR, Vector2(2200.0, 1600.0), 80.0)
	var m: Match = await start(map)
	var b: GameBalance = GameData.balance()
	var base_income: Vector2i = m.economy.income_for(0)
	var miner: Ship = m.spawn_ship(RS, 0, Vector2(1500.0, 800.0 + 100.0 + 90.0))
	var second: Ship = m.spawn_ship(RS, 0, Vector2(1500.0, 800.0 - 100.0 - 90.0))
	var far: Ship = m.spawn_ship(RS, 0, Vector2(1000.0, 2000.0))
	var rival: Ship = m.spawn_ship(RS, 1, Vector2(1500.0 - 100.0 - 90.0, 800.0))
	await seconds(0.5)
	check(miner.mining_island() == m.islands[0], "the first Resource Ship mines the cover island")
	check(second.mining_island() == null and second.blocked_mining_island() == m.islands[0],
		"a second Resource Ship of the same side cannot link to the same island")
	check(rival.mining_island() == m.islands[0], "another side's Resource Ship can mine the same island")
	check(far.mining_island() == null, "a ship away from any island mines nothing")
	check(m.economy.income_for(0) - base_income == Vector2i(b.minor_gold, b.minor_steel),
		"one island pays a Minor island's income, however many ships mine it")
	second.order_move(Vector2(2200.0, 1600.0 + 80.0 + 100.0))
	await seconds(1.0)
	check(second.mining_island() == null, "a ship under way does not mine")
	var waited: int = 0
	while (second.has_destination() or second.mining_island() != m.islands[1]) and waited < 3600:
		await frames(1)
		waited += 1
	check(second.mining_island() == m.islands[1], "it mines the next island once it stops there")
	check(m.economy.income_for(0) - base_income == Vector2i(b.minor_gold, b.minor_steel) * 2, "two islands pay twice")
	check(m.islands[1].owner_team == -1 and m.islands[1].capture_progress <= 0.0, "Resource Ships never capture islands")
	# Once the island is the side's own, its Resource Ship stops mining it; others still may.
	var enemy_miner: Ship = m.spawn_ship(RS, 1, Vector2(2200.0 + 80.0 + 100.0, 1600.0))
	m.islands[1].set_owner_team(0)
	await frames(2)
	check(second.mining_island() == null, "a Resource Ship cannot mine an island its own side owns")
	check(enemy_miner.mining_island() == m.islands[1], "an enemy Resource Ship can mine that island")
	m.islands[1].set_owner_team(-1)
	enemy_miner.kill()
	await frames(2)
	check(second.mining_island() == m.islands[1], "it mines the island again once it is neutral")
	var bank: int = m.economy.gold[0]
	var expected: int = m.economy.income_for(0).x
	m.economy.pay_tick()
	check(m.economy.gold[0] - bank == expected, "mined income is paid on the supply tick")
	# The blocked ship takes the island over once the first miner is gone.
	var third: Ship = m.spawn_ship(RS, 0, Vector2(1500.0, 800.0 - 100.0 - 90.0))
	await seconds(0.5)
	check(third.mining_island() == null, "a newcomer waits while the island is taken")
	miner.kill()
	await frames(2)
	check(third.mining_island() == m.islands[0], "and links up once the first miner is sunk")
	third.kill()
	await frames(2)
	check(m.economy.income_for(0) - base_income == Vector2i(b.minor_gold, b.minor_steel), "a sunk miner earns nothing (%s, %s, %s)" % [
		m.economy.income_for(0) - base_income, second.mining_island(), second.velocity.length()])
	check(not far.stats.has_guns() and far.stats.is_support(), "Resource Ships are unarmed")


func test_16d_radar_ship_spots_far_but_not_submarines() -> void:
	var m: Match = await start(open_map())
	var picket: Ship = m.spawn_ship(RD, 0, Vector2(1000.0, 1200.0))
	var far: Ship = hull(m, BB, 1, Vector2(2000.0, 1200.0))
	var boat: Ship = m.spawn_ship(SS, 1, Vector2(1200.0, 1200.0))
	await seconds(1.0)
	check(far.position.distance_to(picket.position) > GameData.ship(DD).spotting_range, "the target is beyond destroyer spotting")
	check(far.spotted_by[0], "a Radar Ship spots it anyway")
	check(not boat.spotted_by[0], "but not a submerged submarine")
	check(not picket.order_attack(far), "it has no weapons to attack with")
	await seconds(2.0)
	check(picket.salvos_fired == 0 and is_equal_approx(far.hp, far.max_hp * GameData.balance().construction_start_hp_fraction),
		"and deals no damage")


func test_16e_cruiser_and_capital_ship_speeds() -> void:
	var dd: float = GameData.ship_speed(GameData.ship(DD))
	check_near(GameData.ship(CA).speed_factor, 0.5 * 1.5 * 0.85, "CA 1.5x, then -15%")
	check_near(GameData.ship(BC).speed_factor, 0.36 * 1.5 * 0.95, "BC 1.5x, then -5%")
	check_near(GameData.ship(BB).speed_factor, 0.3 * 1.5 * 0.95, "BB 1.5x, then -5%")
	check_near(GameData.ship(SBB).speed_factor, 0.27 * 1.5 * 0.95, "SBB 1.5x, then -5%")
	check_near(GameData.ship(CV).speed_factor, 0.9, "CV unchanged")
	check_near(GameData.ship(DD).speed_factor, 1.0, "DD unchanged")
	check_near(GameData.ship(SS).speed_factor, 0.5, "SS unchanged")
	check(GameData.ship_speed(GameData.ship(SBB)) < dd, "nothing outruns a destroyer")
	await get_tree().process_frame


# --- Supercarrier stacking, broadside turns ---------------------------------

func test_12f_heavy_carrier_stacks_five_per_target_and_retargets() -> void:
	dive_bombers_only(true)
	await _heavy_carrier_stacking()
	dive_bombers_only(false)


func _heavy_carrier_stacking() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	var near: Ship = hull(m, BB, 1, Vector2(1600.0, 1200.0))
	var mid: Ship = hull(m, BB, 1, Vector2(1800.0, 1500.0))
	var spare: Ship = hull(m, BB, 1, Vector2(1900.0, 900.0))
	for ship: Ship in [near, mid, spare]:
		ship.max_hp = 1000000.0
		ship.hp = 1000000.0
	spotter(m, 0, Vector2(1700.0, 1200.0))
	var waited: int = 0
	while cv.squadrons_launched < 10 and waited < 60 * 60:
		await frames(1)
		waited += 1
	check(cv.squadrons_launched == 10 and cv.airborne_squadrons() == 10, "a Supercarrier keeps more than 5 squadrons up (%d)" % cv.airborne_squadrons())
	check(cv.squadrons_on(near) == 5, "the first five stack on the nearest ship (%d)" % cv.squadrons_on(near))
	check(cv.squadrons_on(mid) + cv.squadrons_on(spare) == 5, "the next five go to another ship")
	var second: Ship = mid if cv.squadrons_on(mid) == 5 else spare
	var third: Ship = spare if second == mid else mid
	check(cv.squadrons_on(second) == 5 and cv.squadrons_on(third) == 0, "never more than 5 on one ship")
	await seconds(4.0)
	check(near.hp < near.max_hp and second.hp < second.max_hp, "both targets are bombed at once")
	# The first target sinks: its squadrons move straight on to the ship with room in its stack.
	near.kill()
	await frames(2)
	check(cv.squadrons_on(third) == 5, "squadrons of a sunk target retarget at once (%d on the free ship)" % cv.squadrons_on(third))
	check(cv.squadrons_on(second) == 5, "the full stack stays at 5")
	check(cv.airborne_squadrons() >= 10, "nobody flies home")
	# With nothing in reach, a sunk target's squadrons fly home.
	await seconds(1.0)
	var hp_third: float = third.hp
	await seconds(4.0)
	check(third.hp < hp_third, "the retargeted squadrons bomb their new target")
	third.kill()
	second.kill()
	await seconds(20.0)
	check(cv.airborne_squadrons() == 0, "with no target left in reach every squadron lands (%d up)" % cv.airborne_squadrons())


func test_12g_light_carrier_counts_every_role_toward_five() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(LCV, 0, Vector2(1000.0, 1200.0))
	var bb: Ship = hull(m, BB, 1, Vector2(1600.0, 1200.0))
	bb.max_hp = 1000000.0
	bb.hp = 1000000.0
	var boat: Ship = m.spawn_ship(SS, 1, Vector2(1500.0, 1500.0))
	boat.max_hp = 1000000.0
	boat.hp = 1000000.0
	boat.reveal_timer = 1000.0
	spotter(m, 0, Vector2(1400.0, 1300.0))
	var most: int = 0
	var roles: Dictionary[int, bool] = {}
	for i: int in 40:
		await seconds(1.0)
		most = maxi(most, cv.airborne_squadrons())
		for squadron: PlaneSquadron in squadrons_of(m):
			roles[int(squadron.role)] = true
	check(most == 5, "a Light Carrier never has more than 5 squadrons up, all roles together (%d)" % most)
	check(roles.size() == 3, "it flies dive, torpedo and depth-charge bombers")
	check(cv.squadrons_lost == 0, "no losses against hulls without anti-air")
	boat.reveal_timer = 0.0


func test_12h_heavy_carrier_torpedo_flights_split_over_three_targets() -> void:
	var m: Match = await start(open_map())
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	cv.stats = cv.stats.duplicate() as ShipStats
	cv.stats.max_squadrons = 0
	cv.stats.depth_bomber_interval = 0.0
	var a: Ship = hull(m, BB, 1, Vector2(1700.0, 1200.0))
	var b: Ship = hull(m, BC, 1, Vector2(1800.0, 1500.0))
	var c: Ship = hull(m, SBB, 1, Vector2(1800.0, 900.0))
	for ship: Ship in [a, b, c]:
		ship.max_hp = 1000000.0
		ship.hp = 1000000.0
	spotter(m, 0, Vector2(1700.0, 1200.0), 900.0)
	var waited: int = 0
	while _squadrons_with_role(m, PlaneSquadron.Role.TORPEDO).is_empty() and waited < 600:
		await frames(1)
		waited += 1
	var flights: Array[PlaneSquadron] = _squadrons_with_role(m, PlaneSquadron.Role.TORPEDO)
	check(flights.size() == 3, "one launch sends three torpedo flights (%d)" % flights.size())
	check(cv.missions_on(a, PlaneSquadron.Role.TORPEDO) == 1 and cv.missions_on(b, PlaneSquadron.Role.TORPEDO) == 1
		and cv.missions_on(c, PlaneSquadron.Role.TORPEDO) == 1, "one flight at each of three targets")
	# Only one target: all three go at it, and never more than three at once.
	b.kill()
	c.kill()
	var most: int = 0
	for i: int in 30:
		await seconds(1.0)
		most = maxi(most, cv.missions_on(a, PlaneSquadron.Role.TORPEDO))
	check(most == 3, "a lone target draws up to three flights, no more (%d)" % most)
	check(a.hp < a.max_hp, "the flights hit it")
	# A Light Carrier never sends more than one.
	var light: Ship = m.spawn_ship(LCV, 0, Vector2(1100.0, 1500.0))
	var light_most: int = 0
	for i: int in 25:
		await seconds(1.0)
		light_most = maxi(light_most, light.airborne_of(PlaneSquadron.Role.TORPEDO))
	check(light_most == 1, "a Light Carrier flies one torpedo flight at a time (%d)" % light_most)


func test_12i_heavy_carrier_bombs_hit_ten_percent_harder() -> void:
	var m: Match = await start(open_map())
	var heavy: Ship = m.spawn_ship(CV, 0, Vector2(1000.0, 1200.0))
	var light: Ship = m.spawn_ship(LCV, 0, Vector2(1000.0, 1300.0))
	var a: PlaneSquadron = m.spawn_squadron(heavy, heavy.position, 0.0)
	var b: PlaneSquadron = m.spawn_squadron(light, light.position, 0.0)
	check_near(a.damage, GameData.bomb_damage() * 1.1, "Supercarrier bomb: %.0f" % a.damage, 0.01)
	check_near(b.damage, GameData.bomb_damage(), "Light Carrier bomb: standard", 0.01)
	var torp: PlaneSquadron = m.spawn_squadron(heavy, heavy.position, 0.0, PlaneSquadron.Role.TORPEDO)
	check_near(torp.damage, GameData.bomb_damage(), "only dive bombs get the bonus", 0.01)


func test_16f_player_attack_orders_turn_gun_ships_broadside() -> void:
	var m: Match = await start(open_map())
	var bb: Ship = m.spawn_ship(BB, 0, Vector2(1000.0, 1200.0), 0.0)
	var cl: Ship = m.spawn_ship(CL, 0, Vector2(1000.0, 1600.0), 0.0)
	var dd: Ship = m.spawn_ship(DD, 0, Vector2(1000.0, 800.0), 0.0)
	var ai_bb: Ship = m.spawn_ship(BB, 0, Vector2(1000.0, 2000.0), 0.0)
	var target: Ship = hull(m, BB, 1, Vector2(1700.0, 1200.0))
	target.max_hp = 1000000.0
	target.hp = 1000000.0
	spotter(m, 0, Vector2(1400.0, 1400.0), 900.0)
	await seconds(0.5)
	check(target.spotted_by[0], "the target is spotted")
	# Ships start bow-on to the target; a player order swings their beams toward it.
	var group: Array[int] = []
	for ship: Ship in [bb, cl, dd]:
		group.append(ship.net_id)
	m.execute_command(0, {"type": "attack", "ships": group, "target": m.combatant_ref(target)})
	ai_bb.order_attack(target)
	check(bb.broadside_order and cl.broadside_order and dd.broadside_order, "player attack orders ask for a broadside")
	check(not ai_bb.broadside_order, "orders given in code (the AI) do not")
	await seconds(25.0)
	for ship: Ship in [bb, cl, dd]:
		var bearing: float = (target.position - ship.position).angle()
		var off_beam: float = absf(absf(angle_difference(ship.rotation, bearing)) - PI * 0.5)
		check(off_beam < deg_to_rad(Ship.BROADSIDE_START_DEG),
			"%s lies broadside to its target (%.0f deg off the beam)" % [ship.stats.code, rad_to_deg(off_beam)])
		check(ship.range_to(target) <= ship.stats.gun_range, "%s stays in gun range" % ship.stats.code)
	check(bb.salvos_fired > 0, "and keeps firing")
	var sub: Ship = m.spawn_ship(SS, 0, Vector2(1000.0, 400.0), 0.0)
	var cv: Ship = m.spawn_ship(CV, 0, Vector2(600.0, 1200.0), 0.0)
	check(cv.order_attack(target, true) and not cv.broadside_order, "carriers do not turn broadside")
	sub.order_attack(target)
	check(not sub.broadside_order, "submarines do not turn broadside")
	# A move order ends the broadside.
	bb.order_move(Vector2(900.0, 1200.0))
	check(not bb.broadside_order, "a move order cancels the broadside")


# --- Batch 4: pause, mining marker, radar over islands, garrison regeneration, title ----

func test_40_radar_ships_see_over_islands() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1600.0, 1200.0), 120.0)
	var m: Match = await start(map)
	var radar: Ship = m.spawn_ship(RD, 0, Vector2(1350.0, 1200.0))
	var hidden: Ship = hull(m, CL, 1, Vector2(1850.0, 1200.0))
	var boat: Ship = m.spawn_ship(SS, 1, Vector2(1850.0, 1350.0))
	await seconds(1.0)
	check(not m.has_los(radar.position, hidden.position), "the island is between them")
	check(hidden.spotted_by[0], "a Radar Ship sees a ship behind an island")
	check(not boat.spotted_by[0], "radar does not find submerged submarines")
	radar.kill()
	var scout: Ship = m.spawn_ship(DD, 0, Vector2(1350.0, 1200.0))
	await seconds(1.0)
	check(not hidden.spotted_by[0], "a destroyer in the same spot does not (%s)" % scout.stats.code)


func test_41_shipyard_islands_regenerate_their_garrison() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_MAJOR, Vector2(2400.0, 1200.0), 130.0)
	add_island(map, MapData.KIND_MAJOR, Vector2(1200.0, 2000.0), 130.0)
	var m: Match = await start(map)
	var b: GameBalance = GameData.balance()
	var yard_isle: Island = m.islands[0]
	var bare_isle: Island = m.islands[1]
	yard_isle.set_owner_team(1)
	bare_isle.set_owner_team(1)
	yard_isle.shipyard.tier = 2
	bare_isle.shipyard.tier = 1
	var fort: IslandGarrison = yard_isle.garrison
	var bare: IslandGarrison = bare_isle.garrison
	fort.apply_damage(1000.0, true, false)
	bare.apply_damage(1000.0, true, false)
	var hurt: float = fort.hp
	await seconds(b.garrison_regen_delay - 0.5)
	check_near(fort.hp, hurt, "no healing within %ds of the last hit" % int(b.garrison_regen_delay))
	fort.apply_damage(10.0, true, false)
	hurt = fort.hp
	await seconds(b.garrison_regen_delay - 0.5)
	check_near(fort.hp, hurt, "a new hit restarts the wait")
	await seconds(3.5)
	var healed: float = fort.hp - hurt
	check(healed > fort.max_hp * b.garrison_regen_rate * 2.0 and healed < fort.max_hp * b.garrison_regen_rate * 3.5,
		"then it heals slowly (%.0f HP in ~3s)" % healed)
	check_near(bare.hp, bare.max_hp - 1000.0, "a Tier 1 island does not heal")
	fort.hp = fort.max_hp - 1.0
	await seconds(1.0)
	check_near(fort.hp, fort.max_hp, "never above max HP")


func test_42_resource_ship_mining_marker_and_notice() -> void:
	var map: MapData = open_map()
	add_island(map, MapData.KIND_COVER, Vector2(1500.0, 800.0), 100.0)
	var m: Match = await start(map, [HUMAN, NONE], true)
	var miner: Ship = m.spawn_ship(RS, 0, Vector2(1500.0, 1300.0))
	await seconds(0.5)
	check(miner.shown_mining_island() == null, "no marker away from islands")
	miner.order_move(Vector2(1500.0, 800.0 + 100.0 + 90.0))
	var waited: int = 0
	while miner.shown_mining_island() == null and waited < 3600:
		await frames(1)
		waited += 1
	check(miner.shown_mining_island() == m.islands[0], "the marker shows once it mines")
	await seconds(0.3)
	check(m.hud.last_notice().contains("Resource Ship mining"), "the HUD announces it (%s)" % m.hud.last_notice())


func test_43_pause_freezes_single_player_matches() -> void:
	var m: Match = await start(open_map(), [HUMAN, NONE], true)
	var ship: Ship = m.spawn_ship(DD, 0, Vector2(1000.0, 1200.0))
	ship.order_move(Vector2(2000.0, 1200.0))
	await seconds(0.5)
	check(m.hud._pause_button.visible, "single player has a pause button")
	m.hud.toggle_pause()
	check(get_tree().paused and m.hud.is_paused(), "pause stops the game")
	var t: float = m.sim_time
	var at: Vector2 = ship.position
	await frames(30)
	check_near(m.sim_time, t, "the clock stands still")
	check(ship.position.distance_to(at) < 0.01, "ships stand still")
	m.hud.toggle_pause()
	check(not get_tree().paused, "resume")
	await frames(30)
	check(m.sim_time > t, "the clock runs again")
	m.hud.set_paused(true)
	m.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not get_tree().paused, "a match that ends while paused unpauses the game")


func test_44_title_screen_start_button() -> void:
	var was_shown: bool = GameSettings.menu_shown
	var level: GameSettings.Difficulty = GameSettings.ai_difficulty
	GameSettings.menu_shown = false
	var menu: MainMenu = (load(GameSettings.MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await frames(2)
	check(menu.start_screen != null and menu.start_screen.visible, "the game opens on a title screen")
	check(not menu.size_buttons[0].is_visible_in_tree(), "the menu waits behind it")
	menu.press_start()
	await frames(30)
	check(menu.start_screen == null and menu.size_buttons[0].is_visible_in_tree(), "Start shows the menu")
	menu.queue_free()
	await frames(2)
	var again: MainMenu = (load(GameSettings.MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child(again)
	await frames(2)
	check(again.start_screen == null, "coming back from a match skips the title screen")
	again.queue_free()
	await frames(2)
	GameSettings.menu_shown = was_shown
	GameSettings.ai_difficulty = level


func test_51_menu_guide_credits_and_sound() -> void:
	var was_shown: bool = GameSettings.menu_shown
	GameSettings.menu_shown = true
	var menu: MainMenu = (load(GameSettings.MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await frames(2)
	menu.open_guide()
	await frames(2)
	check(menu.page != null and menu.page.is_visible_in_tree(), "How to Play opens a page")
	var guide: String = (menu.page.find_child("Text", true, false) as RichTextLabel).get_parsed_text()
	check(guide.contains("Controls") and guide.contains("Right click"), "the guide lists the controls")
	for ship_class: ShipStats.ShipClass in GameData.all_classes():
		var stats: ShipStats = GameData.ship(ship_class)
		check(guide.contains(stats.display_name) and MenuPages.ROLES.has(stats.code),
			"the guide describes the %s" % stats.code)
	menu.close_page()
	await frames(2)
	check(menu.page == null, "Back closes the page")
	menu.open_credits()
	await frames(2)
	var credits: String = (menu.page.find_child("Text", true, false) as RichTextLabel).get_parsed_text()
	check(credits.contains("Pixabay") and credits.contains("Godot"), "credits name Pixabay and Godot")
	for path: String in Music.find_tracks():
		var credit: Array[String] = Music.credit_for(path)
		check(credit[1] != "Unknown artist", "%s has a credit entry" % path.get_file())
		check(credits.contains(credit[0]) and credits.contains(credit[1]), "credits list %s by %s" % credit)
	menu.close_page()
	menu.toggle_sound_panel()
	await frames(2)
	check(menu.sound_overlay != null and menu.sound_overlay.is_visible_in_tree(), "Sound opens the volume panel")
	menu.toggle_sound_panel()
	await frames(2)
	check(menu.sound_overlay == null, "and closes it")
	menu.queue_free()
	await frames(2)
	GameSettings.menu_shown = was_shown


func test_52_volume_panel_and_playlist() -> void:
	var m: Match = await start(open_map(), [HUMAN, NONE], true)
	check(m.hud.sound_panel != null and not m.hud.sound_panel.visible, "the HUD has a hidden volume panel")
	m.hud.toggle_sound_panel()
	await frames(1)
	check(m.hud.sound_panel.visible, "the Sound button shows it")
	var music_before: float = AudioMix.volume(AudioMix.MUSIC)
	var sfx_before: float = AudioMix.volume(AudioMix.SFX)
	m.hud.sound_panel.music_slider.value = 0.3
	m.hud.sound_panel.sfx_slider.value = 0.0
	check(absf(AudioMix.volume(AudioMix.MUSIC) - 0.3) < 0.001, "the music slider sets the music volume")
	var sfx_bus: int = AudioServer.get_bus_index(AudioMix.SFX)
	check(sfx_bus >= 0 and AudioServer.is_bus_mute(sfx_bus), "effects at zero silence the SFX bus")
	var music_bus: int = AudioServer.get_bus_index(AudioMix.MUSIC)
	check(music_bus >= 0 and AudioServer.get_bus_volume_db(music_bus) < 0.0, "the Music bus is turned down")
	AudioMix.set_volume(AudioMix.MUSIC, music_before)
	AudioMix.set_volume(AudioMix.SFX, sfx_before)
	m.hud.toggle_sound()
	check(Sfx.muted and m.hud.sound_panel.mute_toggle.button_pressed, "M mutes and the panel shows it")
	m.hud.sound_panel.mute_toggle.button_pressed = false
	check(not Sfx.muted and m.hud._sound_button.text == "Sound", "the panel's switch unmutes")
	m.queue_free()
	await frames(2)
	var tracks: PackedStringArray = Music.find_tracks()
	check(tracks.size() >= 8, "the playlist finds the soundtrack in subfolders (%d tracks)" % tracks.size())
	var saved: PackedStringArray = Music.tracks
	Music.tracks = tracks
	var last: String = tracks[0]
	var repeats: int = 0
	var picked: Dictionary[String, bool] = {}
	for i: int in 200:
		var next: String = Music.pick_next(last)
		if next == last:
			repeats += 1
		picked[next] = true
		last = next
	check(repeats == 0, "a track never plays twice in a row")
	check(picked.size() == tracks.size(), "every track comes up at random")
	Music.tracks = saved
