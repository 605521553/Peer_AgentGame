shader_type canvas_item;
render_mode unshaded;
uniform float color_levels : hint_range(8.0, 64.0) = 32.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.40;

void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	// Ordered 4x4 Bayer dither at the real 384x288 viewport resolution.
	ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) % 4;
	float bayer[16] = float[16](0.0,8.0,2.0,10.0,12.0,4.0,14.0,6.0,3.0,11.0,1.0,9.0,15.0,7.0,13.0,5.0);
	float d = (bayer[p.y * 4 + p.x] / 16.0 - 0.5) * dither_strength;
	vec3 rgb = floor(clamp(sample_color.rgb, vec3(0.0), vec3(1.0)) * color_levels + 0.5 + d) / color_levels;
	COLOR = vec4(rgb, 1.0);
}
