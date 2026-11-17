class_name MapConfig
extends Resource
## Parameters for procedural archipelago generation. One preset per map size:
## res://data/maps/small.tres, res://data/map_config.tres (medium) and res://data/maps/large.tres.

enum Size { SMALL, MEDIUM, LARGE }

@export var map_size: Vector2 = Vector2(6400.0, 3600.0)
## Pathfinding cell size in px.
@export var cell_size: float = 32.0
## Navigation keeps hull centres at least this far from land.
@export var island_clearance: float = 40.0
## Distance of each Home Base from its map edge.
@export var base_margin_x: float = 480.0
## Features generated on one half of the map; the other half is a point mirror.
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
func capturable_islands() -> int:
	return (minor_per_side + major_per_side) * 2 + (1 if center_major else 0)
