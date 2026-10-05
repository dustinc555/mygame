shader_type canvas_item;
render_mode unshaded;
uniform vec4 paper_color : source_color = vec4(0.776, 0.71, 0.553, 1.0);
float grain(vec2 p) { return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
void fragment() {
	float fine = grain(FRAGCOORD.xy) - 0.5;
	float fiber = grain(floor(FRAGCOORD.xy / vec2(3.0, 14.0))) - 0.5;
	float edge = min(min(UV.x, 1.0-UV.x), min(UV.y, 1.0-UV.y));
	float age = 1.0 - 0.09 * exp(-edge * 22.0);
	COLOR = vec4(paper_color.rgb * (age + fine * 0.035 + fiber * 0.018), 1.0);
}
