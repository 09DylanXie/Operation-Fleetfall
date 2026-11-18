class_name MapConfig
extends Resource
## Parameters for procedural archipelago generation. One preset per map size:
## res://data/maps/small.tres, res://data/map_config.tres (medium) and res://data/maps/large.tres.

enum Size { SMALL, MEDIUM, LARGE }

## Area of sea for a two-player match (historically the map rectangle). Maps are round:
## see size_for().
@export var map_size: Vector2 = Vector2(6400.0, 3600.0)
## Pathfinding cell size in px.
@export var cell_size: float = 32.0
## Navigation keeps hull centres at least this far from land.
@export var island_clearance: float = 40.0
## Distance of each Home Base from the rim of the sea.
@export var base_margin_x: float = 480.0
## Features generated per player: one wedge is generated and rotated round the centre.
@export var minor_per_side: int = 2
@export var major_per_side: int = 1
@export var center_major: bool = true
@export var cover_per_side: int = 6
@export var minor_radius: float = 80.0
@export var major_radius: float = 130.0
@export var cover_radius_min: float = 70.0
@export var cover_radius_max: float = 150.0
## Radius of the shallow-water zone around a Minor island.
@export var minor_shallow_radius: float = 330.0
## Open water kept between neighbouring features.
@export var feature_gap: float = 150.0
## Open water kept around each Home Base.
@export var base_clear_radius: float = 420.0


## Minor and Major islands on the whole map.
func capturable_islands(players: int = 2) -> int:
	return (minor_per_side + major_per_side) * players + (1 if center_major else 0)


## Bounding square of the round sea for `players` sides. The sea has the area of
## `map_size` for two players and grows in proportion with every extra player.
func size_for(players: int = 2) -> Vector2:
	var area: float = map_size.x * map_size.y * float(maxi(players, 2)) * 0.5
	var diameter: float = ceilf(2.0 * sqrt(area / PI) / cell_size) * cell_size
	return Vector2(diameter, diameter)
