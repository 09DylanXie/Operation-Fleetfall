class_name PlaneSquadron
extends Projectile
## One squadron of an air wing. Its `home` is the carrier (or island air base) that launched
## it, and it lands there again. Planes fly over islands and land; a ship with anti-air may
## shoot a squadron down.
##
## Roles:
##   DIVE     HE dive bombers: fly to the home's air target, circle overhead and drop an
##            armor-ignoring HE bomb every `bomb_interval` seconds until the strike ends.
##   TORPEDO  Torpedo bombers: fly at one capital ship (`mission_target`), drop two parallel
##            torpedoes from just off its broadside, aimed across its beam, then fly home.
##   DEPTH    Depth-charge bombers: fly over one spotted submarine, drop a depth charge
##            (armor-ignoring) and fly home.

enum Role { DIVE, TORPEDO, DEPTH }

const ORBIT_RADIUS: float = 60.0
## Speed while circling a target or lining up to land, as a fraction of cruise speed.
const LOITER_SPEED_FACTOR: float = 0.6
const LOITER_DISTANCE: float = 220.0
const LAND_RADIUS: float = 70.0
## Torpedo bombers release this far out from the target's side (about half an inch on screen
## at the default zoom).
const TORPEDO_DROP_DISTANCE: float = 70.0
## The two torpedoes run this far apart, side by side.
const TORPEDO_PAIR_SPACING: float = 14.0
const DROP_TOLERANCE: float = 32.0
## A bomber that keeps missing its release point drops anyway after this long close by.
const DROP_TIMEOUT: float = 4.0

var home: Combatant = null
var role: Role = Role.DIVE
## Dive bombers from a carrier: the target this squadron works (each squadron has its own;
## the carrier hands it a new one the moment it sinks or is lost).
var dive_target: Combatant = null
## Torpedo and depth-charge bombers: the one target this flight was sent at.
var mission_target: Combatant = null
var payload_dropped: bool = false
var turn_rate: float = 2.6
var bomb_interval: float = 3.0
var bombs_dropped: int = 0
## Damage of one depth charge (depth-charge bombers).
var depth_charge_damage: float = 100.0
var _bomb_cd: float = 0.0
var _move_speed: float = -1.0
var _near_time: float = 0.0


func _ready() -> void:
	ignore_armor = true


func _physics_process(delta: float) -> void:
	if match_ref.is_over or match_ref.replica:
		return
	if home == null or not home.is_alive() or home.team != team:
		# Nowhere left to land: the flight is lost with its carrier or air base.
		match_ref.spawn_effect(position, Effect.Kind.SPLASH)
		if home != null:
			home.squadron_gone(self, true)
		queue_free()
		return
	_bomb_cd = maxf(0.0, _bomb_cd - delta)
	match role:
		Role.DIVE:
			var target: Combatant = home.dive_target_for(self)
			if target != null:
				_work_target(target, delta)
			else:
				_return_home(delta)
		Role.TORPEDO, Role.DEPTH:
			if payload_dropped or not _mission_valid():
				_return_home(delta)
			else:
				_fly_mission(delta)
	_update_fog_visibility()


func _work_target(target: Combatant, delta: float) -> void:
	var seen: bool = target.spotted_by[team]
	var center: Vector2 = target.position
	if not seen and not target.is_structure():
		center = target.last_known_position[team]
	var to_center: Vector2 = center - position
	var dist: float = to_center.length()
	var orbit: float = ORBIT_RADIUS + target.hit_radius() * 0.5
	if dist > orbit * 1.8:
		_steer(to_center, speed, delta)
		return
	# On station: circle the target, easing in or out toward the orbit radius.
	var radial: Vector2 = to_center / maxf(dist, 0.001)
	var tangent: Vector2 = radial.orthogonal()
	if tangent.dot(direction) < 0.0:
		tangent = -tangent
	var pull: float = clampf((dist - orbit) / orbit, -1.0, 1.0)
	_steer(tangent + radial * pull, speed * LOITER_SPEED_FACTOR, delta)
	if seen and _bomb_cd <= 0.0:
		_bomb(target)


## A one-shot flight keeps going while its target lives, stays in sight (submarines) and
## stays inside the home's reach.
func _mission_valid() -> bool:
	var target: Combatant = mission_target
	if target == null or not target.is_alive() or not target.is_enemy_of(team):
		return false
	if role == Role.DEPTH and not target.spotted_by[team]:
		return false
	return home.position.distance_to(target.position) <= home.air_reach()


func _fly_mission(delta: float) -> void:
	var target: Combatant = mission_target
	var aim: Vector2 = target.position if target.spotted_by[team] else target.last_known_position[team]
	if role == Role.TORPEDO:
		aim = _torpedo_release_point(target)
	var to_aim: Vector2 = aim - position
	var dist: float = to_aim.length()
	_steer(to_aim, speed, delta)
	if dist < DROP_TOLERANCE * 4.0:
		_near_time += delta
	if not target.spotted_by[team]:
		return
	if dist <= DROP_TOLERANCE or _near_time >= DROP_TIMEOUT:
		if role == Role.TORPEDO:
			_drop_torpedoes(target)
		else:
			_drop_depth_charge(target)


## Just off the target's side nearer to this flight, led for the target's motion.
func _torpedo_release_point(target: Combatant) -> Vector2:
	var beam: Vector2 = Vector2.from_angle(target.rotation).orthogonal()
	if beam.dot(position - target.position) < 0.0:
		beam = -beam
	var half_beam: float = target.hit_radius() * 0.25
	var ship: Ship = target as Ship
	if ship != null:
		half_beam = ship.stats.hull_width * 0.5
	var run: float = TORPEDO_DROP_DISTANCE + half_beam
	var lead: Vector2 = target.velocity * run / maxf(1.0, GameData.torpedo_speed())
	return target.position + lead + beam * run


func _drop_torpedoes(target: Combatant) -> void:
	payload_dropped = true
	var beam: Vector2 = Vector2.from_angle(target.rotation).orthogonal()
	if beam.dot(position - target.position) < 0.0:
		beam = -beam
	var axis: Vector2 = Vector2.from_angle(target.rotation)
	var heading: float = (-beam).angle()
	var travel: float = TORPEDO_DROP_DISTANCE * 3.0 + target.hit_radius()
	for side: float in [-0.5, 0.5]:
		match_ref.spawn_air_torpedo(team, position + axis * TORPEDO_PAIR_SPACING * side, heading, travel)
	bombs_dropped += 1
	target.register_attacker(home, 8.0)
	_anti_air(target)


func _drop_depth_charge(target: Combatant) -> void:
	payload_dropped = true
	bombs_dropped += 1
	match_ref.spawn_effect(target.position, Effect.Kind.DEPTH_CHARGE)
	target.register_attacker(home, 4.0)
	target.apply_damage(depth_charge_damage, true, false)


func _return_home(delta: float) -> void:
	var to_home: Vector2 = home.position - position
	var dist: float = to_home.length()
	if dist <= LAND_RADIUS:
		home.squadron_gone(self, false)
		queue_free()
		return
	_steer(to_home, speed if dist > LOITER_DISTANCE else speed * LOITER_SPEED_FACTOR, delta)


func _steer(desired: Vector2, move_speed: float, delta: float) -> void:
	var diff: float = angle_difference(direction.angle(), desired.angle())
	var max_turn: float = turn_rate * delta
	var angle: float = direction.angle() + clampf(diff, -max_turn, max_turn)
	direction = Vector2.from_angle(angle)
	rotation = angle
	_move_speed = move_speed
	var step: float = move_speed * delta
	position += direction * step
	traveled += step


func _bomb(target: Combatant) -> void:
	_bomb_cd = bomb_interval
	bombs_dropped += 1
	target.apply_damage(damage, true, false)
	target.register_attacker(home, bomb_interval + 1.0)
	match_ref.spawn_effect(target.position, Effect.Kind.BOMB)
	_anti_air(target)


## Anti-air answers every attack run: the squadron may not come out of it.
func _anti_air(target: Combatant) -> void:
	var aa: float = target.aa_kill_chance()
	if aa > 0.0 and target.is_alive() and match_ref.rng.randf() < aa:
		match_ref.spawn_effect(position, Effect.Kind.HIT)
		home.squadron_gone(self, true)
		queue_free()


## Shot down by anti-air outside a bomb run (Super Battleship barrage).
func shoot_down() -> void:
	if is_queued_for_deletion():
		return
	match_ref.spawn_effect(position, Effect.Kind.HIT)
	if home != null and is_instance_valid(home):
		home.squadron_gone(self, true)
	queue_free()


func net_speed() -> float:
	return _move_speed if _move_speed >= 0.0 else speed


func _draw() -> void:
	var color: Color = Ship.TEAM_COLORS[team].lightened(0.35)
	match role:
		Role.DIVE:
			for offset: Vector2 in [Vector2(6.0, 0.0), Vector2(-5.0, -7.0), Vector2(-5.0, 7.0)]:
				draw_colored_polygon(PackedVector2Array([offset + Vector2(6.0, 0.0),
					offset + Vector2(-4.0, 4.0), offset + Vector2(-4.0, -4.0)]), color)
		Role.TORPEDO:
			# Two heavier planes, each with a torpedo slung underneath until it is dropped.
			for offset: Vector2 in [Vector2(0.0, -6.0), Vector2(0.0, 6.0)]:
				draw_line(offset + Vector2(-6.0, 0.0), offset + Vector2(7.0, 0.0), color, 2.5)
				draw_line(offset + Vector2(1.0, -6.0), offset + Vector2(1.0, 6.0), color, 2.0)
				draw_line(offset + Vector2(-6.0, -2.5), offset + Vector2(-6.0, 2.5), color, 1.5)
				if not payload_dropped:
					draw_line(offset + Vector2(-2.0, 1.5), offset + Vector2(5.0, 1.5), Color(0.25, 0.27, 0.28), 1.5)
		Role.DEPTH:
			for offset: Vector2 in [Vector2(0.0, -5.0), Vector2(0.0, 5.0)]:
				draw_line(offset + Vector2(-5.0, 0.0), offset + Vector2(6.0, 0.0), color.darkened(0.15), 2.0)
				draw_line(offset + Vector2(1.0, -5.0), offset + Vector2(1.0, 5.0), color.darkened(0.15), 1.8)
				if not payload_dropped:
					draw_circle(offset + Vector2(0.0, 0.0), 1.6, Color(0.15, 0.15, 0.16))
