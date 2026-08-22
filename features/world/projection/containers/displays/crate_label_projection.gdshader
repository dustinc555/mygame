shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D label_texture : source_color, filter_linear_mipmap;
uniform vec2 label_half_size = vec2(0.075, 0.075);
uniform vec2 label_center = vec2(0.0, 0.17);

varying vec3 crate_local_position;
varying vec3 crate_local_normal;


void vertex() {
	crate_local_position = VERTEX;
	crate_local_normal = NORMAL;
}


void fragment() {
	vec4 base_color = texture(base_color_texture, UV);
	vec3 packed_surface = texture(orm_texture, UV).rgb;
	ALBEDO = base_color.rgb;
	METALLIC = packed_surface.b;
	ROUGHNESS = packed_surface.g;
	NORMAL_MAP = texture(normal_texture, UV).rgb;

	vec3 local_normal = normalize(crate_local_normal);
	if (abs(local_normal.z) > 0.55) {
		vec2 label_uv = (crate_local_position.xy - label_center) / (label_half_size * 2.0) + vec2(0.5);
		label_uv.y = 1.0 - label_uv.y;
		if (crate_local_position.z < 0.0) {
			label_uv.x = 1.0 - label_uv.x;
		}
		if (all(greaterThanEqual(label_uv, vec2(0.0))) && all(lessThanEqual(label_uv, vec2(1.0)))) {
			vec4 label = texture(label_texture, label_uv);
			ALBEDO = mix(ALBEDO, label.rgb, label.a);
		}
	}
}
