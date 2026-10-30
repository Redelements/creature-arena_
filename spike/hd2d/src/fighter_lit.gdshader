// HD-2D spike, Step 4b: a fighter frame on a vertical billboard quad, lit per pixel by the
// scene's lights from the sheet's normal map and glowing from its emissive sheet.
//
// The three sheets share one grid layout (cols x rows of frame_w x frame_h). `frame` picks
// the cell; `flip` mirrors it for a fighter facing left (the normal's x flips with it).
// The normal sheet holds screen normals (R right, G up, B toward the camera: tools/splat3d.py
// pack_normals), so they map straight onto the billboard's right / up / facing axes.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_nearest, repeat_disable;
uniform sampler2D emissive_tex : source_color, filter_nearest, repeat_disable;
uniform int cols = 12;
uniform int rows = 15;
uniform int frame = 0;
uniform bool flip = false;
uniform bool has_normal = true;
uniform bool has_emissive = true;
uniform float emissive_strength = 2.0;
uniform float normal_strength = 1.0;

varying vec3 v_right;
varying vec3 v_up;
varying vec3 v_fwd;

void vertex() {
	// A fixed-Y billboard, as StandardMaterial3D's BILLBOARD_FIXED_Y: the quad stands on its
	// base, turned about Y to face the camera (in the shadow pass, the light).
	vec3 cam_z = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), cam_z));
	mat4 bill = mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(cam_z, 0.0), MODEL_MATRIX[3]);
	mat4 sc = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bill * sc;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// The sheet's normal axes in view space: the quad's right, world up, toward the camera.
	v_right = normalize(mat3(VIEW_MATRIX) * right);
	v_up = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	v_fwd = normalize(mat3(VIEW_MATRIX) * cam_z);
}

void fragment() {
	vec2 cell = vec2(1.0 / float(cols), 1.0 / float(rows));
	vec2 local = UV;
	if (flip) {
		local.x = 1.0 - local.x;
	}
	int f = clamp(frame, 0, cols * rows - 1);
	vec2 uv = (vec2(float(f % cols), float(f / cols)) + local) * cell;
	vec4 c = texture(albedo_tex, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	if (has_normal) {
		vec4 n = texture(normal_tex, uv);
		if (n.a > 0.01) {
			vec3 sn = n.rgb * 2.0 - 1.0;
			if (flip) {
				sn.x = -sn.x;
			}
			sn = normalize(mix(vec3(0.0, 0.0, 1.0), sn, normal_strength));
			NORMAL = normalize(v_right * sn.x + v_up * sn.y + v_fwd * sn.z);
		} else {
			NORMAL = v_fwd;
		}
	} else {
		NORMAL = v_fwd;
	}
	if (has_emissive) {
		vec4 e = texture(emissive_tex, uv);
		EMISSION = e.rgb * e.a * emissive_strength;
	}
}
