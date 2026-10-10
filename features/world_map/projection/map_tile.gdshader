shader_type canvas_item;
render_mode unshaded;
uniform sampler2D discovery_mask : filter_linear, repeat_disable;
uniform bool discovery_enabled = true;
void fragment() {
	vec4 terrain = texture(TEXTURE, UV);
	float known = discovery_enabled ? texture(discovery_mask, UV).r : 1.0;
	// Soft cartographic edge, but zero disclosure outside explored ground.
	terrain.a *= smoothstep(0.15, 0.85, known);
	COLOR = terrain;
}
