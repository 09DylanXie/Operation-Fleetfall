class_name Ocean
extends ColorRect
## The animated sea under everything (shader-driven, cosmetic only). Covers the map plus a
## margin so the dark water beyond the rim is drawn by the same shader.

const SHADER_PATH: String = "res://assets/shaders/ocean.gdshader"
const MARGIN: float = 2500.0


func setup(map: MapData) -> void:
	position = Vector2(-MARGIN, -MARGIN)
	size = map.size + Vector2(MARGIN, MARGIN) * 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -20
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("margin", MARGIN)
	mat.set_shader_parameter("map_size", map.size)
	mat.set_shader_parameter("circular", map.circular)
	if map.circular:
		mat.set_shader_parameter("center", map.center())
		mat.set_shader_parameter("radius", map.radius())
	material = mat
