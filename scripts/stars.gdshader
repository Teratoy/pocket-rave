shader_type canvas_item;
// Twinkles each star pixel in the starfield and slowly blinks a dim cross
// halo on the four pixels around it. Everything stays on the texture's own
// pixel grid. Any bright, opaque pixel counts as a star, so the art can be
// redrawn freely. Each star gets its own timing from where it sits.

uniform vec3 halo_color : source_color = vec3(0.30, 0.38, 0.62);
// Seconds for one halo blink, picked per star between these.
uniform float halo_period_min = 5.0;
uniform float halo_period_max = 9.0;
// Seconds for one twinkle, picked per star between these.
uniform float twinkle_period_min = 1.2;
uniform float twinkle_period_max = 2.6;
// Dimmest a star gets at the bottom of its twinkle.
uniform float twinkle_low = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

bool is_star(vec4 c) {
	return c.a > 0.5 && max(c.r, max(c.g, c.b)) > 0.5;
}

// 0..1 halo brightness for the star at this pixel. Dark for most of the
// cycle, then slowly swells and fades.
float halo(vec2 star) {
	float period = mix(halo_period_min, halo_period_max, hash(star + 17.0));
	float t = fract(TIME / period + hash(star));
	return pow(0.5 - 0.5 * cos(t * TAU), 3.0);
}

float twinkle(vec2 star) {
	float period = mix(twinkle_period_min, twinkle_period_max, hash(star + 41.0));
	float t = fract(TIME / period + hash(star + 5.0));
	return mix(twinkle_low, 1.0, 0.5 + 0.5 * cos(t * TAU));
}

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 cell = clamp(ivec2(floor(UV * vec2(size))), ivec2(0), size - 1);
	vec4 c = texelFetch(TEXTURE, cell, 0);

	if (is_star(c)) {
		// Pushed to white, then dimmed by the twinkle and lifted while the halo is lit.
		float b = min(twinkle(vec2(cell)) + 0.3 * halo(vec2(cell)), 1.0);
		COLOR = vec4(vec3(b), 1.0);
	} else {
		float h = 0.0;
		ivec2 sides[4] = { ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1) };
		for (int i = 0; i < 4; i++) {
			ivec2 n = cell + sides[i];
			if (all(greaterThanEqual(n, ivec2(0))) && all(lessThan(n, size))
					&& is_star(texelFetch(TEXTURE, n, 0))) {
				h = max(h, halo(vec2(n)));
			}
		}
		COLOR = vec4(max(c.rgb, halo_color * h), max(c.a, h));
	}
}
