extends Node
## Balance check: two hand-picked squads fight on open water until one side is gone.
##
## Run:  godot --headless --path . --fixed-fps 60 res://tests/duel.tscn -- --a=DD:5 --b=CL:2
## Optional:  --pass   team A sails past team B (broadside) instead of attacking head-on.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const MAX_TIME: float = 600.0

var _match: Match = null
var _sail_past: bool = false
var _cost: Array[int] = [0, 0]
var _start_hp: Array[float] = [0.0, 0.0]
var _retarget: float = 0.0
var _done: bool = false
var _labels: Array[String] = ["", ""]
## Torpedoes launched per ship (instance id), kept after the ship sinks.
var _torpedoes: Array[Dictionary] = [{}, {}]


func _ready() -> void:
	var specs: Array[String] = ["DD:5", "CL:2"]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--a="):
			specs[0] = arg.trim_prefix("--a=")
		elif arg.begins_with("--b="):
			specs[1] = arg.trim_prefix("--b=")
		elif arg == "--pass":
			_sail_past = true
	var map: MapData = MapData.new()
	map.size = Vector2(6000.0, 3000.0)
	map.base_positions = [Vector2(200.0, 1500.0), Vector2(5800.0, 1500.0)]
	_match = (load(MAIN_SCENE) as PackedScene).instantiate() as Match
	_match.map_override = map
	_match.map_seed = 7
	_match.team_control = [Match.ControlType.NONE, Match.ControlType.NONE]
	_match.create_ui = false
	_match.enable_weather = false
	add_child(_match)
	for team: int in 2:
		_labels[team] = specs[team]
		var parts: PackedStringArray = specs[team].split(":")
		var stats: ShipStats = null
		for cls: ShipStats.ShipClass in GameData.all_classes():
			if GameData.ship(cls).code == parts[0]:
				stats = GameData.ship(cls)
		var count: int = int(parts[1]) if parts.size() > 1 else 1
		for i: int in count:
			var at: Vector2 = Vector2(2400.0 if team == 0 else 3600.0, 1500.0 + 110.0 * (float(i) - float(count - 1) * 0.5))
			if _sail_past and team == 0:
				at = Vector2(2700.0 + 110.0 * float(i), 1950.0)
			var ship: Ship = _match.spawn_ship(stats.ship_class, team, at, 0.0 if team == 0 else PI)
			_cost[team] += stats.gold_cost
			_start_hp[team] += ship.max_hp
			if _sail_past and team == 0:
				ship.order_move(Vector2(4500.0 + 110.0 * float(i), 1950.0))


func _physics_process(delta: float) -> void:
	if _done:
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 1.0
		for team: int in 2:
			if _sail_past and team == 0:
				continue
			var foes: Array[Ship] = _match.ships_of(1 - team)
			for ship: Ship in _match.ships_of(team):
				if ship.priority_target != null or ship.torpedo_order != null or foes.is_empty():
					continue
				var best: Ship = foes[0]
				for foe: Ship in foes:
					if ship.position.distance_to(foe.position) < ship.position.distance_to(best.position):
						best = foe
				ship.order_attack(best)
	for ship: Ship in _match.ships:
		if is_instance_valid(ship):
			_torpedoes[ship.team][ship.get_instance_id()] = ship.torpedoes_launched
	var alive: Array[int] = [_match.ships_of(0).size(), _match.ships_of(1).size()]
	if alive[0] == 0 or alive[1] == 0 or _match.sim_time >= MAX_TIME:
		_done = true
		var hp: Array[float] = [0.0, 0.0]
		var torps: Array[int] = [0, 0]
		for team: int in 2:
			for ship: Ship in _match.ships_of(team):
				hp[team] += ship.hp
			for count: int in _torpedoes[team].values():
				torps[team] += count
		var winner: String = "DRAW/TIMEOUT"
		if alive[0] > 0 and alive[1] == 0:
			winner = "A"
		elif alive[1] > 0 and alive[0] == 0:
			winner = "B"
		print("DUEL A=%s (%dG) vs B=%s (%dG)%s -> winner %s at %.0fs | A left %d (%.0f%% hp) | B left %d (%.0f%% hp) | torpedoes launched A %d, B %d" % [
			_labels[0], _cost[0], _labels[1], _cost[1], " [A sails past]" if _sail_past else "", winner, _match.sim_time,
			alive[0], 100.0 * hp[0] / _start_hp[0], alive[1], 100.0 * hp[1] / _start_hp[1], torps[0], torps[1]])
		get_tree().quit(0)
