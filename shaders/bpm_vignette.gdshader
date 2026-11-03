shader_type canvas_item;

// Красная виньетка высокого BPM: края экрана наливаются тёмной кровью, от краёв к центру тянутся ветвящиеся
// сосуды (текстура BPMVignette: R — яркая сердцевина, G — свечение). На ударе сердца виньетка темнеет,
// а сосуды вспыхивают и проступают глубже к центру. intensity — 0..1 (от BPM), pulse — огибающая удара 0..1

uniform sampler2D veins_tex : filter_linear;
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

void fragment() {
	vec2 c = UV - 0.5;
	// 1 — середина края экрана, ~1.4 — угол
	float r = length(c * 2.0);
	vec4 v = texture(veins_tex, UV);

	// Тёмная «дымка» крови у краёв
	float smoke = 0.75 + 0.5 * vnoise(UV * vec2(7.0, 4.0) + TIME * 0.08);
	float base_a = smoothstep(0.5 - pulse * 0.08, 1.4, r) * (0.42 + 0.2 * pulse) * smoke;
	// Сосуды видны у краёв; на ударе — глубже
	float reach = smoothstep(0.8 - pulse * 0.2 - intensity * 0.05, 1.25, r);
	float glow = clamp(v.g * 2.2, 0.0, 1.0) * (0.45 + 0.55 * pulse);
	float core = clamp(v.r, 0.0, 1.0) * (0.6 + 0.4 * pulse);
	float veins_a = clamp(core + glow * 0.7, 0.0, 1.0) * reach;

	vec3 vein_col = mix(vec3(0.5, 0.01, 0.03), vec3(1.0, 0.3, 0.24), core);
	float a = max(base_a, veins_a);
	vec3 col = mix(vec3(0.2, 0.0, 0.01), vein_col, veins_a / max(a, 0.001));
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * intensity * 0.8);
}
