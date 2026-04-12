shader_type sky;

// Sky color uniforms
uniform vec3 zenith_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 ground_color : source_color;
uniform float horizon_blur : hint_range(0.0, 1.0) = 0.1;

// Sun / moon uniforms
uniform vec3 sun_direction; // Direction from your DirectionalLight3D
uniform vec3 moon_direction;
uniform vec3 sun_color : source_color;
uniform vec3 moon_color : source_color;

uniform float sun_size : hint_range(0.01, 0.5) = 0.05;
uniform float sun_blur : hint_range(0.01, 20.0) = 10.0;
uniform float moon_size : hint_range(0.01, 0.5) = 0.04;
uniform float moon_blur : hint_range(0.01, 20.0) = 10.0;
uniform float moon_crescent_offset : hint_range(-0.1, 0.1) = 0.01;

// A simple high-frequency hash function
float hash(vec2 p) {
	p  = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void sky() {
    float v_val = EYEDIR.y;
    
    // 1. Create screen-space noise
    // SCREEN_UV is available in the sky shader in Godot 4
    float dither = hash(SCREEN_UV * 1000.0); 
    
    // 2. Apply a tiny offset to the blend value (approx 1/255th of a color step)
    float dither_strength = 0.01;
    float blended_v = v_val + (dither - 0.5) * dither_strength;

    vec3 final_color;
    if (blended_v > 0.0) {
        float blend = smoothstep(0.0, horizon_blur, blended_v);
        final_color = mix(horizon_color, zenith_color, blend);
    } else {
        float blend = smoothstep(0.0, -horizon_blur, blended_v);
        final_color = mix(horizon_color, ground_color, blend);
    }
	
	// --- SUN ---
    float sun_dot = distance(EYEDIR, sun_direction);
    // Draw the sun disk
    float sun_mask = smoothstep(sun_size, sun_size * 0.9, sun_dot);
    // Draw the glow using an exponential decay
    float sun_glow = exp(-sun_dot * sun_blur);
    vec3 final_sun = sun_color * (sun_mask + sun_glow);
    
    // --- MOON ---
    float moon_dot = distance(EYEDIR + vec3(0.01, 0.005, 0.0), moon_direction);
    
    // 1. The main moon body
    float moon_mask = smoothstep(moon_size, moon_size * 0.9, moon_dot);
    
    // 2. The "biter" circle 
    // We offset the EYEDIR slightly to the side to shift the shadow
    float moon_shadow_dot = distance(EYEDIR + vec3(moon_crescent_offset, 0.0, 0.0), moon_direction);
    float moon_shadow_mask = smoothstep(moon_size, moon_size * 0.9, moon_shadow_dot);
    
    // 3. Subtract the shadow from the moon
    // clamp ensures we don't get negative color values
    float crescent = clamp(moon_mask - moon_shadow_mask, 0.0, 1.0);
    
    // 4. The Glow (Keep this a full circle for a "magical" look)
    float moon_glow = exp(-moon_dot * moon_blur);
    vec3 final_moon = moon_color * (crescent + moon_glow);

	// Make the final color
	COLOR = final_color + final_sun + final_moon;
}