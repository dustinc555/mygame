shader_type sky;
render_mode use_half_res_pass;

// Only atmosphere/nebula/clouds use the soft half-resolution pass. Celestial
// silhouettes, surface maps and stars are evaluated at the actual screen resolution.
// No TIME or POSITION: world time owns pause/load and camera travel has no parallax.
uniform sampler2D planet_surface : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moon_surface : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ring_profile : source_color, filter_linear_mipmap, repeat_disable;
uniform float ring_inner_radius = 1.18;
uniform float ring_outer_radius = 1.68;
uniform float ring_density = 1.0;
uniform float ring_brightness = 1.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 planet_direction = vec3(0.5, 0.5, -0.707);
uniform mat3 planet_basis = mat3(1.0);
uniform mat3 star_basis = mat3(1.0);
uniform float planet_radius = 0.4848;
uniform float moon_radius = 0.02269;
uniform float sun_radius = 0.00611;
uniform float planet_spin = 0.0;
uniform float day_amount = 0.0;
uniform float night_amount = 1.0;
uniform float twilight_amount = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float aurora_phase = 0.0;
uniform float nebula_brightness = 0.65;
uniform float nebula_coverage = 0.55;
uniform vec4 nebula_teal : source_color = vec4(0.17, 0.63, 0.65, 1.0);
uniform vec4 nebula_violet : source_color = vec4(0.48, 0.23, 0.64, 1.0);
uniform float star_brightness = 1.0;
uniform float cloud_coverage = 0.28;
uniform float aurora_brightness = 0.16;


float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 hash23(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yzz) * q.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
		mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
		mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amplitude = 0.54;
	for (int i = 0; i < 5; i++) {
		sum += amplitude * noise3(p);
		p = p * 2.03 + vec3(17.13, 9.21, 5.47);
		amplitude *= 0.48;
	}
	return sum;
}

vec3 atmosphere(vec3 d) {
	float altitude = max(d.y, 0.0);
	float horizon = exp(-altitude * 4.8);
	vec3 night = mix(vec3(0.0025, 0.0038, 0.009), vec3(0.013, 0.019, 0.030), horizon);
	vec3 daylight = mix(vec3(0.085, 0.22, 0.43), vec3(0.43, 0.55, 0.65), horizon);
	float toward_sun = dot(normalize(d.xz + vec2(0.0001)), normalize(sun_direction.xz + vec2(0.0001)));
	float sunset = pow(max(toward_sun * 0.5 + 0.5, 0.0), 5.0) * exp(-altitude * 3.2);
	vec3 dusk = mix(vec3(0.038, 0.028, 0.080), vec3(0.29, 0.075, 0.027), sunset);
	vec3 color = mix(night, dusk, twilight_amount);
	color = mix(color, daylight, day_amount);
	float angle = acos(clamp(dot(d, sun_direction), -1.0, 1.0));
	float haze = exp(-angle * 10.0) * 0.22 + exp(-angle * 2.5) * 0.018;
	color += mix(vec3(1.0, 0.37, 0.10), vec3(1.0, 0.89, 0.67), day_amount) * haze * smoothstep(-0.12, 0.04, sun_direction.y);
	return color;
}

vec3 nebula(vec3 d) {
	vec3 p = star_basis * d;
	// A broad tilted star river encircles the sphere, with independent structures
	// outside the river. Domain-space noise has no panorama seam or pole smear.
	float latitude = dot(p, normalize(vec3(0.42, 0.76, 0.50)));
	float river = exp(-pow(abs(latitude) * 2.9, 1.35));
	vec3 q = p * 3.0;
	float warp = fbm(q + vec3(8.1, 2.7, 15.9));
	float broad = fbm(q * 1.9 + vec3(warp * 2.3, warp, -warp));
	float filaments = fbm(q * 6.1 + vec3(broad * 4.0, warp * 3.0, 7.0));
	float clouds = smoothstep(0.56 - nebula_coverage * 0.20, 0.79, broad) * (0.18 + river * 1.25);
	float ridge = pow(max(1.0 - abs(filaments * 2.0 - 1.0), 0.0), 7.0);
	float dust = smoothstep(0.40, 0.66, fbm(q * 2.8 + vec3(23.0, 4.0, 9.0)));
	float extinction = exp(-dust * dust * 7.0);
	float hue = smoothstep(0.30, 0.73, noise3(p * 2.5 + vec3(4.0, 8.0, 13.0)));
	vec3 color = mix(nebula_teal.rgb, nebula_violet.rgb, hue);
	vec3 luminous = color * clouds * (0.50 + ridge * 1.6) * extinction;
	luminous += vec3(0.22, 0.29, 0.38) * river * pow(max(filaments - 0.36, 0.0), 2.0) * extinction * 0.16;
	// Nearby auroral veils, not implausibly fast deformation of a distant nebula.
	float curtain = p.y - 0.43 - sin(p.x * 4.0 + p.z * 2.0 + aurora_phase) * 0.13;
	float veil = exp(-abs(curtain) * 25.0) * pow(noise3(p * 24.0 + vec3(sin(aurora_phase), cos(aurora_phase), 0.0)), 3.0);
	luminous += vec3(0.06, 0.29, 0.23) * veil * aurora_brightness;
	return luminous * nebula_brightness * 2.6;
}

float cloud_density(vec3 d) {
	if (d.y <= 0.0 || cloud_coverage <= 0.0) {
		return 0.0;
	}
	vec3 p = vec3(d.x / (d.y + 0.25), 0.34, d.z / (d.y + 0.25));
	p.xz += cloud_offset;
	float large = fbm(p * 1.5);
	float small = noise3(p * 16.0 + vec3(11.0));
	float coverage = smoothstep(0.72 - cloud_coverage * 0.38, 0.89 - cloud_coverage * 0.30, large + small * 0.09);
	return coverage * smoothstep(0.0, 0.15, d.y) * 0.76;
}

vec3 cloud_color(vec3 d) {
	float edge = pow(max(dot(d, sun_direction), 0.0), 12.0);
	vec3 daylight = mix(vec3(0.45, 0.54, 0.62), vec3(1.0, 0.94, 0.81), edge);
	vec3 dusk = mix(vec3(0.08, 0.06, 0.10), vec3(0.65, 0.24, 0.065), edge);
	return mix(mix(vec3(0.012, 0.017, 0.027), dusk, twilight_amount), daylight, day_amount);
}

// Cube-face star placement avoids stretched equirectangular stars near the poles.
vec3 star_field(vec3 direction) {
	vec3 d = star_basis * direction;
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= max(a.y, a.z)) {
		uv = d.yz / a.x;
		face = sign(d.x) * 7.0;
	} else if (a.y >= a.z) {
		uv = d.xz / a.y;
		face = sign(d.y) * 17.0;
	} else {
		uv = d.xy / a.z;
		face = sign(d.z) * 29.0;
	}
	vec3 color = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 160.0 : 340.0;
		vec2 cell = uv * scale;
		vec2 id = floor(cell);
		vec3 seed = hash23(id + vec2(face, float(layer) * 43.7));
		vec2 offset = fract(cell) - (vec2(0.25) + seed.xy * 0.5);
		float footprint = max(length(fwidth(cell)), 0.10);
		float radius = max(0.045, footprint * 0.38);
		float disk = exp(-dot(offset, offset) / (radius * radius));
		float present = step(layer == 0 ? 0.986 : 0.992, seed.z);
		// Independent brightness distribution: a few landmarks among faint stars,
		// not thousands of equally bright pixels competing with the giant.
		float brightness = layer == 0 ? 0.35 + pow(seed.y, 5.0) * 1.6 : 0.16;
		vec3 tint = mix(vec3(0.69, 0.79, 1.0), vec3(1.0, 0.84, 0.62), seed.x);
		color += tint * disk * present * brightness;
	}
	return color * star_brightness;
}

vec2 sphere_uv(vec3 n) {
	return vec2(atan(n.z, n.x) / TAU + 0.5, acos(clamp(n.y, -1.0, 1.0)) / PI);
}

// Analytic spheres live only in this directional sky calculation. Their virtual
// distances never enter the world's depth buffer or depend on the camera position.
float sphere_hit(vec3 ray, vec3 center, float radius) {
	float b = dot(ray, center);
	float h = b * b - dot(center, center) + radius * radius;
	if (h < 0.0 || b <= 0.0) {
		return -1.0;
	}
	return b - sqrt(h);
}

vec4 ring_sample(float radius) {
	float span = max(ring_outer_radius - ring_inner_radius, 0.01);
	return texture(ring_profile, vec2((radius - ring_inner_radius) / span, 0.5));
}

float ring_optical_depth(float opacity) {
	return -log(max(1.0 - opacity, 0.001)) * ring_density;
}

float ring_shadow(vec3 point, vec3 axis) {
	float denominator = dot(sun_direction, axis);
	if (abs(denominator) < 0.001) {
		return 1.0;
	}
	float distance = -dot(point, axis) / denominator;
	if (distance <= 0.002) {
		return 1.0;
	}
	float radius = length(point + sun_direction * distance);
	if (radius <= ring_inner_radius || radius >= ring_outer_radius) {
		return 1.0;
	}
	float depth = ring_optical_depth(ring_sample(radius).a);
	return exp(-depth / max(abs(denominator), 0.025));
}

vec3 giant_world(vec3 color, vec3 d) {
	vec3 center = planet_direction / max(planet_radius, 0.01);
	vec3 axis = planet_basis[1];
	float hit = sphere_hit(d, center, 1.0);
	if (hit > 0.0) {
		vec3 n = normalize(d * hit - center);
		vec3 local = transpose(planet_basis) * n;
		vec2 uv = sphere_uv(local);
		uv.x += planet_spin;
		vec3 albedo = texture(planet_surface, uv).rgb;
		float incidence = max(dot(n, sun_direction), 0.0);
		float diffuse = pow(incidence, 0.78) * ring_shadow(n, axis);
		float limb = pow(1.0 - max(dot(n, -d), 0.0), 3.5);
		vec3 surface = albedo * (diffuse * 1.7 + 0.0025);
		// Thin illuminated atmosphere, never a broad uniform halo on the dark side.
		surface += vec3(0.12, 0.31, 0.47) * limb * smoothstep(-0.15, 0.45, dot(n, sun_direction)) * 0.28;
		color = surface;
	}
	float denominator = dot(d, axis);
	if (abs(denominator) > 0.0001) {
		float distance = dot(center, axis) / denominator;
		vec3 point = d * distance - center;
		float radius = length(point);
		if (distance > 0.0 && (hit < 0.0 || distance < hit) && radius > ring_inner_radius && radius < ring_outer_radius) {
			vec4 ring = ring_sample(radius);
			float depth = ring_optical_depth(ring.a);
			float view_cosine = max(abs(denominator), 0.025);
			float sun_cosine = max(abs(dot(axis, sun_direction)), 0.025);
			float opacity = 1.0 - exp(-depth / view_cosine);
			// Single-scattered light through a thin particle layer. The unlit face
			// transmits light through sparse dust instead of glowing like a solid disc.
			float reflection = sun_cosine / (sun_cosine + view_cosine)
				* (1.0 - exp(-depth * (1.0 / sun_cosine + 1.0 / view_cosine)));
			float difference = sun_cosine - view_cosine;
			float transmission;
			if (abs(difference) < 0.001) {
				transmission = depth / view_cosine * exp(-depth / view_cosine);
			} else {
				transmission = sun_cosine / difference
					* (exp(-depth / sun_cosine) - exp(-depth / view_cosine));
			}
			bool lit_face = dot(axis, sun_direction) * dot(axis, -d) > 0.0;
			float scattering = lit_face ? reflection : transmission * 0.65;
			float b = dot(point, sun_direction);
			float closest = sqrt(max(dot(point, point) - b * b, 0.0));
			float penumbra = 0.006 + max(-b, 0.0) * sun_radius;
			float shadow = b < 0.0 ? smoothstep(1.0 - penumbra, 1.0 + penumbra, closest) : 1.0;
			vec3 light = ring.rgb * (scattering * shadow * 1.8 + opacity * 0.012) * ring_brightness;
			color = color * (1.0 - opacity) + light;
		}
	}
	return color;
}

vec3 rocky_moon(vec3 color, vec3 d) {
	float hit = sphere_hit(d, moon_direction, moon_radius);
	if (hit <= 0.0) {
		return color;
	}
	vec3 n = normalize(d * hit - moon_direction);
	vec3 albedo = texture(moon_surface, sphere_uv(n)).rgb;
	float incidence = max(dot(n, sun_direction), 0.0);
	// Airless, rough diffuse rock, with only faint reflected light on the night side.
	float earthshine = 0.002;
	return albedo * (pow(incidence, 0.65) * 2.0 + earthshine);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 air = atmosphere(d);
	if (AT_CUBEMAP_PASS) {
		// Expensive detail is background-only, not six more renders per update.
		COLOR = air;
	} else if (AT_HALF_RES_PASS) {
		float visibility = (1.0 - day_amount) * (1.0 - twilight_amount * 0.78);
		COLOR = nebula(d) * visibility;
		ALPHA = cloud_density(d);
	} else {
		float visibility = (1.0 - day_amount) * (1.0 - twilight_amount * 0.88);
		vec3 space = HALF_RES_COLOR.rgb + star_field(d) * visibility;
		float angle = acos(clamp(dot(d, sun_direction), -1.0, 1.0));
		float pixel_angle = max(length(fwidth(d)), 0.0001);
		float disk = 1.0 - smoothstep(sun_radius - pixel_angle, sun_radius + pixel_angle, angle);
		float limb = sqrt(max(1.0 - pow(angle / max(sun_radius, 0.0001), 2.0), 0.0));
		space += vec3(1.0, 0.94, 0.80) * disk * (9.0 + limb * 4.0);
		space = giant_world(space, d);
		space = rocky_moon(space, d);
		float airmass = 1.0 / max(d.y + 0.16, 0.16);
		float transmission = exp(-airmass * (0.025 + day_amount * 0.16));
		float horizon = smoothstep(-0.055, 0.025, d.y);
		vec3 color = air + space * transmission * horizon;
		color = mix(color, cloud_color(d), HALF_RES_COLOR.a);
		COLOR = max(color, vec3(0.0));
	}
}
