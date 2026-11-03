shader_type canvas_item;

// Резервуар HP: стеклянная колба в металлической обойме (крышки с болтами, боковые стойки), внутри — кровь.
// Уровень — доля HP; поверхность наклоняется и плещется (tilt, wave — их считает HealthFlask по инерции игрока
// и камеры). На стекле — трещины от попаданий (до 4 точек), на критическом HP кровь кипит и мигает аварийный
// диод на верхней крышке. Координаты — пиксели прямоугольника (rect_size).

uniform vec2 rect_size = vec2(54.0, 120.0);
uniform float fill = 1.0;
uniform float tilt = 0.0; // наклон поверхности, px по вертикали на px по горизонтали
uniform float wave = 0.0; // амплитуда волн, px
uniform float boil = 0.0; // 0..1 — кипение на критическом HP
uniform float diode = 0.0; // 0..1 — яркость аварийного диода
uniform float flash = 0.0; // 0..1 — вспышка стекла при попадании
uniform float crack_visibility = 0.0; // 0..1 — трещины гаснут при лечении
uniform vec4 cracks[4]; // x, y (px), сила 0..1, зерно

const float CAP_H = 14.0;
const float GLASS_X0 = 8.0;
const float GLASS_X1 = 46.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float box(vec2 p, vec2 a, vec2 b, float r) {
	vec2 c = (a + b) * 0.5;
	vec2 h = (b - a) * 0.5 - r;
	vec2 q = abs(p - c) - h;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Сеть трещин одной точки удара: лучи с изломом и обрывками кольца
float crack(vec2 p, vec4 c) {
	if (c.z <= 0.0) {
		return 0.0;
	}
	vec2 d = p - c.xy;
	float r = length(d);
	float a = atan(d.y, d.x);
	float rays = 7.0;
	float t = a / 6.2831853 * rays + c.w * 13.0 + (vnoise(r * 0.35 + c.w * 31.0) - 0.5) * 0.5;
	float id = floor(t);
	float dist = abs(fract(t) - 0.5) * 6.2831853 * r / rays;
	float len = c.z * (14.0 + 22.0 * hash(id + c.w * 7.0));
	float ray = (1.0 - smoothstep(0.35, 0.9, dist)) * (1.0 - smoothstep(len * 0.7, len, r));
	float ring_r = 4.0 + 4.0 * c.z;
	float ring = (1.0 - smoothstep(0.3, 0.8, abs(r - ring_r))) * step(0.45, hash(floor(a * 3.0) + c.w * 5.0));
	return max(ray, ring * c.z);
}

void fragment() {
	vec2 p = UV * rect_size;
	float aa = 0.8;
	vec4 col = vec4(0.0);

	float glass_y0 = CAP_H;
	float glass_y1 = rect_size.y - CAP_H;
	float d_glass = box(p, vec2(GLASS_X0, glass_y0 - 2.0), vec2(GLASS_X1, glass_y1 + 2.0), 4.0);
	float in_glass = 1.0 - smoothstep(-aa, aa, d_glass);

	// --- Стекло и кровь внутри ---
	if (in_glass > 0.0) {
		float inner_x0 = GLASS_X0 + 2.0;
		float inner_x1 = GLASS_X1 - 2.0;
		float span = inner_x1 - inner_x0;
		float u = clamp((p.x - inner_x0) / span, 0.0, 1.0);
		float level = glass_y1 - fill * (glass_y1 - glass_y0);
		float surf = level + tilt * (p.x - (inner_x0 + inner_x1) * 0.5)
			+ wave * sin(p.x * 0.33 + TIME * 7.0) + wave * 0.5 * sin(p.x * 0.71 - TIME * 11.0)
			+ boil * 1.2 * sin(p.x * 1.3 + TIME * 23.0) * vnoise(p.x * 0.2 + TIME * 3.0);
		// Цилиндр: к краям темнее
		float cyl = 0.55 + 0.45 * sin(3.14159 * u);
		vec3 glass_col = vec3(0.55, 0.62, 0.66) * cyl;
		float glass_a = 0.16;
		vec4 inside = vec4(glass_col, glass_a);
		if (p.y > surf && fill > 0.001) {
			float depth = clamp((p.y - surf) / 60.0, 0.0, 1.0);
			vec3 blood = mix(vec3(0.78, 0.04, 0.07), vec3(0.34, 0.0, 0.03), depth) * cyl;
			blood *= 1.0 + boil * 0.25 * vnoise(p.y * 0.3 - TIME * 6.0);
			// Пузыри кипения: всплывают колонками
			for (int i = 0; i < 6; i++) {
				float fi = float(i);
				float bx = inner_x0 + 3.0 + hash(fi + 1.0) * (span - 6.0);
				float speed = 22.0 + hash(fi + 9.0) * 30.0;
				float by = glass_y1 - mod(TIME * speed + hash(fi + 4.0) * 90.0, glass_y1 - surf + 4.0);
				float br = 1.2 + hash(fi + 17.0) * 1.4;
				float db = length(p - vec2(bx + sin(TIME * 5.0 + fi) * 1.2, by)) - br;
				blood = mix(blood, vec3(1.0, 0.45, 0.35), boil * (1.0 - smoothstep(0.0, 0.8, abs(db))) * 0.9);
			}
			inside = vec4(blood, 0.97);
			// Мениск — светлая линия поверхности
			float meniscus = 1.0 - smoothstep(0.0, 1.6, p.y - surf);
			inside.rgb = mix(inside.rgb, vec3(1.0, 0.35, 0.3), meniscus * 0.8);
		}
		// Деления шкалы справа на стекле
		float tick_y = (p.y - glass_y0) / (glass_y1 - glass_y0) * 10.0;
		float tick = (1.0 - smoothstep(0.0, 0.08, abs(fract(tick_y + 0.5) - 0.5))) * step(inner_x1 - 6.0, p.x) * step(p.x, inner_x1 - 1.0);
		inside = mix(inside, vec4(0.9, 0.9, 0.9, 0.8), tick * 0.5);
		// Блики стекла
		float hl = (1.0 - smoothstep(0.0, 1.6, abs(p.x - (GLASS_X0 + 6.0)))) * 0.45 + (1.0 - smoothstep(0.0, 0.8, abs(p.x - (GLASS_X1 - 5.0)))) * 0.2;
		inside.rgb += vec3(hl);
		inside.a = max(inside.a, hl);
		// Трещины
		float cr = 0.0;
		for (int i = 0; i < 4; i++) {
			cr = max(cr, crack(p, cracks[i]));
		}
		cr *= crack_visibility;
		inside = mix(inside, vec4(0.92, 0.95, 1.0, 0.95), cr * 0.85);
		inside.rgb += vec3(flash * 0.5);
		inside.a = max(inside.a, flash * 0.4);
		// Кромка стекла
		float rim = 1.0 - smoothstep(0.0, 1.2, abs(d_glass + 0.6));
		inside = mix(inside, vec4(0.8, 0.88, 0.92, 0.8), rim * 0.7);
		col = mix(col, inside, in_glass);
	}

	// --- Металлическая обойма: стойки и крышки ---
	float d_rods = min(box(p, vec2(3.0, 10.0), vec2(7.0, rect_size.y - 10.0), 1.5), box(p, vec2(rect_size.x - 7.0, 10.0), vec2(rect_size.x - 3.0, rect_size.y - 10.0), 1.5));
	float d_caps = min(box(p, vec2(1.0, 0.0), vec2(rect_size.x - 1.0, CAP_H), 3.0), box(p, vec2(1.0, rect_size.y - CAP_H), vec2(rect_size.x - 1.0, rect_size.y), 3.0));
	float d_metal = min(d_rods, d_caps);
	float in_metal = 1.0 - smoothstep(-aa, aa, d_metal);
	if (in_metal > 0.0) {
		// Полированная сталь: вертикальный градиент и горизонтальная «шлифовка»
		float local_y = p.y < rect_size.y * 0.5 ? p.y / CAP_H : (rect_size.y - p.y) / CAP_H;
		float grad = d_caps < d_rods ? 0.35 + 0.5 * (1.0 - abs(local_y - 0.4)) : 0.3 + 0.4 * (1.0 - abs(UV.x * 2.0 - 1.0));
		vec3 steel = vec3(0.32, 0.33, 0.36) * grad + vec3(0.04) * hash2(floor(p * vec2(0.5, 3.0)));
		// Болты по краям крышек
		vec2 bolt_l = vec2(7.0, p.y < rect_size.y * 0.5 ? CAP_H * 0.5 : rect_size.y - CAP_H * 0.5);
		vec2 bolt_r = vec2(rect_size.x - 7.0, bolt_l.y);
		float bolt = 1.0 - smoothstep(1.2, 2.0, min(length(p - bolt_l), length(p - bolt_r)));
		steel = mix(steel, vec3(0.6, 0.6, 0.62), bolt * 0.8);
		// Контур
		steel *= mix(0.45, 1.0, smoothstep(0.0, 1.5, -d_metal));
		col = mix(col, vec4(steel, 1.0), in_metal);
	}

	// --- Аварийный диод на верхней крышке ---
	vec2 dc = vec2(rect_size.x * 0.5, CAP_H * 0.5);
	float dd = length(p - dc);
	vec3 diode_off = vec3(0.22, 0.03, 0.03);
	vec3 diode_on = vec3(1.0, 0.15, 0.08);
	float lens = 1.0 - smoothstep(2.6, 3.4, dd);
	col = mix(col, vec4(mix(diode_off, diode_on, diode) + vec3(0.25) * (1.0 - smoothstep(0.0, 1.0, length(p - dc + vec2(0.9, 0.9)))), 1.0), lens);
	float halo = exp(-dd * 0.28) * diode * 0.8;
	col.rgb += diode_on * halo;
	col.a = max(col.a, halo);

	COLOR = col;
}
