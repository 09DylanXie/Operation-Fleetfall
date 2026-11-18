shader_type canvas_item;
// Animated open ocean: drifting colour swells, travelling wave crests, foam streaks and
// sun glints. The rect extends `margin` past the map on every side, so
// UV * rect_size - margin is the world position.

uniform vec2 rect_size = vec2(10000.0, 10000.0);
uniform float margin = 2000.0;
uniform vec2 map_size = vec2(6000.0, 6000.0);
uniform bool circular = true;
uniform vec2 center = vec2(3000.0, 3000.0);
uniform float radius = 3000.0;
uniform vec4 deep : source_color = vec4(0.035, 0.13, 0.23, 1.0);
uniform vec4 mid : source_color = vec4(0.06, 0.21, 0.33, 1.0);
uniform vec4 crest_color : source_color = vec4(0.55, 0.75, 0.86, 1.0);
uniform vec4 outside : source_color = vec4(0.025, 0.065, 0.11, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 w = UV * rect_size - vec2(margin);
	float t = TIME;
	float inside_d = circular ? length(w - center) - radius
		: max(max(-w.x, w.x - map_size.x), max(-w.y, w.y - map_size.y));
	if (inside_d > 0.0) {
		COLOR = outside;
	} else {
		vec2 p = w / 420.0;
		float big = fbm(p + vec2(t * 0.018, t * 0.011));
		float warp = fbm(p * 2.6 + vec2(-t * 0.035, t * 0.028) + big * 1.5);
		vec3 col = mix(deep.rgb, mid.rgb, smoothstep(0.25, 0.8, big));
		// Long swell bands rolling across the sea.
		float swell = sin(dot(w, vec2(0.6, 0.8)) / 55.0 + warp * 5.0 - t * 0.9);
		col += vec3(0.02, 0.035, 0.045) * swell;
		// Thin travelling wave crests.
		float crest = sin(dot(w, vec2(0.75, 0.66)) / 21.0 + warp * 9.0 - t * 1.7);
		float crest2 = sin(dot(w, vec2(-0.5, 0.86)) / 17.0 + big * 8.0 - t * 1.3);
		float lines = smoothstep(0.94, 1.0, crest) * smoothstep(0.45, 0.75, warp)
			+ smoothstep(0.96, 1.0, crest2) * smoothstep(0.5, 0.8, big) * 0.6;
		col = mix(col, crest_color.rgb, lines * 0.32);
		// Wind-blown foam flecks.
		float fleck = noise(w / 7.0 + vec2(t * 0.9, t * 0.4));
		col += vec3(0.5, 0.6, 0.65) * smoothstep(0.965, 1.0, fleck) * smoothstep(0.55, 0.85, warp) * 0.35;
		// Sun glints.
		float glint = noise(w / 3.5 - vec2(t * 0.6, -t * 0.8));
		col += vec3(0.7) * smoothstep(0.985, 1.0, glint) * 0.4;
		// Darker, deeper water toward the rim.
		col *= 1.0 - 0.28 * smoothstep(-260.0, 0.0, inside_d);
		COLOR = vec4(col, 1.0);
	}
}
