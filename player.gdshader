shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_nearest;
uniform float resolution = 320.0; 
uniform float noise_amount = 0.06; // Сила шума (можно менять в Инспекторе)
uniform float player_speed = 0.0; // Текущая горизонтальная скорость игрока
uniform float speed_threshold = 14.5; // Порог скорости для начала эффекта (только на действительно высокой скорости)
uniform float max_speed_threshold = 19.5; // Скорость максимального эффекта

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
        
        // Мягкая базовая виньетка
        float dist = distance(uv, vec2(0.5, 0.5));
        float base_vignette = smoothstep(0.85, 0.45, dist);
        
        // Эффект высокой скорости (тонкая, едва уловимая виньетка + слабые спидлайны на пике скорости)
        float speed_factor = clamp((player_speed - speed_threshold) / (max_speed_threshold - speed_threshold), 0.0, 1.0);
        if (speed_factor > 0.0) {
            // Тонкое динамическое усиление виньетки по краям
            float speed_vignette = smoothstep(0.85 - (speed_factor * 0.06), 0.40, dist);
            base_vignette *= mix(1.0, speed_vignette, speed_factor * 0.15);
            
            // Едва заметные радиальные полосы скорости (speed lines) на самом краю экрана
            vec2 dir = uv - vec2(0.5, 0.5);
            float angle = atan(dir.y, dir.x);
            float ray_sector = floor((angle + 3.14159265) * 18.0);
            float ray_rand = fract(sin(ray_sector * 92.13 + floor(TIME * 24.0) * 17.89) * 43758.5453);
            float is_ray = step(0.72, ray_rand);
            float edge_mask = smoothstep(0.42, 0.70, dist);
            float line_intensity = is_ray * edge_mask * speed_factor * 0.08;
            
            tex_color.rgb += vec3(line_intensity);
        }
        
        tex_color.rgb *= base_vignette;
        COLOR = tex_color;
    }
}