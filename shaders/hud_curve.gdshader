shader_type canvas_item;
render_mode blend_premul_alpha;

// Панели HUD на «выпуклом телевизоре»: текстура SubViewport с панелями выводится с той же выпуклостью и той же
// пикселизацией, что и картинка мира в пост-шейдере player.gdshader (коэффициент выпуклости 0.1, resolution
// HUD копирует из материала пост-шейдера), — панели гнутся вместе с рамкой экрана, за её краем не видны, и
// пиксели у них того же размера и на той же сетке. Текстура вьюпорта с прозрачным фоном — с предумноженной
// альфой, отсюда blend_premul_alpha

uniform sampler2D hud_tex : filter_nearest;
// Клеток по ширине экрана, как resolution в player.gdshader; 0 — без пикселизации
uniform float resolution = 0.0;
// Должен совпадать с выпуклостью в player.gdshader
const float BULGE = 0.1;

void fragment() {
	vec2 uv = UV - 0.5;
	uv *= 1.0 + (uv.y * uv.y * BULGE) + (uv.x * uv.x * BULGE);
	uv += 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		if (resolution > 0.0) {
			// Та же сетка, что у пост-шейдера; берём центр клетки
			float screen_aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
			vec2 cells = vec2(resolution, resolution / screen_aspect);
			uv = (floor(uv * cells) + 0.5) / cells;
		}
		COLOR = texture(hud_tex, uv);
	}
}
