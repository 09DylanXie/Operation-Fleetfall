class_name PlaneSquadron
extends Projectile
## One squadron of a carrier's air wing. It flies to its carrier's air target, circles
## overhead and drops an armor-ignoring HE bomb every `bomb_interval` seconds. It keeps
## following the carrier's orders while airborne and lands when the strike ends.
## Planes fly over islands and land; a ship with anti-air may shoot the squadron down.

const ORBIT_RADIUS: float = 60.0
## Speed while circling a target or lining up to land, as a fraction of cruise speed.
const LOITER_SPEED_FACTOR: float = 0.6
const LOITER_DISTANCE: float = 220.0
const LAND_RADIUS: float = 70.0

var carrier: Ship = null
var turn_rate: float = 2.6
var bomb_interval: float = 3.0
var bombs_dropped: int = 0
var _bomb_cd: float = 0.0


func _ready() -> void:
	ignore_armor = true


func _physics_process(delta: float) -> void:
	if match_ref.is_over:
		return
	if carrier == null or not carrier.is_alive():
		# Nowhere left to land: the air wing is lost with its carrier.
		match_ref.spawn_effect(position, Effect.Kind.SPLASH)
		queue_free()
		return
	_bomb_cd = maxf(0.0, _bomb_cd - delta)
	if carrier.strike_active():
		_work_target(carrier.air_target(), delta)
	else:
		_return_to_carrier(delta)
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


func _return_to_carrier(delta: float) -> void:
	var to_carrier: Vector2 = carrier.position - position
	var dist: float = to_carrier.length()
	if dist <= LAND_RADIUS:
		carrier.squadron_gone(self, false)
		queue_free()
		return
	_steer(to_carrier, speed if dist > LOITER_DISTANCE else speed * LOITER_SPEED_FACTOR, delta)


func _steer(desired: Vector2, move_speed: float, delta: float) -> void:
	var diff: float = angle_difference(direction.angle(), desired.angle())
	var max_turn: float = turn_rate * delta
	var angle: float = direction.angle() + clampf(diff, -max_turn, max_turn)
	direction = Vector2.from_angle(angle)
	rotation = angle
	var step: float = move_speed * delta
	position += direction * step
	traveled += step


func _bomb(target: Combatant) -> void:
	_bomb_cd = bomb_interval
	bombs_dropped += 1
	target.apply_damage(damage, true, false)
	target.register_attacker(carrier, bomb_interval + 1.0)
	match_ref.spawn_effect(target.position, Effect.Kind.BOMB)
	# Anti-air answers every bomb run: the squadron may not come out of it.
	var aa: float = target.aa_kill_chance()
	if aa > 0.0 and target.is_alive() and match_ref.rng.randf() < aa:
		match_ref.spawn_effect(position, Effect.Kind.HIT)
		carrier.squadron_gone(self, true)
		queue_free()


func _draw() -> void:
	var color: Color = Ship.TEAM_COLORS[team].lightened(0.35)
	for offset: Vector2 in [Vector2(6.0, 0.0), Vector2(-5.0, -7.0), Vector2(-5.0, 7.0)]:
		draw_colored_polygon(PackedVector2Array([offset + Vector2(6.0, 0.0),
			offset + Vector2(-4.0, 4.0), offset + Vector2(-4.0, -4.0)]), color)
