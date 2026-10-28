shader_type canvas_item;
// Draws a sprite as a solid black silhouette with hard pixel edges,
// for the shadows (see shadows.gd), which fade it as a group.

void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, step(0.01, texture(TEXTURE, UV).a));
}
