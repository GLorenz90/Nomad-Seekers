// World-space grid for blockout geometry: thin lines every metre, bold lines
// every 4 m, so speed, jump height and gap distance are easy to judge.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.45, 0.47, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(0.3, 0.32, 0.35, 1.0);
uniform float cell_size = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 p, float size, float width_px) {
	vec2 coord = p / size;
	vec2 g = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.0001));
	return 1.0 - min(min(g.x, g.y) / width_px, 1.0);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	float minor = grid_line(p, cell_size, 1.0) * 0.5;
	float major = grid_line(p, cell_size * 4.0, 2.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, max(minor, major));
	ROUGHNESS = 0.9;
}
