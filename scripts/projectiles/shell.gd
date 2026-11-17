class_name Shell
extends Projectile
## Artillery: straight line, no homing, stopped by islands. One Shell node carries
## every shell fired by a single gun mount.

var shell_count: int = 1


func _physics_process(delta: float) -> void:
	if match_ref.is_over:
		return
	if _advance_ballistic(delta):
		_update_fog_visibility()


func _draw() -> void:
	var color: Color = Color(1.0, 0.92, 0.6)
	for i: int in shell_count:
		var y: float = (float(i) - float(shell_count - 1) * 0.5) * 3.0
		draw_line(Vector2(-7.0, y), Vector2(0.0, y), color, 1.5)
