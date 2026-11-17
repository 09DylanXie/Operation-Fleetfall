class_name FogOverlay
extends ColorRect
## Renders the fog of war for the local team from VisionSystem's source list.

const SHADER_PATH: String = "res://assets/shaders/fog.gdshader"
const MAX_SOURCES: int = 96

var match_ref: Match = null
var _material: ShaderMaterial = null


func setup(p_match: Match) -> void:
	match_ref = p_match
	position = Vector2.ZERO
	size = p_match.map_data.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter("map_size", size)
	_material.set_shader_parameter("source_count", 0)
	material = _material
	visible = not p_match.spectator and p_match.local_team >= 0


func _process(_delta: float) -> void:
	if not visible or match_ref == null or match_ref.vision == null:
		return
	var sources: PackedVector3Array = match_ref.vision.fog_sources(match_ref.local_team)
	var padded: PackedVector3Array = PackedVector3Array()
	padded.resize(MAX_SOURCES)
	var count: int = mini(sources.size(), MAX_SOURCES)
	for i: int in count:
		padded[i] = sources[i]
	_material.set_shader_parameter("sources", padded)
	_material.set_shader_parameter("source_count", count)
