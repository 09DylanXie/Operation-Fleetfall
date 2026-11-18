class_name MapData
extends RefCounted
## Plain description of one generated map. The Match turns this into nodes;
## NavGrid turns it into pathfinding grids.

class IslandDef extends RefCounted:
	## Matches Island.Kind: 0 = COVER, 1 = MINOR, 2 = MAJOR.
	var kind: int = 0
	var position: Vector2 = Vector2.ZERO
	var radius: float = 100.0
	var shallow_radius: float = 0.0
	## Outline in island-local coordinates.
	var polygon: PackedVector2Array = PackedVector2Array()

const KIND_COVER: int = 0
const KIND_MINOR: int = 1
const KIND_MAJOR: int = 2

var size: Vector2 = Vector2(6400.0, 3600.0)
## Generated maps are a round sea inscribed in `size` (a square); hand-built test maps
## may stay rectangular.
var circular: bool = false
var seed_used: int = 0
var cell_size: float = 32.0
var clearance: float = 40.0
var base_radius: float = 80.0
var base_positions: Array[Vector2] = []
var islands: Array[IslandDef] = []


func add_island(kind: int, position: Vector2, radius: float, shallow_radius: float,
		polygon: PackedVector2Array) -> IslandDef:
	var def: IslandDef = IslandDef.new()
	def.kind = kind
	def.position = position
	def.radius = radius
	def.shallow_radius = shallow_radius
	def.polygon = polygon
	islands.append(def)
	return def


## Regular polygon outline, used by tests and as a fallback shape.
static func circle_polygon(radius: float, points: int = 14) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		poly.append(Vector2.from_angle(TAU * float(i) / float(points)) * radius)
	return poly


func center() -> Vector2:
	return size * 0.5


## Radius of the sea on a circular map.
func radius() -> float:
	return minf(size.x, size.y) * 0.5


## True for points inside the playable sea, at least `margin` from its edge.
func contains(point: Vector2, margin: float = 0.0) -> bool:
	if circular:
		return point.distance_to(center()) <= radius() - margin
	return point.x >= margin and point.y >= margin and point.x <= size.x - margin and point.y <= size.y - margin


## A random point of a circular map, no further than `reach` (0-1) of the way to the rim.
func random_point(rng: RandomNumberGenerator, reach: float) -> Vector2:
	return center() + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius() * reach
