class_name MapGenerator
extends RefCounted
## Seeded procedural archipelago generator. The sea is a circle with one Home Base per
## player spaced evenly round its rim. One player's wedge is generated and rotated round
## the centre once per player, so everybody gets an equivalent layout (with two players
## that is a point mirror). A layout is only accepted if every objective is reachable by
## the hulls that need it.

const MAX_ATTEMPTS: int = 40
const PLACEMENT_TRIES: int = 220
const BLOB_POINTS: int = 14
## Open water kept between a feature's centre and the rim of the sea.
const MAJOR_EDGE_MARGIN: float = 320.0
const MINOR_EDGE_MARGIN: float = 380.0
const COVER_EDGE_MARGIN: float = 200.0


static func generate(seed_value: int, cfg: MapConfig, base_radius: float, players: int = 2) -> MapData:
	var count: int = clampi(players, 2, Layers.MAX_TEAMS)
	var last: MapData = null
	for attempt: int in MAX_ATTEMPTS:
		var attempt_seed: int = seed_value + attempt * 7919
		var map: MapData = _build(attempt_seed, cfg, base_radius, count)
		if map == null:
			continue
		last = map
		if validate(map):
			return map
	if last == null:
		last = _fallback(seed_value, cfg, base_radius, count)
	return last


## Every base must be able to reach every other base, and every capture node must be
## reachable from every base by a hull that can use it.
static func validate(map: MapData) -> bool:
	if map.base_positions.size() < 2:
		return false
	var nav: NavGrid = NavGrid.from_map(map)
	var harbors: Array[Vector2] = []
	for base_pos: Vector2 in map.base_positions:
		var dir: Vector2 = (map.center() - base_pos).normalized()
		harbors.append(nav.nearest_free(base_pos + dir * (map.base_radius + 110.0), false))
	for i: int in range(1, harbors.size()):
		if not nav.is_reachable(harbors[0], harbors[i], false):
			return false
	for def: MapData.IslandDef in map.islands:
		if def.kind == MapData.KIND_COVER:
			continue
		var shallow: bool = def.kind == MapData.KIND_MINOR
		var dir_in: Vector2 = (map.center() - def.position).normalized()
		if dir_in == Vector2.ZERO:
			dir_in = Vector2.RIGHT
		var berth: Vector2 = nav.nearest_free(def.position + dir_in * (def.radius + 70.0), shallow)
		if berth.distance_to(def.position) > def.radius + 150.0:
			return false
		for harbor: Vector2 in harbors:
			if not nav.is_reachable(harbor, berth, shallow):
				return false
	return true


static func make_blob(rng: RandomNumberGenerator, radius: float) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	var phase: float = rng.randf() * TAU
	for i: int in BLOB_POINTS:
		var angle: float = phase + TAU * float(i) / float(BLOB_POINTS)
		poly.append(Vector2.from_angle(angle) * radius * rng.randf_range(0.78, 1.0))
	return poly


static func _new_map(seed_value: int, cfg: MapConfig, base_radius: float, players: int) -> MapData:
	var map: MapData = MapData.new()
	map.size = cfg.size_for(players)
	map.circular = true
	map.seed_used = seed_value
	map.cell_size = cfg.cell_size
	map.clearance = cfg.island_clearance
	map.base_radius = base_radius
	return map


static func _build(seed_value: int, cfg: MapConfig, base_radius: float, players: int) -> MapData:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var map: MapData = _new_map(seed_value, cfg, base_radius, players)
	var center: Vector2 = map.center()
	var step: float = TAU / float(players)
	# Player 1 starts roughly in the west; the others follow clockwise.
	var first_angle: float = PI + rng.randf_range(-0.35, 0.35)

	# Each entry is Vector3(x, y, exclusion_radius).
	var placed: Array[Vector3] = []
	for i: int in players:
		var base_pos: Vector2 = center + Vector2.from_angle(first_angle + step * float(i)) * (
			map.radius() - cfg.base_margin_x)
		map.base_positions.append(base_pos)
		placed.append(Vector3(base_pos.x, base_pos.y, cfg.base_clear_radius))

	if cfg.center_major:
		map.add_island(MapData.KIND_MAJOR, center, cfg.major_radius, 0.0, make_blob(rng, cfg.major_radius))
		placed.append(Vector3(center.x, center.y, cfg.major_radius + cfg.feature_gap))

	for i: int in cfg.major_per_side:
		var excl: float = cfg.major_radius + cfg.feature_gap
		var pos: Vector2 = _place(rng, map, placed, excl, first_angle, players, MAJOR_EDGE_MARGIN)
		if pos == Vector2.INF:
			return null
		_add_rotated(map, placed, rng, MapData.KIND_MAJOR, pos, cfg.major_radius, 0.0, excl, players)

	for i: int in cfg.minor_per_side:
		var excl: float = cfg.minor_shallow_radius + 60.0
		var pos: Vector2 = _place(rng, map, placed, excl, first_angle, players, MINOR_EDGE_MARGIN)
		if pos == Vector2.INF:
			return null
		_add_rotated(map, placed, rng, MapData.KIND_MINOR, pos, cfg.minor_radius,
			cfg.minor_shallow_radius, excl, players)

	for i: int in cfg.cover_per_side:
		var radius: float = rng.randf_range(cfg.cover_radius_min, cfg.cover_radius_max)
		var excl: float = radius + cfg.feature_gap
		var pos: Vector2 = _place(rng, map, placed, excl, first_angle, players, COVER_EDGE_MARGIN)
		if pos == Vector2.INF:
			continue
		_add_rotated(map, placed, rng, MapData.KIND_COVER, pos, radius, 0.0, excl, players)
	return map


## Adds the island and its copy in every other player's wedge.
static func _add_rotated(map: MapData, placed: Array[Vector3], rng: RandomNumberGenerator,
		kind: int, pos: Vector2, radius: float, shallow_radius: float, excl: float, players: int) -> void:
	var poly: PackedVector2Array = make_blob(rng, radius)
	var center: Vector2 = map.center()
	var step: float = TAU / float(players)
	for k: int in players:
		var turn: float = step * float(k)
		var copy: Vector2 = center + (pos - center).rotated(turn)
		var copy_poly: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in poly:
			copy_poly.append(p.rotated(turn))
		map.add_island(kind, copy, radius, shallow_radius, copy_poly)
		placed.append(Vector3(copy.x, copy.y, excl))


## Rejection-samples a spot in the first player's wedge that clears every placed feature
## and its own rotated copies.
static func _place(rng: RandomNumberGenerator, map: MapData, placed: Array[Vector3],
		excl: float, first_angle: float, players: int, edge_margin: float) -> Vector2:
	var center: Vector2 = map.center()
	var step: float = TAU / float(players)
	var reach: float = maxf(1.0, map.radius() - edge_margin)
	for attempt: int in PLACEMENT_TRIES:
		var angle: float = first_angle + rng.randf_range(-0.5, 0.5) * step
		var pos: Vector2 = center + Vector2.from_angle(angle) * sqrt(rng.randf()) * reach
		var ok: bool = true
		for k: int in range(1, players):
			if pos.distance_to(center + (pos - center).rotated(step * float(k))) < excl * 2.0:
				ok = false
				break
		if not ok:
			continue
		for other: Vector3 in placed:
			if pos.distance_to(Vector2(other.x, other.y)) < excl + other.z:
				ok = false
				break
		if ok:
			return pos
	return Vector2.INF


## Minimal always-valid map, only used if generation fails for every attempt.
static func _fallback(seed_value: int, cfg: MapConfig, base_radius: float, players: int) -> MapData:
	var map: MapData = _new_map(seed_value, cfg, base_radius, players)
	var center: Vector2 = map.center()
	var step: float = TAU / float(players)
	map.add_island(MapData.KIND_MAJOR, center, cfg.major_radius, 0.0,
		MapData.circle_polygon(cfg.major_radius))
	for i: int in players:
		var angle: float = PI + step * float(i)
		map.base_positions.append(center + Vector2.from_angle(angle) * (map.radius() - cfg.base_margin_x))
		# One Minor island half-way between each pair of neighbouring bases.
		map.add_island(MapData.KIND_MINOR, center + Vector2.from_angle(angle + step * 0.5) * map.radius() * 0.55,
			cfg.minor_radius, cfg.minor_shallow_radius, MapData.circle_polygon(cfg.minor_radius))
	return map
