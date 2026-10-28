shader_type canvas_item;
// Adds a per-human brightness lift and optional colour, so black sprites can still vary.
// Smooths pixel edges like every other sprite (see smooth_pixels.gdshaderinc).

#include "res://scripts/smooth_pixels.gdshaderinc"

uniform float lift = 0.0;
uniform vec3 tint = vec3(0.0);

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	COLOR = smooth_pixels(TEXTURE, UV) * modulate;
	COLOR.rgb += lift + tint;
}
