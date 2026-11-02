shader_type spatial;

// Лужа крови (ноябрь 2026): неровный край из шума по кругу, мелкие капли вокруг, тёмная глянцевая
// «толстая» середина и светлее-коричневая подсохшая кромка, блик по мениску у края. Вырез по альфе
// (alpha scissor) — рисуется в непрозрачном проходе, без проблем сортировки прозрачных.
// Параметры экземпляра (MeshInstance3D.set_instance_shader_parameter): seed — форма, spread — растекание
// 0..1 (BloodPool твинит при появлении), poison — отравление Инъектором 0..1.

instance uniform float seed = 0.0;
instance uniform float spread = 1.0;
instance uniform float poison = 0.0;

uniform vec3 core_color : source_color = vec3(0.36, 0.01, 0.02);
uniform vec3 rim_color : source_color = vec3(0.55, 0.04, 0.03);
uniform vec3 dry_color : source_color = vec3(0.3, 0.06, 0.03);
uniform vec3 poison_color : source_color = vec3(0.12, 0.32, 0.04);
uniform float edge_radius = 0.72; // средний радиус края (доля половины меша)
uniform float edge_wobble = 0.24; // неровность края
uniform float drop_density = 0.8; // 0 — без капель, 1 — много
uniform float meniscus_strength = 0.6; // сила блика по краю

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

// Толщина лужи в точке p (-1..1): >0 — внутри. Край — шум по окружности (без шва по углу)
float thickness(vec2 p) {
	float r = length(p);
	vec2 dir = r > 0.0001 ? p / r : vec2(1.0, 0.0);
	float n = fbm(dir * 1.6 + vec2(seed * 3.7, seed * 1.3));
	float edge = (edge_radius + edge_wobble * (n - 0.5) * 2.0) * spread;
	// Мелкий шум по всей площади — край «рваный», а не гладкая клякса
	edge += (fbm(p * 6.0 + seed) - 0.5) * 0.08 * spread;
	return edge - r;
}

// Отдельные капли вокруг лужи (появляются, когда лужа почти растеклась)
float drops(vec2 p) {
	vec2 g = p * 4.5 + seed * 5.0;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id);
	vec2 o = (vec2(hash(id + 1.3), hash(id + 7.1)) - 0.5) * 0.5;
	float rad = 0.07 + 0.11 * hash(id + 3.9);
	float present = step(1.0 - 0.35 * drop_density, h) * step(length(p), 0.97) * smoothstep(0.7, 1.0, spread);
	return present * (rad - length(f - o));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = thickness(p);
	float d = drops(p);
	float body = max(t, d * 0.25);
	ALPHA = body > 0.0 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Глубина: 0 у края, 1 к середине — цвет и глянец
	float depth = clamp(body / 0.22, 0.0, 1.0);
	vec3 col = mix(rim_color, core_color, depth);
	// Подсохшая кромка — тонкая коричневатая полоса у самого края
	col = mix(dry_color, col, smoothstep(0.0, 0.18, depth));
	col = mix(col, poison_color, poison);
	ALBEDO = col;
	ROUGHNESS = mix(0.45, 0.25, depth);
	SPECULAR = 0.2;
	EMISSION = poison_color * 0.6 * poison;

	// Мениск: нормаль по градиенту толщины у края — блик обводит лужу
	float e = 0.02;
	float hx = clamp((thickness(p + vec2(e, 0.0)) - t) / e, -4.0, 4.0);
	float hy = clamp((thickness(p + vec2(0.0, e)) - t) / e, -4.0, 4.0);
	float edge_zone = 1.0 - depth;
	NORMAL_MAP = normalize(vec3(-hx * meniscus_strength * edge_zone, -hy * meniscus_strength * edge_zone, 1.0)) * 0.5 + 0.5;
}
