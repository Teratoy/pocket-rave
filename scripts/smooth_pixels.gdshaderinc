// Redraws pixel art with smooth contours. Every run of connected pixels of
// similar colour (see blend_range) is treated as a region, so a shaded shape
// gets one outline rather than one per shade. Each region has a smooth
// field: the field is
// a cubic curve through "is this pixel that colour" over the 4x4 pixels
// around the point, and each point takes the colour whose field is
// strongest. Region edges come out as continuous curves with no corners.
// The curve is mostly a B-spline, which rounds shapes off, with enough
// Catmull-Rom, which passes through every pixel, that single pixels (stars,
// eyes) still win at their centre and survive as dots. Each sprite is
// smoothed in its own texture.

// The graphics setting that turns smoothing on or off (see smooth_pixels.gd).
global uniform bool pixel_smoothing;
// Texels per art pixel, for art that was scaled up before it got here.
uniform float pixel_scale = 1.0;
// When set, only textures of this size are smoothed and anything else drawn
// by the same item (such as a button's text) passes through untouched.
uniform ivec2 only_size = ivec2(0);
// Neighbouring opaque pixels closer in colour than this fade into each other
// instead of meeting at a hard edge, so shading bands read as gradients.
// Transparent pixels never blend, so a sprite never fades into what's behind.
// The moon and path shading steps are up to 0.115 apart; the booth's
// deliberate 0.156 steps stay crisp.
uniform float blend_range = 0.12;
// How far contours round off: 0 follows the pixels' steps closely, 1 is
// smoothest. Above about 0.9, single pixels would disappear.
uniform float roundness = 0.8;

// Pixels that show at all; only these belong to colour regions.
bool visible(vec4 a) {
	return a.a > 0.01;
}

bool similar_colour(vec4 a, vec4 b) {
	return visible(a) && visible(b) && distance(a.rgb, b.rgb) < max(blend_range, 0.02);
}

vec4 art_pixel(sampler2D tex, ivec2 size, ivec2 p) {
	ivec2 t = ivec2((vec2(p) + 0.5) * pixel_scale);
	return texelFetch(tex, clamp(t, ivec2(0), size - 1), 0);
}

// Weights of the pixels at -1, 0, 1 and 2 for a point t of the way from
// pixel 0 to pixel 1: Catmull-Rom mixed toward a B-spline by roundness.
vec4 cubic_weights(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	vec4 catmull_rom = vec4(
			-0.5 * t3 + t2 - 0.5 * t,
			1.5 * t3 - 2.5 * t2 + 1.0,
			-1.5 * t3 + 2.0 * t2 + 0.5 * t,
			0.5 * t3 - 0.5 * t2);
	float u = 1.0 - t;
	vec4 b_spline = vec4(
			u * u * u,
			3.0 * t3 - 6.0 * t2 + 4.0,
			-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0,
			t3) / 6.0;
	return mix(catmull_rom, b_spline, roundness);
}

// The colour of a region at this point: its nearest four pixels blended,
// using only those similar to it, so shading inside a region is smooth.
vec4 region_colour(vec4 near[4], vec2 t, vec4 colour) {
	float weights[4] = {(1.0 - t.x) * (1.0 - t.y), t.x * (1.0 - t.y), (1.0 - t.x) * t.y, t.x * t.y};
	vec4 sum = vec4(0.0);
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		if (similar_colour(near[i], colour)) {
			sum += near[i] * weights[i];
			total += weights[i];
		}
	}
	return total > 0.0 ? sum / total : colour;
}

vec4 smooth_pixels(sampler2D tex, vec2 uv) {
	ivec2 size = textureSize(tex, 0);
	// In pixel units, with pixel centres on whole numbers.
	vec2 p = uv * vec2(size) / pixel_scale - 0.5;
	// One screen pixel in field units, for antialiasing the chosen edge.
	// Taken before any branch so the derivative is defined.
	float aa = max(max(fwidth(p.x), fwidth(p.y)), 0.0001);
	if (!pixel_smoothing || (only_size.x > 0 && any(notEqual(size, only_size)))) {
		return texture(tex, uv);
	}

	vec2 cell = floor(p);
	vec2 t = p - cell;
	ivec2 base = ivec2(cell) - 1;
	vec4 wx = cubic_weights(t.x);
	vec4 wy = cubic_weights(t.y);
	float wxs[4] = {wx.x, wx.y, wx.z, wx.w};
	float wys[4] = {wy.x, wy.y, wy.z, wy.w};
	vec4 px[16];
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			px[j * 4 + i] = art_pixel(tex, size, base + ivec2(i, j));
		}
	}
	// The outline: a smooth field of the pixels' opacity, drawn where it
	// passes half the strongest opacity around, so hard edges and already
	// antialiased ones alike become clean curves.
	float coverage = 0.0;
	float peak = 0.0;
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			coverage += wxs[i] * wys[j] * px[j * 4 + i].a;
			peak = max(peak, px[j * 4 + i].a);
		}
	}
	if (peak < 0.01) {
		return vec4(0.0);
	}
	float mask = clamp((coverage - 0.5 * peak) / (aa * peak) + 0.5, 0.0, 1.0);
	// Colour comes only from solid pixels (as opaque as any around), not the
	// soft ones antialiasing an edge, whose colour is already blended.
	float solid = 0.99 * peak;
	// The point's colour belongs to one of its four nearest pixels' regions.
	vec4 near[4] = {px[5], px[6], px[9], px[10]};

	vec4 best = near[0];
	float best_field = -1e9;
	vec4 second = near[0];
	float second_field = -1e9;
	for (int k = 0; k < 4; k++) {
		vec4 candidate = near[k];
		if (candidate.a < solid) {
			continue;
		}
		bool seen = false;
		for (int m = 0; m < k; m++) {
			seen = seen || similar_colour(near[m], candidate);
		}
		if (seen) {
			continue;
		}
		float field = 0.0;
		for (int j = 0; j < 4; j++) {
			for (int i = 0; i < 4; i++) {
				if (similar_colour(px[j * 4 + i], candidate)) {
					field += wxs[i] * wys[j];
				}
			}
		}
		if (field > best_field) {
			second = best;
			second_field = best_field;
			best = candidate;
			best_field = field;
		} else if (field > second_field) {
			second = candidate;
			second_field = field;
		}
	}

	if (best_field < -1e8) {
		// Only soft pixels nearby: take the closest solid pixel's colour.
		float closest = 1e9;
		for (int j = 0; j < 4; j++) {
			for (int i = 0; i < 4; i++) {
				float dist = length(vec2(float(i - 1), float(j - 1)) - t);
				if (px[j * 4 + i].a >= solid && dist < closest) {
					closest = dist;
					best = px[j * 4 + i];
				}
			}
		}
	}

	vec4 colour = region_colour(near, t, best);
	if (second_field > -1e8) {
		// The two fields cross at the edge, closing at about one per pixel.
		float k = clamp((best_field - second_field) / aa, 0.0, 1.0);
		colour = mix(region_colour(near, t, second), colour, 0.5 + 0.5 * k);
	}
	colour.a *= mask;
	return colour;
}
