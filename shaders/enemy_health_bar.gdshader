shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix;

// Полоска HP врага: квад-биллборд, заполнение по доле HP. Повторяет прежний ProgressBar 130×20 px
// (фон, рамка 2 px, заливка цветом врага). Один материал на всех врагов, значения — instance uniform.

instance uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
instance uniform vec4 fill_color : source_color = vec4(0.95, 0.15, 0.15, 1.0);

uniform vec4 background_color : source_color = vec4(0.08, 0.08, 0.08, 0.85);
uniform vec4 border_color : source_color = vec4(0.35, 0.35, 0.35, 0.9);
// Толщина рамки в долях квада: 2 px из 130×20
uniform vec2 border = vec2(0.0154, 0.1);

void vertex() {
	// Биллборд без учёта масштаба (как Sprite3D с BILLBOARD_ENABLED)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 col = background_color;
	bool in_border = UV.x < border.x || UV.x > 1.0 - border.x || UV.y < border.y || UV.y > 1.0 - border.y;
	if (in_border) {
		col = border_color;
	}
	if (UV.x <= fill_ratio && fill_ratio > 0.0) {
		col = fill_color;
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
