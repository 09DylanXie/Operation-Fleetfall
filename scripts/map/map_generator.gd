class_name MapGenerator
extends RefCounted
## Seeded procedural archipelago generator. One half of the map is generated and
## point-mirrored through the centre so both players get an equivalent layout.
## A layout is only accepted if every objective is reachable by the hulls that need it.

const MAX_ATTEMPTS: int = 40
const PLACEMENT_TRIES: int = 220
const BLOB_POINTS: int = 14


static func generate(seed_value: int, cfg: MapConfig, base_radius: float) -> MapData:
	var last: MapData = null
	for attempt: int in MAX_ATTEMPTS:
		var attempt_seed: int = seed_value + attempt * 7919
		var map: MapData = _build(attempt_seed, cfg, base_radius)
		if map == null:
			continue
		last = map
		if validate(map):
			return map
	if last == null:
		last = _fallback(seed_value, cfg, base_radius)
	return last


## Every capture node must be reachable from both bases by a hull that can use it.
static func validate(map: MapData) -> bool:
	if map.base_positions.size() != 2:
		return false
	var nav: NavGrid = NavGrid.from_map(map)
	var harbors: Array[Vector2] = []
	for base_pos: Vector2 in map.base_positions:
		var dir: Vector2 = (map.center() - base_pos).normalized()
		harbors.append(nav.nearest_free(base_pos + dir * (map.base_radius + 110.0), false))
	if not nav.is_reachable(harbors[0], harbors[1], false):
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


static func _build(seed_value: int, cfg: MapConfig, base_radius: float) -> MapData:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var map: MapData = MapData.new()
	map.size = cfg.map_size
	map.seed_used = seed_value
	map.cell_size = cfg.cell_size
	map.clearance = cfg.island_clearance
	map.base_radius = base_radius

	# Each entry is Vector3(x, y, exclusion_radius).
	var placed: Array[Vector3] = []
	var size: Vector2 = cfg.map_size
	var base0: Vector2 = Vector2(
		cfg.base_margin_x, size.y * 0.5 + rng.randf_range(-size.y * 0.22, size.y * 0.22))
	var base1: Vector2 = size - base0
	map.base_positions = [base0, base1]
	placed.append(Vector3(base0.x, base0.y, cfg.base_clear_radius))
	placed.append(Vector3(base1.x, base1.y, cfg.base_clear_radius))

	if cfg.center_major:
		var c: Vector2 = size * 0.5
		map.add_island(MapData.KIND_MAJOR, c, cfg.major_radius, 0.0, make_blob(rng, cfg.major_radius))
		placed.append(Vector3(c.x, c.y, cfg.major_radius + cfg.feature_gap))

	for i: int in cfg.major_per_side:
		var excl: float = cfg.major_radius + cfg.feature_gap
		var pos: Vector2 = _place(rng, cfg, placed, excl, 1000.0, size.x * 0.5 - 500.0, 320.0)
		if pos == Vector2.INF:
			return null
		_add_mirrored(map, placed, rng, MapData.KIND_MAJOR, pos, cfg.major_radius, 0.0, excl)

	for i: int in cfg.minor_per_side:
		var excl: float = cfg.minor_shallow_radius + 60.0
		var pos: Vector2 = _place(rng, cfg, placed, excl, 700.0, size.x * 0.5 - 420.0, 380.0)
		if pos == Vector2.INF:
			return null
		_add_mirrored(map, placed, rng, MapData.KIND_MINOR, pos, cfg.minor_radius,
			cfg.minor_shallow_radius, excl)

	for i: int in cfg.cover_per_side:
		var radius: float = rng.randf_range(cfg.cover_radius_min, cfg.cover_radius_max)
		var excl: float = radius + cfg.feature_gap
		var pos: Vector2 = _place(rng, cfg, placed, excl, 420.0, size.x * 0.5 - 200.0, 200.0)
		if pos == Vector2.INF:
			continue
		_add_mirrored(map, placed, rng, MapData.KIND_COVER, pos, radius, 0.0, excl)
	return map


static func _add_mirrored(map: MapData, placed: Array[Vector3], rng: RandomNumberGenerator,
		kind: int, pos: Vector2, radius: float, shallow_radius: float, excl: float) -> void:
	var poly: PackedVector2Array = make_blob(rng, radius)
	var mirrored_poly: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in poly:
		mirrored_poly.append(-p)
	var mirror: Vector2 = map.size - pos
	map.add_island(kind, pos, radius, shallow_radius, poly)
	map.add_island(kind, mirror, radius, shallow_radius, mirrored_poly)
	placed.append(Vector3(pos.x, pos.y, excl))
	placed.append(Vector3(mirror.x, mirror.y, excl))


## Rejection-samples a spot on the left half that clears every placed feature and its own mirror.
static func _place(rng: RandomNumberGenerator, cfg: MapConfig, placed: Array[Vector3],
		excl: float, min_x: float, max_x: float, margin_y: float) -> Vector2:
	var size: Vector2 = cfg.map_size
	for attempt: int in PLACEMENT_TRIES:
		var pos: Vector2 = Vector2(
			rng.randf_range(min_x, maxf(min_x + 1.0, max_x)),
			rng.randf_range(margin_y, size.y - margin_y))
		var mirror: Vector2 = size - pos
		if pos.distance_to(mirror) < excl * 2.0:
			continue
		var ok: bool = true
		for other: Vector3 in placed:
			if pos.distance_to(Vector2(other.x, other.y)) < excl + other.z:
				ok = false
				break
		if ok:
			return pos
	return Vector2.INF


## Minimal always-valid map, only used if generation fails for every attempt.
static func _fallback(seed_value: int, cfg: MapConfig, base_radius: float) -> MapData:
	var map: MapData = MapData.new()
	map.size = cfg.map_size
	map.seed_used = seed_value
	map.cell_size = cfg.cell_size
	map.clearance = cfg.island_clearance
	map.base_radius = base_radius
	var size: Vector2 = cfg.map_size
	map.base_positions = [Vector2(cfg.base_margin_x, size.y * 0.5),
		Vector2(size.x - cfg.base_margin_x, size.y * 0.5)]
	map.add_island(MapData.KIND_MAJOR, size * 0.5, cfg.major_radius, 0.0,
		MapData.circle_polygon(cfg.major_radius))
	for side: float in [0.25, 0.75]:
		map.add_island(MapData.KIND_MINOR, Vector2(size.x * side, size.y * 0.22), cfg.minor_radius,
			cfg.minor_shallow_radius, MapData.circle_polygon(cfg.minor_radius))
		map.add_island(MapData.KIND_MINOR, Vector2(size.x * side, size.y * 0.78), cfg.minor_radius,
			cfg.minor_shallow_radius, MapData.circle_polygon(cfg.minor_radius))
	return map
