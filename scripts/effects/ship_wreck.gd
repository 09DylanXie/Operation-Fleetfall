class_name ShipWreck
extends Node2D
## A sinking hull left behind when a cruiser or larger ship is destroyed. Purely cosmetic:
## secondary blasts in the first moments, then the hull lists, darkens and slips under,
## leaving an oil slick and rising bubbles. Destroyers and submarines only explode.

const SINK_TIME: float = 7.0

var stats: ShipStats = null
var team_color: Color = Color.WHITE
var team: int = 0
var turret_angles: PackedFloat32Array = PackedFloat32Array()
var secondary_angles: PackedFloat32Array = PackedFloat32Array()
var _age: float = 0.0
var _seed: int = 0
var _list_side: float = 1.0


## Only ships of cruiser size and up sink; smaller hulls just blow apart.
static func sinks(ship_stats: ShipStats) -> bool:
	return ship_stats.ship_class != ShipStats.ShipClass.DD and ship_stats.ship_class != ShipStats.ShipClass.SS \
		and not ship_stats.is_support()


func setup(ship: Ship) -> void:
	stats = ship.stats
	team = ship.team
	team_color = Ship.TEAM_COLORS[ship.team]
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	position = ship.position
	rotation = ship.rotation
	turret_angles = ship.turret_angles.duplicate()
	secondary_angles = ship.secondary_angles.duplicate()
	_seed = ship.net_id
	_list_side = 1.0 if (_seed & 1) == 0 else -1.0
	z_index = -1


func _process(delta: float) -> void:
	_age += delta
	if _age >= SINK_TIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if stats == null:
		return
	var t: float = clampf(_age / SINK_TIME, 0.0, 1.0)
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	# Oil slick spreading under the hull.
	var slick: float = clampf(t * 1.6, 0.0, 1.0)
	draw_set_transform(Vector2(-hl * 0.1, 0.0), 0.0, Vector2(1.0, 0.45 + 0.4 * slick))
	draw_circle(Vector2.ZERO, hl * (0.6 + 0.6 * slick), Color(0.02, 0.03, 0.04, 0.45 * (1.0 - t * 0.6)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The hull lists toward one side, settles and fades under the surface.
	var sink: float = smoothstep(0.15, 1.0, t)
	var darken: float = 1.0 - 0.55 * sink
	var tint: Color = Color(darken * 0.85, darken * 0.9, darken, 1.0 - sink)
	var squash: float = 1.0 - 0.45 * sink
	var origin: Transform2D = Transform2D(0.0, Vector2(1.0 - 0.12 * sink, squash), 0.0,
		Vector2(-hl * 0.08 * sink, _list_side * hw * 0.5 * sink))
	var tex: Texture2D = ShipArt.baked.get(ShipArt.sprite_key(stats.ship_class, ShipArt.SPRITE_BODY, team))
	if tex != null:
		draw_set_transform_matrix(origin)
		var size: Vector2 = tex.get_size() / ShipArt.BAKE_SCALE
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false, tint)
		ShipArt.draw_guns(self, stats, tint, turret_angles, secondary_angles, origin)
	else:
		ShipArt.draw(self, stats, team_color, tint, turret_angles, secondary_angles, 0.0, origin)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fires keep burning until the water reaches them.
	ShipArt.draw_fires(self, stats, 0.9, _age, rotation, _seed, clampf(1.0 - sink * 1.3, 0.0, 1.0))
	# Magazine and boiler explosions in the first two seconds.
	for i: int in 4:
		var start: float = 0.04 + float(i) * 0.07
		var local: float = (t - start) / 0.08
		if local <= 0.0 or local >= 1.0:
			continue
		var at: Vector2 = Vector2((_r(i) * 1.4 - 0.7) * hl, (_r(i + 9) - 0.5) * hw)
		draw_circle(at, hw * (0.5 + 1.2 * local), Color(1.0, 0.55, 0.15, 0.85 * (1.0 - local)))
		draw_circle(at, hw * 0.6 * (1.0 - local), Color(1.0, 0.92, 0.6, 1.0 - local))
	# Foam where the hull goes down, then bubbles.
	if sink > 0.0:
		draw_arc(Vector2.ZERO, hl * (0.7 + 0.3 * sink), 0.0, TAU, 32, Color(0.85, 0.93, 1.0, 0.35 * sink * (1.0 - t)), 1.5)
		for i: int in 8:
			var phase: float = fmod(_age * 0.9 + _r(i + 20), 1.0)
			var at: Vector2 = Vector2((_r(i + 30) * 1.6 - 0.8) * hl, (_r(i + 40) - 0.5) * hw * 1.6)
			draw_arc(at, 0.8 + 2.5 * phase, 0.0, TAU, 10, Color(0.9, 0.96, 1.0, 0.6 * (1.0 - phase) * sink), 0.8)


func _r(i: int) -> float:
	return float(hash(_seed * 131 + i * 7919) & 0xffff) / 65535.0
