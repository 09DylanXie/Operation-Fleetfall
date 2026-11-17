class_name Ship
extends Combatant
## One hull of any class. Movement has a real heading and turn rate because
## turret arcs, Destroyer broadside tubes and Submarine bow/stern tubes depend on it.

signal construction_completed(ship: Ship)

const THINK_INTERVAL: float = 0.25
const REPATH_INTERVAL: float = 1.0
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
const TEAM_COLORS: Array[Color] = [Color(0.36, 0.72, 1.0), Color(1.0, 0.42, 0.36)]
const RING_GUN_COLOR: Color = Color(1.0, 0.85, 0.4, 0.5)
const RING_TORPEDO_COLOR: Color = Color(0.4, 0.92, 1.0, 0.5)
const RING_PLANE_COLOR: Color = Color(0.82, 0.7, 1.0, 0.5)

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
## Carrier air-strike target picked by an explicit order. It overrides the air wing's own
## choice and survives move orders, so the carrier can reposition while its squadrons work.
var strike_target: Combatant = null
var separation_radius: float = 16.0
var salvos_fired: int = 0
var torpedoes_launched: int = 0
var depth_charges_dropped: int = 0
var squadrons_launched: int = 0
var squadrons_lost: int = 0

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _has_destination: bool = false
var _destination: Vector2 = Vector2.ZERO
var _gun_cd: float = 0.0
var _torp_cd: float = 0.0
var _plane_cd: float = 0.0
var _depth_cd: float = 0.0
var _think_cd: float = 0.0
var _repath_cd: float = 0.0
var _stuck_time: float = 0.0
var _best_dist: float = INF
var _repath_attempts: int = 0
var _chase_lost: bool = false
var _chase_goal: Vector2 = Vector2.ZERO
var _squadrons: Array[PlaneSquadron] = []
var _strike_unseen: float = 0.0
## The target the air wing chose for itself while no strike is ordered.
var _auto_strike: Combatant = null


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


func plane_cooldown() -> float:
	return _plane_cd


func depth_charge_cooldown() -> float:
	return _depth_cd


func airborne_squadrons() -> int:
	return _squadrons.size()


## Chance that this ship shoots down a squadron that has just bombed it.
func aa_kill_chance() -> float:
	return 0.0 if under_construction else stats.aa_kill_chance


func torpedo_speed() -> float:
	return GameData.torpedo_speed() * stats.torpedo_speed_scale


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
	priority_target = null
	torpedo_order = null
	_chase_lost = false
	_set_destination(dest)


## True if this hull's weapons may be aimed at `target` at all: an enemy, and not a
## Submarine for hulls that cannot engage them (Battleships).
func can_engage(target: Combatant) -> bool:
	if target == null or target.team == team:
		return false
	return stats.can_target_submarines or not target.is_submarine()


## Focus a target. Submarines treat this as a manual torpedo attack; carriers close to
## plane range and send their squadrons at it.
func order_attack(target: Combatant) -> bool:
	if not is_combat_ready() or target == null or not target.is_alive() or not can_engage(target):
		return false
	if stats.torpedo_mode == ShipStats.TorpedoMode.MANUAL_BOW_STERN:
		return order_torpedo(target)
	if stats.has_planes():
		order_strike(target)
	priority_target = target
	torpedo_order = null
	_chase_lost = false
	_repath_cd = 0.0
	return true


## Manual Submarine torpedo attack. Home Bases are never valid targets.
func order_torpedo(target: Combatant) -> bool:
	if not is_combat_ready() or stats.torpedo_mode != ShipStats.TorpedoMode.MANUAL_BOW_STERN:
		return false
	if target == null or not target.is_alive() or target.team == team or target.is_structure():
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
	if target == null or not target.is_alive() or target.team == team:
		return false
	strike_target = target
	_strike_unseen = 0.0
	return true


## Drops an ordered air strike; the air wing goes back to choosing its own targets.
func clear_strike() -> void:
	strike_target = null
	_strike_unseen = 0.0


func order_stop() -> void:
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
	if not is_alive() or match_ref == null or match_ref.is_over:
		return
	if reveal_timer > 0.0:
		reveal_timer = maxf(0.0, reveal_timer - delta)
	if under_construction:
		velocity = Vector2.ZERO
		return
	_update_orders(delta)
	_update_movement(delta)
	_update_weapons(delta)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Distance to a target measured to its edge for large structures.
func range_to(target: Combatant) -> float:
	return maxf(0.0, position.distance_to(target.position) - target.range_padding())


func _update_orders(delta: float) -> void:
	var chase: Combatant = torpedo_order if torpedo_order != null else priority_target
	if chase == null:
		return
	if not chase.is_alive() or chase.team == team:
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
			if _has_destination:
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
	velocity = (position - prev) / delta if delta > 0.0 else Vector2.ZERO


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
	_torp_cd = maxf(0.0, _torp_cd - delta)
	_plane_cd = maxf(0.0, _plane_cd - delta)
	_depth_cd = maxf(0.0, _depth_cd - delta)
	_think_cd -= delta
	var think: bool = _think_cd <= 0.0
	if think:
		_think_cd = THINK_INTERVAL
		if stats.has_guns():
			gun_target = _pick_target(stats.gun_range, true)
	if stats.has_guns() and _gun_cd <= 0.0 and gun_target != null:
		_fire_guns()
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
	if not target.is_alive() or target.is_structure() or target.team == team:
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
	if not is_alive() or target == null or not target.is_alive() or target.team == team:
		return false
	return range_to(target) <= stats.plane_range * STRIKE_LEASH


## The air wing works on its own: with a spotted enemy inside plane range a squadron
## launches every `plane_interval` seconds (up to `max_squadrons` airborne). An ordered
## strike target takes over from the carrier's own choice. Planes fly over islands, so no
## line of sight is needed. The squadrons themselves follow `air_target()` each tick.
func _update_air_wing(delta: float) -> void:
	_check_ordered_strike(delta)
	if strike_target != null:
		_auto_strike = null
	elif not _auto_strike_valid():
		_auto_strike = _pick_target(stats.plane_range, false)
	var target: Combatant = air_target()
	if target == null or _plane_cd > 0.0:
		return
	if target.spotted_by[team] and range_to(target) <= stats.plane_range:
		_launch_squadrons(target)


## Drops the ordered strike once its target is dead, lost for too long or out of reach.
func _check_ordered_strike(delta: float) -> void:
	var target: Combatant = strike_target
	if target == null:
		return
	if not target.is_alive() or target.team == team:
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
	if target == null or not target.is_alive() or target.team == team or not target.spotted_by[team]:
		return false
	return range_to(target) <= stats.plane_range * STRIKE_LEASH


func _launch_squadrons(target: Combatant) -> void:
	var heading: float = (target.position - position).angle()
	var launched: bool = false
	for i: int in stats.squadrons_per_launch:
		if _squadrons.size() >= stats.max_squadrons:
			break
		_squadrons.append(match_ref.spawn_squadron(self, position, heading))
		squadrons_launched += 1
		launched = true
	if launched:
		_plane_cd = stats.plane_interval


## Called by a squadron when it lands or is shot down, freeing its place in the air wing.
func squadron_gone(squadron: PlaneSquadron, shot_down: bool) -> void:
	_squadrons.erase(squadron)
	if shot_down:
		squadrons_lost += 1


# --- Drawing ----------------------------------------------------------------

## Range rings are drawn for the local player's own ships only: the selected ones, or the
## whole fleet while the HUD toggle is on. Never for enemy ships.
func shows_range_rings() -> bool:
	if match_ref == null or match_ref.local_team < 0 or team != match_ref.local_team:
		return false
	if not is_combat_ready():
		return false
	return selected or match_ref.show_all_ranges


## One Vector2(radius, kind) per weapon system: kind 0 = guns, 1 = torpedoes, 2 = aircraft.
func range_rings() -> PackedVector2Array:
	var rings: PackedVector2Array = PackedVector2Array()
	if stats.has_guns():
		rings.append(Vector2(stats.gun_range, 0.0))
	if stats.torpedo_mode != ShipStats.TorpedoMode.NONE:
		rings.append(Vector2(stats.torpedo_range, 1.0))
	if stats.has_planes():
		rings.append(Vector2(stats.plane_range, 2.0))
	return rings


func _draw_range_rings() -> void:
	var colors: Array[Color] = [RING_GUN_COLOR, RING_TORPEDO_COLOR, RING_PLANE_COLOR]
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
	var half_w: float = stats.hull_width * 0.5
	var alpha: float = 1.0
	if under_construction:
		alpha = 0.45
	elif stats.is_submarine and reveal_timer <= 0.0:
		alpha = 0.7
	var fill: Color = Color(color.r * 0.75, color.g * 0.75, color.b * 0.75, alpha)
	var outline: Color = Color(color.r, color.g, color.b, alpha)
	var hull: PackedVector2Array = PackedVector2Array()
	if stats.has_planes():
		hull = PackedVector2Array([Vector2(half_l, -half_w * 0.6), Vector2(half_l, half_w * 0.6),
			Vector2(half_l * 0.7, half_w), Vector2(-half_l, half_w), Vector2(-half_l, -half_w),
			Vector2(half_l * 0.7, -half_w)])
	elif stats.is_submarine:
		hull = PackedVector2Array([Vector2(half_l, 0.0), Vector2(half_l * 0.6, half_w),
			Vector2(-half_l * 0.7, half_w), Vector2(-half_l, 0.0), Vector2(-half_l * 0.7, -half_w),
			Vector2(half_l * 0.6, -half_w)])
	else:
		hull = PackedVector2Array([Vector2(half_l, 0.0), Vector2(half_l * 0.45, half_w),
			Vector2(-half_l, half_w * 0.8), Vector2(-half_l, -half_w * 0.8),
			Vector2(half_l * 0.45, -half_w)])
	draw_colored_polygon(hull, fill)
	var closed: PackedVector2Array = hull.duplicate()
	closed.append(hull[0])
	draw_polyline(closed, outline, 1.5)
	if stats.has_planes():
		draw_line(Vector2(-half_l * 0.85, 0.0), Vector2(half_l * 0.85, 0.0), Color(1, 1, 1, 0.6 * alpha), 1.5)
	elif stats.is_submarine:
		draw_circle(Vector2(half_l * 0.1, 0.0), half_w * 0.55, outline)
	for i: int in stats.gun_mounts:
		draw_circle(Vector2(stats.mount_offsets[i], 0.0), maxf(2.0, half_w * 0.42), Color(0.92, 0.94, 0.96, alpha))
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
