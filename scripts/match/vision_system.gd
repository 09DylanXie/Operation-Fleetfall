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
## Per team: the hostile combatants it can currently see (each an Array[Combatant]).
var _spotted: Array[Array] = []
## Per team: Vector3(x, y, range) for every vision source, its allies' included.
var _sources: Array[PackedVector3Array] = []
## Per team: the circles the fog overlay clears (vision sources plus a small disc round own ships).
var _fog_sources: Array[PackedVector3Array] = []
## Per team: Vector3(x, y, range) for every submarine detector.
var _detectors: Array[PackedVector3Array] = []
## Per team: radar (Radar Ships) that sees surface ships over islands, no line of sight needed.
var _radar: Array[PackedVector3Array] = []


func setup(p_match: Match) -> void:
	match_ref = p_match
	for team: int in Layers.MAX_TEAMS:
		var none: Array[Combatant] = []
		_spotted.append(none)
		_sources.append(PackedVector3Array())
		_fog_sources.append(PackedVector3Array())
		_detectors.append(PackedVector3Array())
		_radar.append(PackedVector3Array())


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over:
		return
	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum -= UPDATE_INTERVAL
		update_now()


## Enemies currently visible to `team`. Refreshed every UPDATE_INTERVAL.
func spotted_enemies(team: int) -> Array[Combatant]:
	return _spotted[team]


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
	var count: int = match_ref.team_count
	var own_src: Array[PackedVector3Array] = []
	var own_fog: Array[PackedVector3Array] = []
	var own_det: Array[PackedVector3Array] = []
	var own_radar: Array[PackedVector3Array] = []
	for team: int in count:
		var radar: PackedVector3Array = PackedVector3Array()
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
			src.append(Vector3(island.position.x, island.position.y, island.spotting_range()))
			if island.shipyard != null and island.shipyard.tier > 0:
				det.append(Vector3(island.position.x, island.position.y, balance.sub_detection_range + island.radius))
		for ship: Ship in match_ref.ships:
			if ship.team != team or not ship.is_combat_ready():
				continue
			# A hull with no spotting range (Submarines) sees nothing at all.
			var reach: float = ship.stats.spotting_range * match_ref.spotting_multiplier_at(ship.position)
			if reach > 0.0:
				src.append(Vector3(ship.position.x, ship.position.y, reach))
				if ship.stats.sees_over_islands:
					radar.append(Vector3(ship.position.x, ship.position.y, reach))
			if reach < OWN_SHIP_FOG_RADIUS:
				fog.append(Vector3(ship.position.x, ship.position.y, OWN_SHIP_FOG_RADIUS))
			if ship.stats.detects_submarines:
				det.append(Vector3(ship.position.x, ship.position.y, balance.sub_detection_range))
		own_src.append(src)
		own_fog.append(src + fog)
		own_det.append(det)
		own_radar.append(radar)
	# Vision is shared inside an alliance: a team sees with its own eyes and its allies'.
	for team: int in count:
		var all_src: PackedVector3Array = PackedVector3Array()
		var all_fog: PackedVector3Array = PackedVector3Array()
		var all_det: PackedVector3Array = PackedVector3Array()
		var all_radar: PackedVector3Array = PackedVector3Array()
		for other: int in count:
			if other == team or match_ref.are_allies(team, other):
				all_src += own_src[other]
				all_fog += own_fog[other]
				all_det += own_det[other]
				all_radar += own_radar[other]
		_radar[team] = all_radar
		_sources[team] = all_src
		_fog_sources[team] = all_fog
		_detectors[team] = all_det
	for team: int in count:
		var seen: Array[Combatant] = []
		for ship: Ship in match_ref.ships:
			if not ship.is_alive() or not match_ref.are_enemies(ship.team, team):
				continue
			var vis: bool = _is_ship_visible(ship, team)
			_set_spotted(ship, team, vis)
			if vis:
				seen.append(ship)
		for base: HomeBase in match_ref.bases:
			if not base.is_alive() or not match_ref.are_enemies(base.team, team):
				continue
			var vis_base: bool = _any_source_sees(_sources[team], base.position, base.radius) \
				or _radar_sees(team, base.position, base.radius)
			_set_spotted(base, team, vis_base)
			if vis_base:
				seen.append(base)
		for fort: IslandGarrison in match_ref.garrisons:
			if fort.team < 0 or not match_ref.are_enemies(fort.team, team):
				continue
			var vis_fort: bool = _any_source_sees(_sources[team], fort.position, fort.island.radius, fort.island) \
				or _radar_sees(team, fort.position, fort.island.radius)
			_set_spotted(fort, team, vis_fort)
			if vis_fort:
				seen.append(fort)
		_spotted[team] = seen
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
	return _any_source_sees(_sources[team], ship.position, 0.0) or _radar_sees(team, ship.position, 0.0)


## Radar Ship radar: range only, islands do not block it (surface targets only).
func _radar_sees(team: int, point: Vector2, padding: float) -> bool:
	for source: Vector3 in _radar[team]:
		var reach: float = source.z + padding
		if Vector2(source.x, source.y).distance_squared_to(point) <= reach * reach:
			return true
	return false


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
