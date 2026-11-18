class_name Effect
extends Node2D
## Short-lived visual flash (shell splash, hit, bomb, explosion, flak). Purely cosmetic:
## the scatter of sparks, debris and smoke puffs comes from a hash of the position, so it
## needs no random number generator and never touches the simulation.

enum Kind { SPLASH, HIT, BOMB, EXPLOSION, DEPTH_CHARGE, FLAK, TORPEDO_HIT }

## The sound each kind of effect makes (`Sfx`).
const SOUNDS: Dictionary[Kind, String] = {
	Kind.SPLASH: "splash", Kind.HIT: "hit", Kind.BOMB: "bomb", Kind.EXPLOSION: "explosion",
	Kind.DEPTH_CHARGE: "depth_charge", Kind.FLAK: "flak", Kind.TORPEDO_HIT: "torpedo_hit",
}

const SMOKE: Color = Color(0.18, 0.18, 0.19)
const FLAK_SMOKE: Color = Color(0.12, 0.12, 0.13)

var kind: Kind = Kind.SPLASH
var life: float = 0.35
var _age: float = 0.0
var _seed: int = 0


func setup(p_kind: Kind, p_position: Vector2) -> void:
	kind = p_kind
	position = p_position
	_seed = hash(Vector2i(roundi(p_position.x), roundi(p_position.y))) & 0xffff
	z_index = 4
	match kind:
		Kind.SPLASH:
			life = 0.6
		Kind.HIT:
			life = 0.55
		Kind.BOMB:
			life = 0.9
		Kind.EXPLOSION:
			life = 1.8
		Kind.DEPTH_CHARGE:
			life = 0.9
		Kind.FLAK:
			life = 1.3
		Kind.TORPEDO_HIT:
			life = 1.2


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	queue_redraw()


## Pseudo-random 0-1 value for scatter element `i` (stable for this effect).
func _r(i: int) -> float:
	return float(hash(_seed * 131 + i * 7919) & 0xffff) / 65535.0


func _draw() -> void:
	var t: float = clampf(_age / life, 0.0, 1.0)
	match kind:
		Kind.SPLASH:
			_draw_splash(t, 1.0)
		Kind.HIT:
			_draw_fireball(t, 7.0, 6)
		Kind.BOMB:
			_draw_fireball(t, 16.0, 9)
			_draw_splash(t, 1.6)
		Kind.DEPTH_CHARGE:
			draw_circle(Vector2.ZERO, 6.0 + 16.0 * t, Color(0.9, 0.97, 1.0, 0.7 * (1.0 - t)))
			draw_arc(Vector2.ZERO, 10.0 + 30.0 * t, 0.0, TAU, 24, Color(0.75, 0.9, 1.0, 1.0 - t), 2.0)
			draw_arc(Vector2.ZERO, 4.0 + 18.0 * t, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - t)), 1.5)
		Kind.EXPLOSION:
			_draw_explosion(t)
		Kind.FLAK:
			_draw_flak(t)
		Kind.TORPEDO_HIT:
			_draw_splash(t, 2.6)
			_draw_fireball(t, 11.0, 7)
			draw_arc(Vector2.ZERO, 8.0 + 26.0 * t, 0.0, TAU, 24, Color(0.85, 0.95, 1.0, 0.8 * (1.0 - t)), 2.0)


## White water thrown up by a shell: a spreading foam ring and a few droplets.
func _draw_splash(t: float, scale_by: float) -> void:
	var fade: float = 1.0 - t
	draw_circle(Vector2.ZERO, (2.0 + 4.0 * (1.0 - absf(t - 0.25) * 2.0)) * scale_by,
		Color(0.92, 0.97, 1.0, 0.75 * fade))
	draw_arc(Vector2.ZERO, (3.0 + 11.0 * t) * scale_by, 0.0, TAU, 18, Color(0.85, 0.95, 1.0, 0.8 * fade), 1.4)
	for i: int in 5:
		var dir: Vector2 = Vector2.from_angle(_r(i) * TAU)
		draw_circle(dir * (2.0 + 9.0 * t * (0.6 + _r(i + 20))) * scale_by, 1.1, Color(1.0, 1.0, 1.0, fade))


## A shell or bomb strike: flash, flying sparks and a puff of smoke.
func _draw_fireball(t: float, size: float, sparks: int) -> void:
	var fade: float = 1.0 - t
	var smoke_r: float = size * (0.5 + 1.1 * t)
	draw_circle(Vector2(2.0, -3.0) * t * size * 0.3, smoke_r, Color(SMOKE, 0.45 * fade))
	if t < 0.5:
		var f: float = 1.0 - t * 2.0
		draw_circle(Vector2.ZERO, size * (0.5 + 0.5 * t), Color(1.0, 0.55, 0.15, 0.85 * f))
		draw_circle(Vector2.ZERO, size * 0.35, Color(1.0, 0.92, 0.6, f))
	for i: int in sparks:
		var dir: Vector2 = Vector2.from_angle(_r(i) * TAU)
		var reach: float = size * (0.6 + 1.6 * t) * (0.6 + 0.6 * _r(i + 40))
		draw_line(dir * reach * 0.6, dir * reach, Color(1.0, 0.8, 0.4, fade), 1.2)


## A ship blowing up: a big fireball, a shock ring, flung debris and a rolling smoke cloud.
func _draw_explosion(t: float) -> void:
	var fade: float = 1.0 - t
	for i: int in 7:
		var dir: Vector2 = Vector2.from_angle(_r(i + 100) * TAU)
		var drift: Vector2 = dir * (8.0 + 26.0 * t) * (0.5 + _r(i + 120)) + Vector2(10.0, -6.0) * t
		draw_circle(drift, 8.0 + 16.0 * t * (0.6 + _r(i + 140)), Color(SMOKE, 0.55 * fade))
	if t < 0.22:
		var s: float = t / 0.22
		draw_circle(Vector2.ZERO, 14.0 + 30.0 * s, Color(1.0, 0.95, 0.8, 0.9 * (1.0 - s)))
	if t < 0.6:
		var f: float = 1.0 - t / 0.6
		for i: int in 5:
			var off: Vector2 = Vector2.from_angle(_r(i + 60) * TAU) * 10.0 * _r(i + 80) * (0.5 + t)
			draw_circle(off, (9.0 + 16.0 * t) * (0.7 + 0.5 * _r(i + 90)), Color(1.0, 0.45 + 0.3 * f, 0.1, 0.9 * f))
		draw_circle(Vector2.ZERO, 8.0 * f + 3.0, Color(1.0, 0.9, 0.55, f))
	draw_arc(Vector2.ZERO, 16.0 + 80.0 * t, 0.0, TAU, 36, Color(1.0, 0.92, 0.8, 0.8 * fade * fade), 2.0)
	for i: int in 10:
		var dir: Vector2 = Vector2.from_angle(_r(i) * TAU)
		var reach: float = (10.0 + 60.0 * t) * (0.5 + 0.7 * _r(i + 30))
		draw_rect(Rect2(dir * reach - Vector2(1.2, 1.2), Vector2(2.4, 2.4)), Color(0.2, 0.17, 0.15, fade))
		if t < 0.5:
			draw_line(dir * reach * 0.7, dir * reach, Color(1.0, 0.7, 0.3, 1.0 - t * 2.0), 1.5)


## Anti-aircraft fire: a cluster of black flak bursts, each with a brief flash.
func _draw_flak(t: float) -> void:
	for i: int in 5:
		var start: float = _r(i + 200) * 0.45
		var local: float = (t - start) / maxf(0.01, 1.0 - start)
		if local <= 0.0:
			continue
		var at: Vector2 = Vector2.from_angle(_r(i) * TAU) * 22.0 * _r(i + 10)
		draw_circle(at, 3.0 + 6.0 * local, Color(FLAK_SMOKE, 0.75 * (1.0 - local)))
		if local < 0.2:
			draw_circle(at, 3.0, Color(1.0, 0.85, 0.45, 1.0 - local * 5.0))
