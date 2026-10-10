shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grain_repeat_meters : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float normal_strength : hint_range(0.0, 2.0, 0.05) = 0.7;
uniform float distance_detail_strength : hint_range(0.0, 1.0, 0.05) = 0.8;
uniform float marks_repeat_meters : hint_range(1.0, 20.0, 0.1) = 5.0;
uniform float detail_start_distance : hint_range(0.0, 20.0, 0.5) = 4.0;
uniform float detail_full_distance : hint_range(4.5, 60.0, 0.5) = 16.0;

varying vec3 world_texture_position;
varying vec3 blend_weights;

void vertex() {
	// Keep the accepted StandardMaterial3D world-triplanar orientation and tangent frame.
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	TANGENT = inverse(MODEL_NORMAL_MATRIX) * normalize(vec3(abs(n.y) + abs(n.z), 0.0, -abs(n.x)));
	BINORMAL = inverse(MODEL_NORMAL_MATRIX) * normalize(vec3(0.0, abs(n.x) + abs(n.z), -abs(n.y)));
	blend_weights = pow(abs(n), vec3(8.0));
	blend_weights /= dot(blend_weights, vec3(1.0));
	world_texture_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * vec3(1.0, -1.0, 1.0);
}

vec4 sample_world(sampler2D surface_map, vec3 p) {
	return texture(surface_map, p.xy) * blend_weights.z
		+ texture(surface_map, p.xz) * blend_weights.y
		+ texture(surface_map, p.zy * vec2(-1.0, 1.0)) * blend_weights.x;
}

void fragment() {
	vec3 fine_position = world_texture_position / grain_repeat_meters;
	vec3 original_albedo = sample_world(albedo_texture, fine_position).rgb;
	// Keep the accepted close-up surface. Blend a larger reading of the same
	// photographed trowel marks in smoothly; never replace or enlarge the fine normal map.
	float marks = sample_world(variation_texture, world_texture_position / marks_repeat_meters).r;
	float reading_blend = smoothstep(detail_start_distance, max(detail_full_distance, detail_start_distance + 0.1), length(VERTEX));
	float variation = (marks - 0.5) * 2.0;
	ALBEDO = original_albedo * (1.0 + variation * distance_detail_strength * reading_blend);
	ROUGHNESS = sample_world(roughness_texture, fine_position).r;
	SPECULAR = 0.25;
	METALLIC = 0.0;
	NORMAL_MAP = sample_world(normal_texture, fine_position).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	AO = sample_world(ao_texture, fine_position).r;
	AO_LIGHT_AFFECT = 0.0;
}
