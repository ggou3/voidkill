shader_type canvas_item;
render_mode blend_premul_alpha;

// Панели HUD на «выпуклом телевизоре»: текстура SubViewport с панелями выводится с той же выпуклостью, что и
// картинка мира в пост-шейдере player.gdshader (коэффициент 0.1), — панели гнутся вместе с рамкой экрана,
// за её краем не видны. Текстура вьюпорта с прозрачным фоном — с предумноженной альфой, отсюда blend_premul_alpha

uniform sampler2D hud_tex : filter_linear;
// Должен совпадать с выпуклостью в player.gdshader
const float BULGE = 0.1;

void fragment() {
	vec2 uv = UV - 0.5;
	uv *= 1.0 + (uv.y * uv.y * BULGE) + (uv.x * uv.x * BULGE);
	uv += 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(hud_tex, uv);
	}
}
