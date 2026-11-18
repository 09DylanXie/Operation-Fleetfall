class_name ShipArt
extends RefCounted
## Top-down vector art for every ship class, drawn into a CanvasItem in the ship's local
## frame (x toward the bow, y toward starboard). Purely cosmetic: nothing here touches the
## simulation. Each class is an original drawing loosely inspired by a WWII design:
##   DD  Benson-class destroyer (four single 5-inch gun houses)
##   SS  Type XXI U-boat (streamlined hull and sail)
##   CL  British light cruiser (three triple turrets, two funnels)
##   CA  Admiral Hipper / Lutzow-type heavy cruiser
##   BB  Scharnhorst-style battleship (Bismarck lines with one turret fewer)
##   BC  Italian battlecruiser (four quadruple turrets, red-white bow stripes)
##   SBB Yamato-type super battleship (teak deck, pagoda tower)
##   CV  Supercarrier (SCV): Shinano-type (wooden flight deck and deck markings)
##   LCV Light Carrier: Independence-type (narrow deck on a cruiser hull, four funnels)
##   RS  Resource Ship: a small coastal collier with cargo hatches and derricks
##   RD  Radar Ship: a destroyer-sized radar picket with a big air-search array
##   CLAA AA Cruiser: Atlanta-type (a light cruiser hull bristling with twin dual-purpose
##        mounts, quad pom-poms along the sides and two flak directors)
## Small ships wear dark greys; only the big, expensive hulls get lighter paint and decks.

const SMOKE: Color = Color(0.16, 0.16, 0.17)
const FIRE_OUTER: Color = Color(1.0, 0.42, 0.08)
const FIRE_INNER: Color = Color(1.0, 0.85, 0.4)
const WIND: Vector2 = Vector2(0.85, -0.5)

const DARK_HULL: Color = Color(0.3, 0.32, 0.34)
const MID_HULL: Color = Color(0.4, 0.42, 0.44)
const LIGHT_HULL: Color = Color(0.58, 0.6, 0.62)
const DARK_DECK: Color = Color(0.22, 0.23, 0.25)
const MID_DECK: Color = Color(0.3, 0.31, 0.33)
const PALE_TEAK: Color = Color(0.7, 0.64, 0.52)
const TEAK: Color = Color(0.56, 0.42, 0.27)
const FLIGHT_DECK: Color = Color(0.6, 0.5, 0.36)
const SUPER_DARK: Color = Color(0.45, 0.47, 0.49)
const SUPER_LIGHT: Color = Color(0.68, 0.7, 0.72)
const GUN_DARK: Color = Color(0.5, 0.52, 0.54)
const GUN_LIGHT: Color = Color(0.74, 0.76, 0.78)
const BARREL: Color = Color(0.2, 0.21, 0.22)
const FUNNEL: Color = Color(0.36, 0.37, 0.39)
const FUNNEL_CAP: Color = Color(0.08, 0.08, 0.09)
const SUB_HULL: Color = Color(0.13, 0.14, 0.15)
const ITALIAN_RED: Color = Color(0.72, 0.13, 0.12)
const ITALIAN_WHITE: Color = Color(0.9, 0.9, 0.88)
const MARKING: Color = Color(0.93, 0.93, 0.9)
const GOLD: Color = Color(0.86, 0.7, 0.25)

## Multiplied into every colour drawn (alpha for ghosts and submerged boats, darkening for
## sinking wrecks).
static var _mod: Color = Color.WHITE
## Base transform for the whole drawing (adds the gentle roll of the hull in a swell).
static var _base: Transform2D = Transform2D.IDENTITY
static var _hull_cache: Dictionary = {}


## Draws `stats`' whole ship: hull, superstructure and guns. `turrets` / `secondaries`
## hold each mount's current training angle relative to the bow; `roll` squeezes the beam
## slightly as the hull rolls in the swell.
static func draw(ci: CanvasItem, stats: ShipStats, team_color: Color, modulate: Color,
		turrets: PackedFloat32Array, secondaries: PackedFloat32Array, roll: float = 0.0,
		origin: Transform2D = Transform2D.IDENTITY) -> void:
	var rolled: Transform2D = origin * Transform2D(0.0, Vector2(1.0, 1.0 + roll), 0.0, Vector2.ZERO)
	draw_body(ci, stats, team_color, modulate, rolled)
	draw_guns(ci, stats, modulate, turrets, secondaries, rolled)
	ci.draw_set_transform_matrix(origin)


## The parts of a ship that never move: hull, decks, superstructure, markings. Ships draw
## this once into a child node; only the guns, fires and wake are redrawn every frame.
static func draw_body(ci: CanvasItem, stats: ShipStats, team_color: Color, modulate: Color,
		origin: Transform2D = Transform2D.IDENTITY) -> void:
	_mod = modulate
	_base = origin
	ci.draw_set_transform_matrix(_base)
	match stats.ship_class:
		ShipStats.ShipClass.DD:
			_destroyer(ci, stats, team_color)
		ShipStats.ShipClass.SS:
			_submarine(ci, stats, team_color)
		ShipStats.ShipClass.CL:
			_light_cruiser(ci, stats, team_color)
		ShipStats.ShipClass.CA:
			_heavy_cruiser(ci, stats, team_color)
		ShipStats.ShipClass.BB:
			_battleship(ci, stats, team_color)
		ShipStats.ShipClass.BC:
			_battlecruiser(ci, stats, team_color)
		ShipStats.ShipClass.SBB:
			_super_battleship(ci, stats, team_color)
		ShipStats.ShipClass.CV:
			_carrier(ci, stats, team_color)
		ShipStats.ShipClass.RS:
			_resource_ship(ci, stats, team_color)
		ShipStats.ShipClass.RD:
			_radar_ship(ci, stats, team_color)
		ShipStats.ShipClass.LCV:
			_light_carrier(ci, stats, team_color)
		ShipStats.ShipClass.CLAA:
			_aa_cruiser(ci, stats, team_color)
	ci.draw_set_transform_matrix(origin)
	_mod = Color.WHITE
	_base = Transform2D.IDENTITY


## Gun houses trained to their current angles (main battery and secondaries).
static func draw_guns(ci: CanvasItem, stats: ShipStats, modulate: Color, turrets: PackedFloat32Array,
		secondaries: PackedFloat32Array, origin: Transform2D = Transform2D.IDENTITY) -> void:
	if stats.gun_mounts == 0 and stats.secondary_mounts == 0:
		return
	_mod = modulate
	_base = origin
	var spec: GunSpec = gun_spec(stats.ship_class)
	var sec_tex: Texture2D = baked.get(sprite_key(stats.ship_class, SPRITE_SECONDARY))
	for i: int in stats.secondary_mounts:
		var angle: float = secondaries[i] if i < secondaries.size() else deg_to_rad(stats.secondary_facings_deg[i])
		if sec_tex != null:
			_sprite(ci, sec_tex, stats.secondary_offsets[i], angle)
		else:
			_turret(ci, stats.secondary_offsets[i], angle, spec.sec_radius, spec.sec_barrels,
				spec.sec_radius * 1.7, spec.house)
	var main_tex: Texture2D = baked.get(sprite_key(stats.ship_class, SPRITE_MAIN))
	for i: int in stats.gun_mounts:
		var at: Vector2 = Vector2(stats.mount_offsets[i], 0.0)
		if main_tex != null:
			_sprite(ci, main_tex, at, _mount_angle(turrets, stats, i))
		else:
			_turret(ci, at, _mount_angle(turrets, stats, i), spec.radius, stats.shells_per_mount, spec.length,
				spec.house, spec.wide)
	ci.draw_set_transform_matrix(origin)
	_mod = Color.WHITE
	_base = Transform2D.IDENTITY


## Bow wave and a V of churned water astern, longer the faster the ship goes.
static func draw_wake(ci: CanvasItem, stats: ShipStats, speed: float, t: float, modulate: Color) -> void:
	if speed < 2.0:
		return
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var k: float = clampf(speed / 40.0, 0.0, 1.0)
	var foam: Color = Color(0.9, 0.96, 1.0, 0.55 * k * modulate.a)
	var length: float = (20.0 + stats.hull_length * 0.9) * k
	for side: float in [-1.0, 1.0]:
		var pts: PackedVector2Array = PackedVector2Array()
		var cols: PackedColorArray = PackedColorArray()
		for i: int in 7:
			var f: float = float(i) / 6.0
			var wob: float = sin(t * 3.0 + f * 6.0 + side) * 1.2 * f
			pts.append(Vector2(-hl * 0.85 - length * f, side * (hw * 0.7 + length * 0.32 * f + wob)))
			cols.append(Color(foam, foam.a * (1.0 - f)))
		ci.draw_polyline_colors(pts, cols, 1.4)
		ci.draw_line(Vector2(hl * 0.98, 0.0), Vector2(hl * 0.55, side * (hw + 3.0 * k)), Color(foam, foam.a * 0.9), 1.3)
	# Propeller wash: churned foam straight astern.
	for i: int in 4:
		var f: float = fmod(t * 0.8 + float(i) * 0.25, 1.0)
		ci.draw_circle(Vector2(-hl - length * 0.55 * f, 0.0), hw * (0.25 + 0.35 * f), Color(foam, foam.a * 0.45 * (1.0 - f)))


## Fires that spread as the ship is damaged (`damage` 0-1), with smoke blown downwind.
static func draw_fires(ci: CanvasItem, stats: ShipStats, damage: float, t: float, rotation: float,
		seed: int, strength: float = 1.0) -> void:
	if damage < 0.08:
		return
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var slots: int = maxi(3, int(stats.hull_length / 14.0))
	var count: int = clampi(int(ceil(damage * float(slots))), 1, slots)
	var wind: Vector2 = WIND.rotated(-rotation)
	var size: float = (1.6 + 2.6 * damage) * clampf(stats.hull_length / 70.0, 0.7, 1.6) * strength
	for i: int in count:
		var hx: float = _hash01(seed, i * 2) * 1.5 - 0.75
		var hy: float = _hash01(seed, i * 2 + 1) * 1.0 - 0.5
		var at: Vector2 = Vector2(hx * hl, hy * hw)
		for p: int in 4:
			var phase: float = fmod(t * 0.45 + float(p) * 0.25 + _hash01(seed, i + 50), 1.0)
			var puff: Vector2 = at + wind * (6.0 + 46.0 * phase) * strength
			ci.draw_circle(puff, size * (0.9 + 2.2 * phase), Color(SMOKE, 0.42 * (1.0 - phase) * strength))
		var flick: float = 0.75 + 0.25 * sin(t * 13.0 + float(i) * 2.1) + 0.15 * sin(t * 29.0 + float(i))
		ci.draw_circle(at, size * 1.25 * flick, Color(FIRE_OUTER, 0.85 * strength))
		ci.draw_circle(at + wind * size * 0.3, size * 0.8 * flick, Color(1.0, 0.62, 0.15, 0.9 * strength))
		ci.draw_circle(at, size * 0.45 * flick, Color(FIRE_INNER, strength))


static func _hash01(seed: int, i: int) -> float:
	return float(hash(seed * 977 + i * 7919) & 0xffff) / 65535.0


# --- Drawing helpers --------------------------------------------------------

static func _c(color: Color) -> Color:
	return color * _mod


## Outline of a hull: a straight midbody, a bow that narrows to a point from `bow` (fraction
## of the half length) and a stern that narrows to `transom` of the beam from `stern`.
static func _hull(half_l: float, half_w: float, bow: float, stern: float, transom: float,
		bow_power: float = 0.8) -> PackedVector2Array:
	var key: String = "%.1f|%.1f|%.2f|%.2f|%.2f|%.2f" % [half_l, half_w, bow, stern, transom, bow_power]
	if _hull_cache.has(key):
		return _hull_cache[key]
	var top: PackedVector2Array = PackedVector2Array()
	var n: int = 18
	for i: int in n + 1:
		var u: float = -1.0 + 2.0 * float(i) / float(n)
		var w: float = half_w
		if u > bow:
			var k: float = (u - bow) / (1.0 - bow)
			w = half_w * pow(maxf(0.0, cos(k * PI * 0.5)), bow_power)
		elif u < stern:
			var k: float = (stern - u) / (stern + 1.0)
			w = half_w * lerpf(1.0, transom, k * k)
		top.append(Vector2(u * half_l, w))
	var pts: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in top:
		pts.append(p)
	for i: int in range(top.size() - 1, -1, -1):
		var p: Vector2 = top[i]
		if p.y > 0.001 or (i != top.size() - 1 and i != 0):
			pts.append(Vector2(p.x, -p.y))
	# Drop the duplicated zero-width bow point so the polygon stays simple.
	var clean: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.01:
			clean.append(p)
	if clean.size() > 2 and clean[0].distance_to(clean[clean.size() - 1]) < 0.01:
		clean.remove_at(clean.size() - 1)
	_hull_cache[key] = clean
	return clean


static func _scaled(poly: PackedVector2Array, sx: float, sy: float, shift: float = 0.0) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in poly:
		out.append(Vector2(p.x * sx + shift, p.y * sy))
	return out


static func _poly(ci: CanvasItem, poly: PackedVector2Array, color: Color) -> void:
	ci.draw_colored_polygon(poly, _c(color))


static func _outline(ci: CanvasItem, poly: PackedVector2Array, color: Color, width: float) -> void:
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	ci.draw_polyline(closed, _c(color), width, true)


static func _rect(ci: CanvasItem, x0: float, x1: float, half_y: float, color: Color, y: float = 0.0) -> void:
	ci.draw_rect(Rect2(Vector2(minf(x0, x1), y - half_y), Vector2(absf(x1 - x0), half_y * 2.0)), _c(color))


static func _oval(ci: CanvasItem, at: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 14:
		var a: float = TAU * float(i) / 14.0
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, _c(color))


static func _dot(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(at, r, _c(color))


## Hull with a team-coloured waterline so every side stays recognisable.
static func _base_hull(ci: CanvasItem, hull: PackedVector2Array, paint: Color, team_color: Color) -> void:
	# Soft shadow on the water.
	var shadow: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in hull:
		shadow.append(p * 1.04 + Vector2(1.5, 2.0))
	ci.draw_colored_polygon(shadow, Color(0.0, 0.02, 0.05, 0.35 * _mod.a))
	_poly(ci, hull, paint)
	_outline(ci, hull, team_color, 1.4)


## Planked deck: base colour plus fine fore-aft seams.
static func _planks(ci: CanvasItem, x0: float, x1: float, half_y: float, color: Color, lines: int) -> void:
	var seam: Color = Color(color.r * 0.78, color.g * 0.76, color.b * 0.74, color.a)
	for i: int in lines:
		var y: float = -half_y + (float(i) + 0.5) * (half_y * 2.0 / float(lines))
		ci.draw_line(Vector2(x0, y), Vector2(x1, y), _c(seam), 0.5)


## A gun house trained to `angle` with `barrels` guns of `length`.
static func _turret(ci: CanvasItem, at: Vector2, angle: float, radius: float, barrels: int, length: float,
		house: Color, wide: float = 1.0) -> void:
	ci.draw_set_transform_matrix(_base * Transform2D(angle, at))
	var spacing: float = radius * 0.5 * wide if barrels > 1 else 0.0
	var span: float = spacing * float(barrels - 1)
	for b: int in barrels:
		var y: float = -span * 0.5 + spacing * float(b)
		ci.draw_line(Vector2(radius * 0.3, y), Vector2(radius * 0.3 + length, y), _c(BARREL),
			maxf(0.9, radius * 0.22))
	var hw: float = radius * 0.85 * wide
	var house_pts: PackedVector2Array = PackedVector2Array([
		Vector2(radius * 0.85, -hw * 0.82), Vector2(radius * 0.85, hw * 0.82),
		Vector2(radius * 0.15, hw), Vector2(-radius * 0.7, hw * 0.9),
		Vector2(-radius, hw * 0.45), Vector2(-radius, -hw * 0.45),
		Vector2(-radius * 0.7, -hw * 0.9), Vector2(radius * 0.15, -hw)])
	ci.draw_colored_polygon(house_pts, _c(house))
	var rim: PackedVector2Array = house_pts.duplicate()
	rim.append(house_pts[0])
	ci.draw_polyline(rim, _c(Color(0.12, 0.13, 0.14)), 0.6, true)
	# Rangefinder ears on big turrets.
	if radius > 4.5:
		ci.draw_line(Vector2(-radius * 0.35, -hw * 1.05), Vector2(-radius * 0.35, hw * 1.05), _c(BARREL), 1.0)
	ci.draw_set_transform_matrix(_base)


## How each class's guns look: house size, barrel length and colour.
class GunSpec:
	var radius: float = 3.0
	var length: float = 6.0
	var house: Color = GUN_DARK
	var wide: float = 1.0
	var sec_radius: float = 2.0
	var sec_barrels: int = 2

	func _init(p_radius: float, p_length: float, p_house: Color, p_wide: float = 1.0, p_sec_radius: float = 2.0,
			p_sec_barrels: int = 2) -> void:
		radius = p_radius
		length = p_length
		house = p_house
		wide = p_wide
		sec_radius = p_sec_radius
		sec_barrels = p_sec_barrels


static func gun_spec(cls: ShipStats.ShipClass) -> GunSpec:
	match cls:
		ShipStats.ShipClass.DD:
			return GunSpec.new(2.3, 4.6, GUN_DARK)
		ShipStats.ShipClass.CL:
			return GunSpec.new(3.3, 7.0, GUN_DARK)
		ShipStats.ShipClass.CA:
			return GunSpec.new(3.6, 8.5, GUN_DARK)
		ShipStats.ShipClass.BB:
			return GunSpec.new(5.2, 12.0, GUN_LIGHT, 1.0, 2.0, 2)
		ShipStats.ShipClass.BC:
			return GunSpec.new(4.4, 9.5, GUN_LIGHT, 1.35)
		ShipStats.ShipClass.SBB:
			return GunSpec.new(6.4, 14.0, GUN_LIGHT, 1.05, 2.3, 3)
	return GunSpec.new(3.0, 6.0, GUN_DARK)


# --- Baked sprites ------------------------------------------------------------
# ShipArtCache renders each hull and gun house once into a texture and stores it here;
# drawing a textured quad is far cheaper than re-issuing hundreds of vector commands.

const SPRITE_BODY: int = 0
const SPRITE_MAIN: int = 1
const SPRITE_SECONDARY: int = 2
## Texture pixels per world pixel in baked sprites.
const BAKE_SCALE: float = 6.0

static var baked: Dictionary = {}


static func sprite_key(cls: ShipStats.ShipClass, kind: int, team: int = -1) -> String:
	return "%d|%d|%d" % [int(cls), kind, team]


## Half extent (world pixels) of the square a gun house sprite is baked into.
static func gun_sprite_half(cls: ShipStats.ShipClass, kind: int) -> float:
	var spec: GunSpec = gun_spec(cls)
	if kind == SPRITE_SECONDARY:
		return spec.sec_radius * 3.2 + 2.0
	return maxf(spec.radius * 1.4, spec.radius * 0.3 + spec.length) + 2.0


## Draws the gun house sprite for one mount, centred on its pivot.
static func _sprite(ci: CanvasItem, tex: Texture2D, at: Vector2, angle: float) -> void:
	ci.draw_set_transform_matrix(_base * Transform2D(angle, at))
	var size: Vector2 = tex.get_size() / BAKE_SCALE
	ci.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, _mod)


## Bakes one sprite: called by ShipArtCache inside a SubViewport of the given pixel size.
static func draw_for_bake(ci: CanvasItem, stats: ShipStats, kind: int, team_color: Color, pixel_size: Vector2) -> void:
	var origin: Transform2D = Transform2D(0.0, Vector2(BAKE_SCALE, BAKE_SCALE), 0.0, pixel_size * 0.5)
	if kind == SPRITE_BODY:
		draw_body(ci, stats, team_color, Color.WHITE, origin)
		return
	_mod = Color.WHITE
	_base = origin
	var spec: GunSpec = gun_spec(stats.ship_class)
	if kind == SPRITE_MAIN:
		_turret(ci, Vector2.ZERO, 0.0, spec.radius, stats.shells_per_mount, spec.length, spec.house, spec.wide)
	else:
		_turret(ci, Vector2.ZERO, 0.0, spec.sec_radius, spec.sec_barrels, spec.sec_radius * 1.7, spec.house)
	_base = Transform2D.IDENTITY


static func _mount_angle(turrets: PackedFloat32Array, stats: ShipStats, i: int) -> float:
	if i < turrets.size():
		return turrets[i]
	return deg_to_rad(stats.mount_facings_deg[i])


static func _funnel(ci: CanvasItem, at: Vector2, rx: float, ry: float, body: Color = FUNNEL) -> void:
	_oval(ci, at, rx, ry, body)
	_oval(ci, at + Vector2(-rx * 0.15, 0.0), rx * 0.62, ry * 0.6, FUNNEL_CAP)


static func _aa_row(ci: CanvasItem, x0: float, x1: float, y: float, count: int, r: float, color: Color) -> void:
	for i: int in count:
		var x: float = lerpf(x0, x1, (float(i) + 0.5) / float(count))
		_dot(ci, Vector2(x, y), r, color)
		_dot(ci, Vector2(x, -y), r, color)


## Small team-coloured ensign on the quarterdeck.
static func _ensign(ci: CanvasItem, x: float, team_color: Color, size: float) -> void:
	ci.draw_rect(Rect2(Vector2(x - size, -size * 0.6), Vector2(size * 1.6, size * 1.2)), _c(team_color))


# --- Classes ----------------------------------------------------------------

## Benson-class destroyer: flush deck, bridge forward, two upright funnels, torpedo tubes on
## the centreline and four single enclosed 5-inch mounts (two fore, two aft).
static func _destroyer(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.35, -0.75, 0.55, 0.9)
	_base_hull(ci, hull, MID_HULL, team_color)
	_poly(ci, _scaled(hull, 0.93, 0.78), DARK_DECK)
	# Bridge and forward superstructure.
	_rect(ci, 2.0, 7.0, hw * 0.62, SUPER_DARK)
	_rect(ci, 5.0, 7.0, hw * 0.75, Color(0.52, 0.54, 0.56))
	_dot(ci, Vector2(4.0, 0.0), 1.3, Color(0.18, 0.19, 0.2))
	# Two funnels.
	_funnel(ci, Vector2(-0.5, 0.0), 1.7, 1.5)
	_funnel(ci, Vector2(-4.5, 0.0), 1.7, 1.5)
	# Centreline torpedo tube mounts (quintuple).
	for x: float in [-1.5, -6.5]:
		ci.draw_line(Vector2(x - 0.2, -hw * 0.55), Vector2(x + 0.2, hw * 0.55), _c(Color(0.55, 0.57, 0.58)), 1.4)
	# Depth-charge racks on the stern.
	for side: float in [-1.0, 1.0]:
		ci.draw_line(Vector2(-hl * 0.97, side * hw * 0.35), Vector2(-hl * 0.8, side * hw * 0.35), _c(BARREL), 1.2)
	_ensign(ci, -hl * 0.78, team_color, 1.4)


## Type XXI U-boat: long streamlined casing, smooth faired sail with twin AA turrets.
static func _submarine(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.25, -0.15, 0.0, 0.6)
	_base_hull(ci, hull, SUB_HULL, team_color)
	_poly(ci, _scaled(hull, 0.9, 0.45), Color(0.19, 0.2, 0.21))
	# Faired sail.
	var sail: PackedVector2Array = _hull(5.5, hw * 0.48, 0.35, -0.4, 0.2, 0.7)
	_poly(ci, _scaled(sail, 1.0, 1.0, 1.0), Color(0.24, 0.25, 0.26))
	_outline(ci, _scaled(sail, 1.0, 1.0, 1.0), Color(0.08, 0.08, 0.09), 0.6)
	# Twin 20mm AA turrets fore and aft on the sail.
	for x: float in [4.5, -2.5]:
		_dot(ci, Vector2(x, 0.0), 1.1, Color(0.36, 0.37, 0.38))
		ci.draw_line(Vector2(x, -0.4), Vector2(x + (1.8 if x > 0.0 else -1.8), -0.4), _c(BARREL), 0.5)
		ci.draw_line(Vector2(x, 0.4), Vector2(x + (1.8 if x > 0.0 else -1.8), 0.4), _c(BARREL), 0.5)
	# Stern planes and rudder.
	ci.draw_line(Vector2(-hl * 0.9, -hw * 0.9), Vector2(-hl * 0.9, hw * 0.9), _c(Color(0.2, 0.21, 0.22)), 1.0)
	ci.draw_line(Vector2(-hl * 1.02, 0.0), Vector2(-hl * 0.85, 0.0), _c(Color(0.25, 0.26, 0.27)), 1.0)
	# Bow planes and limber holes along the casing.
	ci.draw_line(Vector2(hl * 0.62, -hw * 1.05), Vector2(hl * 0.62, hw * 1.05), _c(Color(0.2, 0.21, 0.22)), 0.8)
	for i: int in 6:
		var x: float = lerpf(-hl * 0.55, hl * 0.4, float(i) / 5.0)
		_dot(ci, Vector2(x, hw * 0.62), 0.35, Color(0.05, 0.05, 0.05))
		_dot(ci, Vector2(x, -hw * 0.62), 0.35, Color(0.05, 0.05, 0.05))
	_dot(ci, Vector2(-hl * 0.55, 0.0), 0.9, team_color)


## British light cruiser: three triple 6-inch turrets (A and B forward, X aft), tall block
## bridge, two raked funnels and a hangar between them.
static func _light_cruiser(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.4, -0.7, 0.5, 0.85)
	_base_hull(ci, hull, MID_HULL, team_color)
	_poly(ci, _scaled(hull, 0.93, 0.8), MID_DECK)
	# Forecastle break.
	ci.draw_line(Vector2(-6.0, -hw * 0.8), Vector2(-6.0, hw * 0.8), _c(Color(0.18, 0.19, 0.2)), 0.6)
	# Bridge block.
	_rect(ci, 1.0, 5.5, hw * 0.68, SUPER_DARK)
	_rect(ci, 3.5, 5.5, hw * 0.82, Color(0.55, 0.57, 0.59))
	_dot(ci, Vector2(2.0, 0.0), 1.6, Color(0.6, 0.62, 0.64))
	# Hangar and funnels.
	_rect(ci, -2.0, -14.0, hw * 0.5, SUPER_DARK)
	_funnel(ci, Vector2(-3.5, 0.0), 2.2, 1.8)
	_funnel(ci, Vector2(-10.5, 0.0), 2.2, 1.8)
	# Aft director and 4-inch twin AA mounts amidships.
	_rect(ci, -15.0, -17.0, hw * 0.45, SUPER_DARK)
	_aa_row(ci, -12.0, 0.0, hw * 0.7, 2, 1.0, GUN_DARK)
	_ensign(ci, -hl * 0.9, team_color, 1.6)


## Admiral Hipper / Lutzow-type heavy cruiser: Atlantic bow, tower bridge, a single big
## capped funnel, catapult amidships and four twin 8-inch turrets.
static func _heavy_cruiser(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.32, -0.72, 0.5, 0.7)
	_base_hull(ci, hull, MID_HULL, team_color)
	_poly(ci, _scaled(hull, 0.93, 0.8), MID_DECK)
	# Darker bow and stern ends.
	_poly(ci, PackedVector2Array([Vector2(hl * 0.95, 0.0), Vector2(hl * 0.78, hw * 0.55),
		Vector2(hl * 0.78, -hw * 0.55)]), DARK_DECK)
	# Tower bridge.
	_rect(ci, 4.0, 12.0, hw * 0.6, SUPER_DARK)
	_oval(ci, Vector2(9.0, 0.0), 2.6, 2.4, Color(0.56, 0.58, 0.6))
	_dot(ci, Vector2(9.0, 0.0), 1.2, Color(0.25, 0.26, 0.27))
	# Big funnel with cap.
	_funnel(ci, Vector2(-0.5, 0.0), 3.2, 2.6)
	# Catapult and aircraft.
	ci.draw_line(Vector2(-11.0, -hw * 0.5), Vector2(-5.0, hw * 0.5), _c(Color(0.55, 0.56, 0.57)), 1.4)
	_rect(ci, -5.0, -12.0, hw * 0.25, SUPER_DARK)
	# Aft superstructure and mainmast.
	_rect(ci, -11.0, -14.0, hw * 0.55, SUPER_DARK)
	_dot(ci, Vector2(-12.5, 0.0), 1.1, Color(0.6, 0.62, 0.64))
	_aa_row(ci, -10.0, 4.0, hw * 0.72, 3, 1.0, GUN_DARK)
	_ensign(ci, -hl * 0.92, team_color, 1.8)


## Scharnhorst-style battleship (Bismarck lines with three twin turrets): pale scrubbed deck,
## light grey hull with darker painted ends, central superstructure, capped funnel, hangar
## and four twin secondary turrets on the citadel.
static func _battleship(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.38, -0.7, 0.55, 0.8)
	_base_hull(ci, hull, LIGHT_HULL, team_color)
	var deck: PackedVector2Array = _scaled(hull, 0.94, 0.84)
	_poly(ci, deck, PALE_TEAK)
	_planks(ci, -hl * 0.88, hl * 0.6, hw * 0.75, PALE_TEAK, 7)
	# Darker grey bow and stern ends.
	_poly(ci, PackedVector2Array([Vector2(hl * 0.94, 0.0), Vector2(hl * 0.74, hw * 0.6),
		Vector2(hl * 0.74, -hw * 0.6)]), Color(0.44, 0.45, 0.47))
	_rect(ci, -hl * 0.94, -hl * 0.82, hw * 0.55, Color(0.44, 0.45, 0.47))
	# Citadel superstructure.
	_rect(ci, 12.0, -22.0, hw * 0.48, SUPER_LIGHT)
	_oval(ci, Vector2(10.0, 0.0), 4.0, hw * 0.48, SUPER_LIGHT)
	_oval(ci, Vector2(9.0, 0.0), 2.4, 2.4, Color(0.5, 0.52, 0.54))
	_dot(ci, Vector2(9.0, 0.0), 1.3, Color(0.3, 0.31, 0.32))
	_funnel(ci, Vector2(-4.5, 0.0), 3.8, 3.0, Color(0.6, 0.62, 0.64))
	_rect(ci, -9.0, -16.0, hw * 0.3, Color(0.55, 0.57, 0.59))
	ci.draw_line(Vector2(-9.0, -hw * 0.7), Vector2(-9.0, hw * 0.7), _c(Color(0.45, 0.46, 0.48)), 1.2)
	_oval(ci, Vector2(-19.0, 0.0), 2.2, 2.2, Color(0.5, 0.52, 0.54))
	_aa_row(ci, -20.0, 10.0, hw * 0.78, 4, 0.9, GUN_DARK)
	_ensign(ci, -hl * 0.9, team_color, 2.0)


## Italian battlecruiser: long fine hull, red and white air-recognition stripes on the
## forecastle, tower bridge, two funnels and four quadruple turrets.
static func _battlecruiser(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.42, -0.7, 0.5, 0.75)
	_base_hull(ci, hull, LIGHT_HULL, team_color)
	var deck: PackedVector2Array = _scaled(hull, 0.94, 0.84)
	_poly(ci, deck, Color(0.62, 0.62, 0.6))
	_planks(ci, -hl * 0.85, hl * 0.6, hw * 0.75, Color(0.62, 0.62, 0.6), 6)
	# Diagonal red/white stripes across the forecastle.
	var x0: float = stats.mount_offsets[0] + 5.0
	var x1: float = hl * 0.9
	var stripes: int = 6
	for i: int in stripes:
		var a: float = lerpf(x0, x1, float(i) / float(stripes))
		var b: float = lerpf(x0, x1, float(i + 1) / float(stripes))
		var wa: float = _beam_at(hl, hw * 0.84, a, 0.42, 0.75)
		var wb: float = _beam_at(hl, hw * 0.84, b, 0.42, 0.75)
		var col: Color = ITALIAN_RED if i % 2 == 0 else ITALIAN_WHITE
		_poly(ci, PackedVector2Array([Vector2(a - 2.0, -wa), Vector2(b - 2.0, -wb), Vector2(b + 2.0, wb),
			Vector2(a + 2.0, wa)]), col)
	# Superstructure.
	_rect(ci, 10.0, -15.0, hw * 0.45, SUPER_LIGHT)
	_oval(ci, Vector2(8.5, 0.0), 3.4, hw * 0.5, SUPER_LIGHT)
	_oval(ci, Vector2(8.0, 0.0), 2.0, 2.0, Color(0.5, 0.52, 0.54))
	_funnel(ci, Vector2(0.0, 0.0), 2.8, 2.4, Color(0.6, 0.62, 0.64))
	_funnel(ci, Vector2(-8.0, 0.0), 2.8, 2.4, Color(0.6, 0.62, 0.64))
	_oval(ci, Vector2(-13.5, 0.0), 2.0, 2.0, Color(0.5, 0.52, 0.54))
	_aa_row(ci, -14.0, 8.0, hw * 0.76, 4, 0.9, GUN_DARK)
	_ensign(ci, -hl * 0.9, team_color, 1.9)


## Half-beam of a hull outline from `_hull` at x (used to fit deck markings).
static func _beam_at(half_l: float, half_w: float, x: float, bow: float, bow_power: float) -> float:
	var u: float = x / half_l
	if u > bow:
		var k: float = (u - bow) / (1.0 - bow)
		return half_w * pow(maxf(0.0, cos(clampf(k, 0.0, 1.0) * PI * 0.5)), bow_power)
	return half_w


## Yamato-type super battleship: broad hull with a sheer flared bow, teak deck, chrysanthemum
## crest, pagoda tower, raked funnel, three huge triple turrets, triple secondaries, massed
## AA mounts and a dark aircraft deck aft.
static func _super_battleship(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.3, -0.62, 0.6, 0.6)
	_base_hull(ci, hull, Color(0.52, 0.54, 0.56), team_color)
	var deck: PackedVector2Array = _scaled(hull, 0.95, 0.86)
	_poly(ci, deck, TEAK)
	_planks(ci, -hl * 0.72, hl * 0.82, hw * 0.78, TEAK, 9)
	# Aircraft deck aft (steel, dark) with catapults and crane.
	_rect(ci, -hl * 0.72, -hl * 0.94, hw * 0.72, Color(0.3, 0.31, 0.33))
	for side: float in [-1.0, 1.0]:
		ci.draw_line(Vector2(-hl * 0.92, side * hw * 0.55), Vector2(-hl * 0.78, side * hw * 0.3), _c(Color(0.5, 0.5, 0.5)), 1.0)
	_dot(ci, Vector2(-hl * 0.75, 0.0), 1.4, Color(0.4, 0.41, 0.42))
	# Chrysanthemum crest at the bow.
	_dot(ci, Vector2(hl * 0.94, 0.0), 1.3, GOLD)
	# Superstructure: pagoda tower, raked funnel, mainmast.
	_rect(ci, 14.0, -24.0, hw * 0.42, Color(0.6, 0.62, 0.64))
	_oval(ci, Vector2(10.0, 0.0), 6.0, hw * 0.5, SUPER_LIGHT)
	_oval(ci, Vector2(10.5, 0.0), 4.0, hw * 0.36, Color(0.62, 0.64, 0.66))
	_oval(ci, Vector2(11.0, 0.0), 2.4, 2.4, Color(0.48, 0.5, 0.52))
	ci.draw_line(Vector2(11.0, -hw * 0.62), Vector2(11.0, hw * 0.62), _c(BARREL), 1.4)
	# Raked funnel: an elongated oval leaning aft.
	_oval(ci, Vector2(-3.0, 0.0), 5.0, 3.4, Color(0.6, 0.62, 0.64))
	_oval(ci, Vector2(-5.0, 0.0), 2.8, 2.2, FUNNEL_CAP)
	_oval(ci, Vector2(-17.0, 0.0), 2.6, 2.6, Color(0.55, 0.57, 0.59))
	_aa_row(ci, -24.0, 12.0, hw * 0.8, 7, 1.0, Color(0.42, 0.44, 0.46))
	_aa_row(ci, -18.0, 6.0, hw * 0.56, 4, 0.8, Color(0.42, 0.44, 0.46))
	_ensign(ci, -hl * 0.86, team_color, 2.2)


## Shinano-type carrier: hull with a long overhanging wooden flight deck, white edge and
## centre lines, three lifts, a team roundel forward, striped round-down aft and a
## starboard island with a funnel canted outboard.
static func _carrier(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw * 0.82, 0.4, -0.75, 0.6, 0.7)
	_base_hull(ci, hull, MID_HULL, team_color)
	# AA sponsons along both sides.
	for i: int in 7:
		var x: float = lerpf(-hl * 0.7, hl * 0.6, float(i) / 6.0)
		_rect(ci, x - 1.6, x + 1.6, 1.5, Color(0.42, 0.44, 0.46), hw * 0.86)
		_rect(ci, x - 1.6, x + 1.6, 1.5, Color(0.42, 0.44, 0.46), -hw * 0.86)
	# Flight deck.
	var fd_front: float = hl * 0.92
	var fd_back: float = -hl * 0.98
	var fd_w: float = hw * 0.7
	var flight: PackedVector2Array = PackedVector2Array([Vector2(fd_front, -fd_w * 0.6),
		Vector2(fd_front, fd_w * 0.6), Vector2(fd_front - 6.0, fd_w), Vector2(fd_back + 3.0, fd_w),
		Vector2(fd_back, fd_w * 0.8), Vector2(fd_back, -fd_w * 0.8), Vector2(fd_back + 3.0, -fd_w),
		Vector2(fd_front - 6.0, -fd_w)])
	_poly(ci, flight, FLIGHT_DECK)
	_planks(ci, fd_back + 1.0, fd_front - 1.0, fd_w * 0.95, FLIGHT_DECK, 10)
	_outline(ci, flight, Color(0.3, 0.26, 0.2), 0.8)
	# White deck-edge lines and dashed centreline.
	ci.draw_line(Vector2(fd_back + 2.0, fd_w * 0.88), Vector2(fd_front - 6.0, fd_w * 0.88), _c(MARKING), 0.7)
	ci.draw_line(Vector2(fd_back + 2.0, -fd_w * 0.88), Vector2(fd_front - 6.0, -fd_w * 0.88), _c(MARKING), 0.7)
	var x: float = fd_back + 6.0
	while x < fd_front - 6.0:
		ci.draw_line(Vector2(x, 0.0), Vector2(minf(x + 3.0, fd_front - 6.0), 0.0), _c(MARKING), 0.9)
		x += 6.0
	# Lifts.
	for lx: float in [hl * 0.5, 0.0, -hl * 0.55]:
		ci.draw_rect(Rect2(Vector2(lx - 3.5, -3.5), Vector2(7.0, 7.0)), _c(Color(0.42, 0.34, 0.24)), false, 0.8)
	# Arrester-wire bands aft and the striped round-down.
	for i: int in 4:
		var wx: float = -hl * 0.6 - float(i) * 3.0
		ci.draw_line(Vector2(wx, -fd_w * 0.85), Vector2(wx, fd_w * 0.85), _c(Color(0.3, 0.27, 0.22)), 0.5)
	for i: int in 4:
		var sx: float = fd_back + 0.5 + float(i) * 1.6
		var col: Color = ITALIAN_RED if i % 2 == 0 else MARKING
		ci.draw_line(Vector2(sx, -fd_w * 0.75), Vector2(sx, fd_w * 0.75), _c(col), 1.2)
	# Team roundel where a national marking would be.
	_dot(ci, Vector2(hl * 0.72, 0.0), fd_w * 0.42, MARKING)
	_dot(ci, Vector2(hl * 0.72, 0.0), fd_w * 0.32, team_color)
	# Starboard island with a funnel canted outboard.
	var iy: float = fd_w + 1.6
	_rect(ci, 2.0, 12.0, 2.0, SUPER_DARK, iy)
	_rect(ci, 8.0, 12.0, 2.4, Color(0.55, 0.57, 0.59), iy)
	_oval(ci, Vector2(4.0, iy + 2.6), 2.4, 1.6, FUNNEL)
	_oval(ci, Vector2(4.0, iy + 3.4), 1.4, 0.9, FUNNEL_CAP)
	_dot(ci, Vector2(10.0, iy), 1.0, Color(0.3, 0.31, 0.32))


## Light Carrier: an Independence-type conversion of a cruiser hull. Narrow wooden flight
## deck overhanging a slim grey hull, a small bridge island forward on the starboard side
## and four small funnels in pairs aft of it, canted outboard.
static func _light_carrier(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw * 0.72, 0.5, -0.8, 0.55, 0.6)
	_base_hull(ci, hull, MID_HULL, team_color)
	# A few AA tubs along the sides.
	for i: int in 5:
		var x: float = lerpf(-hl * 0.65, hl * 0.55, float(i) / 4.0)
		_rect(ci, x - 1.2, x + 1.2, 1.2, Color(0.42, 0.44, 0.46), hw * 0.78)
		_rect(ci, x - 1.2, x + 1.2, 1.2, Color(0.42, 0.44, 0.46), -hw * 0.78)
	# Flight deck: short of the bow (the cruiser forecastle shows), squared off aft.
	var fd_front: float = hl * 0.78
	var fd_back: float = -hl * 0.96
	var fd_w: float = hw * 0.66
	var flight: PackedVector2Array = PackedVector2Array([Vector2(fd_front, -fd_w * 0.7),
		Vector2(fd_front, fd_w * 0.7), Vector2(fd_front - 4.0, fd_w), Vector2(fd_back + 2.0, fd_w),
		Vector2(fd_back, fd_w * 0.85), Vector2(fd_back, -fd_w * 0.85), Vector2(fd_back + 2.0, -fd_w),
		Vector2(fd_front - 4.0, -fd_w)])
	_poly(ci, flight, FLIGHT_DECK)
	_planks(ci, fd_back + 1.0, fd_front - 1.0, fd_w * 0.95, FLIGHT_DECK, 8)
	_outline(ci, flight, Color(0.3, 0.26, 0.2), 0.7)
	ci.draw_line(Vector2(fd_back + 2.0, fd_w * 0.86), Vector2(fd_front - 4.0, fd_w * 0.86), _c(MARKING), 0.6)
	ci.draw_line(Vector2(fd_back + 2.0, -fd_w * 0.86), Vector2(fd_front - 4.0, -fd_w * 0.86), _c(MARKING), 0.6)
	var x: float = fd_back + 5.0
	while x < fd_front - 5.0:
		ci.draw_line(Vector2(x, 0.0), Vector2(minf(x + 2.5, fd_front - 5.0), 0.0), _c(MARKING), 0.8)
		x += 5.0
	# Two lifts and a few arrester wires.
	for lx: float in [hl * 0.35, -hl * 0.45]:
		ci.draw_rect(Rect2(Vector2(lx - 2.8, -2.8), Vector2(5.6, 5.6)), _c(Color(0.42, 0.34, 0.24)), false, 0.7)
	for i: int in 3:
		var wx: float = -hl * 0.62 - float(i) * 2.6
		ci.draw_line(Vector2(wx, -fd_w * 0.8), Vector2(wx, fd_w * 0.8), _c(Color(0.3, 0.27, 0.22)), 0.45)
	# Forecastle with an AA mount ahead of the deck.
	_dot(ci, Vector2(hl * 0.86, 0.0), 1.4, Color(0.36, 0.37, 0.39))
	# Team roundel.
	_dot(ci, Vector2(hl * 0.58, 0.0), fd_w * 0.42, MARKING)
	_dot(ci, Vector2(hl * 0.58, 0.0), fd_w * 0.32, team_color)
	# Small island forward on the starboard edge, then four funnels in pairs.
	var iy: float = fd_w + 1.2
	_rect(ci, hl * 0.25, hl * 0.25 + 6.0, 1.5, SUPER_DARK, iy)
	_rect(ci, hl * 0.25 + 3.5, hl * 0.25 + 6.0, 1.8, Color(0.55, 0.57, 0.59), iy)
	for fx: float in [hl * 0.02, -hl * 0.1, -hl * 0.3, -hl * 0.42]:
		_oval(ci, Vector2(fx, iy + 1.6), 1.6, 1.1, FUNNEL)
		_oval(ci, Vector2(fx, iy + 2.1), 0.9, 0.6, FUNNEL_CAP)


## Resource Ship: a squat coastal collier. Bluff bow, three cargo hatches with derricks
## between them, bridge and funnel aft. Dark grey like the other small ships.
static func _resource_ship(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.55, -0.7, 0.75, 0.55)
	_base_hull(ci, hull, DARK_HULL, team_color)
	_poly(ci, _scaled(hull, 0.92, 0.8), MID_DECK)
	# Cargo hatches, each with its coaming and a load of ore showing.
	for x: float in [13.0, 4.0, -5.0]:
		_rect(ci, x - 3.4, x + 3.4, hw * 0.58, Color(0.2, 0.21, 0.22))
		_rect(ci, x - 2.6, x + 2.6, hw * 0.44, Color(0.42, 0.34, 0.26))
		for i: int in 3:
			_dot(ci, Vector2(x - 1.6 + float(i) * 1.6, (float(i) - 1.0) * hw * 0.15), 0.7, Color(0.3, 0.24, 0.18))
	# Derrick posts and booms between the hatches.
	for x: float in [8.5, -0.5]:
		_dot(ci, Vector2(x, 0.0), 1.1, Color(0.16, 0.16, 0.17))
		ci.draw_line(Vector2(x, 0.0), Vector2(x + 3.5, -hw * 0.5), _c(Color(0.55, 0.47, 0.25)), 0.7)
		ci.draw_line(Vector2(x, 0.0), Vector2(x - 3.5, hw * 0.5), _c(Color(0.55, 0.47, 0.25)), 0.7)
	# Bridge house and a single funnel aft.
	_rect(ci, -11.0, -17.0, hw * 0.7, SUPER_DARK)
	_rect(ci, -11.0, -12.5, hw * 0.82, Color(0.5, 0.52, 0.54))
	_funnel(ci, Vector2(-19.0, 0.0), 1.9, 1.7)
	_ensign(ci, -hl * 0.9, team_color, 1.4)


## Radar Ship: a destroyer-sized picket. No guns; a tall tripod mast forward carrying a
## big air-search mattress, a height-finder dish aft and a deckhouse full of plot rooms.
static func _radar_ship(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.38, -0.75, 0.55, 0.9)
	_base_hull(ci, hull, MID_HULL, team_color)
	_poly(ci, _scaled(hull, 0.93, 0.78), DARK_DECK)
	# Long deckhouse with the plot rooms.
	_rect(ci, -12.0, 8.0, hw * 0.55, SUPER_DARK)
	_rect(ci, 5.0, 8.0, hw * 0.7, Color(0.52, 0.54, 0.56))
	_funnel(ci, Vector2(-2.0, 0.0), 1.6, 1.4)
	# Tripod mast with the air-search array spread across the beam.
	var mast: Vector2 = Vector2(2.5, 0.0)
	for leg: Vector2 in [Vector2(4.5, -2.0), Vector2(4.5, 2.0), Vector2(0.5, 0.0)]:
		ci.draw_line(mast, leg, _c(Color(0.2, 0.2, 0.21)), 0.7)
	_rect(ci, 1.8, 3.2, hw * 1.15, Color(0.7, 0.72, 0.74))
	for i: int in 7:
		var y: float = lerpf(-hw * 1.05, hw * 1.05, float(i) / 6.0)
		ci.draw_line(Vector2(1.8, y), Vector2(3.2, y), _c(Color(0.35, 0.36, 0.38)), 0.4)
	_dot(ci, mast, 1.0, Color(0.85, 0.2, 0.15))
	# Height-finder dish aft.
	_oval(ci, Vector2(-9.0, 0.0), 2.6, 2.6, Color(0.66, 0.68, 0.7))
	_oval(ci, Vector2(-9.0, 0.0), 1.6, 1.6, Color(0.45, 0.47, 0.49))
	_dot(ci, Vector2(-9.0, 0.0), 0.5, Color(0.15, 0.15, 0.16))
	_ensign(ci, -hl * 0.8, team_color, 1.4)


## AA Cruiser: an Atlanta-type light cruiser with no main battery. Six twin dual-purpose
## mounts on the centreline (three stepped forward, three aft), two more on the wings,
## quad pom-poms down both sides and a pair of flak directors. All baked into the hull: the
## flak has no turrets to train.
static func _aa_cruiser(ci: CanvasItem, stats: ShipStats, team_color: Color) -> void:
	var hl: float = stats.hull_length * 0.5
	var hw: float = stats.hull_width * 0.5
	var hull: PackedVector2Array = _hull(hl, hw, 0.4, -0.7, 0.5, 0.85)
	_base_hull(ci, hull, MID_HULL, team_color)
	_poly(ci, _scaled(hull, 0.93, 0.8), MID_DECK)
	ci.draw_line(Vector2(-6.0, -hw * 0.8), Vector2(-6.0, hw * 0.8), _c(Color(0.18, 0.19, 0.2)), 0.6)
	# Tall bridge with a flak director on top, and a second director aft.
	_rect(ci, 4.0, 10.0, hw * 0.62, SUPER_DARK)
	_rect(ci, 8.0, 10.0, hw * 0.78, Color(0.55, 0.57, 0.59))
	_oval(ci, Vector2(6.0, 0.0), 1.8, 1.8, Color(0.7, 0.72, 0.74))
	_dot(ci, Vector2(6.0, 0.0), 0.7, Color(0.2, 0.2, 0.21))
	_rect(ci, -12.0, -15.5, hw * 0.5, SUPER_DARK)
	_oval(ci, Vector2(-13.8, 0.0), 1.6, 1.6, Color(0.7, 0.72, 0.74))
	_dot(ci, Vector2(-13.8, 0.0), 0.6, Color(0.2, 0.2, 0.21))
	# Two slim funnels amidships.
	_rect(ci, 1.5, -10.0, hw * 0.42, SUPER_DARK)
	_funnel(ci, Vector2(-0.5, 0.0), 1.9, 1.5)
	_funnel(ci, Vector2(-7.5, 0.0), 1.9, 1.5)
	# Twin dual-purpose mounts: pale houses, short high-angle barrels.
	var house: Color = Color(0.68, 0.7, 0.72)
	for x: float in [26.0, 20.5, 15.0]:
		_turret(ci, Vector2(x, 0.0), 0.0, 2.3, 2, 3.6, house)
	for x: float in [-19.5, -24.5, -29.0]:
		_turret(ci, Vector2(x, 0.0), PI, 2.3, 2, 3.6, house)
	for y: float in [-hw * 0.6, hw * 0.6]:
		_turret(ci, Vector2(-10.5, y), signf(y) * PI * 0.5, 1.9, 2, 3.0, house)
	# Quad pom-poms in tubs down both sides, and the team ensign aft.
	_aa_row(ci, -4.0, 12.0, hw * 0.66, 3, 1.1, Color(0.24, 0.25, 0.27))
	_aa_row(ci, -4.0, 12.0, hw * 0.66, 3, 0.6, GUN_LIGHT)
	_ensign(ci, -hl * 0.95, team_color, 1.5)
