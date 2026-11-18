class_name IslandTerrain
extends Node2D
## The look of an island, drawn once (it never changes): Pacific-campaign style reefs,
## beaches and jungle. Major islands carry an airfield (runway, hangars, revetments, fuel
## tanks, AA pits), Minor islands a small outpost (huts, radio mast, gun pits), and cover
## islands are jungle atolls or volcanic peaks. Sits behind its Island, whose own drawing
## (dock, capture ring, flag) goes on top. Cosmetic only; layout comes from a seeded RNG.

const REEF: Color = Color(0.2, 0.55, 0.58, 0.55)
const SURF: Color = Color(0.85, 0.95, 0.97, 0.55)
const SAND: Color = Color(0.83, 0.76, 0.56)
const WET_SAND: Color = Color(0.66, 0.6, 0.44)
const JUNGLE: Color = Color(0.16, 0.33, 0.17)
const JUNGLE_DARK: Color = Color(0.1, 0.24, 0.12)
const CANOPY: Array[Color] = [Color(0.2, 0.4, 0.19), Color(0.25, 0.46, 0.22), Color(0.14, 0.3, 0.15),
	Color(0.3, 0.5, 0.24)]
const DIRT: Color = Color(0.55, 0.47, 0.33)
const RUNWAY: Color = Color(0.27, 0.27, 0.26)
const CONCRETE: Color = Color(0.56, 0.56, 0.53)
const ROOF: Color = Color(0.36, 0.4, 0.33)
const HUT: Color = Color(0.48, 0.36, 0.22)
const ROCK: Color = Color(0.4, 0.37, 0.33)
const MARK: Color = Color(0.92, 0.92, 0.88)

var kind: int = 0
var radius: float = 100.0
var shallow_radius: float = 0.0
var polygon: PackedVector2Array = PackedVector2Array()
var _seed: int = 0
## The terrain is rendered once into this texture (thousands of trees and huts become one
## textured quad); null until the bake finishes, and vector drawing is used meanwhile.
var _texture: Texture2D = null
var _texture_rect: Rect2 = Rect2()
## True for the throwaway copy that draws into the bake viewport.
var _bake_copy: bool = false

const BAKE_SCALE: float = 3.0


func setup(p_kind: int, p_radius: float, p_shallow: float, p_polygon: PackedVector2Array, world_pos: Vector2) -> void:
	kind = p_kind
	radius = p_radius
	shallow_radius = p_shallow
	polygon = p_polygon
	_seed = hash(Vector2i(roundi(world_pos.x), roundi(world_pos.y)))
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	if not _bake_copy and ShipArtCache.can_bake():
		_bake.call_deferred()


func _bake() -> void:
	var reach: float = 4.0
	for p: Vector2 in polygon:
		reach = maxf(reach, p.length())
	reach += 26.0
	var vp: SubViewport = SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size = Vector2i(ceili(reach * 2.0 * BAKE_SCALE), ceili(reach * 2.0 * BAKE_SCALE))
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var copy: IslandTerrain = IslandTerrain.new()
	copy._bake_copy = true
	copy.kind = kind
	copy.radius = radius
	copy.polygon = polygon
	copy._seed = _seed
	copy.position = Vector2(vp.size) * 0.5
	copy.scale = Vector2(BAKE_SCALE, BAKE_SCALE)
	vp.add_child(copy)
	add_child(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = vp.get_texture().get_image()
	vp.queue_free()
	if image == null or image.is_empty():
		return
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	_texture_rect = Rect2(-Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	queue_redraw()


func _draw() -> void:
	if polygon.size() < 3:
		return
	if kind == MapData.KIND_MINOR and shallow_radius > 0.0 and not _bake_copy:
		_draw_lagoon()
	if _texture != null:
		draw_texture_rect(_texture, _texture_rect, false)
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	# Fringing reef and its line of surf.
	var reef: PackedVector2Array = _grow(polygon, 1.0, 18.0)
	draw_colored_polygon(reef, REEF)
	_ring(reef, SURF, 1.5)
	draw_colored_polygon(_grow(polygon, 1.0, 6.0), Color(0.45, 0.78, 0.78, 0.5))
	# Beach, wet sand line and jungle interior.
	draw_colored_polygon(polygon, SAND)
	_ring(polygon, WET_SAND, 2.0)
	var jungle: PackedVector2Array = _grow(polygon, 0.84, -6.0)
	draw_colored_polygon(jungle, JUNGLE)
	match kind:
		MapData.KIND_MAJOR:
			_draw_canopy(rng, jungle, 70)
			_draw_airfield(rng)
		MapData.KIND_MINOR:
			_draw_canopy(rng, jungle, 34)
			_draw_outpost(rng)
		_:
			if radius >= 115.0 and rng.randf() < 0.6:
				_draw_volcano(rng, jungle)
			else:
				_draw_canopy(rng, jungle, int(radius * 0.4))
				_draw_rocks(rng)
	_draw_palms(rng)


## Shallow turquoise water around a Minor island (ships of deep draft cannot enter).
func _draw_lagoon() -> void:
	var steps: int = 5
	for i: int in steps:
		var f: float = 1.0 - float(i) / float(steps)
		draw_circle(Vector2.ZERO, shallow_radius * f, Color(0.18, 0.5, 0.55, 0.12))
	draw_arc(Vector2.ZERO, shallow_radius, 0.0, TAU, 72, Color(0.5, 0.82, 0.85, 0.3), 1.5)


## Polygon scaled by `scale_by` and pushed out (or in) by `pad` pixels along each radius.
func _grow(poly: PackedVector2Array, scale_by: float, pad: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in poly:
		var l: float = p.length()
		out.append(p.normalized() * maxf(4.0, l * scale_by + pad) if l > 0.001 else p)
	return out


func _ring(poly: PackedVector2Array, color: Color, width: float) -> void:
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, color, width, true)


func _random_point_in(rng: RandomNumberGenerator, poly: PackedVector2Array, reach: float) -> Vector2:
	for attempt: int in 12:
		var p: Vector2 = Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	return Vector2.ZERO


func _draw_canopy(rng: RandomNumberGenerator, area: PackedVector2Array, count: int) -> void:
	for i: int in count:
		var p: Vector2 = _random_point_in(rng, area, radius)
		var r: float = rng.randf_range(5.0, 11.0)
		draw_circle(p + Vector2(1.5, 2.0), r, JUNGLE_DARK)
		draw_circle(p, r, CANOPY[rng.randi() % CANOPY.size()])
		draw_circle(p - Vector2(r * 0.3, r * 0.3), r * 0.45, Color(0.34, 0.55, 0.28, 0.6))


## Coconut palms along the beach.
func _draw_palms(rng: RandomNumberGenerator) -> void:
	var count: int = int(radius * 0.18)
	for i: int in count:
		var a: float = rng.randf() * TAU
		var edge: Vector2 = _edge_point(a)
		var p: Vector2 = edge * rng.randf_range(0.78, 0.9)
		var size: float = rng.randf_range(5.0, 8.0)
		var spin: float = rng.randf() * TAU
		for f: int in 6:
			var dir: Vector2 = Vector2.from_angle(spin + TAU * float(f) / 6.0)
			draw_line(p, p + dir * size, Color(0.22, 0.45, 0.2), 2.2)
			draw_line(p + dir * size * 0.3, p + dir * size * 0.95, Color(0.32, 0.56, 0.26), 1.0)
		draw_circle(p, 1.5, Color(0.4, 0.3, 0.18))


## Point on the island outline in direction `angle` (interpolated between polygon vertices).
func _edge_point(angle: float) -> Vector2:
	var best: Vector2 = polygon[0]
	var hit: Variant = null
	var far: Vector2 = Vector2.from_angle(angle) * radius * 2.0
	for i: int in polygon.size():
		hit = Geometry2D.segment_intersects_segment(Vector2.ZERO, far, polygon[i], polygon[(i + 1) % polygon.size()])
		if hit != null:
			return hit as Vector2
	return best


## A wartime airfield: cleared ground, one long runway with markings, a taxiway, hangars,
## aircraft revetments, fuel tanks, a control tower and AA gun pits.
func _draw_airfield(rng: RandomNumberGenerator) -> void:
	var angle: float = rng.randf() * PI
	var along: Vector2 = Vector2.from_angle(angle)
	var across: Vector2 = along.orthogonal()
	var min_r: float = radius
	for p: Vector2 in polygon:
		min_r = minf(min_r, p.length())
	var half_len: float = min_r * 0.86
	var half_w: float = 8.0
	# Cleared dirt around the strip.
	draw_colored_polygon(_quad(Vector2.ZERO, along, across, half_len * 0.95, half_w + 22.0), Color(DIRT, 0.85))
	draw_colored_polygon(_quad(across * 24.0, along, across, half_len * 0.5, 16.0), Color(DIRT, 0.9))
	# Runway with dashed centreline and threshold bars.
	draw_colored_polygon(_quad(Vector2.ZERO, along, across, half_len, half_w), RUNWAY)
	var x: float = -half_len + 14.0
	while x < half_len - 14.0:
		draw_line(along * x, along * minf(x + 7.0, half_len - 14.0), MARK, 1.2)
		x += 14.0
	for end: float in [-1.0, 1.0]:
		for b: int in 4:
			var off: float = -half_w + 2.5 + float(b) * 3.7
			var base: Vector2 = along * end * (half_len - 3.0) + across * off
			draw_line(base, base - along * end * 6.0, MARK, 1.6)
	# Taxiway and apron.
	draw_line(across * half_w, across * 28.0, RUNWAY, 6.0)
	draw_colored_polygon(_quad(across * 30.0, along, across, half_len * 0.36, 8.0), Color(0.38, 0.37, 0.34))
	# Hangars (curved roofs) beside the apron.
	for h: int in 3:
		var at: Vector2 = across * 45.0 + along * (-half_len * 0.3 + float(h) * half_len * 0.3)
		draw_colored_polygon(_quad(at, along, across, 7.0, 9.0), ROOF)
		for r: int in 3:
			var line_at: Vector2 = at + along * (-4.0 + float(r) * 4.0)
			draw_line(line_at - across * 8.0, line_at + across * 8.0, Color(0.27, 0.3, 0.25), 0.8)
	# Revetments on the far side of the strip.
	for v: int in 4:
		var at: Vector2 = -across * 26.0 + along * (-half_len * 0.45 + float(v) * half_len * 0.3)
		var u: PackedVector2Array = PackedVector2Array([at - along * 5.0 - across * 5.0, at - along * 5.0 + across * 4.0,
			at + along * 5.0 + across * 4.0, at + along * 5.0 - across * 5.0])
		draw_polyline(u, Color(0.45, 0.4, 0.3), 2.5)
		_plane_icon(at, angle + PI * 0.5)
	# Fuel tanks, control tower and AA gun pits.
	for f: int in 3:
		draw_circle(across * 58.0 + along * (half_len * 0.45 + float(f) * 7.0), 3.2, Color(0.6, 0.6, 0.57))
	draw_rect(Rect2(across * 32.0 - along * half_len * 0.48 - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), CONCRETE)
	draw_circle(across * 32.0 - along * half_len * 0.48, 2.0, Color(0.25, 0.27, 0.3))
	for g: int in 4:
		var a: float = angle + PI * 0.25 + float(g) * PI * 0.5
		_gun_pit(Vector2.from_angle(a) * min_r * 0.6)


## A small single-engine aircraft parked in a revetment.
func _plane_icon(at: Vector2, heading: float) -> void:
	var fwd: Vector2 = Vector2.from_angle(heading)
	var side: Vector2 = fwd.orthogonal()
	draw_line(at - fwd * 3.5, at + fwd * 3.5, Color(0.3, 0.33, 0.28), 1.6)
	draw_line(at + fwd * 0.8 - side * 4.5, at + fwd * 0.8 + side * 4.5, Color(0.3, 0.33, 0.28), 1.6)
	draw_line(at - fwd * 3.0 - side * 1.8, at - fwd * 3.0 + side * 1.8, Color(0.3, 0.33, 0.28), 1.2)


func _gun_pit(at: Vector2) -> void:
	draw_circle(at, 6.0, Color(0.5, 0.44, 0.32))
	draw_arc(at, 6.0, 0.0, TAU, 14, Color(0.35, 0.3, 0.22), 2.0)
	draw_circle(at, 2.2, Color(0.25, 0.26, 0.24))


func _quad(center: Vector2, along: Vector2, across: Vector2, half_len: float, half_w: float) -> PackedVector2Array:
	return PackedVector2Array([center - along * half_len - across * half_w, center + along * half_len - across * half_w,
		center + along * half_len + across * half_w, center - along * half_len + across * half_w])


## A Minor island outpost: a clearing with huts, a radio mast and sandbagged gun pits.
func _draw_outpost(rng: RandomNumberGenerator) -> void:
	draw_circle(Vector2.ZERO, radius * 0.42, Color(DIRT, 0.9))
	var spin: float = rng.randf() * TAU
	for h: int in 4:
		var a: float = spin + float(h) * TAU / 4.0 + rng.randf_range(-0.3, 0.3)
		var at: Vector2 = Vector2.from_angle(a) * radius * 0.25
		var along: Vector2 = Vector2.from_angle(a + PI * 0.5)
		draw_colored_polygon(_quad(at, along, along.orthogonal(), 5.5, 3.5), HUT)
		draw_line(at - along * 5.5, at + along * 5.5, Color(0.34, 0.25, 0.15), 1.0)
	# Radio mast with guy wires.
	var mast: Vector2 = Vector2.from_angle(spin + PI * 0.25) * radius * 0.12
	for g: int in 3:
		draw_line(mast, mast + Vector2.from_angle(float(g) * TAU / 3.0) * 9.0, Color(0.2, 0.2, 0.2, 0.7), 0.7)
	draw_circle(mast, 1.8, Color(0.15, 0.15, 0.15))
	for g: int in 2:
		_gun_pit(Vector2.from_angle(spin + PI * 0.75 + float(g) * PI) * radius * 0.55)


## A volcanic cover island: concentric slopes rising to a crater.
func _draw_volcano(rng: RandomNumberGenerator, jungle: PackedVector2Array) -> void:
	_draw_canopy(rng, jungle, int(radius * 0.25))
	var peak: Vector2 = Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15)) * radius
	var levels: Array[Color] = [Color(0.36, 0.33, 0.27), Color(0.42, 0.38, 0.32), Color(0.48, 0.44, 0.38),
		Color(0.36, 0.32, 0.28)]
	for i: int in levels.size():
		var f: float = 0.62 - float(i) * 0.14
		var ring: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in polygon:
			ring.append(peak + p * f)
		draw_colored_polygon(ring, levels[i])
		_ring(ring, Color(0.25, 0.22, 0.18, 0.6), 1.0)
	draw_circle(peak, radius * 0.07, Color(0.16, 0.13, 0.11))


func _draw_rocks(rng: RandomNumberGenerator) -> void:
	for i: int in int(radius * 0.08):
		var p: Vector2 = _edge_point(rng.randf() * TAU) * rng.randf_range(0.6, 0.95)
		var r: float = rng.randf_range(3.0, 7.0)
		draw_circle(p + Vector2(1.0, 1.5), r, Color(0.2, 0.18, 0.16))
		draw_circle(p, r, ROCK)
