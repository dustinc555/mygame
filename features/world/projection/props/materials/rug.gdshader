shader_type spatial;
render_mode cull_disabled;

// The vendor cloth atlas has fabric in UV1 and a separate white motif in UV2.
// glTF's single base-color slot loses that layered material. Keep both maps;
// do not overwrite the vendor mesh/UVs or turn the whole rug into an icon mask.
uniform sampler2D cloth_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloth_normal : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloth_orm : filter_linear_mipmap, repeat_disable;
uniform vec4 fabric_color : source_color = vec4(0.48, 0.18, 0.12, 1.0);
uniform vec4 pattern_color : source_color = vec4(0.88, 0.67, 0.32, 1.0);

void fragment() {
	vec3 fabric = texture(cloth_texture, UV).rgb;
	vec3 mask = texture(cloth_texture, UV2).rgb;
	float motif = smoothstep(0.28, 0.62, min(min(mask.r, mask.g), mask.b));
	ALBEDO = fabric * mix(fabric_color.rgb, pattern_color.rgb, motif);
	NORMAL_MAP = texture(cloth_normal, UV).rgb;
	ROUGHNESS = max(0.85, texture(cloth_orm, UV).g);
}
