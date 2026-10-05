shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Кровавая перегородка между секторами: полупрозрачная стена стекающей крови,
// пульсирующая в такт сердцу игрока. Фазу сердцебиения накапливает BloodBarrier по BPM игрока.

uniform vec4 blood_color : source_color = vec4(0.45, 0.01, 0.02, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.42;
// Накопленная фаза сердцебиения в ударах: целая часть — номер удара, дробная — положение внутри удара
uniform float beat_phase = 0.0;
// Скорость стекания крови
uniform float flow_speed = 0.35;
// Плотность потоков по ширине стены (на метр)
uniform float streaks_per_meter = 1.6;
uniform float wall_width = 12.0;
// 0 — целая стена, 1 — полностью обрушена
uniform float collapse : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float column = floor(uv.x * wall_width * streaks_per_meter);
	// у каждого потока своя скорость стекания
	float speed = flow_speed * (0.6 + hash(vec2(column, 3.7)));
	float drip = noise(vec2(uv.x * wall_width * streaks_per_meter, uv.y * 4.0 - TIME * speed * 4.0));
	float streak = smoothstep(0.45, 0.95, drip);

	// Двойной удар сердца (lub-dub) за один период
	float t = fract(beat_phase);
	float lub = exp(-pow(t * 12.0, 2.0)) + exp(-pow((t - 1.0) * 12.0, 2.0));
	float dub = 0.6 * exp(-pow((t - 0.2) * 14.0, 2.0));
	float pulse = clamp(lub + dub, 0.0, 1.0);

	vec3 col = mix(blood_color.rgb, highlight_color.rgb, streak * 0.55 + pulse * 0.45);
	float alpha = base_alpha + streak * 0.25 + pulse * 0.18;
	ALBEDO = col;
	ALPHA = clamp(alpha * (1.0 - collapse), 0.0, 1.0);
}
