shader_type canvas_item;
render_mode blend_mul;
// A map's grade: a gentle colour multiply and a vignette, one full-screen rect under the
// HUD. The vignette is stepped (a few flat levels with an ordered-dither seam, one texel a
// canvas pixel), so it reads as pixel art, not a smooth gradient. Its middle leans toward
// the side the map's light comes from (`centre`, GradeView.centre_for), so the lit side of
// the screen stays open and the other falls off a little sooner: a light pool for free.

uniform vec3 tint = vec3(1.0);
uniform float vignette = 0.0;
uniform vec2 centre = vec2(0.5);
uniform vec2 canvas = vec2(480.0, 270.0);
uniform float levels = 5.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 px = floor(UV * canvas);
	vec2 q = (UV - centre) * 2.0;
	float d = length(q * vec2(0.8, 1.0));
	float v = smoothstep(0.55, 1.35, d);
	int i = (int(px.y) % 4) * 4 + int(px.x) % 4;
	float dith = (BAYER[i] + 0.5) / 16.0;
	float vq = floor(v * levels + dith) / levels;
	COLOR = vec4(tint * (1.0 - vignette * vq), 1.0);
}
