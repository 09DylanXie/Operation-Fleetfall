class_name Effect
extends Node2D
## Short-lived visual flash (shell splash, hit, bomb, explosion). Purely cosmetic.

enum Kind { SPLASH, HIT, BOMB, EXPLOSION, DEPTH_CHARGE }

var kind: Kind = Kind.SPLASH
var life: float = 0.35
var _age: float = 0.0


func setup(p_kind: Kind, p_position: Vector2) -> void:
	kind = p_kind
	position = p_position
	match kind:
		Kind.SPLASH:
			life = 0.35
		Kind.HIT:
			life = 0.3
		Kind.BOMB:
			life = 0.5
		Kind.EXPLOSION:
			life = 0.9
		Kind.DEPTH_CHARGE:
			life = 0.7


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_age / life, 0.0, 1.0)
	match kind:
		Kind.SPLASH:
			draw_arc(Vector2.ZERO, 3.0 + 9.0 * t, 0.0, TAU, 16, Color(0.85, 0.95, 1.0, 1.0 - t), 1.5)
		Kind.HIT:
			draw_circle(Vector2.ZERO, 3.0 + 7.0 * t, Color(1.0, 0.75, 0.3, 1.0 - t))
		Kind.BOMB:
			draw_circle(Vector2.ZERO, 8.0 + 22.0 * t, Color(1.0, 0.55, 0.2, 0.8 * (1.0 - t)))
		Kind.DEPTH_CHARGE:
			draw_circle(Vector2.ZERO, 6.0 + 16.0 * t, Color(0.9, 0.97, 1.0, 0.7 * (1.0 - t)))
			draw_arc(Vector2.ZERO, 10.0 + 30.0 * t, 0.0, TAU, 24, Color(0.75, 0.9, 1.0, 1.0 - t), 2.0)
			draw_arc(Vector2.ZERO, 4.0 + 18.0 * t, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - t)), 1.5)
		Kind.EXPLOSION:
			draw_circle(Vector2.ZERO, 10.0 + 40.0 * t, Color(1.0, 0.6, 0.25, 0.75 * (1.0 - t)))
			draw_arc(Vector2.ZERO, 14.0 + 55.0 * t, 0.0, TAU, 28, Color(1.0, 0.9, 0.7, 1.0 - t), 2.0)
