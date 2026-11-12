// Darkness rooms (Part 11, reworked 2026-11-11): everything farther than
// `radius` from the Seeker is drawn black, so sight is genuinely short.
// A full-screen quad reads the depth buffer, rebuilds each pixel's world
// position and fades it out past the radius. The sky counts as infinitely far.
// Target rings and damage numbers draw after it (higher render priority), so
// targeting still reads through the dark.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 center = vec3(0.0);
uniform float radius = 8.0;
uniform float fade = 1.5;
uniform float strength = 1.0;

void vertex() {
	// Full-screen quad (QuadMesh 2 x 2), at the near plane (reversed Z).
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float d = depth <= 0.0 ? 1.0e6 : distance(world, center);
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(radius - fade, radius, d) * strength;
}
