shader_type canvas_item;
render_mode blend_add, unshaded;
// One pass of BloomView's separable blur: 9 taps along `dir` (in texels of the source),
// Gaussian weights. The source holds premultiplied light (black where nothing glows), so
// the result is added: run along x into the second half-res viewport, then along y
// straight onto the screen (blend_add), times `strength`.

uniform vec2 dir = vec2(1.0, 0.0);
uniform float spread = 2.0;  // texels between taps
uniform float strength = 1.0;

void fragment() {
	vec2 step_uv = TEXTURE_PIXEL_SIZE * dir * spread;
	vec3 sum = texture(TEXTURE, UV).rgb * 0.2270;
	sum += (texture(TEXTURE, UV + step_uv).rgb + texture(TEXTURE, UV - step_uv).rgb) * 0.1945;
	sum += (texture(TEXTURE, UV + step_uv * 2.0).rgb + texture(TEXTURE, UV - step_uv * 2.0).rgb) * 0.1216;
	sum += (texture(TEXTURE, UV + step_uv * 3.0).rgb + texture(TEXTURE, UV - step_uv * 3.0).rgb) * 0.0540;
	sum += (texture(TEXTURE, UV + step_uv * 4.0).rgb + texture(TEXTURE, UV - step_uv * 4.0).rgb) * 0.0162;
	COLOR = vec4(sum * strength, 1.0);
}
