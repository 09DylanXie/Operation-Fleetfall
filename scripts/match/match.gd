class_name Match
extends Node2D
## Root of a skirmish. Owns the world, the systems (economy, vision, weather,
## navigation) and the controllers. Ships, yards and the AI all act through
## the small API here so the player and the AI use exactly the same commands.
##
## Command-line user args (after "--"): --seed=N  --ai-vs-ai  --size=small|medium|large

signal match_ended(winner: int)
signal ship_spawned(ship: Ship)

enum ControlType { HUMAN, AI, NONE }

const SHIP_SCENE: String = "res://scenes/ships/ship.tscn"
const ISLAND_SCENE: String = "res://scenes/environment/island.tscn"
const HOME_BASE_SCENE: String = "res://scenes/environment/home_base.tscn"
const WEATHER_SCENE: String = "res://scenes/environment/weather_front.tscn"
const SHELL_SCENE: String = "res://scenes/projectiles/shell.tscn"
const TORPEDO_SCENE: String = "res://scenes/projectiles/torpedo.tscn"
const SQUADRON_SCENE: String = "res://scenes/projectiles/plane_squadron.tscn"
const HUD_SCENE: String = "res://scenes/ui/hud.tscn"
const FORMATION_SPACING: float = 90.0
## Distance from a site's shore to its building slip (the longest hull must clear the shore).
const SLIP_OFFSET: float = 70.0

## 0 picks a random seed.
var map_seed: int = 0
## ControlType per team.
var team_control: Array[int] = [ControlType.HUMAN, ControlType.AI]
## GameSettings.Difficulty per team for AI teams; teams not listed use GameSettings.ai_difficulty.
var ai_difficulty: Array[int] = []
## Supply a hand-built map instead of generating one (used by tests).
var map_override: MapData = null
var create_ui: bool = true
## HUD toggle: draw the range rings of every ship of the local player, not just the selection.
var show_all_ranges: bool = false
var enable_weather: bool = true
## Reveal everything (no fog). Forced on when no human is playing.
var spectator: bool = false

var balance: GameBalance = null
var map_config: MapConfig = null
var map_data: MapData = null
var nav: NavGrid = null
var economy: Economy = null
var vision: VisionSystem = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var sim_time: float = 0.0
var ships: Array[Ship] = []
var bases: Array[HomeBase] = []
## One per capturable island, same order as the capturable islands.
var garrisons: Array[IslandGarrison] = []
var islands: Array[Island] = []
var yards: Array[Shipyard] = []
var fronts: Array[WeatherFront] = []
var ai_controllers: Array[AIController] = []
var player: PlayerController = null
var camera: CameraRig = null
var hud: HUD = null
var fog: FogOverlay = null
var local_team: int = 0
var winner: int = -1
var is_over: bool = false

var _ship_scene: PackedScene = null
var _island_scene: PackedScene = null
var _base_scene: PackedScene = null
var _weather_scene: PackedScene = null
var _shell_scene: PackedScene = null
var _torpedo_scene: PackedScene = null
var _squadron_scene: PackedScene = null
var _islands_root: Node2D = null
var _bases_root: Node2D = null
var _ships_root: Node2D = null
var _projectiles_root: Node2D = null
var _effects_root: Node2D = null
var _weather_root: Node2D = null
var _graveyard: Array[Combatant] = []
var _frame: int = 0


func _ready() -> void:
	_apply_cmdline()
	balance = GameData.balance()
	map_config = GameData.map_config_for(GameSettings.map_size)
	if map_seed == 0:
		var seeder: RandomNumberGenerator = RandomNumberGenerator.new()
		seeder.randomize()
		map_seed = seeder.randi_range(1, 999999)
	rng.seed = map_seed + 104729
	local_team = team_control.find(ControlType.HUMAN)
	if local_team < 0:
		spectator = true

	_ship_scene = load(SHIP_SCENE) as PackedScene
	_island_scene = load(ISLAND_SCENE) as PackedScene
	_base_scene = load(HOME_BASE_SCENE) as PackedScene
	_weather_scene = load(WEATHER_SCENE) as PackedScene
	_shell_scene = load(SHELL_SCENE) as PackedScene
	_torpedo_scene = load(TORPEDO_SCENE) as PackedScene
	_squadron_scene = load(SQUADRON_SCENE) as PackedScene

	if map_override != null:
		map_data = map_override
	else:
		map_data = MapGenerator.generate(map_seed, map_config, balance.home_base_radius)
	nav = NavGrid.from_map(map_data)

	_islands_root = _make_root("Islands")
	_bases_root = _make_root("Bases")
	_ships_root = _make_root("Ships")
	_projectiles_root = _make_root("Projectiles")
	_effects_root = _make_root("Effects")
	_weather_root = _make_root("Weather")

	economy = Economy.new()
	economy.name = "Economy"
	economy.setup(self)
	add_child(economy)
	vision = VisionSystem.new()
	vision.name = "Vision"
	vision.setup(self)
	add_child(vision)

	_spawn_world()
	_setup_controllers()
	if create_ui:
		_setup_ui()
	queue_redraw()


func _apply_cmdline() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--ai-vs-ai":
			team_control = [ControlType.AI, ControlType.AI]
		elif arg.begins_with("--seed="):
			map_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--size=") and not GameSettings.menu_shown:
			GameSettings.map_size = GameSettings.size_from_name(arg.trim_prefix("--size="))
		elif arg.begins_with("--difficulty=") and not GameSettings.menu_shown:
			GameSettings.ai_difficulty = GameSettings.difficulty_from_name(arg.trim_prefix("--difficulty="))


func _make_root(root_name: String) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = root_name
	add_child(node)
	return node


func _spawn_world() -> void:
	for def: MapData.IslandDef in map_data.islands:
		var island: Island = _island_scene.instantiate() as Island
		island.setup(def, self)
		_islands_root.add_child(island)
		islands.append(island)
		if island.shipyard != null:
			yards.append(island.shipyard)
			_configure_yard(island.shipyard, map_data.center(), island.kind == Island.Kind.MINOR)
			island.owner_changed.connect(_on_island_owner_changed)
			var fort: IslandGarrison = IslandGarrison.new()
			fort.name = "Garrison%d" % garrisons.size()
			fort.setup(island, self)
			_bases_root.add_child(fort)
			island.garrison = fort
			garrisons.append(fort)
	for team: int in map_data.base_positions.size():
		var base: HomeBase = _base_scene.instantiate() as HomeBase
		base.setup(team, self, map_data.base_positions[team])
		base.destroyed.connect(_on_combatant_destroyed)
		_bases_root.add_child(base)
		bases.append(base)
		yards.append(base.shipyard)
		_configure_yard(base.shipyard, map_data.center(), false)
	if enable_weather:
		for i: int in balance.weather_front_count:
			var front: WeatherFront = _weather_scene.instantiate() as WeatherFront
			var start: Vector2 = Vector2(
				rng.randf_range(map_data.size.x * 0.3, map_data.size.x * 0.7),
				rng.randf_range(map_data.size.y * 0.15, map_data.size.y * 0.85))
			front.setup(self, start, balance.weather_radius, balance.weather_speed)
			_weather_root.add_child(front)
			fronts.append(front)


## Places the slip and rally point on the side of the site facing `toward`.
func _configure_yard(yard: Shipyard, toward: Vector2, shallow: bool) -> void:
	var dir: Vector2 = (toward - yard.site_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	yard.slip_position = nav.nearest_free(yard.site_position + dir * (yard.site_radius + SLIP_OFFSET), shallow)
	yard.slip_rotation = dir.angle()
	yard.rally_point = nav.nearest_free(yard.site_position + dir * (yard.site_radius + 240.0), shallow)


func _on_island_owner_changed(island: Island, new_owner: int) -> void:
	if new_owner >= 0 and new_owner < bases.size():
		# Launch new hulls on the friendly side of the island.
		_configure_yard(island.shipyard, bases[new_owner].position, island.kind == Island.Kind.MINOR)


func _setup_controllers() -> void:
	for team: int in team_control.size():
		if team_control[team] == ControlType.AI:
			var ai: AIController = AIController.new()
			ai.name = "AI%d" % team
			var level: GameSettings.Difficulty = GameSettings.ai_difficulty
			if team < ai_difficulty.size():
				level = ai_difficulty[team] as GameSettings.Difficulty
			ai.setup(self, team, level)
			add_child(ai)
			ai_controllers.append(ai)


func _setup_ui() -> void:
	fog = FogOverlay.new()
	fog.name = "Fog"
	fog.setup(self)
	add_child(fog)
	camera = CameraRig.new()
	camera.name = "Camera"
	camera.setup(self)
	add_child(camera)
	hud = (load(HUD_SCENE) as PackedScene).instantiate() as HUD
	add_child(hud)
	player = PlayerController.new()
	player.name = "Player"
	player.setup(self, maxi(local_team, 0))
	player.input_enabled = local_team >= 0
	add_child(player)
	hud.setup(self)
	var focus_team: int = maxi(local_team, 0)
	if focus_team < bases.size():
		camera.position = bases[focus_team].position
	else:
		camera.position = map_data.center()


func _physics_process(delta: float) -> void:
	if is_over:
		return
	sim_time += delta
	_frame += 1
	if _frame % 2 == 0:
		_separate_ships()


func _process(_delta: float) -> void:
	if not create_ui:
		return
	for ship: Ship in ships:
		ship.visible = is_combatant_visible_to_local(ship)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for dead: Combatant in _graveyard:
			if is_instance_valid(dead) and not dead.is_inside_tree():
				dead.free()


# --- Queries ----------------------------------------------------------------

## Ships that count toward the cap: afloat, on the slip, and queued.
func fleet_count(team: int) -> int:
	var count: int = 0
	for ship: Ship in ships:
		if ship.team == team and ship.is_alive():
			count += 1
	for yard: Shipyard in yards:
		if yard.team == team:
			count += yard.pending_ship_orders()
	return count


func yards_of(team: int) -> Array[Shipyard]:
	var result: Array[Shipyard] = []
	for yard: Shipyard in yards:
		if yard.team == team:
			result.append(yard)
	return result


func ships_of(team: int, combat_ready_only: bool = true) -> Array[Ship]:
	var result: Array[Ship] = []
	for ship: Ship in ships:
		if ship.team != team or not ship.is_alive():
			continue
		if combat_ready_only and ship.under_construction:
			continue
		result.append(ship)
	return result


## True when no island lies on the segment a-b. `ignore` is left out of the test (the
## island an island garrison stands on).
func has_los(a: Vector2, b: Vector2, ignore: CollisionObject2D = null) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, Layers.ISLANDS)
	if ignore != null:
		query.exclude = [ignore.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Swept test for a projectile of `team`: first island or enemy hull on the segment.
## Submerged submarines the firing team cannot see are passed over.
func cast_projectile(from: Vector2, to: Vector2, team: int) -> Dictionary:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		from, to, Layers.ISLANDS | Layers.enemy_hitbox(team))
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = true
	var excluded: Array[RID] = []
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for i: int in 6:
		query.exclude = excluded
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return hit
		var collider: Object = hit["collider"]
		if collider is Ship:
			var ship: Ship = collider as Ship
			if ship.stats.is_submarine and not ship.under_construction and not ship.spotted_by[team]:
				excluded.append(ship.get_rid())
				continue
		return hit
	return {}


func spotting_multiplier_at(point: Vector2) -> float:
	for front: WeatherFront in fronts:
		if front.contains(point):
			return balance.weather_spotting_multiplier
	return 1.0


func is_combatant_visible_to_local(target: Combatant) -> bool:
	if spectator or local_team < 0 or target.team == local_team:
		return true
	return target.spotted_by[local_team]


func is_point_visible_to_local(point: Vector2, owner_team: int) -> bool:
	if spectator or local_team < 0 or owner_team == local_team:
		return true
	return vision.is_point_in_vision(local_team, point)


# --- Spawning ---------------------------------------------------------------

func spawn_ship(ship_class: ShipStats.ShipClass, team: int, at: Vector2, heading: float = 0.0,
		under_construction: bool = false) -> Ship:
	var ship: Ship = _ship_scene.instantiate() as Ship
	ship.setup(GameData.ship(ship_class), team, self, under_construction)
	ship.position = at
	ship.rotation = heading
	ship.destroyed.connect(_on_combatant_destroyed)
	_ships_root.add_child(ship)
	ships.append(ship)
	if create_ui:
		ship.visible = is_combatant_visible_to_local(ship)
	ship_spawned.emit(ship)
	return ship


func spawn_shell(shooter: Ship, origin: Vector2, angle: float, damage: float, speed: float,
		max_travel: float, shell_count: int) -> Shell:
	var shell: Shell = _shell_scene.instantiate() as Shell
	shell.launch(self, shooter.team, origin, angle, damage, speed, max_travel)
	shell.shell_count = shell_count
	_projectiles_root.add_child(shell)
	return shell


func spawn_torpedo(shooter: Ship, origin: Vector2, angle: float, max_travel: float,
		homing_target: Combatant, homing_time: float) -> Torpedo:
	var torpedo: Torpedo = _torpedo_scene.instantiate() as Torpedo
	torpedo.launch(self, shooter.team, origin, angle, GameData.torpedo_damage(),
		shooter.torpedo_speed(), max_travel)
	torpedo.from_submarine = shooter.stats.is_submarine
	torpedo.homing_target = homing_target
	torpedo.homing_time_left = homing_time
	torpedo.homing_turn_rate = deg_to_rad(balance.torpedo_homing_turn_deg)
	_projectiles_root.add_child(torpedo)
	return torpedo


## A squadron belongs to its carrier for as long as it is airborne and takes its target from it.
func spawn_squadron(carrier: Ship, origin: Vector2, heading: float) -> PlaneSquadron:
	var squadron: PlaneSquadron = _squadron_scene.instantiate() as PlaneSquadron
	squadron.launch(self, carrier.team, origin, heading, GameData.bomb_damage(), GameData.plane_speed(), INF)
	squadron.carrier = carrier
	squadron.bomb_interval = balance.bomb_interval
	squadron.turn_rate = deg_to_rad(balance.plane_turn_rate_deg)
	_projectiles_root.add_child(squadron)
	return squadron


func spawn_effect(at: Vector2, kind: Effect.Kind) -> void:
	if not create_ui or not is_point_visible_to_local(at, -1):
		return
	var effect: Effect = Effect.new()
	effect.setup(kind, at)
	_effects_root.add_child(effect)


func projectile_count() -> int:
	return _projectiles_root.get_child_count()


func projectiles() -> Array[Node]:
	return _projectiles_root.get_children()


# --- Group orders -----------------------------------------------------------

func formation_positions(center: Vector2, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var cols: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(cols)))
	for i: int in count:
		var col: int = i % cols
		var row: int = floori(float(i) / float(cols))
		var offset: Vector2 = Vector2(float(col) - float(cols - 1) * 0.5, float(row) - float(rows - 1) * 0.5)
		result.append(center + offset * FORMATION_SPACING)
	return result


func order_group_move(group: Array[Ship], center: Vector2) -> void:
	var slots: Array[Vector2] = formation_positions(center, group.size())
	for i: int in group.size():
		group[i].order_move(slots[i])


## Sends ships to lie in a friendly yard's dock (repairs happen there by themselves).
func order_group_dock(group: Array[Ship], yard: Shipyard) -> void:
	order_group_move(group, yard.dock_point())


## The yard of `team` whose dock `ship` is lying in, or null.
func dock_of(ship: Ship) -> Shipyard:
	for yard: Shipyard in yards:
		if yard.in_dock(ship):
			return yard
	return null


# --- Internals --------------------------------------------------------------

func _separate_ships() -> void:
	var count: int = ships.size()
	for i: int in count:
		var a: Ship = ships[i]
		if not a.is_alive():
			continue
		for j: int in range(i + 1, count):
			var b: Ship = ships[j]
			if not b.is_alive():
				continue
			var min_dist: float = a.separation_radius + b.separation_radius
			var d: Vector2 = b.position - a.position
			if absf(d.x) >= min_dist or absf(d.y) >= min_dist:
				continue
			var len_sq: float = d.length_squared()
			if len_sq >= min_dist * min_dist:
				continue
			var dist: float = sqrt(len_sq)
			var dir: Vector2 = d / dist if dist > 0.01 else Vector2.from_angle(rng.randf() * TAU)
			var push: float = (min_dist - dist) * 0.25
			# A hull on the slip cannot move, so the other ship takes the whole correction.
			var a_share: float = 0.5
			if a.under_construction:
				a_share = 0.0
			elif b.under_construction:
				a_share = 1.0
			a.nudge(-dir * push * a_share)
			b.nudge(dir * push * (1.0 - a_share))


func _on_combatant_destroyed(who: Combatant) -> void:
	spawn_effect(who.position, Effect.Kind.EXPLOSION)
	if who is HomeBase and not is_over:
		_end_match(1 - who.team)
	_bury.call_deferred(who)


func _bury(who: Combatant) -> void:
	if who is Ship:
		ships.erase(who as Ship)
	var parent: Node = who.get_parent()
	if parent != null:
		parent.remove_child(who)
	_graveyard.append(who)


func _end_match(winning_team: int) -> void:
	is_over = true
	winner = winning_team
	match_ended.emit(winner)


func _draw() -> void:
	if map_data == null:
		return
	var size: Vector2 = map_data.size
	draw_rect(Rect2(Vector2(-2000.0, -2000.0), size + Vector2(4000.0, 4000.0)), Color(0.03, 0.08, 0.13))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.2, 0.31))
	var grid: Color = Color(1.0, 1.0, 1.0, 0.035)
	var x: float = 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid, 1.0)
		x += 400.0
	var y: float = 0.0
	while y <= size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid, 1.0)
		y += 400.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.75, 0.9, 0.4), false, 3.0)
