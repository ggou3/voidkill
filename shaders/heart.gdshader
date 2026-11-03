shader_type canvas_item;

// Анатомическое сердце (вид спереди) индикатора BPM. Силуэт — SDF из эллипсов (желудочки, предсердия) и
// капсул (аорта с дугой и ветвями, лёгочный ствол, верхняя полая вена). Объём — высота из расстояния до края,
// свет — диффуз с подповерхностным красным в тенях и влажный блик. На мышце — жировые борозды с венечными
// артериями и мелкие вены. beat — огибающая удара 0..1, beat_scale — сила удара, intensity — доля BPM 0..1,
// alive — 0 после смерти (сердце темнеет)

uniform float beat = 0.0;
uniform float beat_scale = 0.05;
uniform float intensity = 0.0;
uniform float alive = 1.0;

// Поле зрения в единицах сердца: запас под удар и тень
const float VIEW = 1.28;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sd_ellipse(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 0.0001);
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x);
	float b = mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Купол высоты w над фигурой: 0 на краю, w в глубине
float dome(float d, float w) {
	float x = clamp(-d / w, 0.0, 1.0);
	return sqrt(1.0 - (1.0 - x) * (1.0 - x)) * w;
}

// Мышца: желудочки с верхушкой справа внизу, правое предсердие слева, ушко левого предсердия справа
float sd_body(vec2 p) {
	float d = sd_ellipse(rot(p - vec2(-0.02, 0.2), 0.5), vec2(0.58, 0.52));
	d = smin(d, sd_capsule(p, vec2(0.02, 0.25), vec2(0.3, 0.8), 0.16), 0.3);
	d = smin(d, sd_ellipse(rot(p - vec2(0.3, 0.26), 0.4), vec2(0.32, 0.47)), 0.15);
	d = smin(d, sd_ellipse(p - vec2(-0.5, -0.12), vec2(0.24, 0.3)), 0.12);
	d = smin(d, sd_ellipse(rot(p - vec2(0.5, -0.24), -0.4), vec2(0.17, 0.11)), 0.08);
	return d;
}

// x — расстояние до силуэта, y — высота рельефа, z — материал (0 мышца, 1 аорта, 2 лёгочный ствол, 3 вена)
vec3 heart_field(vec2 p) {
	float swell = beat * 0.012;
	float d_body = sd_body(p);

	float d_aorta = sd_capsule(p, vec2(-0.06, -0.1), vec2(-0.08, -0.58), 0.13 + swell);
	vec2 q = p - vec2(0.13, -0.58);
	d_aorta = min(d_aorta, max(abs(length(q) - 0.21) - 0.115 - swell, q.y));
	d_aorta = min(d_aorta, sd_capsule(p, vec2(0.34, -0.58), vec2(0.36, -0.3), 0.1 + swell));
	d_aorta = min(d_aorta, sd_capsule(p, vec2(-0.02, -0.72), vec2(-0.1, -0.98), 0.055));
	d_aorta = min(d_aorta, sd_capsule(p, vec2(0.13, -0.78), vec2(0.13, -1.0), 0.05));
	d_aorta = min(d_aorta, sd_capsule(p, vec2(0.27, -0.72), vec2(0.34, -0.96), 0.05));

	float d_pulm = sd_capsule(p, vec2(0.1, -0.02), vec2(0.2, -0.42), 0.12 + swell);
	d_pulm = smin(d_pulm, sd_capsule(p, vec2(0.2, -0.42), vec2(0.52, -0.46), 0.075), 0.06);

	float d_vena = sd_capsule(p, vec2(-0.42, -0.2), vec2(-0.38, -0.95), 0.11);

	vec3 best = vec3(d_body, dome(d_body, 0.42), 0.0);
	float h = dome(d_aorta, 0.13);
	if (h > best.y) {
		best = vec3(best.x, h, 1.0);
	}
	h = dome(d_pulm, 0.12) + 0.02 * step(d_pulm, 0.0);
	if (h > best.y) {
		best = vec3(best.x, h, 2.0);
	}
	h = dome(d_vena, 0.11);
	if (h > best.y) {
		best = vec3(best.x, h, 3.0);
	}
	best.x = min(min(d_body, d_aorta), min(d_pulm, d_vena));
	return best;
}

// Передняя межжелудочковая борозда и венечная борозда (жир), x — до борозд, y — до артерий в них и ветвей
vec2 grooves(vec2 p) {
	vec2 w = p + (vec2(vnoise(p * 6.0), vnoise(p * 6.0 + 5.3)) - 0.5) * 0.07;
	float g = sd_capsule(w, vec2(0.1, -0.02), vec2(0.08, 0.38), 0.0);
	g = min(g, sd_capsule(w, vec2(0.08, 0.38), vec2(0.27, 0.8), 0.0));
	float sulcus = sd_capsule(w, vec2(-0.4, 0.12), vec2(-0.2, -0.02), 0.0);
	sulcus = min(sulcus, sd_capsule(w, vec2(-0.2, -0.02), vec2(0.12, -0.06), 0.0));
	sulcus = min(sulcus, sd_capsule(w, vec2(0.12, -0.06), vec2(0.4, -0.06), 0.0));
	float art = min(g, sulcus);
	art = min(art, sd_capsule(w, vec2(0.09, 0.14), vec2(0.36, 0.3), 0.0) + 0.006);
	art = min(art, sd_capsule(w, vec2(0.08, 0.36), vec2(-0.2, 0.55), 0.0) + 0.006);
	art = min(art, sd_capsule(w, vec2(0.17, 0.58), vec2(0.42, 0.6), 0.0) + 0.008);
	art = min(art, sd_capsule(w, vec2(0.09, 0.08), vec2(-0.26, 0.22), 0.0) + 0.008);
	return vec2(min(g, sulcus), art);
}

void fragment() {
	float s = 1.0 + beat * beat_scale;
	vec2 p = (UV * 2.0 - 1.0) * VIEW;
	// Удар: сердце раздувается, по вертикали — меньше (сокращение «к верхушке»)
	p /= vec2(s, 1.0 + beat * beat_scale * 0.6);
	p += vec2(-0.03, 0.0);

	vec3 f = heart_field(p);
	float d = f.x;
	float e = 0.012;
	float hx = heart_field(p + vec2(e, 0.0)).y;
	float hy = heart_field(p + vec2(0.0, e)).y;

	// Рельеф мышечных волокон — по наклонённой вдоль желудочков сетке шума
	vec2 fp = rot(p, 0.6) * vec2(5.0, 16.0);
	float fib = fbm(fp);
	float fib_x = fbm(fp + vec2(0.3, 0.0));
	float fib_y = fbm(fp + vec2(0.0, 0.3));
	float bump = f.z < 0.5 ? 0.035 : 0.012;
	vec3 n = normalize(vec3(-(hx - f.y) / e - (fib_x - fib) * bump * 10.0, -(hy - f.y) / e - (fib_y - fib) * bump * 10.0, 1.0));

	vec2 gr = grooves(p);
	// Жир в бороздах — комками неровной ширины, местами прерывается
	float lumps = fbm(p * 8.0 + 11.0);
	float fat = (1.0 - smoothstep(0.02, 0.05 + lumps * 0.09, gr.x)) * smoothstep(0.3, 0.55, lumps) * step(f.z, 0.5);
	float artery = (1.0 - smoothstep(0.01, 0.022, gr.y)) * step(f.z, 0.5);
	float vein = smoothstep(0.93, 0.985, 1.0 - abs(vnoise(p * 7.0 + 2.0) * 2.0 - 1.0)) * step(f.z, 0.5) * (1.0 - fat);

	vec3 muscle = mix(vec3(0.24, 0.015, 0.025), vec3(0.62, 0.07, 0.07), 0.45 + 0.55 * fib);
	vec3 albedo = muscle;
	float vessel_tone = 0.8 + 0.25 * fbm(p * 10.0);
	if (f.z > 2.5) {
		albedo = vec3(0.25, 0.07, 0.16) * vessel_tone;
	} else if (f.z > 1.5) {
		albedo = vec3(0.5, 0.15, 0.17) * vessel_tone;
	} else if (f.z > 0.5) {
		albedo = vec3(0.6, 0.25, 0.22) * vessel_tone;
	}
	albedo = mix(albedo, vec3(0.3, 0.04, 0.12), vein * 0.6);
	albedo = mix(albedo, vec3(0.66, 0.5, 0.3) * (0.75 + 0.35 * fbm(p * 14.0)), fat * 0.75);
	albedo = mix(albedo, vec3(0.38, 0.03, 0.05), artery * 0.85);

	vec3 L = normalize(vec3(-0.45, -0.65, 0.65));
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float diff = clamp(dot(n, L), 0.0, 1.0);
	vec3 col = albedo * (0.22 + 0.95 * (diff * 0.75 + 0.25));
	col += vec3(0.1, 0.0, 0.005) * (1.0 - diff);
	// Затенение у краёв и в стыках сосудов с мышцей
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.12, f.y));
	float wet = (0.6 + 0.4 * fbm(p * 11.0 + 3.0)) * (f.z < 0.5 ? 1.0 : 0.55);
	col += vec3(1.0, 0.82, 0.78) * (pow(max(dot(n, H), 0.0), 40.0) * 0.45 + pow(max(dot(n, H), 0.0), 220.0) * 1.1) * wet;

	// Прилив крови на ударе, сильнее на высоком BPM
	col *= 1.0 + beat * (0.18 + 0.3 * intensity);
	col = mix(col, col * vec3(1.15, 0.8, 0.8), beat * 0.3);
	// Остановившееся сердце — тёмное и тусклое
	col = mix(col * vec3(0.4, 0.28, 0.3), col, alive);
	// Тёмный контур — читается на любом фоне
	col *= mix(0.3, 1.0, smoothstep(0.0, 0.035, -d));

	float aa = max(fwidth(d), 0.0001);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float outside = max(d, 0.0);
	float shadow = (1.0 - smoothstep(0.0, 0.16, outside)) * 0.5;
	float glow = exp(-outside * 9.0) * intensity * (0.25 + 0.75 * beat) * alive * 0.8;
	vec4 bg = vec4(vec3(0.7, 0.0, 0.03) * glow / max(shadow + glow, 0.001), max(shadow, glow));
	COLOR = mix(bg, vec4(col, 1.0), inside);
}
