shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float distortion_strength : hint_range(0.0, 0.15) = 0.04;
uniform float ripple_speed : hint_range(0.0, 10.0) = 3.2;
uniform float visibility : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_color : source_color = vec4(0.12, 0.05, 0.18, 1.0); // cold dark amethyst
uniform vec4 rim_color : source_color = vec4(0.72, 0.28, 1.0, 1.0); // bright electric violet
uniform float rim_power : hint_range(0.5, 8.0) = 3.2;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float needle_glow : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Normal in view space gives refractive displacement based on 3D geometry
    vec2 normal_offset = NORMAL.xy * distortion_strength;
    
    // Dynamic heat haze / active camouflage ripple
    float wave = sin(SCREEN_UV.y * 32.0 + TIME * ripple_speed) * cos(SCREEN_UV.x * 24.0 + TIME * (ripple_speed * 0.8));
    vec2 ripple = vec2(wave * 0.007, -wave * 0.005);
    
    // UV offset active in stealth, fades out as visibility reaches 1.0
    vec2 distorted_uv = clamp(SCREEN_UV + (normal_offset + ripple) * (1.0 - visibility * 0.85), vec2(0.001), vec2(0.999));
    vec3 bg = texture(screen_texture, distorted_uv).rgb;
    
    // Fresnel rim calculation
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    
    // Stealth refractive appearance with subtle ethereal shimmer
    vec3 stealth_fx = bg + rim_color.rgb * (fresnel * 0.28);
    
    // Solid amethyst body with violet rim highlight
    vec3 solid_fx = base_color.rgb + rim_color.rgb * (fresnel * 0.55);
    
    // Hit flash and needle effects
    vec3 flash_fx = vec3(1.0, 0.2, 0.2) * hit_flash;
    vec3 needle_fx = vec3(0.75, 0.88, 1.0) * needle_glow * 1.5;
    
    vec3 mixed_color = mix(stealth_fx, solid_fx, visibility) + flash_fx + needle_fx;
    
    // In stealth: emit distorted background directly; in solid: emit only highlights
    EMISSION = mix(mixed_color, rim_color.rgb * (fresnel * 0.35), visibility) + flash_fx + needle_fx;
    ALBEDO = mix(vec3(0.0), mixed_color, visibility);
    ROUGHNESS = mix(0.1, 0.45, visibility);
    METALLIC = mix(0.0, 0.5, visibility);
    ALPHA = 1.0;
}
