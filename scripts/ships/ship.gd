class_name Ship
extends Combatant
## One hull of any class. Movement has a real heading and turn rate because
## turret arcs, Destroyer broadside tubes and Submarine bow/stern tubes depend on it.

signal construction_completed(ship: Ship)

const THINK_INTERVAL: float = 0.25
const REPATH_INTERVAL: float = 1.0
## Broadside turns (player attack orders): start turning once the target is this far off
## the beam, stop once within `BROADSIDE_DONE_DEG`, re-aim the turn every `BROADSIDE_REPLAN`s.
const BROADSIDE_START_DEG: float = 25.0
const BROADSIDE_DONE_DEG: float = 8.0
const BROADSIDE_REPLAN: float = 0.5
## Destroyer tubes bear within this angle either side of the port/starboard beam.
const BROADSIDE_HALF_ARC_DEG: float = 40.0
const ARRIVE_FINAL: float = 14.0
const ARRIVE_WAYPOINT: float = 36.0
const STUCK_TIME: float = 3.0
const CHASE_REPATH_DISTANCE: float = 40.0
## A carrier calls off its strike once the target has been out of sight this long.
const STRIKE_LOST_TIME: float = 10.0
## Squadrons keep working a target out to this multiple of plane range from their carrier.
const STRIKE_LEASH: float = 1.2
const TEAM_COLORS: Array[Color] = [Color(0.36, 0.72, 1.0), Color(1.0, 0.42, 0.36),
	Color(0.45, 0.88, 0.45), Color(0.8, 0.55, 1.0)]
const RING_GUN_COLOR: Color = Color(1.0, 0.85, 0.4, 0.5)
const RING_TORPEDO_COLOR: Color = Color(0.4, 0.92, 1.0, 0.5)
const RING_PLANE_COLOR: Color = Color(0.82, 0.7, 1.0, 0.5)
const RING_SECONDARY_COLOR: Color = Color(1.0, 0.6, 0.3, 0.45)
## Floats per ship in a network snapshot (see net_write).
const NET_FIELDS: int = 22
## A replica keeps sailing a ship along its last known course for this long without news.
const NET_EXTRAPOLATE_TIME: float = 0.25
const NET_SNAP_DISTANCE: float = 250.0
## A Resource Ship mines only while (nearly) stopped; the swell alone moves it about 3 px/s.
const MINING_MAX_SPEED: float = 8.0

var stats: ShipStats = null
var under_construction: bool = false
var build_progress: float = 1.0
var selected: bool = false
## While > 0 the whole enemy team can see this hull (Submarine reveal penalty).
var reveal_timer: float = 0.0
## Player/AI focus target; still bound by spotting, range and LOS.
var priority_target: Combatant = null
## Pending manual torpedo attack (Submarines only). Cleared after one salvo.
var torpedo_order: Combatant = null
var gun_target: Combatant = null
## What the secondary battery is shooting at (picked on its own, within secondary range).
var secondary_target: Combatant = null
var secondary_salvos: int = 0
## Carrier air-strike target picked by an explicit order. It overrides the air wing's own
## choice and survives move orders, so the carrier can reposition while its squadrons work.
var strike_target: Combatant = null
var separation_radius: float = 16.0
var salvos_fired: int = 0
var torpedoes_launched: int = 0
var depth_charges_dropped: int = 0
var squadrons_launched: int = 0
var squadrons_lost: int = 0
## Stable id given by the Match; the same on the host and on every client.
var net_id: int = 0
## Replica only: where the host last said this ship is (the drawn position eases toward it).
var net_pos: Vector2 = Vector2.ZERO
var net_rot: float = 0.0

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _has_destination: bool = false
var _destination: Vector2 = Vector2.ZERO
var _gun_cd: float = 0.0
var _sec_cd: float = 0.0
var _torp_cd: float = 0.0
var _plane_cd: float = 0.0
var _torpedo_bomber_cd: float = 0.0
var _depth_bomber_cd: float = 0.0
var _depth_cd: float = 0.0
var _think_cd: float = 0.0
var _repath_cd: float = 0.0
var _stuck_time: float = 0.0
var _best_dist: float = INF
var _repath_attempts: int = 0
var _chase_lost: bool = false
var _chase_goal: Vector2 = Vector2.ZERO
## Player attack orders: in range, gun ships swing their beam toward the target.
var broadside_order: bool = false
var _broadside_turning: bool = false
var _broadside_cd: float = 0.0
var _squadrons: Array[PlaneSquadron] = []
var _strike_unseen: float = 0.0
## The target the air wing chose for itself while no strike is ordered.
var _auto_strike: Combatant = null
var _net_age: float = 0.0
var _net_squadrons: int = 0
var _net_strike_ref: int = 0
var _net_auto_ref: int = 0
var _aa_cd: float = 0.0
## Flak barrages fired and squadrons they brought down (Super Battleship).
var flak_barrages: int = 0
var flak_kills: int = 0
## Cosmetic: each mount's current training angle relative to the bow (radians).
var turret_angles: PackedFloat32Array = PackedFloat32Array()
var secondary_angles: PackedFloat32Array = PackedFloat32Array()
var _look_target: Combatant = null
var _look_cd: float = 0.0
## Cosmetic clock for waves, fires and smoke.
var _anim_time: float = 0.0
var _wake_layer: ShipLayer = null
var _body_layer: ShipLayer = null


func setup(p_stats: ShipStats, p_team: int, p_match: Match, p_under_construction: bool) -> void:
	stats = p_stats
	team = p_team
	match_ref = p_match
	max_hp = stats.max_hp
	base_armor = stats.base_armor
	under_construction = p_under_construction
	separation_radius = stats.hull_length * 0.34
	if under_construction:
		build_progress = 0.0
		hp = max_hp * GameData.balance().construction_start_hp_fraction
	else:
		build_progress = 1.0
		hp = max_hp
	turret_angles.resize(stats.gun_mounts)
	for i: int in stats.gun_mounts:
		turret_angles[i] = deg_to_rad(stats.mount_facings_deg[i])
	secondary_angles.resize(stats.secondary_mounts)
	for i: int in stats.secondary_mounts:
		secondary_angles[i] = deg_to_rad(stats.secondary_facings_deg[i])
	if match_ref == null or match_ref.create_ui:
		_wake_layer = ShipLayer.new()
		_wake_layer.setup(self, ShipLayer.Mode.WAKE)
		add_child(_wake_layer)
		_body_layer = ShipLayer.new()
		_body_layer.setup(self, ShipLayer.Mode.BODY)
		add_child(_body_layer)


func anim_time() -> float:
	return _anim_time


func _ready() -> void:
	var shape: CapsuleShape2D = CapsuleShape2D.new()
	shape.radius = stats.hull_width * 0.5
	shape.height = maxf(stats.hull_length, stats.hull_width)
	var hitbox: CollisionShape2D = get_node("Hitbox") as CollisionShape2D
	hitbox.shape = shape
	hitbox.rotation = PI * 0.5
	configure_layers()
	if match_ref != null:
		_think_cd = match_ref.rng.randf() * THINK_INTERVAL


func is_submarine() -> bool:
	return stats.is_submarine


func hit_radius() -> float:
	return stats.hull_length * 0.5


func max_speed() -> float:
	return GameData.ship_speed(stats)


func is_combat_ready() -> bool:
	return is_alive() and not under_construction


func has_destination() -> bool:
	return _has_destination


func destination() -> Vector2:
	return _destination


func torpedo_ready() -> bool:
	return stats.torpedo_mode != ShipStats.TorpedoMode.NONE and _torp_cd <= 0.0


func torpedo_cooldown() -> float:
	return _torp_cd


func gun_cooldown() -> float:
	return _gun_cd


func secondary_cooldown() -> float:
	return _sec_cd


func plane_cooldown() -> float:
	return _plane_cd


func torpedo_bomber_cooldown() -> float:
	return _torpedo_bomber_cd


func depth_bomber_cooldown() -> float:
	return _depth_bomber_cd


func depth_charge_cooldown() -> float:
	return _depth_cd


## Every squadron of this carrier in the air, all roles.
func airborne_squadrons() -> int:
	if match_ref != null and match_ref.replica:
		return _net_squadrons
	return _squadrons.size()


## Squadrons of one role in the air (host only; a replica knows only the total).
func airborne_of(role: PlaneSquadron.Role) -> int:
	var count: int = 0
	for squadron: PlaneSquadron in _squadrons:
		if squadron.role == role:
			count += 1
	return count


## Chance that this ship shoots down a squadron that has just bombed it.
func aa_kill_chance() -> float:
	return 0.0 if under_construction else stats.aa_kill_chance


func torpedo_speed() -> float:
	return GameData.torpedo_speed() * stats.torpedo_speed_scale


## Resource Ships: the island this ship is mining - it has stopped within `mining_reach` of
## the shore of any island (Home Bases are not islands). null otherwise.
func mining_island() -> Island:
	if not stats.mines_islands or not is_combat_ready() or has_destination() \
			or velocity.length() > MINING_MAX_SPEED:
		return null
	var reach: float = GameData.balance().mining_reach
	for island: Island in match_ref.islands:
		var limit: float = island.radius + reach
		if position.distance_squared_to(island.position) <= limit * limit:
			return island
	return null


# --- Construction -----------------------------------------------------------

func add_construction_progress(fraction: float) -> void:
	if not under_construction or not is_alive():
		return
	var start_frac: float = GameData.balance().construction_start_hp_fraction
	build_progress = minf(1.0, build_progress + fraction)
	hp = minf(max_hp, hp + max_hp * (1.0 - start_frac) * fraction)


func complete_construction() -> void:
	if not under_construction:
		return
	under_construction = false
	build_progress = 1.0
	construction_completed.emit(self)


# --- Orders (shared by the player and the AI) -------------------------------

func order_move(dest: Vector2) -> void:
	if not is_combat_ready():
		return
	_end_broadside()
	priority_target = null
	torpedo_order = null
	_chase_lost = false
	_set_destination(dest)


## True if this hull's weapons may be aimed at `target` at all: an enemy, and not a
## Submarine for hulls that cannot engage them (Battleships).
func can_engage(target: Combatant) -> bool:
	if target == null or not target.is_enemy_of(team):
		return false
	return stats.can_target_submarines or not target.is_submarine()


## Focus a target. Submarines treat this as a manual torpedo attack; carriers close to
## plane range and send their squadrons at it. `broadside` (player orders): once in range a
## gun ship turns its broadside toward the target so every turret bears.
func order_attack(target: Combatant, broadside: bool = false) -> bool:
	if stats.is_support() or not is_combat_ready() or target == null or not target.is_alive() or not can_engage(target):
		return false
	if stats.torpedo_mode == ShipStats.TorpedoMode.MANUAL_BOW_STERN:
		return order_torpedo(target)
	if stats.has_planes():
		order_strike(target)
	priority_target = target
	torpedo_order = null
	_chase_lost = false
	_repath_cd = 0.0
	_end_broadside()
	broadside_order = broadside and stats.has_guns()
	return true


func _end_broadside() -> void:
	broadside_order = false
	_broadside_turning = false
	_broadside_cd = 0.0


## Manual Submarine torpedo attack. Home Bases are never valid targets.
func order_torpedo(target: Combatant) -> bool:
	if not is_combat_ready() or stats.torpedo_mode != ShipStats.TorpedoMode.MANUAL_BOW_STERN:
		return false
	if target == null or not target.is_alive() or not target.is_enemy_of(team) or target.is_structure():
		return false
	torpedo_order = target
	priority_target = null
	_chase_lost = false
	_repath_cd = 0.0
	return true


## Carrier air strike on one specific target, without moving the carrier. It overrides the
## air wing's own choice until the target dies, is lost or leaves plane range.
func order_strike(target: Combatant) -> bool:
	if not is_combat_ready() or not stats.has_planes():
		return false
	if target == null or not target.is_alive() or not target.is_enemy_of(team):
		return false
	strike_target = target
	_strike_unseen = 0.0
	_redirect_dive_bombers(target)
	return true


## An ordered strike pulls the dive bombers already in the air onto the new target, the
## nearest first, as many as may stack on it.
func _redirect_dive_bombers(target: Combatant) -> void:
	var room: int = _stack_room(target, null)
	if room <= 0:
		return
	var others: Array[PlaneSquadron] = []
	for squadron: PlaneSquadron in _squadrons:
		if squadron.role == PlaneSquadron.Role.DIVE and squadron.dive_target != target:
			others.append(squadron)
	others.sort_custom(func(a: PlaneSquadron, b: PlaneSquadron) -> bool:
		return a.position.distance_squared_to(target.position) < b.position.distance_squared_to(target.position))
	for squadron: PlaneSquadron in others:
		if room <= 0:
			break
		squadron.dive_target = target
		room -= 1


## Drops an ordered air strike; the air wing goes back to choosing its own targets.
func clear_strike() -> void:
	strike_target = null
	_strike_unseen = 0.0


func order_stop() -> void:
	_end_broadside()
	priority_target = null
	torpedo_order = null
	clear_strike()
	_chase_lost = false
	_clear_path()


func _clear_path() -> void:
	_has_destination = false
	_path = PackedVector2Array()
	_path_index = 0
	_stuck_time = 0.0
	_best_dist = INF


func _set_destination(dest: Vector2) -> void:
	var path: PackedVector2Array = match_ref.nav.find_path(position, dest, stats.shallow_draft)
	if path.is_empty():
		_clear_path()
		return
	_path = path
	_path_index = 0
	_destination = path[path.size() - 1]
	_has_destination = true
	_stuck_time = 0.0
	_best_dist = INF
	_repath_attempts = 0


# --- Simulation -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive() or match_ref == null or match_ref.is_over or match_ref.replica:
		return
	if reveal_timer > 0.0:
		reveal_timer = maxf(0.0, reveal_timer - delta)
	if under_construction:
		velocity = Vector2.ZERO
		return
	_update_orders(delta)
	_update_movement(delta)
	_update_weapons(delta)


func _process(delta: float) -> void:
	_anim_time += delta
	if visible and stats != null and is_alive():
		_train_turrets(delta)
		queue_redraw()


## Cosmetic turret training: mounts turn toward what the ship is shooting at (on a client,
## the nearest enemy it could be shooting at) at a rate set by the hull's size and speed.
func _train_turrets(delta: float) -> void:
	if under_construction:
		return
	var replica: bool = match_ref != null and match_ref.replica
	_look_cd -= delta
	if replica and _look_cd <= 0.0:
		_look_cd = 0.3
		var reach: float = maxf(stats.gun_range, stats.secondary_range)
		_look_target = _pick_target(reach, false) if reach > 0.0 else null
	var main_target: Combatant = _look_target if replica else gun_target
	var side_target: Combatant = _look_target if replica else secondary_target
	var step: float = deg_to_rad(stats.turret_traverse_deg()) * delta
	for i: int in turret_angles.size():
		var rest: float = deg_to_rad(stats.mount_facings_deg[i])
		var want: float = rest
		if main_target != null and is_instance_valid(main_target) and main_target.is_alive():
			var bearing: float = angle_difference(rotation, (main_target.position - mount_position(i)).angle())
			if absf(angle_difference(rest, bearing)) <= deg_to_rad(stats.mount_arc_half_deg):
				want = bearing
		turret_angles[i] = _turn_toward(turret_angles[i], want, rest, deg_to_rad(stats.mount_arc_half_deg), step)
	for i: int in secondary_angles.size():
		var rest: float = deg_to_rad(stats.secondary_facings_deg[i])
		var want: float = rest
		if side_target != null and is_instance_valid(side_target) and side_target.is_alive():
			var bearing: float = angle_difference(rotation, (side_target.position - secondary_position(i)).angle())
			if absf(angle_difference(rest, bearing)) <= deg_to_rad(stats.secondary_arc_half_deg):
				want = bearing
		secondary_angles[i] = _turn_toward(secondary_angles[i], want, rest,
			deg_to_rad(stats.secondary_arc_half_deg), step * 1.6)


## Turns `current` toward `want` the short way round the mount's arc (never through the
## dead zone behind it, where the superstructure is).
static func _turn_toward(current: float, want: float, rest: float, half_arc: float, step: float) -> float:
	var cur_off: float = angle_difference(rest, current)
	var want_off: float = clampf(angle_difference(rest, want), -half_arc, half_arc)
	var diff: float = want_off - cur_off
	return rest + cur_off + clampf(diff, -step, step)


## Distance to a target measured to its edge for large structures.
func range_to(target: Combatant) -> float:
	return maxf(0.0, position.distance_to(target.position) - target.range_padding())


func _update_orders(delta: float) -> void:
	var chase: Combatant = torpedo_order if torpedo_order != null else priority_target
	if chase == null:
		return
	if not chase.is_alive() or not chase.is_enemy_of(team):
		# Sunk, or an island garrison that fell or changed hands.
		priority_target = null
		torpedo_order = null
		_clear_path()
		return
	if chase.spotted_by[team]:
		_chase_lost = false
		var needs_los: bool = not stats.has_planes()
		# Gun ships close to gun range; torpedo boats and carriers to their own reach.
		var reach: float = (stats.gun_range if stats.has_guns() else stats.engage_range()) * 0.9
		if stats.has_depth_charges() and chase.is_submarine():
			# Sub hunting: run right over the boat so the depth charges reach it.
			reach = stats.depth_charge_range * 0.6
		if range_to(chase) <= reach and (not needs_los or has_los_to(position, chase)):
			if broadside_order and chase == priority_target and not chase.is_submarine():
				_turn_broadside(chase, delta)
			elif _has_destination:
				_clear_path()
		else:
			_chase_toward(chase.position, delta)
	elif chase.is_structure():
		# Bases and island garrisons never move and both sides know where they are: keep
		# closing until it is spotted.
		_chase_lost = false
		_chase_toward(chase.position, delta)
	elif not _chase_lost:
		# Lost contact: sail to where it was last seen, then drop the order.
		_chase_lost = true
		_set_destination(chase.last_known_position[team])
	elif not _has_destination:
		priority_target = null
		torpedo_order = null
		_chase_lost = false


## In range of an ordered target: swing the hull until it lies across the line of fire (the
## nearer of the two beams), sailing a short leg abeam to turn, then stop there. A new turn
## starts only once the target has drawn well off the beam.
func _turn_broadside(target: Combatant, delta: float) -> void:
	var bearing: float = (target.position - position).angle()
	var port: float = bearing + PI * 0.5
	var starboard: float = bearing - PI * 0.5
	var heading: float = port if absf(angle_difference(rotation, port)) <= absf(angle_difference(rotation, starboard)) else starboard
	var off: float = absf(angle_difference(rotation, heading))
	if off <= deg_to_rad(BROADSIDE_DONE_DEG) or (not _broadside_turning and off < deg_to_rad(BROADSIDE_START_DEG)):
		_broadside_turning = false
		if _has_destination:
			_clear_path()
		return
	_broadside_turning = true
	_broadside_cd -= delta
	if _has_destination and _broadside_cd > 0.0:
		return
	_broadside_cd = BROADSIDE_REPLAN
	var run: float = maxf(stats.hull_length * 2.5, 120.0)
	for h: float in [heading, heading + PI]:
		var goal: Vector2 = position + Vector2.from_angle(h) * run
		if not match_ref.nav.is_blocked(goal, stats.shallow_draft):
			_set_destination(goal)
			return
	_broadside_turning = false


## Re-plans toward a chased target only when it has actually moved, so the
## stuck detection of the current route is not reset every second.
func _chase_toward(goal: Vector2, delta: float) -> void:
	_repath_cd -= delta
	if _repath_cd > 0.0:
		return
	_repath_cd = REPATH_INTERVAL
	if not _has_destination or _chase_goal.distance_to(goal) > CHASE_REPATH_DISTANCE:
		_chase_goal = goal
		_set_destination(goal)


func _update_movement(delta: float) -> void:
	var prev: Vector2 = position
	if _has_destination:
		var waypoint: Vector2 = _path[_path_index]
		var to_wp: Vector2 = waypoint - position
		var dist: float = to_wp.length()
		var is_last: bool = _path_index == _path.size() - 1
		var arrive: float = ARRIVE_FINAL if is_last else ARRIVE_WAYPOINT
		if dist <= arrive:
			if is_last:
				_clear_path()
			else:
				_path_index += 1
				_best_dist = INF
				_stuck_time = 0.0
		else:
			var diff: float = angle_difference(rotation, to_wp.angle())
			var max_turn: float = deg_to_rad(stats.turn_rate_deg) * delta
			rotation += clampf(diff, -max_turn, max_turn)
			# Slow down while the bow is off-course so the turning circle stays tight.
			var speed: float = max_speed() * maxf(0.12, cos(diff))
			if is_last:
				speed = minf(speed, maxf(14.0, dist * 1.5))
			var step: Vector2 = Vector2.from_angle(rotation) * speed * delta
			var nav: NavGrid = match_ref.nav
			if not nav.is_blocked(position + step, stats.shallow_draft):
				position += step
			elif absf(step.x) >= absf(step.y) and not nav.is_blocked(position + Vector2(step.x, 0.0), stats.shallow_draft):
				# Slide along the obstacle instead of grinding to a halt against it.
				position.x += step.x
			elif not nav.is_blocked(position + Vector2(0.0, step.y), stats.shallow_draft):
				position.y += step.y
			elif not nav.is_blocked(position + Vector2(step.x, 0.0), stats.shallow_draft):
				position.x += step.x
			else:
				_stuck_time += delta
			if dist < _best_dist - 1.0:
				_best_dist = dist
				_stuck_time = 0.0
			else:
				_stuck_time += delta
			if _stuck_time > STUCK_TIME:
				_handle_stuck()
	_drift_with_waves(delta)
	velocity = (position - prev) / delta if delta > 0.0 else Vector2.ZERO


## The sea moves every hull a little: an oscillating swell (Match.wave_drift) that pushes
## ships back and forth by a few pixels without ever carrying them away.
func _drift_with_waves(delta: float) -> void:
	var push: Vector2 = match_ref.wave_drift(position, stats.hull_length) * delta
	if push != Vector2.ZERO and not match_ref.nav.is_blocked(position + push, stats.shallow_draft):
		position += push


func _handle_stuck() -> void:
	_stuck_time = 0.0
	_best_dist = INF
	_repath_attempts += 1
	if match_ref.nav.is_blocked(position, stats.shallow_draft):
		position = match_ref.nav.nearest_free(position, stats.shallow_draft)
	if _repath_attempts > 3:
		_clear_path()
		return
	var attempts: int = _repath_attempts
	var dest: Vector2 = _destination
	_set_destination(dest)
	_repath_attempts = attempts


## Small positional correction used by ship-to-ship separation.
func nudge(offset: Vector2) -> void:
	if under_construction or not is_alive():
		return
	var next: Vector2 = position + offset
	if not match_ref.nav.is_blocked(next, stats.shallow_draft):
		position = next


# --- Weapons ----------------------------------------------------------------

func _update_weapons(delta: float) -> void:
	_gun_cd = maxf(0.0, _gun_cd - delta)
	_sec_cd = maxf(0.0, _sec_cd - delta)
	_torp_cd = maxf(0.0, _torp_cd - delta)
	_plane_cd = maxf(0.0, _plane_cd - delta)
	_torpedo_bomber_cd = maxf(0.0, _torpedo_bomber_cd - delta)
	_depth_bomber_cd = maxf(0.0, _depth_bomber_cd - delta)
	_depth_cd = maxf(0.0, _depth_cd - delta)
	_think_cd -= delta
	var think: bool = _think_cd <= 0.0
	if think:
		_think_cd = THINK_INTERVAL
		if stats.has_guns():
			gun_target = _pick_target(stats.gun_range, true)
		if stats.has_secondaries():
			secondary_target = _pick_target(stats.secondary_range, true)
	if stats.has_guns() and _gun_cd <= 0.0 and gun_target != null:
		_fire_guns()
	if stats.has_secondaries() and _sec_cd <= 0.0 and secondary_target != null:
		_fire_secondaries()
	match stats.torpedo_mode:
		ShipStats.TorpedoMode.AUTO_BROADSIDE:
			if think and _torp_cd <= 0.0:
				_try_auto_torpedoes()
		ShipStats.TorpedoMode.MANUAL_BOW_STERN:
			# Submarines never auto-engage: they fire only on an explicit order.
			if torpedo_order != null and _torp_cd <= 0.0:
				_try_manual_torpedoes()
	if stats.has_depth_charges() and think and _depth_cd <= 0.0:
		_try_depth_charges()
	if stats.has_planes():
		_update_air_wing(delta)
	if stats.has_periodic_aa():
		_aa_cd = maxf(0.0, _aa_cd - delta)
		if think and _aa_cd <= 0.0:
			_aa_barrage()


## Super Battleship flak: every `periodic_aa_interval` seconds each enemy squadron within
## range is shot down with `periodic_aa_chance`. The timer starts when planes come in range.
func _aa_barrage() -> void:
	var targets: Array[PlaneSquadron] = []
	var r2: float = stats.periodic_aa_range * stats.periodic_aa_range
	for node: Node in match_ref.projectiles():
		var squadron: PlaneSquadron = node as PlaneSquadron
		if squadron == null or squadron.is_queued_for_deletion() or not match_ref.are_enemies(squadron.team, team):
			continue
		if squadron.position.distance_squared_to(position) <= r2:
			targets.append(squadron)
	if targets.is_empty():
		return
	_aa_cd = stats.periodic_aa_interval
	flak_barrages += 1
	for squadron: PlaneSquadron in targets:
		match_ref.spawn_effect(squadron.position, Effect.Kind.FLAK)
		if match_ref.rng.randf() < stats.periodic_aa_chance:
			flak_kills += 1
			squadron.shoot_down()


## Destroyer depth charges: automatic against the nearest detected enemy submarine close
## aboard. No line of fire is needed and armor does not help the boat.
func _try_depth_charges() -> void:
	var best: Ship = null
	var best_dist: float = stats.depth_charge_range
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive() or not enemy.is_submarine() or not enemy.spotted_by[team]:
			continue
		var boat: Ship = enemy as Ship
		if boat.under_construction:
			continue
		var dist: float = position.distance_to(boat.position)
		if dist <= best_dist:
			best_dist = dist
			best = boat
	if best == null:
		return
	_depth_cd = stats.depth_charge_interval
	depth_charges_dropped += 1
	match_ref.spawn_effect(best.position, Effect.Kind.DEPTH_CHARGE)
	best.register_attacker(self, stats.depth_charge_interval + 1.0)
	best.apply_damage(stats.depth_charge_damage, true, false)


## Line of sight from `from` to a target; a garrison's own island does not hide it.
func has_los_to(from: Vector2, target: Combatant) -> bool:
	return match_ref.has_los(from, target.position, target.los_blocker())


func _target_valid(target: Combatant, max_range: float, needs_los: bool) -> bool:
	if target == null or not target.is_alive() or not target.spotted_by[team] or not can_engage(target):
		return false
	if range_to(target) > max_range:
		return false
	return not needs_los or has_los_to(position, target)


## Priority target if it is legal, otherwise the nearest spotted enemy in range.
func _pick_target(max_range: float, needs_los: bool) -> Combatant:
	if _target_valid(priority_target, max_range, needs_los):
		return priority_target
	var best: Combatant = null
	var best_score: float = INF
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive() or not enemy.spotted_by[team] or not can_engage(enemy):
			continue
		var dist: float = range_to(enemy)
		if dist > max_range:
			continue
		# Armed ships first, then defenseless hulls on the slip, then island garrisons, then the base.
		var score: float = dist
		if enemy.is_home_base():
			score += 200000.0
		elif enemy.is_structure():
			score += 150000.0
		elif (enemy as Ship).under_construction:
			score += 100000.0
		if score >= best_score:
			continue
		if needs_los and not has_los_to(position, enemy):
			continue
		best = enemy
		best_score = score
	return best


func _lead_point(from: Vector2, target: Combatant, projectile_speed: float) -> Vector2:
	var aim: Vector2 = target.position
	for i: int in 2:
		var t: float = from.distance_to(aim) / maxf(1.0, projectile_speed)
		aim = target.position + target.velocity * t
	return aim


func mount_position(index: int) -> Vector2:
	return position + Vector2(stats.mount_offsets[index], 0.0).rotated(rotation)


## True if mount `index` can train onto `point`.
func mount_bears_on(index: int, point: Vector2) -> bool:
	var facing: float = rotation + deg_to_rad(stats.mount_facings_deg[index])
	var bearing: float = (point - mount_position(index)).angle()
	return absf(angle_difference(facing, bearing)) <= deg_to_rad(stats.mount_arc_half_deg)


## Fires every mount that bears on the target and has its own clear line of sight.
func _fire_guns() -> void:
	var target: Combatant = gun_target
	if not _target_valid(target, stats.gun_range, false):
		gun_target = null
		return
	var fired: bool = false
	var mount_damage: float = stats.shell_damage * float(stats.shells_per_mount)
	var max_travel: float = stats.gun_range * 1.15 + target.range_padding()
	for i: int in stats.gun_mounts:
		var origin: Vector2 = mount_position(i)
		var aim: Vector2 = _lead_point(origin, target, stats.shell_speed)
		if not mount_bears_on(i, aim):
			continue
		if not has_los_to(origin, target):
			continue
		var spread: float = deg_to_rad(stats.dispersion_deg)
		var angle: float = (aim - origin).angle() + match_ref.rng.randf_range(-spread, spread)
		match_ref.spawn_shell(self, origin, angle, mount_damage, stats.shell_speed, max_travel,
			stats.shells_per_mount)
		fired = true
	if fired:
		_gun_cd = stats.fire_interval
		salvos_fired += 1
		target.register_attacker(self, stats.fire_interval + 1.0)


func secondary_position(index: int) -> Vector2:
	return position + stats.secondary_offsets[index].rotated(rotation)


func secondary_bears_on(index: int, point: Vector2) -> bool:
	var facing: float = rotation + deg_to_rad(stats.secondary_facings_deg[index])
	var bearing: float = (point - secondary_position(index)).angle()
	return absf(angle_difference(facing, bearing)) <= deg_to_rad(stats.secondary_arc_half_deg)


## Secondary battery: every mount that bears fires one shell at the battery's own target.
func _fire_secondaries() -> void:
	var target: Combatant = secondary_target
	if not _target_valid(target, stats.secondary_range, false):
		secondary_target = null
		return
	var fired: bool = false
	var max_travel: float = stats.secondary_range * 1.15 + target.range_padding()
	var spread: float = deg_to_rad(stats.secondary_dispersion_deg)
	for i: int in stats.secondary_mounts:
		var origin: Vector2 = secondary_position(i)
		var aim: Vector2 = _lead_point(origin, target, stats.secondary_shell_speed)
		if not secondary_bears_on(i, aim) or not has_los_to(origin, target):
			continue
		var angle: float = (aim - origin).angle() + match_ref.rng.randf_range(-spread, spread)
		match_ref.spawn_shell(self, origin, angle, stats.secondary_shell_damage, stats.secondary_shell_speed,
			max_travel, 1)
		fired = true
	if fired:
		_sec_cd = stats.secondary_interval
		secondary_salvos += 1
		target.register_attacker(self, stats.secondary_interval + 1.0)


## Signed bearing of `point` relative to the bow (-PI..PI, positive = starboard).
func relative_bearing(point: Vector2) -> float:
	return angle_difference(rotation, (point - position).angle())


func in_broadside_arc(point: Vector2) -> bool:
	var off_beam: float = absf(absf(relative_bearing(point)) - PI * 0.5)
	return off_beam <= deg_to_rad(BROADSIDE_HALF_ARC_DEG)


## Destroyer torpedoes: automatic, but only when a target sits in a broadside arc.
## The 30s cooldown is not spent unless torpedoes actually launch.
func _try_auto_torpedoes() -> void:
	var best: Combatant = null
	var best_dist: float = INF
	if _torpedo_candidate_ok(priority_target):
		best = priority_target
	else:
		for enemy: Combatant in match_ref.vision.spotted_enemies(team):
			if not _torpedo_candidate_ok(enemy):
				continue
			var dist: float = range_to(enemy)
			if enemy.is_structure():
				dist += 100000.0
			if dist < best_dist:
				best_dist = dist
				best = enemy
	if best == null:
		return
	var side: float = signf(relative_bearing(best.position))
	var origin: Vector2 = position + Vector2.from_angle(rotation + side * PI * 0.5) * stats.hull_width
	var aim: Vector2 = _lead_point(origin, best, torpedo_speed())
	_launch_torpedoes(origin, (aim - origin).angle(), null, 0.0, best)


func _torpedo_candidate_ok(enemy: Combatant) -> bool:
	if enemy == null or not enemy.is_alive() or not enemy.spotted_by[team]:
		return false
	if range_to(enemy) > stats.torpedo_range:
		return false
	if not in_broadside_arc(enemy.position):
		return false
	return has_los_to(position, enemy)


## Submarine torpedoes: bow or stern tubes, 2s homing ping, 15s reveal penalty.
func _try_manual_torpedoes() -> void:
	var target: Combatant = torpedo_order
	if not target.is_alive() or target.is_structure() or not target.is_enemy_of(team):
		torpedo_order = null
		return
	if not target.spotted_by[team]:
		return
	if range_to(target) > stats.torpedo_range:
		return
	if not has_los_to(position, target):
		return
	var bow: bool = absf(relative_bearing(target.position)) <= PI * 0.5
	var tube_dir: float = rotation if bow else rotation + PI
	var origin: Vector2 = position + Vector2.from_angle(tube_dir) * stats.hull_length * 0.5
	_launch_torpedoes(origin, tube_dir, target, GameData.balance().sub_homing_time, target)
	reveal_timer = GameData.balance().sub_reveal_time
	torpedo_order = null
	_clear_path()


func _launch_torpedoes(origin: Vector2, angle: float, homing_target: Combatant,
		homing_time: float, attacked: Combatant) -> void:
	var count: int = stats.torpedoes_per_launch
	var spread: float = deg_to_rad(stats.torpedo_spread_deg)
	var max_travel: float = stats.torpedo_range * 1.25 + attacked.range_padding()
	for i: int in count:
		var offset: float = (float(i) - float(count - 1) * 0.5) * spread
		match_ref.spawn_torpedo(self, origin, angle + offset, max_travel, homing_target, homing_time)
	_torp_cd = stats.torpedo_interval
	torpedoes_launched += count
	attacked.register_attacker(self, 8.0)


# --- Carrier air wing -------------------------------------------------------

## What the air wing is working right now: the ordered strike target if there is one,
## otherwise the target the carrier picked for itself.
func air_target() -> Combatant:
	return strike_target if strike_target != null else _auto_strike


## True while the squadrons in the air may work the current air target.
func strike_active() -> bool:
	var target: Combatant = air_target()
	if not is_alive() or target == null or not target.is_alive() or not target.is_enemy_of(team):
		return false
	return range_to(target) <= stats.plane_range * STRIKE_LEASH


func air_reach() -> float:
	return stats.plane_range * STRIKE_LEASH


## The air wing works on its own. With a spotted enemy inside plane range:
## - HE dive bombers launch every `plane_interval` seconds (up to `max_squadrons` airborne)
##   and work `air_target()`: the ordered strike target, or the carrier's own choice.
## - Torpedo bombers launch every `torpedo_bomber_interval` seconds at a capital ship
##   (Battlecruiser or larger), drop their torpedoes and fly home.
## - Depth-charge bombers launch every `depth_bomber_interval` seconds at a spotted submarine.
## Planes fly over islands, so no line of sight is needed.
func _update_air_wing(delta: float) -> void:
	_check_ordered_strike(delta)
	if strike_target != null:
		_auto_strike = null
	elif not _auto_strike_valid():
		_auto_strike = _pick_target(stats.plane_range, false)
	if _plane_cd <= 0.0:
		_launch_squadrons()
	if stats.has_torpedo_bombers() and _torpedo_bomber_cd <= 0.0 and _air_wing_has_room() \
			and airborne_of(PlaneSquadron.Role.TORPEDO) < stats.max_torpedo_bombers:
		if _launch_torpedo_flights() > 0:
			_torpedo_bomber_cd = stats.torpedo_bomber_interval
	if stats.has_depth_bombers() and _depth_bomber_cd <= 0.0 and _air_wing_has_room() \
			and airborne_of(PlaneSquadron.Role.DEPTH) < stats.max_depth_bombers:
		var boat: Ship = _pick_mission_target(true)
		if boat != null:
			_launch_mission(PlaneSquadron.Role.DEPTH, boat)
			_depth_bomber_cd = stats.depth_bomber_interval


## True if a torpedo bomber may be sent at `target`: Battlecruisers and larger only.
static func torpedo_bomber_can_target(target: Combatant) -> bool:
	var ship: Ship = target as Ship
	return ship != null and ShipStats.is_capital_class(ship.stats.ship_class)


## A spotted enemy ship in plane range for a torpedo flight (`subs` false: capital ships) or
## a depth-charge flight (`subs` true: submarines). The ordered strike target comes first if
## it qualifies, then the nearest.
func _pick_mission_target(subs: bool) -> Ship:
	var ordered: Ship = air_target() as Ship
	if _mission_target_ok(ordered, subs):
		return ordered
	var best: Ship = null
	var best_dist: float = INF
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		var ship: Ship = enemy as Ship
		if not _mission_target_ok(ship, subs):
			continue
		var dist: float = range_to(ship)
		if dist < best_dist:
			best_dist = dist
			best = ship
	return best


func _mission_target_ok(ship: Ship, subs: bool) -> bool:
	if ship == null or not ship.is_alive() or not ship.spotted_by[team] or not ship.is_enemy_of(team):
		return false
	if subs != ship.stats.is_submarine:
		return false
	if not subs and not torpedo_bomber_can_target(ship):
		return false
	return range_to(ship) <= stats.plane_range


## Sends up to `torpedo_flights_per_launch` torpedo flights, dealt round-robin over up to that
## many capital targets (the ordered strike target first, then the nearest), with at most
## `torpedo_flights_per_target` flights on any one target. One target in reach gets them all;
## two targets get A, B, A. Returns the number launched.
func _launch_torpedo_flights() -> int:
	var targets: Array[Ship] = _torpedo_targets(stats.torpedo_flights_per_launch)
	if targets.is_empty():
		return 0
	var launched: int = 0
	var index: int = 0
	var misses: int = 0
	while launched < stats.torpedo_flights_per_launch and misses < targets.size():
		if not _air_wing_has_room() or airborne_of(PlaneSquadron.Role.TORPEDO) >= stats.max_torpedo_bombers:
			break
		var target: Ship = targets[index % targets.size()]
		index += 1
		if missions_on(target, PlaneSquadron.Role.TORPEDO) >= stats.torpedo_flights_per_target:
			misses += 1
			continue
		misses = 0
		_launch_mission(PlaneSquadron.Role.TORPEDO, target)
		launched += 1
	return launched


## Up to `count` torpedo-bomber targets: the ordered strike target first if it qualifies, then
## the nearest spotted capital ships in plane range that still have room for a flight.
func _torpedo_targets(count: int) -> Array[Ship]:
	var picked: Array[Ship] = []
	var ordered: Ship = air_target() as Ship
	if _mission_target_ok(ordered, false) \
			and missions_on(ordered, PlaneSquadron.Role.TORPEDO) < stats.torpedo_flights_per_target:
		picked.append(ordered)
	var others: Array[Ship] = []
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		var ship: Ship = enemy as Ship
		if ship == ordered or not _mission_target_ok(ship, false):
			continue
		if missions_on(ship, PlaneSquadron.Role.TORPEDO) >= stats.torpedo_flights_per_target:
			continue
		others.append(ship)
	others.sort_custom(func(a: Ship, b: Ship) -> bool:
		var da: float = range_to(a)
		var db: float = range_to(b)
		return da < db or (da == db and a.net_id < b.net_id))
	for ship: Ship in others:
		if picked.size() >= count:
			break
		picked.append(ship)
	return picked


## Airborne flights of `role` from this carrier sent at `target`.
func missions_on(target: Combatant, role: PlaneSquadron.Role) -> int:
	var count: int = 0
	for squadron: PlaneSquadron in _squadrons:
		if squadron.role == role and squadron.mission_target == target:
			count += 1
	return count


func _launch_mission(role: PlaneSquadron.Role, target: Ship) -> void:
	var heading: float = (target.position - position).angle()
	_squadrons.append(match_ref.spawn_squadron(self, position, heading, role, target))
	squadrons_launched += 1


## Drops the ordered strike once its target is dead, lost for too long or out of reach.
func _check_ordered_strike(delta: float) -> void:
	var target: Combatant = strike_target
	if target == null:
		return
	if not target.is_alive() or not target.is_enemy_of(team):
		clear_strike()
		return
	if target.spotted_by[team] or target.is_structure():
		_strike_unseen = 0.0
	else:
		_strike_unseen += delta
		if _strike_unseen > STRIKE_LOST_TIME:
			clear_strike()
			return
	if range_to(target) > stats.plane_range * STRIKE_LEASH and priority_target != target:
		# Out of reach and the carrier is not closing on it: the strike is called off.
		clear_strike()


## The carrier keeps its own target until it sinks, slips out of sight or out of reach.
func _auto_strike_valid() -> bool:
	var target: Combatant = _auto_strike
	if target == null or not target.is_alive() or not target.is_enemy_of(team) or not target.spotted_by[team]:
		return false
	return range_to(target) <= stats.plane_range * STRIKE_LEASH


## Dive bombers: each launch goes to the ordered strike target while it has room in its
## stack (`squadrons_per_target`), otherwise to the nearest spotted enemy in plane range that
## has room. A Heavy Carrier can so work several targets at once, up to 5 squadrons on each;
## a Light Carrier is capped at `max_total_squadrons` in the air.
func _launch_squadrons() -> void:
	var launched: bool = false
	for i: int in stats.squadrons_per_launch:
		if airborne_of(PlaneSquadron.Role.DIVE) >= stats.max_squadrons or not _air_wing_has_room():
			break
		var target: Combatant = _pick_dive_target(position, null)
		if target == null or not target.spotted_by[team] or range_to(target) > stats.plane_range:
			break
		var squadron: PlaneSquadron = match_ref.spawn_squadron(self, position, (target.position - position).angle())
		squadron.dive_target = target
		_squadrons.append(squadron)
		squadrons_launched += 1
		launched = true
	if launched:
		_plane_cd = stats.plane_interval


func _air_wing_has_room() -> bool:
	return stats.max_total_squadrons <= 0 or _squadrons.size() < stats.max_total_squadrons


## Dive-bomber squadrons from this carrier working `target` (not counting `skip`).
func squadrons_on(target: Combatant, skip: PlaneSquadron = null) -> int:
	var count: int = 0
	for squadron: PlaneSquadron in _squadrons:
		if squadron != skip and squadron.role == PlaneSquadron.Role.DIVE and squadron.dive_target == target:
			count += 1
	return count


func _stack_room(target: Combatant, skip: PlaneSquadron) -> int:
	if stats.squadrons_per_target <= 0:
		return 1000000
	return stats.squadrons_per_target - squadrons_on(target, skip)


## Each squadron keeps its own target; when that one sinks or is lost the squadron goes
## straight to another target within the carrier's strike reach (or home if there is none).
func dive_target_for(squadron: PlaneSquadron) -> Combatant:
	if not is_alive():
		return null
	if _dive_target_ok(squadron.dive_target):
		return squadron.dive_target
	squadron.dive_target = _pick_dive_target(squadron.position, squadron)
	return squadron.dive_target


func _dive_target_ok(target: Combatant) -> bool:
	if target == null or not target.is_alive() or not target.is_enemy_of(team):
		return false
	if target == strike_target:
		# The ordered strike stays on (circling the last known position) until
		# _check_ordered_strike calls it off.
		return true
	return target.spotted_by[team] and range_to(target) <= air_reach()


## The ordered strike target if it has room, otherwise the nearest spotted enemy to `from`
## inside plane range with room in its stack (armed ships before hulls, garrisons and bases).
func _pick_dive_target(from: Vector2, squadron: PlaneSquadron) -> Combatant:
	if strike_target != null and _dive_target_ok(strike_target) and _stack_room(strike_target, squadron) > 0:
		return strike_target
	var best: Combatant = null
	var best_score: float = INF
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive() or not enemy.spotted_by[team] or not can_engage(enemy):
			continue
		if range_to(enemy) > stats.plane_range or _stack_room(enemy, squadron) <= 0:
			continue
		var score: float = from.distance_to(enemy.position)
		if enemy.is_home_base():
			score += 200000.0
		elif enemy.is_structure():
			score += 150000.0
		elif (enemy as Ship).under_construction:
			score += 100000.0
		if score < best_score:
			best = enemy
			best_score = score
	return best


## Called by a squadron when it lands or is shot down, freeing its place in the air wing.
func squadron_gone(squadron: PlaneSquadron, shot_down: bool) -> void:
	_squadrons.erase(squadron)
	if shot_down:
		squadrons_lost += 1


# --- Network replication ----------------------------------------------------

## Appends this ship's NET_FIELDS floats to a snapshot.
func net_write(out: PackedFloat32Array) -> void:
	var replica: bool = match_ref.replica
	var at: Vector2 = net_pos if replica else position
	out.append_array(PackedFloat32Array([
		float(net_id), float(stats.ship_class), float(team), at.x, at.y, net_rot if replica else rotation,
		hp, 1.0 if under_construction else 0.0, build_progress, reveal_timer, velocity.x, velocity.y,
		_gun_cd, _torp_cd, _plane_cd, _depth_cd, float(airborne_squadrons()),
		float(_net_strike_ref if replica else match_ref.combatant_ref(strike_target)),
		float(_net_auto_ref if replica else match_ref.combatant_ref(_auto_strike)), _sec_cd,
		_torpedo_bomber_cd, _depth_bomber_cd]))


## Replica: takes this ship's state from a snapshot. `snap` jumps straight to the new position.
func net_read(data: PackedFloat32Array, at: int, snap: bool) -> void:
	net_pos = Vector2(data[at + 3], data[at + 4])
	net_rot = data[at + 5]
	hp = data[at + 6]
	under_construction = data[at + 7] > 0.5
	build_progress = data[at + 8]
	reveal_timer = data[at + 9]
	velocity = Vector2(data[at + 10], data[at + 11])
	_gun_cd = data[at + 12]
	_torp_cd = data[at + 13]
	_plane_cd = data[at + 14]
	_depth_cd = data[at + 15]
	_net_squadrons = int(data[at + 16])
	_net_strike_ref = int(data[at + 17])
	_net_auto_ref = int(data[at + 18])
	_sec_cd = data[at + 19]
	_torpedo_bomber_cd = data[at + 20]
	_depth_bomber_cd = data[at + 21]
	_net_age = 0.0
	if snap or under_construction or position.distance_to(net_pos) > NET_SNAP_DISTANCE:
		position = net_pos
		rotation = net_rot


## Replica: turns the target ids of the last snapshot back into combatants (for the HUD).
func net_resolve_targets() -> void:
	strike_target = match_ref.combatant_from_ref(_net_strike_ref)
	_auto_strike = match_ref.combatant_from_ref(_net_auto_ref)


## Replica: eases the drawn hull toward the host's position, sailing on briefly between snapshots.
func net_smooth(delta: float) -> void:
	if under_construction:
		return
	_net_age = minf(_net_age + delta, NET_EXTRAPOLATE_TIME)
	var weight: float = 1.0 - exp(-14.0 * delta)
	position = position.lerp(net_pos + velocity * _net_age, weight)
	rotation = lerp_angle(rotation, net_rot, weight)


# --- Drawing ----------------------------------------------------------------

## Range rings are drawn for the local player's own ships only: the selected ones, or the
## whole fleet while the HUD toggle is on. Never for enemy ships.
func shows_range_rings() -> bool:
	if match_ref == null or match_ref.local_team < 0 or team != match_ref.local_team:
		return false
	if not is_combat_ready():
		return false
	return selected or match_ref.show_all_ranges


## One Vector2(radius, kind) per weapon system: kind 0 = guns, 1 = torpedoes, 2 = aircraft,
## 3 = secondary guns.
func range_rings() -> PackedVector2Array:
	var rings: PackedVector2Array = PackedVector2Array()
	if stats.has_guns():
		rings.append(Vector2(stats.gun_range, 0.0))
	if stats.torpedo_mode != ShipStats.TorpedoMode.NONE:
		rings.append(Vector2(stats.torpedo_range, 1.0))
	if stats.has_planes():
		rings.append(Vector2(stats.plane_range, 2.0))
	if stats.has_secondaries():
		rings.append(Vector2(stats.secondary_range, 3.0))
	return rings


func _draw_range_rings() -> void:
	var colors: Array[Color] = [RING_GUN_COLOR, RING_TORPEDO_COLOR, RING_PLANE_COLOR, RING_SECONDARY_COLOR]
	for ring: Vector2 in range_rings():
		var segments: int = clampi(int(ring.x / 8.0), 48, 160)
		draw_arc(Vector2.ZERO, ring.x, 0.0, TAU, segments, colors[int(ring.y)], 2.0, true)


func _draw() -> void:
	if stats == null:
		return
	if shows_range_rings():
		_draw_range_rings()
	var color: Color = TEAM_COLORS[team]
	var half_l: float = stats.hull_length * 0.5
	var tint: Color = Color.WHITE
	if under_construction:
		tint = Color(1.0, 1.0, 1.0, 0.45)
	elif stats.is_submarine and reveal_timer <= 0.0:
		# Submerged: seen through the water, dim and blue.
		tint = Color(0.62, 0.78, 0.92, 0.62)
	var roll: float = 0.0
	if not under_construction:
		roll = sin(_anim_time * 1.1 + float(net_id)) * 0.03 * clampf(60.0 / stats.hull_length, 0.5, 1.3)
	if _body_layer != null:
		# The hull is a baked sprite on its own layer; here it is only re-tinted and rolled.
		_body_layer.modulate = tint
		_body_layer.scale = Vector2(1.0, 1.0 + roll)
		_wake_layer.modulate = tint
		ShipArt.draw_guns(self, stats, tint, turret_angles, secondary_angles,
			Transform2D(0.0, Vector2(1.0, 1.0 + roll), 0.0, Vector2.ZERO))
	else:
		ShipArt.draw(self, stats, color, tint, turret_angles, secondary_angles, roll)
	if not under_construction and max_hp > 0.0:
		ShipArt.draw_fires(self, stats, 1.0 - clampf(hp / max_hp, 0.0, 1.0), _anim_time, rotation, net_id)
	if selected:
		draw_arc(Vector2.ZERO, half_l + 8.0, 0.0, TAU, 40, Color(0.5, 1.0, 0.55, 0.9), 1.5)
	# Overlays stay screen-aligned regardless of heading.
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var bar_w: float = maxf(30.0, stats.hull_length * 0.7)
	var bar_pos: Vector2 = Vector2(-bar_w * 0.5, -half_l - 16.0)
	var frac: float = clampf(hp / max_hp, 0.0, 1.0)
	if frac < 0.999 or selected or under_construction:
		draw_rect(Rect2(bar_pos, Vector2(bar_w, 4.0)), Color(0, 0, 0, 0.6))
		var hp_color: Color = Color(0.3, 0.9, 0.35) if frac > 0.5 else (Color(0.95, 0.8, 0.2) if frac > 0.25 else Color(0.95, 0.25, 0.2))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * frac, 4.0)), hp_color)
	if under_construction:
		draw_rect(Rect2(bar_pos + Vector2(0.0, 6.0), Vector2(bar_w, 3.0)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar_pos + Vector2(0.0, 6.0), Vector2(bar_w * build_progress, 3.0)), Color(1.0, 0.85, 0.3))
	if stats.is_submarine and reveal_timer > 0.0:
		draw_arc(Vector2.ZERO, half_l + 4.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.2, 0.9), 1.5)
	if stats.mines_islands:
		_draw_mining_marker(half_l)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Resource Ship at work: a pulsing gold ring, a line to the island and a coin badge above
## the hull. Cosmetic; drawn screen-aligned.
func _draw_mining_marker(half_l: float) -> void:
	var mine: Island = shown_mining_island()
	if mine == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.0)
	var gold: Color = Color(1.0, 0.82, 0.3)
	var to_island: Vector2 = (mine.position - position).rotated(0.0)
	var edge: Vector2 = to_island - to_island.normalized() * mine.radius
	draw_dashes(Vector2.ZERO, edge, Color(gold.r, gold.g, gold.b, 0.55), 1.5, 8.0)
	draw_arc(Vector2.ZERO, half_l + 6.0 + 4.0 * pulse, 0.0, TAU, 32, Color(gold.r, gold.g, gold.b, 0.4 + 0.4 * pulse), 2.0)
	var badge: Vector2 = Vector2(0.0, -half_l - 30.0 - 2.0 * pulse)
	draw_circle(badge + Vector2(0.0, 1.5), 9.0, Color(0.25, 0.15, 0.0, 0.8))
	draw_circle(badge, 9.0, Color(0.95, 0.72, 0.2))
	draw_circle(badge, 6.5, Color(1.0, 0.86, 0.38))
	# A little pick across the coin.
	draw_line(badge + Vector2(-4.0, 4.0), badge + Vector2(4.0, -4.0), Color(0.35, 0.22, 0.05), 2.0)
	draw_arc(badge + Vector2(2.5, -2.5), 4.5, PI * 0.75, PI * 1.75, 8, Color(0.35, 0.22, 0.05), 2.0)


## The island this Resource Ship is mining (a replica judges by the synced speed).
func shown_mining_island() -> Island:
	if not match_ref.replica:
		return mining_island()
	if not stats.mines_islands or not is_combat_ready() or velocity.length() > MINING_MAX_SPEED:
		return null
	var reach: float = GameData.balance().mining_reach
	for island: Island in match_ref.islands:
		var limit: float = island.radius + reach
		if position.distance_squared_to(island.position) <= limit * limit:
			return island
	return null


func draw_dashes(from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var length: float = from.distance_to(to)
	if length < 1.0:
		return
	var dir: Vector2 = (to - from) / length
	var at: float = fmod(_anim_time * 12.0, dash * 2.0)
	while at < length:
		draw_line(from + dir * at, from + dir * minf(at + dash, length), color, width)
		at += dash * 2.0
