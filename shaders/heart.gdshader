shader_type canvas_item;

// Анатомическое сердце (вид спереди) индикатора BPM, по референсу — гладкое глянцевое, коралово-красное.
// Силуэт — SDF из эллипсов (желудочки, большое правое предсердие слева, ушко левого предсердия справа) и капсул
// (дуга аорты с тремя ветвями, верхняя полая вена, лёгочный ствол и лёгочные вены вправо). Объём — высота из
// расстояния до края, свет — мягкий диффуз и широкий влажный блик. По поверхности ветвятся тёмные венечные
// сосуды, предсердие отделено бороздой. beat — огибающая удара 0..1, beat_scale — сила удара,
// intensity — доля BPM 0..1, alive — 0 после смерти (сердце темнеет)

uniform float beat = 0.0;
uniform float beat_scale = 0.05;
uniform float intensity = 0.0;
uniform float alive = 1.0;

// Поле зрения в единицах сердца: запас под удар и тень
const float VIEW = 1.3;

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

// Отрезок с сужением: радиус ra у начала, rb у конца
float sd_taper(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
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

// Купол высоты w над фигурой: 0 на краю, w в глубине
float dome(float d, float w) {
	float x = clamp(-d / w, 0.0, 1.0);
	return sqrt(1.0 - (1.0 - x) * (1.0 - x)) * w;
}

// Мышца: желудочки с верхушкой справа внизу, большое правое предсердие слева, ушко левого предсердия справа
float sd_body(vec2 p) {
	float d = sd_ellipse(rot(p - vec2(0.02, 0.22), 0.45), vec2(0.56, 0.52));
	d = smin(d, sd_capsule(p, vec2(0.05, 0.3), vec2(0.27, 0.8), 0.15), 0.32);
	d = smin(d, sd_ellipse(rot(p - vec2(0.3, 0.24), 0.4), vec2(0.3, 0.46)), 0.15);
	d = smin(d, sd_ellipse(p - vec2(-0.47, -0.04), vec2(0.3, 0.36)), 0.1);
	d = smin(d, sd_ellipse(rot(p - vec2(0.5, -0.2), -0.4), vec2(0.17, 0.11)), 0.08);
	return d;
}

// x — расстояние до силуэта, y — высота рельефа, z — материал (0 мышца, 1 аорта, 2 лёгочные сосуды, 3 вена)
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

	float d_pulm = sd_capsule(p, vec2(0.1, -0.02), vec2(0.2, -0.4), 0.12 + swell);
	d_pulm = smin(d_pulm, sd_capsule(p, vec2(0.2, -0.4), vec2(0.62, -0.46), 0.075), 0.06);
	d_pulm = min(d_pulm, sd_capsule(p, vec2(0.44, -0.3), vec2(0.7, -0.33), 0.055));
	d_pulm = min(d_pulm, sd_capsule(p, vec2(0.5, -0.12), vec2(0.72, -0.16), 0.05));

	float d_vena = sd_capsule(p, vec2(-0.4, -0.2), vec2(-0.37, -0.82), 0.1);
	d_vena = min(d_vena, sd_capsule(p, vec2(-0.6, -0.3), vec2(-0.76, -0.36), 0.05));

	vec3 best = vec3(d_body, dome(d_body, 0.45), 0.0);
	float h = dome(d_aorta, 0.13);
	if (h > best.y) {
		best = vec3(best.x, h, 1.0);
	}
	h = dome(d_pulm, 0.11) + 0.02 * step(d_pulm, 0.0);
	if (h > best.y) {
		best = vec3(best.x, h, 2.0);
	}
	h = dome(d_vena, 0.1);
	if (h > best.y) {
		best = vec3(best.x, h, 3.0);
	}
	best.x = min(min(d_body, d_aorta), min(d_pulm, d_vena));
	return best;
}

// Венечные сосуды — деревья с сужением: передняя нисходящая с диагональными ветвями к верхушке, правая
// венечная по борозде предсердия, огибающая справа вверху. x — до ближайшего сосуда, y — до борозды предсердия
vec2 coronary(vec2 p) {
	vec2 w = p + (vec2(vnoise(p * 9.0), vnoise(p * 9.0 + 7.3)) - 0.5) * 0.045;
	// Передняя нисходящая
	float d = sd_taper(w, vec2(0.12, -0.06), vec2(0.09, 0.2), 0.018, 0.016);
	d = min(d, sd_taper(w, vec2(0.09, 0.2), vec2(0.17, 0.46), 0.016, 0.013));
	d = min(d, sd_taper(w, vec2(0.17, 0.46), vec2(0.3, 0.8), 0.013, 0.005));
	// Её ветви вправо, к левому желудочку
	d = min(d, sd_taper(w, vec2(0.1, 0.12), vec2(0.3, 0.22), 0.01, 0.007));
	d = min(d, sd_taper(w, vec2(0.3, 0.22), vec2(0.5, 0.26), 0.007, 0.003));
	d = min(d, sd_taper(w, vec2(0.3, 0.22), vec2(0.38, 0.4), 0.006, 0.003));
	d = min(d, sd_taper(w, vec2(0.14, 0.36), vec2(0.34, 0.5), 0.009, 0.004));
	d = min(d, sd_taper(w, vec2(0.34, 0.5), vec2(0.46, 0.5), 0.004, 0.002));
	d = min(d, sd_taper(w, vec2(0.22, 0.58), vec2(0.38, 0.68), 0.006, 0.002));
	// И влево, к правому желудочку
	d = min(d, sd_taper(w, vec2(0.1, 0.26), vec2(-0.08, 0.38), 0.008, 0.004));
	d = min(d, sd_taper(w, vec2(-0.08, 0.38), vec2(-0.16, 0.5), 0.004, 0.002));
	d = min(d, sd_taper(w, vec2(-0.08, 0.38), vec2(-0.22, 0.36), 0.004, 0.002));
	d = min(d, sd_taper(w, vec2(0.18, 0.5), vec2(0.06, 0.64), 0.007, 0.003));
	d = min(d, sd_taper(w, vec2(0.06, 0.64), vec2(0.04, 0.74), 0.003, 0.002));
	d = min(d, sd_taper(w, vec2(0.09, 0.04), vec2(-0.12, 0.12), 0.008, 0.003));
	// Правая венечная — по борозде между предсердием и желудочком, с ветвями на желудочек
	float groove = sd_capsule(w, vec2(-0.14, -0.04), vec2(-0.3, 0.16), 0.0);
	groove = min(groove, sd_capsule(w, vec2(-0.3, 0.16), vec2(-0.36, 0.38), 0.0));
	groove = min(groove, sd_capsule(w, vec2(-0.36, 0.38), vec2(-0.28, 0.58), 0.0));
	d = min(d, groove - 0.013);
	d = min(d, sd_taper(w, vec2(-0.31, 0.22), vec2(-0.12, 0.3), 0.007, 0.002));
	d = min(d, sd_taper(w, vec2(-0.35, 0.42), vec2(-0.16, 0.56), 0.007, 0.002));
	d = min(d, sd_taper(w, vec2(-0.29, 0.56), vec2(-0.1, 0.7), 0.006, 0.002));
	// Огибающая — справа вверху вдоль ушка, ветвь вниз по краю
	d = min(d, sd_taper(w, vec2(0.16, -0.09), vec2(0.36, -0.06), 0.012, 0.01));
	d = min(d, sd_taper(w, vec2(0.36, -0.06), vec2(0.52, 0.06), 0.01, 0.006));
	d = min(d, sd_taper(w, vec2(0.45, 0.0), vec2(0.54, 0.24), 0.006, 0.002));
	// Мелкие сосуды на предсердии
	d = min(d, sd_taper(w, vec2(-0.5, -0.3), vec2(-0.42, -0.06), 0.006, 0.002));
	d = min(d, sd_taper(w, vec2(-0.62, -0.1), vec2(-0.48, 0.1), 0.005, 0.002));
	return vec2(d, groove);
}

void fragment() {
	float s = 1.0 + beat * beat_scale;
	vec2 p = (UV * 2.0 - 1.0) * VIEW;
	// Удар: сердце раздувается, по вертикали — меньше (сокращение «к верхушке»)
	p /= vec2(s, 1.0 + beat * beat_scale * 0.6);
	p += vec2(0.0, -0.02);

	vec3 f = heart_field(p);
	float d = f.x;
	float e = 0.012;
	float hx = heart_field(p + vec2(e, 0.0)).y;
	float hy = heart_field(p + vec2(0.0, e)).y;
	vec3 n = normalize(vec3(-(hx - f.y) / e, -(hy - f.y) / e, 1.0));

	// Сосуды и борозда — только на мышце
	float on_muscle = step(f.z, 0.5);
	vec2 cor = coronary(p);
	float aa_v = max(fwidth(cor.x), 0.002);
	float vessel = (1.0 - smoothstep(-aa_v, aa_v, cor.x)) * on_muscle;
	float vessel_shade = (1.0 - smoothstep(0.0, 0.03, cor.x)) * on_muscle; // тень вдоль сосуда
	float groove = (1.0 - smoothstep(0.0, 0.07, cor.y)) * on_muscle;
	// Сосуды чуть выпуклые: наклон нормали поперёк сосуда
	n = normalize(n + vec3(dFdx(cor.x), dFdy(cor.x), 0.0) * vessel * 8.0);

	vec3 albedo = vec3(0.8, 0.2, 0.2);
	if (f.z > 2.5) {
		albedo = vec3(0.76, 0.26, 0.28);
	} else if (f.z > 1.5) {
		albedo = vec3(0.8, 0.28, 0.28);
	} else if (f.z > 0.5) {
		albedo = vec3(0.88, 0.38, 0.36);
	}
	albedo *= 0.94 + 0.12 * vnoise(p * 6.0);
	albedo *= 1.0 - groove * 0.25 - vessel_shade * 0.18;
	albedo = mix(albedo, vec3(0.42, 0.03, 0.05), vessel * 0.9);

	vec3 L = normalize(vec3(-0.5, -0.6, 0.7));
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float diff = clamp(dot(n, L), 0.0, 1.0);
	// Мягкий свет без чёрных теней: в тени — глубокий красный
	vec3 col = albedo * (0.35 + 0.8 * diff);
	col = mix(col, col * vec3(0.75, 0.35, 0.38), (1.0 - diff) * 0.5);
	// Затенение у краёв силуэта и в стыках сосудов с мышцей
	col *= mix(0.6, 1.0, smoothstep(0.0, 0.14, f.y));
	float nh = max(dot(n, H), 0.0);
	col += vec3(1.0, 0.78, 0.74) * (pow(nh, 14.0) * 0.22 + pow(nh, 90.0) * 0.55);

	// Прилив крови на ударе, сильнее на высоком BPM
	col *= 1.0 + beat * (0.15 + 0.25 * intensity);
	// Остановившееся сердце — тёмное и тусклое
	col = mix(col * vec3(0.4, 0.28, 0.3), col, alive);
	// Тёмный контур — читается на любом фоне
	col *= mix(0.4, 1.0, smoothstep(0.0, 0.03, -d));

	float aa = max(fwidth(d), 0.0001);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float outside = max(d, 0.0);
	float shadow = (1.0 - smoothstep(0.0, 0.16, outside)) * 0.5;
	float glow = exp(-outside * 9.0) * intensity * (0.25 + 0.75 * beat) * alive * 0.8;
	vec4 bg = vec4(vec3(0.7, 0.0, 0.03) * glow / max(shadow + glow, 0.001), max(shadow, glow));
	COLOR = mix(bg, vec4(col, 1.0), inside);
}
