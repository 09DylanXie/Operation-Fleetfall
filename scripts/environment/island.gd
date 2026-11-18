class_name Island
extends StaticBody2D
## Hard cover: blocks vision, shells and torpedoes. Minor and Major islands are
## also capturable resource nodes that can host a Shipyard.
##
## Only a neutral island can be captured (30 second hold). An island that already has an
## owner is defended by its IslandGarrison: the attacker must shoot that down to 0 HP,
## which turns the island neutral and destroys its shipyard.

signal owner_changed(island: Island, new_owner: int)

enum Kind { COVER, MINOR, MAJOR }

const CAPTURE_TICK: float = 0.2

var kind: Kind = Kind.COVER
var radius: float = 100.0
var shallow_radius: float = 0.0
var polygon: PackedVector2Array = PackedVector2Array()
## -1 while neutral.
var owner_team: int = -1
var capturing_team: int = -1
var capture_progress: float = 0.0
var contested: bool = false
var shipyard: Shipyard = null
## Created by the Match for capturable islands.
var garrison: IslandGarrison = null
## Times this island's garrison has been shot down.
var times_fallen: int = 0
## Radar bought by the owner (Major islands with a Tier 3 shipyard): DD-level spotting.
## Lost when the island changes hands.
var has_radar: bool = false
var match_ref: Match = null
var selected: bool = false
var _tick: float = 0.0


func setup(def: MapData.IslandDef, p_match: Match) -> void:
	kind = def.kind as Kind
	position = def.position
	radius = def.radius
	shallow_radius = def.shallow_radius
	polygon = def.polygon
	match_ref = p_match


func _ready() -> void:
	collision_layer = Layers.ISLANDS
	collision_mask = 0
	var collision: CollisionPolygon2D = get_node("Collision") as CollisionPolygon2D
	collision.polygon = polygon
	if match_ref == null or match_ref.create_ui:
		var terrain: IslandTerrain = IslandTerrain.new()
		terrain.name = "Terrain"
		terrain.setup(int(kind), radius, shallow_radius, polygon, position)
		add_child(terrain)
	if kind == Kind.MINOR and shallow_radius > 0.0:
		# Shallow water marker on its own layer; navigation enforces the draft rule.
		var area: Area2D = Area2D.new()
		area.name = "ShallowWater"
		area.collision_layer = Layers.SHALLOW
		area.collision_mask = 0
		area.monitoring = false
		var shape: CollisionShape2D = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = shallow_radius
		shape.shape = circle
		area.add_child(shape)
		add_child(area)
	if is_capturable():
		shipyard = Shipyard.new()
		shipyard.name = "Shipyard"
		shipyard.match_ref = match_ref
		shipyard.team = -1
		shipyard.tier = 0
		var balance: GameBalance = GameData.balance()
		shipyard.max_tier = balance.minor_shipyard_max_tier if kind == Kind.MINOR else balance.major_shipyard_max_tier
		shipyard.site_name = display_name()
		shipyard.site_position = position
		shipyard.site_radius = radius
		add_child(shipyard)
	else:
		set_physics_process(false)


func is_capturable() -> bool:
	return kind != Kind.COVER


func display_name() -> String:
	match kind:
		Kind.MINOR:
			return "Minor Island"
		Kind.MAJOR:
			return "Major Island"
	return "Island"


func capture_radius() -> float:
	var balance: GameBalance = GameData.balance()
	return balance.minor_capture_radius if kind == Kind.MINOR else balance.major_capture_radius


## True when this island runs an air base and can buy radar: a Major island whose
## shipyard has reached Tier 3.
func has_air_base() -> bool:
	return kind == Kind.MAJOR and owner_team >= 0 and shipyard != null and shipyard.tier >= 3


func spotting_range() -> float:
	var balance: GameBalance = GameData.balance()
	return balance.radar_spotting if has_radar else balance.island_spotting


## "" if `team` may buy radar here now, otherwise the reason it may not.
func radar_block_reason(team: int) -> String:
	if owner_team != team:
		return "Not your island"
	if kind != Kind.MAJOR:
		return "Radar can only be built on a Major island"
	if not has_air_base():
		return "Radar needs a Tier 3 shipyard on this island"
	if has_radar:
		return "This island already has radar"
	return ""


## Buys radar for `team`. Returns "" on success or the reason it was refused.
func try_buy_radar(team: int) -> String:
	var problem: String = radar_block_reason(team)
	if problem != "":
		return problem
	var balance: GameBalance = GameData.balance()
	if not match_ref.economy.spend(team, balance.radar_gold_cost, balance.radar_steel_cost):
		return "Not enough resources for radar (%dG / %dS)" % [balance.radar_gold_cost, balance.radar_steel_cost]
	has_radar = true
	queue_redraw()
	return ""


func income() -> Vector2i:
	var balance: GameBalance = GameData.balance()
	match kind:
		Kind.MINOR:
			return Vector2i(balance.minor_gold, balance.minor_steel)
		Kind.MAJOR:
			return Vector2i(balance.major_gold, balance.major_steel)
	return Vector2i.ZERO


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over or match_ref.replica:
		return
	_tick += delta
	if _tick >= CAPTURE_TICK:
		_tick -= CAPTURE_TICK
		_update_capture(CAPTURE_TICK)


## A team captures a neutral island by keeping combat-ready ships inside the radius,
## uncontested, for capture_time. An owned island is not captured: its garrison must fall.
func _update_capture(dt: float) -> void:
	var present: Array[int] = [0, 0, 0, 0]
	var r2: float = capture_radius() * capture_radius()
	for ship: Ship in match_ref.ships:
		# Non-combat hulls (Resource and Radar Ships) neither capture nor contest islands.
		if ship.is_combat_ready() and not ship.stats.is_support() and ship.position.distance_squared_to(position) <= r2:
			present[ship.team] += 1
	# Contested when two sides that are not allies are both here. Allies do not block
	# each other: the lowest-numbered side present takes the island.
	var team_here: int = -1
	contested = false
	for t: int in present.size():
		if present[t] <= 0:
			continue
		if team_here < 0:
			team_here = t
		elif match_ref.are_enemies(team_here, t):
			contested = true
	if contested:
		return
	if team_here == -1 or owner_team >= 0:
		capture_progress = maxf(0.0, capture_progress - dt)
		if capture_progress <= 0.0:
			capturing_team = -1
		return
	if capturing_team != team_here:
		capturing_team = team_here
		capture_progress = 0.0
	capture_progress += dt
	if capture_progress >= GameData.balance().capture_time:
		set_owner_team(team_here)


func set_owner_team(new_owner: int) -> void:
	if new_owner == owner_team:
		return
	owner_team = new_owner
	capture_progress = 0.0
	capturing_team = -1
	has_radar = false
	if shipyard != null:
		shipyard.reassign(new_owner)
	if garrison != null:
		garrison.assign(new_owner)
	owner_changed.emit(self, new_owner)
	queue_redraw()


## The garrison was shot down: the island and its shipyard are lost and it is neutral again.
func garrison_fell() -> void:
	times_fallen += 1
	set_owner_team(-1)


func _process(_delta: float) -> void:
	if is_capturable():
		queue_redraw()


func _draw() -> void:
	# The land itself is drawn once by the IslandTerrain child; this draws what changes.
	if polygon.size() < 3:
		return
	if not is_capturable():
		return
	DockArt.draw(self, shipyard, position, match_ref.local_team if match_ref != null else -1)
	var ring: Color = Color(0.8, 0.8, 0.8, 0.5)
	if owner_team >= 0:
		ring = Ship.TEAM_COLORS[owner_team]
		ring.a = 0.75
	draw_arc(Vector2.ZERO, capture_radius(), 0.0, TAU, 72, ring, 2.0 if not selected else 4.0)
	# Flag and shipyard tier pips.
	var flag: Color = Color(0.85, 0.85, 0.85) if owner_team < 0 else Ship.TEAM_COLORS[owner_team]
	draw_line(Vector2(0.0, 10.0), Vector2(0.0, -26.0), Color(0.15, 0.15, 0.15), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0.0, -26.0), Vector2(22.0, -19.0), Vector2(0.0, -12.0)]), flag)
	if shipyard != null:
		for i: int in shipyard.max_tier:
			var pip: Vector2 = Vector2(-12.0 + 12.0 * float(i), 24.0)
			draw_circle(pip, 4.5, Color(0.1, 0.1, 0.1))
			if i < shipyard.tier:
				draw_circle(pip, 3.2, Color(1.0, 0.85, 0.3))
	if capture_progress > 0.0 and capturing_team >= 0:
		var frac: float = clampf(capture_progress / GameData.balance().capture_time, 0.0, 1.0)
		var cap_color: Color = Ship.TEAM_COLORS[capturing_team]
		draw_arc(Vector2.ZERO, radius + 14.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, cap_color, 5.0)
	if has_radar:
		# Radar mast on the hill, with a slowly turning antenna.
		var mast: Vector2 = Vector2(-radius * 0.3, -radius * 0.25)
		draw_circle(mast, 5.0, Color(0.3, 0.31, 0.3))
		var sweep: float = Time.get_ticks_msec() * 0.0025
		draw_line(mast - Vector2.from_angle(sweep) * 9.0, mast + Vector2.from_angle(sweep) * 9.0,
			Color(0.8, 0.82, 0.84), 2.5)
	if garrison != null and garrison.is_alive() and match_ref.is_combatant_visible_to_local(garrison):
		# Garrison hit points, like the bar over a Home Base (shown to whoever can see the garrison).
		var bar_w: float = radius * 1.5
		var bar_pos: Vector2 = Vector2(-bar_w * 0.5, -radius - 30.0)
		var hp_frac: float = clampf(garrison.hp / garrison.max_hp, 0.0, 1.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, 6.0)), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_frac, 6.0)),
			Color(0.3, 0.9, 0.35) if hp_frac > 0.4 else Color(0.95, 0.3, 0.2))
	if contested:
		draw_arc(Vector2.ZERO, radius + 22.0, 0.0, TAU, 48, Color(1.0, 0.9, 0.2, 0.8), 2.0)
