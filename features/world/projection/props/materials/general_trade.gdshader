shader_type spatial;
render_mode cull_disabled;

uniform sampler2D emblem : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 wood_color : source_color = vec4(0.12, 0.09, 0.065, 1.0);
uniform vec4 paint_color : source_color = vec4(0.90, 0.84, 0.68, 1.0);
varying vec2 board_uv;
varying float face_weight;

void vertex() {
	// Local bounds of the inherited Sign_Pub face. Both sides share the
	// symmetric emblem; the bracket, chains and trim retain vendor materials.
	board_uv = vec2((VERTEX.x - 0.402612) / 0.691591, (0.188221 - VERTEX.y) / 0.535225);
	face_weight = abs(NORMAL.z);
}

void fragment() {
	float grain = sin(board_uv.y * 310.0 + sin(board_uv.x * 17.0) * 1.5);
	float fine_grain = sin(board_uv.y * 913.0 + board_uv.x * 29.0);
	float wear = smoothstep(0.65, 1.0, grain * fine_grain);
	float ink = texture(emblem, board_uv).a * smoothstep(0.8, 0.95, face_weight);
	vec3 wood = wood_color.rgb * (0.92 + 0.08 * grain);
	vec3 paint = paint_color.rgb * (1.0 - 0.22 * wear);
	ALBEDO = mix(wood, paint, ink);
	ROUGHNESS = 0.94;
}
