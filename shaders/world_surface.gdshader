shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// Процедурная поверхность уровня (ноябрь 2026): плитка / кладка / панели и шумовая грязь в мировых
// координатах — трипланарно, без UV и без файлов текстур. Цвет — albedo, рисунок только слегка его
// модулирует: освещённость и контраст с чёрными силуэтами врагов (docs/levels.md) почти не меняются.

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// 0 — плитка (квадраты), 1 — кладка (кирпич 2:1, ряды со сдвигом), 2 — панели (квадраты с заклёпками)
uniform int pattern = 0;
// Размер плитки / длина кирпича / размер панели, м
uniform float tile_size = 2.0;
// Ширина шва в долях плитки
uniform float groove_width = 0.025;
uniform float groove_darkness = 0.4;
// Разброс яркости от плитки к плитке (±половина)
uniform float tile_variation = 0.12;
uniform float grime_strength = 0.18;
uniform float grime_scale = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

// Рисунок на плоскости: x — шов (0..1), y — случайное число плитки, z — заклёпка (0..1)
vec3 surface_pattern(vec2 uv) {
	vec2 cell = uv / tile_size;
	float aspect = 1.0;
	if (pattern == 1) {
		cell.y *= 2.0;
		cell.x += 0.5 * mod(floor(cell.y), 2.0);
		aspect = 2.0;
	}
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	vec2 edge = min(f, 1.0 - f);
	edge.x *= aspect; // в единицах высоты кирпича: ширина плитки = aspect × высота
	float gw = groove_width;
	float groove = 1.0 - smoothstep(gw * 0.5, gw, min(edge.x, edge.y));
	float rivet = 0.0;
	if (pattern == 2) {
		// Заклёпки у четырёх углов панели: центры в 0.08 от краёв (симметрично через abs)
		vec2 to_rivet = abs(f - 0.5) - vec2(0.42);
		rivet = 1.0 - smoothstep(0.015, 0.025, length(to_rivet));
	}
	return vec3(groove, hash(id), rivet);
}

void fragment() {
	vec3 n = abs(normalize(world_normal));
	vec3 w = n * n * n * n;
	w /= (w.x + w.y + w.z);
	vec3 px = surface_pattern(world_pos.zy);
	vec3 py = surface_pattern(world_pos.xz);
	vec3 pz = surface_pattern(world_pos.xy);
	vec3 p = px * w.x + py * w.y + pz * w.z;
	float grime = fbm(world_pos.zy * grime_scale) * w.x + fbm(world_pos.xz * grime_scale) * w.y + fbm(world_pos.xy * grime_scale) * w.z;
	grime = smoothstep(0.35, 0.8, grime);

	vec3 col = albedo.rgb;
	col *= 1.0 + (p.y - 0.5) * tile_variation;
	col *= mix(1.0, 1.0 - grime_strength, grime);
	col *= 1.0 - p.x * groove_darkness;
	col = mix(col, col * 1.35 + vec3(0.03), p.z);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness + grime * 0.08 + p.x * 0.1 - p.z * 0.3, 0.0, 1.0);
	METALLIC = clamp(metallic + p.z * 0.4, 0.0, 1.0);
}
