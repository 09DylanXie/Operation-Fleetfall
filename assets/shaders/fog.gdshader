shader_type canvas_item;
// Fog of war: darkens everything outside the local team's vision circles.
// The rect covers the whole map, so UV * map_size is the world position.

const int MAX_SOURCES = 96;

uniform vec2 map_size = vec2(6400.0, 3600.0);
uniform int source_count = 0;
uniform vec3 sources[MAX_SOURCES];
uniform float fog_alpha = 0.62;
uniform float edge_softness = 60.0;

void fragment() {
	vec2 world = UV * map_size;
	float clear = 0.0;
	for (int i = 0; i < MAX_SOURCES; i++) {
		if (i >= source_count) {
			break;
		}
		float d = distance(world, sources[i].xy);
		clear = max(clear, 1.0 - smoothstep(sources[i].z - edge_softness, sources[i].z, d));
	}
	COLOR = vec4(0.01, 0.03, 0.06, fog_alpha * (1.0 - clear));
}
