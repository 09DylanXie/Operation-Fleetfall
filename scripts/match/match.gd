class_name Match
extends Node2D
## Root of a skirmish. Owns the world, the systems (economy, vision, weather,
## navigation) and the controllers. Ships, yards and the AI all act through
## the small API here so the player and the AI use exactly the same commands.
##
##
## Every player action is a plain Dictionary "command" run by execute_command(); a LAN
## client sends its commands to the host instead and only mirrors the host's state
## (`replica`, see NetSync and the Net autoload).
##
## Command-line user args (after "--"): --seed=N  --ai-vs-ai  --size=small|medium|large
## --players=2..4 (extra sides are AI)

signal match_ended(winner: int)
## A side lost its Home Base while the match goes on (three or more sides).
signal team_eliminated(team: int)
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
## Most ships one command may name (the fleet cap, with room to spare).
const MAX_COMMAND_SHIPS: int = 64
const MAX_LOGGED_EFFECTS: int = 300
## Peak swell push on a mid-sized hull, pixels per second.
const WAVE_DRIFT: float = 3.0
## Distance from a site's shore to its building slip (the longest hull must clear the shore).
const SLIP_OFFSET: float = 70.0

## 0 picks a random seed.
var map_seed: int = 0
## ControlType per team. Its size is the number of sides (2 to Layers.MAX_TEAMS).
var team_control: Array[int] = [ControlType.HUMAN, ControlType.AI]
## Alliance id per team: sides with the same id are allies (shared vision, cannot shoot
## each other, win together). Teams not listed fight alone.
var alliance: Array[int] = []
## True for a side whose Home Base has been destroyed.
var eliminated: Array[bool] = []
## Offline rule: the match ends as soon as the local human's alliance is out of the game.
var end_when_local_out: bool = true
var team_count: int = 2
## LAN client: this Match runs no simulation, it mirrors the host's snapshots.
var replica: bool = false
## Replica: where commands go instead of being executed here (set by Net).
var command_sink: Callable = Callable()
## Network games: the side this machine plays (-2 = decide from team_control as usual).
var net_local_team: int = -2
## Host: keep a log of visual effects for the next snapshot.
var record_effects: bool = false
## Display name per side.
var side_names: Array[String] = []
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
## Living ships by Ship.net_id.
var ships_by_id: Dictionary[int, Ship] = {}
## Replica: projectiles by Projectile.net_id.
var net_projectiles: Dictionary[int, Projectile] = {}
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
## The animated sea (only when there is a screen to draw it on).
var ocean: Ocean = null
## Baked ship sprites (only when there is a screen).
var art_cache: ShipArtCache = null
var _weather_root: Node2D = null
var _unsounded: Array[Projectile] = []
var _graveyard: Array[Combatant] = []
## Per team: the hitbox layers of every side it may shoot.
var _hostile_masks: Array[int] = []
var _frame: int = 0
var _next_ship_id: int = 1
var _next_projectile_id: int = 1
var _effect_log: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	if not Net.configure_match(self):
		if GameSettings.menu_shown and map_override == null and team_control.size() == 2:
			for i: int in GameSettings.ai_opponents - 1:
				team_control.append(ControlType.AI)
		_apply_cmdline()
	_setup_teams()
	balance = GameData.balance()
	map_config = GameData.map_config_for(GameSettings.map_size)
	if map_seed == 0:
		var seeder: RandomNumberGenerator = RandomNumberGenerator.new()
		seeder.randomize()
		map_seed = seeder.randi_range(1, 999999)
	rng.seed = map_seed + 104729
	local_team = team_control.find(ControlType.HUMAN) if net_local_team < -1 else net_local_team
	if local_team < 0:
		spectator = true
	while side_names.size() < team_count:
		side_names.append("Team %d" % (side_names.size() + 1))

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
		map_data = MapGenerator.generate(map_seed, map_config, balance.home_base_radius, team_count)
	nav = NavGrid.from_map(map_data)

	if create_ui:
		art_cache = ShipArtCache.new()
		art_cache.name = "ShipArt"
		add_child(art_cache)
		art_cache.bake(team_count)
		ocean = Ocean.new()
		ocean.name = "Ocean"
		ocean.setup(map_data)
		add_child(ocean)
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
		Sfx.set_ambience(true)
	queue_redraw()


func _apply_cmdline() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--ai-vs-ai":
			for team: int in team_control.size():
				team_control[team] = ControlType.AI
		elif arg.begins_with("--seed="):
			map_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--players="):
			var wanted: int = clampi(int(arg.trim_prefix("--players=")), 2, Layers.MAX_TEAMS)
			while team_control.size() < wanted:
				team_control.append(ControlType.AI)
			team_control.resize(wanted)
		elif arg.begins_with("--size=") and not GameSettings.menu_shown:
			GameSettings.map_size = GameSettings.size_from_name(arg.trim_prefix("--size="))
		elif arg.begins_with("--difficulty=") and not GameSettings.menu_shown:
			GameSettings.ai_difficulty = GameSettings.difficulty_from_name(arg.trim_prefix("--difficulty="))


func _setup_teams() -> void:
	team_count = clampi(team_control.size(), 2, Layers.MAX_TEAMS)
	team_control.resize(team_count)
	alliance.resize(mini(alliance.size(), team_count))
	while alliance.size() < team_count:
		alliance.append(1000 + alliance.size())
	eliminated.resize(team_count)
	eliminated.fill(false)
	_hostile_masks.clear()
	for team: int in team_count:
		var mask: int = 0
		for other: int in team_count:
			if are_enemies(team, other):
				mask |= Layers.team_hitbox(other)
		_hostile_masks.append(mask)


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
			var start: Vector2 = Vector2.ZERO
			if map_data.circular:
				start = map_data.random_point(rng, 0.6)
			else:
				start = Vector2(
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
			_add_ai(team)


func _add_ai(team: int) -> void:
	var ai: AIController = AIController.new()
	ai.name = "AI%d" % team
	var level: GameSettings.Difficulty = GameSettings.ai_difficulty
	if team < ai_difficulty.size():
		level = ai_difficulty[team] as GameSettings.Difficulty
	ai.setup(self, team, level)
	add_child(ai)
	ai_controllers.append(ai)


## A human player has left a network game: the computer plays on for that side.
func give_side_to_ai(team: int) -> void:
	if replica or is_over or team < 0 or team >= team_count or eliminated[team]:
		return
	if team_control[team] == ControlType.AI:
		return
	team_control[team] = ControlType.AI
	_add_ai(team)


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
	if is_over or replica:
		return
	sim_time += delta
	_frame += 1
	if _frame % 2 == 0:
		_separate_ships()


func _process(delta: float) -> void:
	if replica and not is_over:
		for ship: Ship in ships:
			ship.net_smooth(delta)
		for id: int in net_projectiles:
			net_projectiles[id].net_advance(delta)
	if not create_ui:
		return
	if not _unsounded.is_empty():
		_play_launch_sounds()
	for ship: Ship in ships:
		ship.visible = is_combatant_visible_to_local(ship)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and create_ui:
		Sfx.set_ambience(false)
	if what == NOTIFICATION_PREDELETE:
		for dead: Combatant in _graveyard:
			if is_instance_valid(dead) and not dead.is_inside_tree():
				dead.free()


# --- Queries ----------------------------------------------------------------

## Same side, or two sides in one alliance. Neutral (-1) is nobody's ally.
func are_allies(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= team_count or b >= team_count:
		return false
	return a == b or alliance[a] == alliance[b]


## Two different sides that are not allied. A neutral site is "not friendly" to everyone.
func are_enemies(a: int, b: int) -> bool:
	return a != b and not are_allies(a, b)


## Alliance ids that still have a Home Base standing.
func living_alliances() -> Array[int]:
	var result: Array[int] = []
	for team: int in team_count:
		if not eliminated[team] and not result.has(alliance[team]):
			result.append(alliance[team])
	return result


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
		from, to, Layers.ISLANDS | _hostile_masks[team])
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
	if spectator or local_team < 0 or not are_enemies(target.team, local_team):
		return true
	return target.spotted_by[local_team]


func is_point_visible_to_local(point: Vector2, owner_team: int) -> bool:
	if spectator or local_team < 0 or are_allies(owner_team, local_team):
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
	ship.net_id = _next_ship_id
	_next_ship_id += 1
	ships_by_id[ship.net_id] = ship
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
	_launch(shell)
	return shell


## Battleships and Super Battleships: the targets submarine torpedoes track closely.
static func _is_battleship(target: Combatant) -> bool:
	var ship: Ship = target as Ship
	if ship == null:
		return false
	var cls: ShipStats.ShipClass = ship.stats.ship_class
	return cls == ShipStats.ShipClass.BB or cls == ShipStats.ShipClass.SBB


func spawn_torpedo(shooter: Ship, origin: Vector2, angle: float, max_travel: float,
		homing_target: Combatant, homing_time: float) -> Torpedo:
	var torpedo: Torpedo = _torpedo_scene.instantiate() as Torpedo
	torpedo.launch(self, shooter.team, origin, angle, GameData.torpedo_damage(),
		shooter.torpedo_speed(), max_travel)
	torpedo.from_submarine = shooter.stats.is_submarine
	torpedo.homing_target = homing_target
	torpedo.homing_time_left = homing_time
	torpedo.homing_turn_rate = deg_to_rad(balance.torpedo_homing_turn_deg)
	if shooter.stats.is_submarine and homing_time > 0.0 and _is_battleship(homing_target):
		torpedo.homing_time_left = maxf(homing_time, balance.sub_battleship_homing_time)
		torpedo.homing_turn_rate = deg_to_rad(balance.sub_battleship_homing_turn_deg)
	_launch(torpedo)
	return torpedo


## A squadron belongs to its home (a carrier or an island air base) for as long as it is
## airborne. Dive bombers take their target from the home; torpedo and depth-charge bombers
## fly at `mission_target`.
func spawn_squadron(home: Combatant, origin: Vector2, heading: float,
		role: PlaneSquadron.Role = PlaneSquadron.Role.DIVE, mission_target: Combatant = null) -> PlaneSquadron:
	var squadron: PlaneSquadron = _squadron_scene.instantiate() as PlaneSquadron
	var bomb: float = GameData.bomb_damage()
	var carrier: Ship = home as Ship
	if carrier != null and role == PlaneSquadron.Role.DIVE:
		bomb *= carrier.stats.bomb_damage_multiplier
	squadron.launch(self, home.team, origin, heading, bomb, GameData.plane_speed(), INF)
	squadron.home = home
	squadron.role = role
	squadron.mission_target = mission_target
	squadron.bomb_interval = balance.bomb_interval
	squadron.depth_charge_damage = GameData.ship(ShipStats.ShipClass.DD).depth_charge_damage
	squadron.turn_rate = deg_to_rad(balance.plane_turn_rate_deg)
	_launch(squadron)
	return squadron


## A torpedo dropped by a torpedo bomber: standard torpedo damage and speed, no homing.
func spawn_air_torpedo(team: int, origin: Vector2, angle: float, max_travel: float) -> Torpedo:
	var torpedo: Torpedo = _torpedo_scene.instantiate() as Torpedo
	torpedo.launch(self, team, origin, angle, GameData.torpedo_damage(), GameData.torpedo_speed(), max_travel)
	_launch(torpedo)
	return torpedo


## Removes an unfinished hull whose order was cancelled: no explosion and no wreck.
func scrap_hull(hull: Ship) -> void:
	if hull == null or not hull.is_alive():
		return
	hull.net_kill()
	ships.erase(hull)
	ships_by_id.erase(hull.net_id)
	var parent: Node = hull.get_parent()
	if parent != null:
		parent.remove_child(hull)
	_graveyard.append(hull)


func _launch(projectile: Projectile) -> void:
	projectile.net_id = _next_projectile_id
	_next_projectile_id += 1
	_projectiles_root.add_child(projectile)
	_queue_launch_sound(projectile)


## Cosmetic: a gun, torpedo or aircraft launch is heard on the next frame (once a replica
## projectile has its position), if the local player can see where it happened.
func _queue_launch_sound(projectile: Projectile) -> void:
	if create_ui and Sfx.enabled:
		_unsounded.append(projectile)


func _play_launch_sounds() -> void:
	for projectile: Projectile in _unsounded:
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			continue
		if not is_point_visible_to_local(projectile.position, projectile.team):
			continue
		var sound: String = "gun_mid"
		if projectile is Torpedo:
			sound = "torpedo_launch"
		elif projectile is PlaneSquadron:
			sound = "plane"
		elif projectile.speed <= 320.0:
			sound = "gun_small"
		elif projectile.speed >= 415.0:
			sound = "gun_big"
		Sfx.play_at(sound, projectile.position)
	_unsounded.clear()


## The swell: a slow back-and-forth push on every hull (pixels per second), different in
## each part of the sea. It oscillates, so a ship at anchor rocks in place instead of
## drifting off; small hulls are pushed harder than big ones. Deterministic (sim clock).
func wave_drift(at: Vector2, hull_length: float) -> Vector2:
	var strength: float = WAVE_DRIFT * clampf(60.0 / maxf(20.0, hull_length), 0.45, 1.4)
	var t: float = sim_time
	return Vector2(cos(t * 0.7 + at.y * 0.004 + at.x * 0.0013),
		sin(t * 0.55 + at.x * 0.0035 - at.y * 0.0011)) * strength


func spawn_effect(at: Vector2, kind: Effect.Kind) -> void:
	if record_effects and _effect_log.size() < MAX_LOGGED_EFFECTS * 3:
		_effect_log.append_array(PackedFloat32Array([float(kind), at.x, at.y]))
	if not create_ui or not is_point_visible_to_local(at, -1):
		return
	Sfx.play_at(Effect.SOUNDS.get(kind, "hit") as String, at)
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


# --- Commands ---------------------------------------------------------------
# A command is a Dictionary with a "type" and plain data, so that it can travel over the
# network. Ships are named by Ship.net_id, shipyards by their index in `yards`, targets by
# combatant_ref(). Commands from other machines are never trusted: every field is checked
# and a side can only ever command what it owns.

## A player action of the local side. Returns the notice to show the player ("" for none).
func command(cmd: Dictionary) -> String:
	if replica:
		if command_sink.is_valid():
			command_sink.call(cmd)
		return ""
	return execute_command(local_team, cmd)


## Runs one command for `team` (the host does this for every player). Returns a
## player-facing notice, or "" when there is nothing to say.
func execute_command(team: int, cmd: Dictionary) -> String:
	if replica or is_over or team < 0 or team >= team_count or eliminated[team]:
		return ""
	var kind: Variant = cmd.get("type")
	if not kind is String:
		return ""
	match kind as String:
		"move":
			var group: Array[Ship] = _cmd_ships(team, cmd)
			var point: Vector2 = _cmd_point(cmd)
			if not group.is_empty() and point != Vector2.INF:
				order_group_move(group, point)
		"stop":
			for ship: Ship in _cmd_ships(team, cmd):
				ship.order_stop()
		"attack":
			return _cmd_attack(team, cmd)
		"dock":
			var yard: Shipyard = _cmd_yard(team, cmd)
			var group: Array[Ship] = _cmd_ships(team, cmd)
			if yard == null or group.is_empty():
				return ""
			order_group_dock(group, yard)
			# Tell the player up front if some of these ships will not be repaired there.
			for ship: Ship in group:
				var problem: String = yard.repair_block_reason(ship)
				if problem != "":
					return "Docking at %s - %s" % [yard.site_name, problem]
			return "Docking at %s for repairs" % yard.site_name
		"build":
			var yard: Shipyard = _cmd_yard(team, cmd)
			var cls: Variant = cmd.get("cls")
			if yard == null or not cls is int or not GameData.all_classes().has(cls as int):
				return ""
			return yard.try_enqueue_ship(int(cls) as ShipStats.ShipClass)
		"upgrade":
			var yard: Shipyard = _cmd_yard(team, cmd)
			if yard != null:
				return yard.try_enqueue_upgrade()
		"cancel":
			var yard: Shipyard = _cmd_yard(team, cmd)
			if yard != null:
				yard.cancel_last()
		"radar":
			var yard: Shipyard = _cmd_yard(team, cmd)
			var site: Island = yard.get_parent() as Island if yard != null else null
			if site == null:
				return "Radar can only be built on a Major island"
			var problem: String = site.try_buy_radar(team)
			return problem if problem != "" else "Radar built on %s" % yard.site_name
		"rally":
			var yard: Shipyard = _cmd_yard(team, cmd)
			var point: Vector2 = _cmd_point(cmd)
			if yard != null and point != Vector2.INF:
				yard.rally_point = nav.nearest_free(point, false)
	return ""


func _cmd_attack(team: int, cmd: Dictionary) -> String:
	var ref: Variant = cmd.get("target")
	if not ref is int:
		return ""
	var target: Combatant = combatant_from_ref(ref as int)
	if target == null or not target.is_alive() or not target.is_enemy_of(team):
		return ""
	# Only what the side can see may be ordered attacked - and island garrisons, whose
	# position everybody knows.
	if not target.spotted_by[team] and not target is IslandGarrison:
		return ""
	var note: String = ""
	for ship: Ship in _cmd_ships(team, cmd):
		if ship.order_attack(target, true):
			continue
		if target.is_home_base() and ship.stats.is_submarine:
			note = "Submarines cannot attack the Home Base"
		elif target.is_structure() and ship.stats.is_submarine:
			note = "Submarines cannot attack an island garrison"
		elif target.is_submarine() and not ship.stats.can_target_submarines:
			note = "%ss cannot target Submarines" % ship.stats.display_name
	return note


## The combat-ready ships of `team` named by the command, in the order given.
func _cmd_ships(team: int, cmd: Dictionary) -> Array[Ship]:
	var result: Array[Ship] = []
	var raw: Variant = cmd.get("ships")
	if not raw is Array:
		return result
	var ids: Array = raw as Array
	if ids.size() > MAX_COMMAND_SHIPS:
		return result
	for id: Variant in ids:
		if not id is int:
			continue
		var ship: Ship = ships_by_id.get(id as int) as Ship
		if ship != null and ship.team == team and ship.is_combat_ready() and not result.has(ship):
			result.append(ship)
	return result


## The shipyard of `team` named by the command, or null.
func _cmd_yard(team: int, cmd: Dictionary) -> Shipyard:
	var index: Variant = cmd.get("yard")
	if not index is int or (index as int) < 0 or (index as int) >= yards.size():
		return null
	var yard: Shipyard = yards[index as int]
	return yard if yard.team == team else null


## The map point named by the command (kept near the map), or Vector2.INF if it is malformed.
func _cmd_point(cmd: Dictionary) -> Vector2:
	var x: Variant = cmd.get("x")
	var y: Variant = cmd.get("y")
	if not (x is float or x is int) or not (y is float or y is int):
		return Vector2.INF
	var point: Vector2 = Vector2(float(x), float(y))
	if not point.is_finite():
		return Vector2.INF
	return point.clamp(Vector2(-2000.0, -2000.0), map_data.size + Vector2(2000.0, 2000.0))


func ship_ids(group: Array[Ship]) -> Array[int]:
	var ids: Array[int] = []
	for ship: Ship in group:
		ids.append(ship.net_id)
	return ids


## A number that names a combatant on every machine: a ship's id (> 0), a Home Base
## (-1 - team) or an island garrison (-100 - index). 0 is "nothing".
func combatant_ref(who: Combatant) -> int:
	if who == null or not who.is_alive():
		return 0
	if who is Ship:
		return (who as Ship).net_id
	if who is HomeBase:
		return -1 - who.team
	if who is IslandGarrison:
		return -100 - garrisons.find(who as IslandGarrison)
	return 0


func combatant_from_ref(ref: int) -> Combatant:
	if ref > 0:
		return ships_by_id.get(ref) as Ship
	if ref <= -100:
		var index: int = -100 - ref
		return garrisons[index] if index < garrisons.size() else null
	if ref < 0:
		var team: int = -1 - ref
		return bases[team] if team < bases.size() else null
	return null


# --- Network replica --------------------------------------------------------
# Used by NetSync on a client to mirror the host. None of this runs game rules.

func frame() -> int:
	return _frame


func net_set_clock(host_frame: int, host_time: float) -> void:
	_frame = host_frame
	sim_time = host_time


## Host: the visual effects since the last call.
func take_effect_log() -> PackedFloat32Array:
	var effects: PackedFloat32Array = _effect_log
	_effect_log = PackedFloat32Array()
	return effects


func net_spawn_ship(id: int, ship_class: int, team: int, at: Vector2, heading: float,
		under_construction: bool) -> Ship:
	var ship: Ship = _ship_scene.instantiate() as Ship
	ship.setup(GameData.ship(ship_class as ShipStats.ShipClass), clampi(team, 0, team_count - 1), self, under_construction)
	ship.position = at
	ship.rotation = heading
	ship.net_id = id
	ships_by_id[id] = ship
	_ships_root.add_child(ship)
	ships.append(ship)
	if create_ui:
		ship.visible = is_combatant_visible_to_local(ship)
	ship_spawned.emit(ship)
	return ship


## The host no longer lists this ship or base: it is gone.
func net_remove(who: Combatant) -> void:
	if not who.is_alive():
		return
	who.net_kill()
	_bury(who)


func net_spawn_projectile(id: int, kind: int, team: int, shell_count: int) -> Projectile:
	var scene: PackedScene = _shell_scene
	if kind == 1:
		scene = _torpedo_scene
	elif kind == 2:
		scene = _squadron_scene
	var projectile: Projectile = scene.instantiate() as Projectile
	projectile.match_ref = self
	projectile.team = clampi(team, 0, team_count - 1)
	projectile.net_id = id
	if projectile is Shell:
		(projectile as Shell).shell_count = clampi(shell_count, 1, 8)
	elif projectile is PlaneSquadron:
		# Squadrons send their role in the count field (role + 1).
		(projectile as PlaneSquadron).role = clampi(shell_count - 1, 0, PlaneSquadron.Role.size() - 1) as PlaneSquadron.Role
	projectile.set_physics_process(false)
	_projectiles_root.add_child(projectile)
	net_projectiles[id] = projectile
	_queue_launch_sound(projectile)
	return projectile


func net_remove_projectile(id: int) -> void:
	var projectile: Projectile = net_projectiles.get(id) as Projectile
	net_projectiles.erase(id)
	if projectile != null:
		projectile.queue_free()


## Replica: the host reports that `team` has lost its Home Base.
func net_eliminate(team: int, announce: bool) -> void:
	if eliminated[team]:
		return
	eliminated[team] = true
	if announce:
		team_eliminated.emit(team)


func net_end(winning_team: int) -> void:
	if not is_over:
		_end_match(winning_team)


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
	if replica:
		return
	spawn_effect(who.position, Effect.Kind.EXPLOSION)
	if who is HomeBase and not is_over:
		_on_base_lost(who.team)
	_bury.call_deferred(who)


## A side without a Home Base is out. The match ends once a single alliance is left (or,
## offline, when the local player's alliance is gone); otherwise it carries on without the
## loser: its fleet sinks and its islands and shipyards are abandoned.
func _on_base_lost(team: int) -> void:
	eliminated[team] = true
	var survivors: Array[int] = living_alliances()
	var local_out: bool = end_when_local_out and local_team >= 0 and not survivors.has(alliance[local_team])
	if survivors.size() <= 1 or local_out:
		_end_match(_surviving_team(team))
		return
	for ship: Ship in ships.duplicate():
		if ship.team == team and ship.is_alive():
			ship.kill()
	for island: Island in islands:
		if island.owner_team == team:
			island.set_owner_team(-1)
	bases[team].shipyard.reassign(-1)
	team_eliminated.emit(team)


## The lowest-numbered side still standing, an enemy of `loser` if there is one.
func _surviving_team(loser: int) -> int:
	var any: int = -1
	for team: int in team_count:
		if eliminated[team]:
			continue
		if are_enemies(team, loser):
			return team
		if any < 0:
			any = team
	return any


func _bury(who: Combatant) -> void:
	if who is Ship:
		ships.erase(who as Ship)
		ships_by_id.erase((who as Ship).net_id)
		_leave_wreck(who as Ship)
	var parent: Node = who.get_parent()
	if parent != null:
		parent.remove_child(who)
	_graveyard.append(who)


## A cruiser or bigger that the local player could see goes down slowly (cosmetic only).
func _leave_wreck(ship: Ship) -> void:
	if not create_ui or not ship.visible or ship.under_construction or not ShipWreck.sinks(ship.stats):
		return
	var wreck: ShipWreck = ShipWreck.new()
	wreck.setup(ship)
	_effects_root.add_child(wreck)


func _end_match(winning_team: int) -> void:
	is_over = true
	winner = winning_team
	match_ended.emit(winner)


func _draw() -> void:
	if map_data == null:
		return
	var size: Vector2 = map_data.size
	if ocean != null:
		# The ocean shader paints the water; only the rim is drawn here.
		if map_data.circular:
			draw_arc(map_data.center(), map_data.radius(), 0.0, TAU, 200, Color(0.55, 0.78, 0.92, 0.35), 3.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.78, 0.92, 0.35), false, 3.0)
		return
	draw_rect(Rect2(Vector2(-2000.0, -2000.0), size + Vector2(4000.0, 4000.0)), Color(0.03, 0.08, 0.13))
	if map_data.circular:
		_draw_round_sea()
		return
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


## The round sea of a generated map: grid lines clipped to the circle and a visible rim.
func _draw_round_sea() -> void:
	var center: Vector2 = map_data.center()
	var radius: float = map_data.radius()
	draw_circle(center, radius, Color(0.07, 0.2, 0.31))
	var grid: Color = Color(1.0, 1.0, 1.0, 0.035)
	var offset: float = -floorf(radius / 400.0) * 400.0
	while offset <= radius:
		var half: float = sqrt(maxf(0.0, radius * radius - offset * offset))
		draw_line(center + Vector2(offset, -half), center + Vector2(offset, half), grid, 1.0)
		draw_line(center + Vector2(-half, offset), center + Vector2(half, offset), grid, 1.0)
		offset += 400.0
	draw_arc(center, radius, 0.0, TAU, 160, Color(0.5, 0.75, 0.9, 0.55), 4.0)
