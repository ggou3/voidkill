shader_type canvas_item;

// Красная виньетка высокого BPM: края экрана наливаются кровью, от краёв к центру тянется сетка капилляров.
// На ударе сердца виньетка темнеет, а капилляры вспыхивают и заходят глубже. intensity — 0..1 (от BPM),
// pulse — огибающая удара 0..1

uniform float intensity = 0.0;
uniform float pulse = 0.0;

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

// Хребты шума: 1 на линии уровня 0.5 — извилистые линии сосудов
float ridge(vec2 p, float sharp) {
	return pow(1.0 - abs(vnoise(p) * 2.0 - 1.0), sharp);
}

// Толстые ветви и тонкая сетка; доменное искажение делает их извилистыми
float capillaries(vec2 p) {
	vec2 w = p + vec2(vnoise(p * 1.7), vnoise(p * 1.7 + 4.1)) * 1.2;
	float big = ridge(w * 3.0, 14.0);
	float mid = ridge(w * 6.0 + 3.0, 18.0) * 0.75;
	float fine = ridge(w * 12.0 + 7.0, 22.0) * 0.45;
	return max(big, max(mid, fine));
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 c = UV - 0.5;
	// 1 — середина края экрана, ~1.4 — угол
	float r = length(c * 2.0);
	vec2 q = c * vec2(aspect, 1.0) * 2.2;

	float vignette = smoothstep(0.55 - pulse * 0.1, 1.35, r);
	float reach = smoothstep(0.72 - pulse * 0.2 - intensity * 0.08, 1.25, r);
	float veins = capillaries(q) * reach;

	float a = max(vignette * (0.4 + 0.25 * pulse), veins * (0.65 + 0.35 * pulse));
	vec3 col = mix(vec3(0.32, 0.0, 0.02), vec3(0.78, 0.02, 0.05), clamp(veins * 1.4, 0.0, 1.0));
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * intensity * 0.85);
}
