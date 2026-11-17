extends Node
## Plays a full AI-vs-AI skirmish on a generated map and reports how it went.
## Used as a soak test: the match must reach a winner with no script errors,
## no ship on land, no ship in water its hull cannot enter, and no fleet over the cap.
##
## Run:  godot --headless --path . --fixed-fps 60 res://tests/sim_match.tscn -- --seed=3
## Optional:  --max-minutes=N (default 60)   --ui (build HUD/fog/camera too)   --quiet

const MAIN_SCENE: String = "res://scenes/main.tscn"
const REPORT_INTERVAL: float = 120.0

var _match: Match = null
var _max_time: float = 3600.0
var _quiet: bool = false
var _next_report: float = REPORT_INTERVAL
var _violations: Array[String] = []
var _peak_fleet: Array[int] = [0, 0]
var _peak_projectiles: int = 0
var _built: Array[int] = [0, 0]
var _lost: Array[int] = [0, 0]
var _classes_built: Dictionary[String, int] = {}
var _captures: int = 0
## Island garrisons shot down, and islands captured again after falling.
var _garrisons_fallen: int = 0
var _retaken: int = 0
var _island_owner: Dictionary[Island, int] = {}
var _idle_since: Dictionary[Ship, float] = {}
var _stuck_reports: int = 0
## Per carrier (instance id): x = squadrons launched, y = squadrons shot down.
var _air_wings: Dictionary[int, Vector2i] = {}
## Per carrier: x = audits alive, y = audits with a strike ordered, z = audits with an enemy in plane range.
var _air_time: Dictionary[int, Vector3i] = {}
var _dd_torpedoes: Dictionary[int, int] = {}
var _dd_charges: Dictionary[int, int] = {}
var _wall_start: int = 0
## Per team: orders sent at the previous physics frame, and sim time of the last order.
var _orders_seen: Array[int] = [0, 0]
var _last_order_time: Array[float] = [-1000.0, -1000.0]
var _done: bool = false


func _ready() -> void:
	var seed_value: int = 1
	var with_ui: bool = false
	var levels: Array[int] = [int(GameSettings.Difficulty.HARD), int(GameSettings.Difficulty.HARD)]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--max-minutes="):
			_max_time = float(arg.trim_prefix("--max-minutes=")) * 60.0
		elif arg == "--ui":
			with_ui = true
		elif arg == "--quiet":
			_quiet = true
		elif arg.begins_with("--difficulty="):
			var level: int = int(GameSettings.difficulty_from_name(arg.trim_prefix("--difficulty=")))
			levels = [level, level]
		elif arg.begins_with("--difficulty0="):
			levels[0] = int(GameSettings.difficulty_from_name(arg.trim_prefix("--difficulty0=")))
		elif arg.begins_with("--difficulty1="):
			levels[1] = int(GameSettings.difficulty_from_name(arg.trim_prefix("--difficulty1=")))
	_match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	_match.map_seed = seed_value
	_match.team_control = [Match.ControlType.AI, Match.ControlType.AI]
	_match.ai_difficulty = levels
	_match.create_ui = with_ui
	_match.ship_spawned.connect(_on_ship_spawned)
	_match.match_ended.connect(_on_match_ended)
	add_child(_match)
	for island: Island in _match.islands:
		if island.is_capturable():
			_island_owner[island] = island.owner_team
			island.owner_changed.connect(_on_island_owner_changed)
	_wall_start = Time.get_ticks_msec()
	print("SIM seed=%d islands=%d ui=%s difficulty=%s/%s" % [seed_value, _match.islands.size(), with_ui,
		GameSettings.difficulty_name(levels[0] as GameSettings.Difficulty),
		GameSettings.difficulty_name(levels[1] as GameSettings.Difficulty)])


func _on_island_owner_changed(island: Island, new_owner: int) -> void:
	var previous: int = _island_owner.get(island, -1)
	_island_owner[island] = new_owner
	if new_owner >= 0:
		_captures += 1
		if island.times_fallen > 0:
			_retaken += 1
		if previous >= 0:
			_violation("island changed hands without its garrison falling")
		if island.garrison == null or island.garrison.team != new_owner or island.garrison.hp < island.garrison.max_hp:
			_violation("captured island has no fresh garrison")
	else:
		_garrisons_fallen += 1


func _on_ship_spawned(ship: Ship) -> void:
	_built[ship.team] += 1
	var key: String = "%d:%s" % [ship.team, ship.stats.code]
	_classes_built[key] = int(_classes_built.get(key, 0)) + 1
	ship.destroyed.connect(func(_who: Combatant) -> void: _lost[ship.team] += 1)


func _violation(text: String) -> void:
	if _violations.size() < 25 and not _violations.has(text):
		_violations.append(text)
		print("VIOLATION t=%.0f %s" % [_match.sim_time, text])


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_audit_orders()
	if Engine.get_physics_frames() % 30 == 0:
		_audit()
	if _match.sim_time >= _next_report:
		_next_report += REPORT_INTERVAL
		if not _quiet:
			_report_line()
	if _match.sim_time >= _max_time:
		_finish("TIMEOUT")


## Easy and Medium may control only one ship at a time: never two orders in one interval.
func _audit_orders() -> void:
	for ai: AIController in _match.ai_controllers:
		var sent: int = ai.orders_sent - _orders_seen[ai.team]
		if sent <= 0:
			continue
		_orders_seen[ai.team] = ai.orders_sent
		if not ai.is_limited():
			continue
		if sent > 1 or _match.sim_time - _last_order_time[ai.team] < ai.order_interval() - 0.05:
			_violation("%s AI of team %d gave more than one ship order at a time" % [
				GameSettings.difficulty_name(ai.difficulty), ai.team])
		_last_order_time[ai.team] = _match.sim_time


func _audit() -> void:
	var cap: int = GameData.balance().fleet_cap
	_peak_projectiles = maxi(_peak_projectiles, _match.projectile_count())
	for team: int in 2:
		var fleet: int = _match.fleet_count(team)
		_peak_fleet[team] = maxi(_peak_fleet[team], fleet)
		if fleet > cap:
			_violation("team %d fleet %d exceeds cap" % [team, fleet])
		if _match.economy.gold[team] < 0 or _match.economy.steel[team] < 0:
			_violation("team %d bank went negative" % team)
	for ship: Ship in _match.ships:
		if not ship.is_alive():
			continue
		for island: Island in _match.islands:
			var dist: float = ship.position.distance_to(island.position)
			if dist < island.radius * 0.8:
				_violation("%s of team %d is on land" % [ship.stats.code, ship.team])
			elif island.kind == Island.Kind.MINOR and not ship.stats.shallow_draft and dist < island.shallow_radius - 48.0:
				_violation("deep-draft %s of team %d is in shallow water" % [ship.stats.code, ship.team])
		if ship.under_construction and (ship.salvos_fired > 0 or ship.torpedoes_launched > 0 or ship.squadrons_launched > 0 \
					or ship.depth_charges_dropped > 0):
			_violation("hull under construction fired")
		if ship.stats.torpedo_mode == ShipStats.TorpedoMode.AUTO_BROADSIDE:
			_dd_torpedoes[ship.get_instance_id()] = ship.torpedoes_launched
			_dd_charges[ship.get_instance_id()] = ship.depth_charges_dropped
		if ship.stats.has_planes():
			_air_wings[ship.get_instance_id()] = Vector2i(ship.squadrons_launched, ship.squadrons_lost)
			if ship.is_combat_ready():
				var seen: Vector3i = _air_time.get(ship.get_instance_id(), Vector3i.ZERO)
				seen.x += 1
				if ship.air_target() != null:
					seen.y += 1
				for enemy: Combatant in _match.vision.spotted_enemies(ship.team):
					if enemy.is_alive() and ship.range_to(enemy) <= ship.stats.plane_range:
						seen.z += 1
						break
				_air_time[ship.get_instance_id()] = seen
			if ship.airborne_squadrons() > ship.stats.max_squadrons:
				_violation("carrier of team %d has %d squadrons airborne" % [ship.team, ship.airborne_squadrons()])
		if ship.position.x < -50.0 or ship.position.y < -50.0 \
				or ship.position.x > _match.map_data.size.x + 50.0 or ship.position.y > _match.map_data.size.y + 50.0:
			_violation("%s left the map" % ship.stats.code)
		# A ship that has somewhere to go but has not moved for 40s is stuck.
		if ship.is_combat_ready() and ship.has_destination() and ship.velocity.length() < 2.0:
			if not _idle_since.has(ship):
				_idle_since[ship] = _match.sim_time
			elif _match.sim_time - _idle_since[ship] > 40.0:
				_stuck_reports += 1
				_idle_since[ship] = _match.sim_time
				if _stuck_reports <= 8:
					print("STUCK t=%.0f %s team %d at %s -> %s blocked=%s attack=%s torp=%s" % [_match.sim_time,
						ship.stats.code, ship.team, ship.position.round(), ship.destination().round(),
						_match.nav.is_blocked(ship.position, ship.stats.shallow_draft),
						ship.priority_target != null, ship.torpedo_order != null])
		else:
			_idle_since.erase(ship)


func _report_line() -> void:
	var parts: Array[String] = []
	for team: int in 2:
		var owned: int = 0
		for island: Island in _match.islands:
			if island.owner_team == team:
				owned += 1
		var ai: AIController = _match.ai_controllers[team]
		parts.append("T%d fleet=%d isl=%d bank=%d/%d base=%.0f %s w%d" % [team, _match.fleet_count(team), owned,
			_match.economy.gold[team], _match.economy.steel[team], _match.bases[team].hp,
			AIController.ArmyState.keys()[ai.army_state], ai.waves_launched])
	print("t=%4.0fs  %s  |  %s  proj=%d" % [_match.sim_time, parts[0], parts[1], _match.projectile_count()])


func _on_match_ended(_winner: int) -> void:
	_finish.call_deferred("WINNER")


func _finish(outcome: String) -> void:
	if _done:
		return
	_done = true
	_report_line()
	var wall: float = float(Time.get_ticks_msec() - _wall_start) / 1000.0
	print("SIM RESULT %s winner=%d sim_time=%.0fs wall=%.1fs speed=%.0fx" % [outcome, _match.winner, _match.sim_time,
		wall, _match.sim_time / maxf(wall, 0.001)])
	print("  built=%s lost=%s peak_fleet=%s captures=%d peak_projectiles=%d stuck_reports=%d" % [
		_built, _lost, _peak_fleet, _captures, _peak_projectiles, _stuck_reports])
	var keys: Array = _classes_built.keys()
	keys.sort()
	var roster: Array[String] = []
	for key: String in keys:
		roster.append("%s=%d" % [key, _classes_built[key]])
	print("  classes: " + ", ".join(roster))
	var air: Vector2i = Vector2i.ZERO
	for wing: Vector2i in _air_wings.values():
		air += wing
	print("  carriers=%d squadrons_launched=%d squadrons_shot_down=%d" % [_air_wings.size(), air.x, air.y])
	var air_time: Vector3i = Vector3i.ZERO
	for seen: Vector3i in _air_time.values():
		air_time += seen
	print("  carrier seconds: afloat=%.0f striking=%.0f enemy_in_plane_range=%.0f" % [
		float(air_time.x) * 0.5, float(air_time.y) * 0.5, float(air_time.z) * 0.5])
	var dd_torpedoes: int = 0
	for count: int in _dd_torpedoes.values():
		dd_torpedoes += count
	var dd_charges: int = 0
	for count: int in _dd_charges.values():
		dd_charges += count
	print("  destroyers=%d torpedoes_launched=%d depth_charges=%d" % [_dd_torpedoes.size(), dd_torpedoes, dd_charges])
	print("  garrisons_fallen=%d islands_retaken=%d orders=%s" % [_garrisons_fallen, _retaken, _orders_seen])
	print("  violations=%d" % _violations.size())
	var ok: bool = outcome == "WINNER" and _violations.is_empty()
	print("SIM " + ("OK" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
