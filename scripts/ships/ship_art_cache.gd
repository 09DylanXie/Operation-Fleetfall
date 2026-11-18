class_name ShipArtCache
extends Node
## Renders every ship hull (one per class and side) and every gun house (one per class)
## into mipmapped textures once at the start of a match, then hands them to ShipArt.
## Until the bake finishes ships fall back to vector drawing. Cosmetic only.

signal baked

const PAD: float = 6.0

var is_baked: bool = false


class Drawer extends Node2D:
	var stats: ShipStats = null
	var kind: int = 0
	var team_color: Color = Color.WHITE
	var pixel_size: Vector2 = Vector2.ZERO

	func _draw() -> void:
		ShipArt.draw_for_bake(self, stats, kind, team_color, pixel_size)


## Baking needs a real renderer; headless runs (tests, servers) draw nothing anyway.
static func can_bake() -> bool:
	return DisplayServer.get_name() != "headless"


func bake(team_count: int) -> void:
	ShipArt.baked.clear()
	if not can_bake():
		return
	var jobs: Array[Array] = []
	for cls: ShipStats.ShipClass in GameData.all_classes():
		var stats: ShipStats = GameData.ship(cls)
		for team: int in team_count:
			var body: Vector2 = Vector2(stats.hull_length + PAD * 2.0, stats.hull_width + PAD * 2.0)
			jobs.append([ShipArt.sprite_key(cls, ShipArt.SPRITE_BODY, team),
				_viewport(stats, ShipArt.SPRITE_BODY, Ship.TEAM_COLORS[team], body)])
		if stats.gun_mounts > 0:
			var half: float = ShipArt.gun_sprite_half(cls, ShipArt.SPRITE_MAIN)
			jobs.append([ShipArt.sprite_key(cls, ShipArt.SPRITE_MAIN),
				_viewport(stats, ShipArt.SPRITE_MAIN, Color.WHITE, Vector2(half, half) * 2.0)])
		if stats.secondary_mounts > 0:
			var half: float = ShipArt.gun_sprite_half(cls, ShipArt.SPRITE_SECONDARY)
			jobs.append([ShipArt.sprite_key(cls, ShipArt.SPRITE_SECONDARY),
				_viewport(stats, ShipArt.SPRITE_SECONDARY, Color.WHITE, Vector2(half, half) * 2.0)])
	# Let the viewports render once, then copy them out (with mipmaps for zoomed-out views).
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for job: Array in jobs:
		var vp: SubViewport = job[1]
		var image: Image = vp.get_texture().get_image()
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			ShipArt.baked[job[0]] = ImageTexture.create_from_image(image)
		vp.queue_free()
	is_baked = true
	baked.emit()


func _viewport(stats: ShipStats, kind: int, team_color: Color, world_size: Vector2) -> SubViewport:
	var vp: SubViewport = SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size = Vector2i(ceili(world_size.x * ShipArt.BAKE_SCALE), ceili(world_size.y * ShipArt.BAKE_SCALE))
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var drawer: Drawer = Drawer.new()
	drawer.stats = stats
	drawer.kind = kind
	drawer.team_color = team_color
	drawer.pixel_size = Vector2(vp.size)
	vp.add_child(drawer)
	add_child(vp)
	return vp


func _exit_tree() -> void:
	ShipArt.baked.clear()
