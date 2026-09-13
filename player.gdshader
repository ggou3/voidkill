shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_nearest;
uniform float resolution = 320.0; 
uniform float noise_amount = 0.06; // Сила шума (можно менять в Инспекторе)
uniform float player_speed = 0.0; // Текущая горизонтальная скорость игрока
uniform float speed_threshold = 14.5; // Порог скорости для начала эффекта (только на действительно высокой скорости)
uniform float max_speed_threshold = 19.5; // Скорость максимального эффекта
uniform float overdrive_factor = 0.0; // 0.0 при bpm <= 180, плавно растет до 1.0 при bpm = 200 (тир OVERDRIVE)

// Функция генерации псевдослучайного шума на основе времени и координат
float random(vec2 uv, float time) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233)) + time) * 43758.5453123);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Выпуклость экрана (сделана чуть слабее)
    uv -= 0.5;
    uv *= 1.0 + (uv.y * uv.y * 0.1) + (uv.x * uv.x * 0.1);
    uv += 0.5;

    // Черные рамки за пределами экрана
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        // Пикселизация
        vec2 pixelated_uv = floor(uv * resolution) / resolution;
        vec4 tex_color = texture(SCREEN_TEXTURE, pixelated_uv);
        
        // Наложение динамического шума
        // Вычитаем 0.5, чтобы шум уходил как в светлые, так и в темные тона, не выбеливая картинку
        float noise = (random(pixelated_uv, TIME) - 0.5) * noise_amount;
        tex_color.rgb += noise;
        
        // Desaturation на тире OVERDRIVE (плавный переход от bpm 180 к bpm 200)
        // Обесцвечивает фон и врагов, сохраняя видимыми красные элементы (кровь, урон, вспышки, алые глаза)
        if (overdrive_factor > 0.0) {
            float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
            
            // Выделение красного оттенка (преобладание красного над зеленым и синим)
            float max_gb = max(tex_color.g, tex_color.b);
            float red_diff = tex_color.r - max_gb;
            float red_ratio = red_diff / max(tex_color.r, 0.001);
            
            // Маска красного цвета (активна для крови, алых глаз, дульных вспышек и индикаторов урона)
            float red_mask = smoothstep(0.06, 0.22, red_diff) * smoothstep(0.18, 0.40, red_ratio);
            
            // Обесцвеченная картинка с сохранением насыщенности красных пикселей
            vec3 desaturated_col = mix(vec3(gray), tex_color.rgb, red_mask);
            
            // Почти полное обесцвечивание фона (~92%) при максимальном OVERDRIVE (bpm = 200)
            float desat_amount = overdrive_factor * 0.92;
            tex_color.rgb = mix(tex_color.rgb, desaturated_col, desat_amount);
        }
        
        // Мягкая базовая виньетка
        float dist = distance(uv, vec2(0.5, 0.5));
        float base_vignette = smoothstep(0.85, 0.45, dist);
        
        // Эффект высокой скорости и тира OVERDRIVE
        float speed_factor = clamp((player_speed - speed_threshold) / (max_speed_threshold - speed_threshold), 0.0, 1.0);
        // Дополнительный множитель интенсивности x1.5-2 на тире OVERDRIVE
        float overdrive_intensity_mult = 1.0 + (overdrive_factor * 0.85); // 1.0x при bpm 180 -> ~1.85x при bpm 200
        
        if (speed_factor > 0.0 || overdrive_factor > 0.0) {
            // Тонкое динамическое усиление виньетки по краям, усиленное на тире OVERDRIVE
            float combined_vignette_factor = clamp(speed_factor * overdrive_intensity_mult + (overdrive_factor * 0.18), 0.0, 1.5);
            float speed_vignette = smoothstep(0.85 - (combined_vignette_factor * 0.08), 0.38, dist);
            base_vignette *= mix(1.0, speed_vignette, combined_vignette_factor * 0.22);
        }
        
        if (speed_factor > 0.0) {
            // Радиальные полосы скорости (speed lines) на самом краю экрана,
            // усиленные множителем x1.5-2 на тире OVERDRIVE
            vec2 dir = uv - vec2(0.5, 0.5);
            float angle = atan(dir.y, dir.x);
            float ray_sector = floor((angle + 3.14159265) * 18.0);
            float ray_rand = fract(sin(ray_sector * 92.13 + floor(TIME * 24.0) * 17.89) * 43758.5453);
            float is_ray = step(0.72, ray_rand);
            float edge_mask = smoothstep(0.42, 0.70, dist);
            float line_intensity = is_ray * edge_mask * speed_factor * 0.08 * overdrive_intensity_mult;
            
            tex_color.rgb += vec3(line_intensity);
        }
        
        tex_color.rgb *= base_vignette;
        COLOR = tex_color;
    }
}