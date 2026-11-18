class_name ShipLayer
extends Node2D
## One drawing layer under a Ship, behind its guns and overlays. The BODY layer (hull,
## decks, superstructure) draws the baked hull sprite and is only re-tinted through
## `modulate`; the WAKE layer redraws every frame while the ship is under way.

enum Mode { WAKE, BODY }

var mode: Mode = Mode.BODY
var ship: Ship = null


func setup(p_ship: Ship, p_mode: Mode) -> void:
	ship = p_ship
	mode = p_mode
	show_behind_parent = true
	name = "Wake" if mode == Mode.WAKE else "Body"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(mode == Mode.WAKE)


func _ready() -> void:
	if mode == Mode.BODY and ship.match_ref != null and ship.match_ref.art_cache != null \
			and not ship.match_ref.art_cache.is_baked:
		ship.match_ref.art_cache.baked.connect(queue_redraw, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if ship.visible:
		queue_redraw()


func _draw() -> void:
	if ship == null or ship.stats == null:
		return
	if mode == Mode.BODY:
		var tex: Texture2D = ShipArt.baked.get(ShipArt.sprite_key(ship.stats.ship_class, ShipArt.SPRITE_BODY, ship.team))
		if tex != null:
			var size: Vector2 = tex.get_size() / ShipArt.BAKE_SCALE
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
		else:
			ShipArt.draw_body(self, ship.stats, Ship.TEAM_COLORS[ship.team], Color.WHITE)
	elif not ship.under_construction and ship.is_alive():
		ShipArt.draw_wake(self, ship.stats, ship.velocity.length(), ship.anim_time(), Color.WHITE)
