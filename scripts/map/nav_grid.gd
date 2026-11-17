class_name NavGrid
extends RefCounted
## Two pathfinding grids over the same map:
##  - shallow-draft hulls (DD, SS) are blocked only by land;
##  - deep-draft hulls (CL, CA, BB, CV) are also blocked by shallow water.

const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const MAX_FREE_SEARCH_RINGS: int = 40
const SEGMENT_MARGIN_CELLS: float = 0.3

var cell_size: float = 32.0
var size_cells: Vector2i = Vector2i.ZERO
var _shallow_grid: AStarGrid2D = AStarGrid2D.new()
var _deep_grid: AStarGrid2D = AStarGrid2D.new()


static func from_map(map: MapData) -> NavGrid:
	var nav: NavGrid = NavGrid.new()
	nav.setup(map.size, map.cell_size)
	for def: MapData.IslandDef in map.islands:
		var world_poly: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in def.polygon:
			world_poly.append(p + def.position)
		nav.block_polygon(world_poly, map.clearance)
		if def.kind == MapData.KIND_MINOR and def.shallow_radius > 0.0:
			nav.block_circle(def.position, def.shallow_radius, true)
	for base_pos: Vector2 in map.base_positions:
		nav.block_circle(base_pos, map.base_radius + map.clearance, false)
	return nav


func setup(map_size: Vector2, p_cell_size: float) -> void:
	cell_size = p_cell_size
	size_cells = Vector2i(int(map_size.x / cell_size), int(map_size.y / cell_size))
	for grid: AStarGrid2D in [_shallow_grid, _deep_grid]:
		grid.region = Rect2i(Vector2i.ZERO, size_cells)
		grid.cell_size = Vector2(cell_size, cell_size)
		grid.offset = Vector2(cell_size, cell_size) * 0.5
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()


func _grid_for(shallow_draft: bool) -> AStarGrid2D:
	return _shallow_grid if shallow_draft else _deep_grid


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size_cells.x and cell.y < size_cells.y


func to_cell(point: Vector2) -> Vector2i:
	return Vector2i(int(floor(point.x / cell_size)), int(floor(point.y / cell_size)))


func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


## Blocks every cell whose centre is inside the polygon or within `clearance` of its edge.
func block_polygon(world_polygon: PackedVector2Array, clearance: float) -> void:
	if world_polygon.size() < 3:
		return
	var min_p: Vector2 = world_polygon[0]
	var max_p: Vector2 = world_polygon[0]
	for p: Vector2 in world_polygon:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var lo: Vector2i = to_cell(min_p - Vector2(clearance, clearance))
	var hi: Vector2i = to_cell(max_p + Vector2(clearance, clearance))
	var count: int = world_polygon.size()
	for cy: int in range(lo.y, hi.y + 1):
		for cx: int in range(lo.x, hi.x + 1):
			var cell: Vector2i = Vector2i(cx, cy)
			if not in_bounds(cell):
				continue
			var c: Vector2 = cell_center(cell)
			var blocked: bool = Geometry2D.is_point_in_polygon(c, world_polygon)
			if not blocked:
				for i: int in count:
					var a: Vector2 = world_polygon[i]
					var b: Vector2 = world_polygon[(i + 1) % count]
					var closest: Vector2 = Geometry2D.get_closest_point_to_segment(c, a, b)
					if closest.distance_to(c) < clearance:
						blocked = true
						break
			if blocked:
				_shallow_grid.set_point_solid(cell, true)
				_deep_grid.set_point_solid(cell, true)


## Blocks cells within `radius`. With deep_only the area stays open to shallow-draft hulls.
func block_circle(center: Vector2, radius: float, deep_only: bool) -> void:
	var lo: Vector2i = to_cell(center - Vector2(radius, radius))
	var hi: Vector2i = to_cell(center + Vector2(radius, radius))
	var r2: float = radius * radius
	for cy: int in range(lo.y, hi.y + 1):
		for cx: int in range(lo.x, hi.x + 1):
			var cell: Vector2i = Vector2i(cx, cy)
			if not in_bounds(cell):
				continue
			if cell_center(cell).distance_squared_to(center) <= r2:
				_deep_grid.set_point_solid(cell, true)
				if not deep_only:
					_shallow_grid.set_point_solid(cell, true)


func is_blocked(point: Vector2, shallow_draft: bool) -> bool:
	var cell: Vector2i = to_cell(point)
	if not in_bounds(cell):
		return true
	return _grid_for(shallow_draft).is_point_solid(cell)


## True for water only shallow-draft hulls may enter.
func is_shallow_water(point: Vector2) -> bool:
	var cell: Vector2i = to_cell(point)
	if not in_bounds(cell):
		return false
	return _deep_grid.is_point_solid(cell) and not _shallow_grid.is_point_solid(cell)


func _nearest_free_cell(cell: Vector2i, grid: AStarGrid2D) -> Vector2i:
	var start: Vector2i = Vector2i(
		clampi(cell.x, 0, size_cells.x - 1), clampi(cell.y, 0, size_cells.y - 1))
	if not grid.is_point_solid(start):
		return start
	for ring: int in range(1, MAX_FREE_SEARCH_RINGS + 1):
		var best: Vector2i = INVALID_CELL
		var best_d: float = INF
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c: Vector2i = start + Vector2i(dx, dy)
				if not in_bounds(c) or grid.is_point_solid(c):
					continue
				var d: float = float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = c
		if best != INVALID_CELL:
			return best
	return INVALID_CELL


## Closest navigable point to `point` for the given draft (the point itself if already free).
func nearest_free(point: Vector2, shallow_draft: bool) -> Vector2:
	if not is_blocked(point, shallow_draft):
		return point
	var cell: Vector2i = _nearest_free_cell(to_cell(point), _grid_for(shallow_draft))
	if cell == INVALID_CELL:
		return point
	return cell_center(cell)


## True if a hull can sail straight from a to b. The corridor is checked along
## three parallel lines so a ship that drifts slightly off the line while turning
## still cannot clip the corner of a blocked cell.
func _segment_clear(a: Vector2, b: Vector2, grid: AStarGrid2D) -> bool:
	var length: float = a.distance_to(b)
	var steps: int = maxi(1, int(ceil(length / (cell_size * 0.4))))
	var side: Vector2 = Vector2.ZERO
	if length > 0.001:
		side = (b - a).orthogonal() / length * (cell_size * SEGMENT_MARGIN_CELLS)
	for i: int in range(0, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		for offset: Vector2 in [Vector2.ZERO, side, -side]:
			var cell: Vector2i = to_cell(p + offset)
			if not in_bounds(cell) or grid.is_point_solid(cell):
				return false
	return true


func is_reachable(from: Vector2, to: Vector2, shallow_draft: bool) -> bool:
	var grid: AStarGrid2D = _grid_for(shallow_draft)
	var a: Vector2i = _nearest_free_cell(to_cell(from), grid)
	var b: Vector2i = _nearest_free_cell(to_cell(to), grid)
	if a == INVALID_CELL or b == INVALID_CELL:
		return false
	if a == b:
		return true
	return not grid.get_id_path(a, b).is_empty()


## Waypoints from `from` to `to` (excluding the start). Empty if no route exists.
## If the goal is blocked or cut off the path ends at the closest reachable point.
func find_path(from: Vector2, to: Vector2, shallow_draft: bool) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var grid: AStarGrid2D = _grid_for(shallow_draft)
	var a: Vector2i = _nearest_free_cell(to_cell(from), grid)
	var b: Vector2i = _nearest_free_cell(to_cell(to), grid)
	if a == INVALID_CELL or b == INVALID_CELL:
		return result
	var goal: Vector2 = to if (to_cell(to) == b and in_bounds(to_cell(to))) else cell_center(b)
	if a == b:
		result.append(goal)
		return result
	var ids: Array[Vector2i] = grid.get_id_path(a, b)
	if ids.is_empty():
		ids = grid.get_id_path(a, b, true)
		if ids.is_empty():
			return result
		goal = cell_center(ids[ids.size() - 1])
	var points: PackedVector2Array = PackedVector2Array()
	for id: Vector2i in ids:
		points.append(cell_center(id))
	points[points.size() - 1] = goal
	# String-pull: skip waypoints while a straight run stays in open water.
	# The farthest visible waypoint is found by bisection, which keeps long routes cheap.
	var anchor: Vector2 = from if not grid.is_point_solid(to_cell_clamped(from)) else points[0]
	var i: int = 0
	var last: int = points.size() - 1
	while i <= last:
		var lo: int = i
		var hi: int = last
		while lo < hi:
			var mid: int = (lo + hi + 1) >> 1
			if _segment_clear(anchor, points[mid], grid):
				lo = mid
			else:
				hi = mid - 1
		result.append(points[lo])
		anchor = points[lo]
		i = lo + 1
	return result


func to_cell_clamped(point: Vector2) -> Vector2i:
	var cell: Vector2i = to_cell(point)
	return Vector2i(clampi(cell.x, 0, size_cells.x - 1), clampi(cell.y, 0, size_cells.y - 1))
