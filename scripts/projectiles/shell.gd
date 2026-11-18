class_name Shell
extends Projectile
## Artillery: straight line, no homing, stopped by islands. One Shell node carries
## every shell fired by a single gun mount.

var shell_count: int = 1
## Cosmetic: how long this shell has been drawn (its tracer grows to full length, then holds).
var _tracer_age: float = 0.0

const TRACER_TIME: float = 0.09
const SHELL_COLOR: Color = Color(0.8, 0.82, 0.85)
const TRACER_COLOR: Color = Color(0.9, 0.91, 0.93)


func _physics_process(delta: float) -> void:
	if match_ref.is_over or match_ref.replica:
		return
	if _advance_ballistic(delta):
		_update_fog_visibility()


func _process(delta: float) -> void:
	if _tracer_age < TRACER_TIME:
		_tracer_age += delta
		queue_redraw()


## Grey armour-piercing shells, each trailing a thin tracer that fades out behind it
## (about a tenth of a second of flight).
func _draw() -> void:
	var tail: float = speed * minf(_tracer_age, TRACER_TIME)
	for i: int in shell_count:
		var y: float = (float(i) - float(shell_count - 1) * 0.5) * 3.0
		if tail > 4.0:
			draw_polyline_colors(PackedVector2Array([Vector2(-tail, y), Vector2(-tail * 0.5, y), Vector2(-3.0, y)]),
				PackedColorArray([Color(TRACER_COLOR, 0.0), Color(TRACER_COLOR, 0.18), Color(TRACER_COLOR, 0.55)]), 1.0)
		draw_line(Vector2(-3.5, y), Vector2(0.0, y), SHELL_COLOR, 2.0)
		draw_circle(Vector2(0.0, y), 1.0, Color(0.92, 0.93, 0.95))
