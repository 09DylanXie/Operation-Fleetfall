class_name Torpedo
extends Projectile
## Straight-running torpedo. Submarine torpedoes home on their target for the
## first `homing_time_left` seconds (the "homing ping"), then lock their course.

var homing_target: Combatant = null
var homing_time_left: float = 0.0
var homing_turn_rate: float = 1.0


func _physics_process(delta: float) -> void:
	if match_ref.is_over or match_ref.replica:
		return
	if homing_time_left > 0.0:
		homing_time_left -= delta
		if homing_target != null and homing_target.is_alive():
			var desired: float = (homing_target.position - position).angle()
			var diff: float = angle_difference(direction.angle(), desired)
			var max_turn: float = homing_turn_rate * delta
			var angle: float = direction.angle() + clampf(diff, -max_turn, max_turn)
			direction = Vector2.from_angle(angle)
			rotation = angle
	if _advance_ballistic(delta):
		_update_fog_visibility()


func is_homing() -> bool:
	return homing_time_left > 0.0


func _draw() -> void:
	draw_line(Vector2(-26.0, 0.0), Vector2(-8.0, 0.0), Color(1, 1, 1, 0.35), 2.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(4.0, 0.0), Color(0.75, 0.95, 1.0), 3.0)
