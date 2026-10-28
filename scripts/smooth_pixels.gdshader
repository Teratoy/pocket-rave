shader_type canvas_item;
// Draws a sprite with its same coloured pixel edges smoothed.

#include "res://scripts/smooth_pixels.gdshaderinc"

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	COLOR = smooth_pixels(TEXTURE, UV) * modulate;
}
