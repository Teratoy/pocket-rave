shader_type canvas_item;
// Adds a per-human brightness lift and optional colour (the dresscode), so black sprites can still vary.
// Only the body takes them: near-black pixels. Anything drawn in a colour (a deal, a hat) stays as drawn.
// Smooths pixel edges like every other sprite (see smooth_pixels.gdshaderinc).

#include "res://scripts/smooth_pixels.gdshaderinc"

uniform float lift = 0.0;
uniform vec3 tint = vec3(0.0);

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 c = smooth_pixels(TEXTURE, UV);
	// Fully body up to about #0a0a0a, not at all from about #1f1f1f.
	float body = 1.0 - smoothstep(0.04, 0.12, max(c.r, max(c.g, c.b)));
	COLOR = c * modulate;
	COLOR.rgb += (lift + tint) * body;
}
