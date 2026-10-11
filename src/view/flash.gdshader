shader_type canvas_item;
// Tints a sprite toward flash_color (the white hit flash, the charge glow), and can
// draw a 1 px rim around its silhouette (Craglash's Stoneskin shield), and can turn it to
// grey stone (Hissy Fitz's Petrify Punch).

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(0.85, 0.85, 0.88, 1.0);
uniform float stone : hint_range(0.0, 1.0) = 0.0;
uniform bool ice = false;  // frozen in ice (Flavor Blast) rather than stone

void fragment() {
	if (stone > 0.0) {
		float l = dot(COLOR.rgb, vec3(0.3, 0.55, 0.15));
		vec3 rock = ice ? mix(vec3(0.42, 0.72, 0.84), vec3(0.9, 0.98, 1.0), l)
			: mix(vec3(0.36, 0.34, 0.32), vec3(0.82, 0.8, 0.76), l);
		COLOR.rgb = mix(COLOR.rgb, rock, stone);
	}
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash);
	if (rim > 0.0 && COLOR.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float n = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (n > 0.0) {
			COLOR = vec4(rim_color.rgb, rim);
		}
	}
}
