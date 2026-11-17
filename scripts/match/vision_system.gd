class_name VisionSystem
extends Node
## Team-shared fog of war. Runs at 5 Hz. An enemy is spotted when any friendly
## observer has it inside its (weather-adjusted) spotting range with a line of
## sight that no island blocks. Submarines are only revealed by enemy Destroyers
## and Shipyards at close range, or by their own torpedo-launch penalty.

signal vision_updated

const UPDATE_INTERVAL: float = 0.2
## The fog is always lifted this far around a team's own ships, even ones that spot nothing.
const OWN_SHIP_FOG_RADIUS: float = 110.0

var match_ref: Match = null
var _accum: float = 0.0
var _spotted_team_0: Array[Combatant] = []
var _spotted_team_1: Array[Combatant] = []
## Per team: Vector3(x, y, range) for every vision source.
var _sources: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
## Per team: the circles the fog overlay clears (vision sources plus a small disc round own ships).
var _fog_sources: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
## Per team: Vector3(x, y, range) for every submarine detector.
var _detectors: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]


func setup(p_match: Match) -> void:
	match_ref = p_match


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over:
		return
	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum -= UPDATE_INTERVAL
		update_now()


## Enemies currently visible to `team`. Refreshed every UPDATE_INTERVAL.
func spotted_enemies(team: int) -> Array[Combatant]:
	return _spotted_team_0 if team == 0 else _spotted_team_1


func sources(team: int) -> PackedVector3Array:
	return _sources[team]


func fog_sources(team: int) -> PackedVector3Array:
	return _fog_sources[team]


## Circle-only test (no LOS), used for cosmetic fog checks on projectiles and effects.
func is_point_in_vision(team: int, point: Vector2) -> bool:
	for source: Vector3 in _fog_sources[team]:
		if Vector2(source.x, source.y).distance_squared_to(point) <= source.z * source.z:
			return true
	return false


func update_now() -> void:
	var balance: GameBalance = GameData.balance()
	for team: int in 2:
		var src: PackedVector3Array = PackedVector3Array()
		var fog: PackedVector3Array = PackedVector3Array()
		var det: PackedVector3Array = PackedVector3Array()
		if team < match_ref.bases.size():
			var base: HomeBase = match_ref.bases[team]
			if base.is_alive():
				src.append(Vector3(base.position.x, base.position.y, balance.home_base_spotting))
				det.append(Vector3(base.position.x, base.position.y, balance.sub_detection_range + base.radius))
		for island: Island in match_ref.islands:
			if island.owner_team != team:
				continue
			src.append(Vector3(island.position.x, island.position.y, balance.island_spotting))
			if island.shipyard != null and island.shipyard.tier > 0:
				det.append(Vector3(island.position.x, island.position.y, balance.sub_detection_range + island.radius))
		for ship: Ship in match_ref.ships:
			if ship.team != team or not ship.is_combat_ready():
				continue
			# A hull with no spotting range (Submarines) sees nothing at all.
			var reach: float = ship.stats.spotting_range * match_ref.spotting_multiplier_at(ship.position)
			if reach > 0.0:
				src.append(Vector3(ship.position.x, ship.position.y, reach))
			if reach < OWN_SHIP_FOG_RADIUS:
				fog.append(Vector3(ship.position.x, ship.position.y, OWN_SHIP_FOG_RADIUS))
			if ship.stats.detects_submarines:
				det.append(Vector3(ship.position.x, ship.position.y, balance.sub_detection_range))
		_sources[team] = src
		_fog_sources[team] = src + fog
		_detectors[team] = det
	for team: int in 2:
		var enemy_team: int = 1 - team
		var seen: Array[Combatant] = []
		for ship: Ship in match_ref.ships:
			if ship.team != enemy_team or not ship.is_alive():
				continue
			var vis: bool = _is_ship_visible(ship, team)
			_set_spotted(ship, team, vis)
			if vis:
				seen.append(ship)
		if enemy_team < match_ref.bases.size():
			var base: HomeBase = match_ref.bases[enemy_team]
			if base.is_alive():
				var vis_base: bool = _any_source_sees(_sources[team], base.position, base.radius)
				_set_spotted(base, team, vis_base)
				if vis_base:
					seen.append(base)
		for fort: IslandGarrison in match_ref.garrisons:
			if fort.team != enemy_team:
				continue
			var vis_fort: bool = _any_source_sees(_sources[team], fort.position, fort.island.radius, fort.island)
			_set_spotted(fort, team, vis_fort)
			if vis_fort:
				seen.append(fort)
		if team == 0:
			_spotted_team_0 = seen
		else:
			_spotted_team_1 = seen
	vision_updated.emit()


func _set_spotted(target: Combatant, team: int, value: bool) -> void:
	target.spotted_by[team] = value
	if value:
		target.last_known_position[team] = target.position


func _is_ship_visible(ship: Ship, team: int) -> bool:
	if ship.reveal_timer > 0.0:
		return true
	if ship.stats.is_submarine and not ship.under_construction:
		return _any_source_sees(_detectors[team], ship.position, 0.0)
	return _any_source_sees(_sources[team], ship.position, 0.0)


func _any_source_sees(list: PackedVector3Array, point: Vector2, padding: float,
		ignore: CollisionObject2D = null) -> bool:
	for source: Vector3 in list:
		var origin: Vector2 = Vector2(source.x, source.y)
		var reach: float = source.z + padding
		if origin.distance_squared_to(point) > reach * reach:
			continue
		if match_ref.has_los(origin, point, ignore):
			return true
	return false
