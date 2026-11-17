class_name Projectile
extends Node2D
## Base for shells, torpedoes and plane squadrons. Projectiles are simulated by
## swept raycasts each physics tick rather than physics bodies.

const VISIBILITY_INTERVAL: int = 6

var team: int = 0
var damage: float = 0.0
var speed: float = 300.0
var direction: Vector2 = Vector2.RIGHT
var max_distance: float = 1000.0
var traveled: float = 0.0
var ignore_armor: bool = false
var from_submarine: bool = false
var match_ref: Match = null
var _frame: int = 0


func launch(p_match: Match, p_team: int, origin: Vector2, angle: float, p_damage: float,
		p_speed: float, p_max_distance: float) -> void:
	match_ref = p_match
	team = p_team
	position = origin
	direction = Vector2.from_angle(angle)
	rotation = angle
	damage = p_damage
	speed = p_speed
	max_distance = p_max_distance


## Advances along `direction`, resolving island and hull collisions. Returns false once spent.
func _advance_ballistic(delta: float) -> bool:
	var step: float = speed * delta
	var next: Vector2 = position + direction * step
	var hit: Dictionary = match_ref.cast_projectile(position, next, team)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var point: Vector2 = hit["position"]
		var struck: Combatant = collider as Combatant
		if collider is Island:
			# The shore of an enemy-held island: the hit lands on its garrison.
			var fort: IslandGarrison = (collider as Island).garrison
			if fort != null and fort.is_alive() and fort.team != team:
				struck = fort
		if struck != null:
			struck.apply_damage(damage, ignore_armor, from_submarine)
			match_ref.spawn_effect(point, Effect.Kind.HIT)
		else:
			match_ref.spawn_effect(point, Effect.Kind.SPLASH)
		queue_free()
		return false
	position = next
	traveled += step
	if traveled >= max_distance:
		match_ref.spawn_effect(position, Effect.Kind.SPLASH)
		queue_free()
		return false
	return true


func _update_fog_visibility() -> void:
	_frame += 1
	if _frame % VISIBILITY_INTERVAL == 1:
		visible = match_ref.is_point_visible_to_local(position, team)
