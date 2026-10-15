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
uniform float hue = 0.0;  // palette: the sprite's hues turned round the wheel (0..1)

vec3 hue_shift(vec3 c, float h) {
	// Rotate RGB about the grey axis: cheap and keeps brightness.
	float a = h * 6.28318;
	float cs = cos(a);
	float sn = sin(a);
	mat3 m = mat3(vec3(0.299, 0.587, 0.114), vec3(0.299, 0.587, 0.114), vec3(0.299, 0.587, 0.114))
		+ cs * mat3(vec3(0.701, -0.587, -0.114), vec3(-0.299, 0.413, -0.114), vec3(-0.3, -0.588, 0.886))
		+ sn * mat3(vec3(0.168, 0.33, -0.497), vec3(-0.328, 0.035, 0.292), vec3(1.25, -1.05, -0.203));
	return clamp(c * m, 0.0, 1.0);
}

void fragment() {
	if (hue > 0.0) {
		COLOR.rgb = hue_shift(COLOR.rgb, hue);
	}
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
