shader_type sky;

// cloud credits https://www.shadertoy.com/view/NlKGWK https://gemini.google.com/app/bb4e659bd960ac82
// star credits https://www.shadertoy.com/view/ldlcRf https://gemini.google.com/app/ad4c60f80d2cb15d

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

// --- STAR UNIFORMS ---
uniform float star_threshold : hint_range(0.0, 1.0) = 0.995; // How many stars
uniform float star_size : hint_range(0.0, 1.0) = 0.2;      // How big the dots are
uniform float star_glow_intensity : hint_range(0.0, 5.0) = 0.2;
uniform float star_twinkle_speed : hint_range(0.0, 10.0) = 1.3;
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 1.0);

// --- CLOUD UNIFORMS (Add these at the top) ---
uniform float cloud_scale : hint_range(0.1, 2.0) = 0.05;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.0025;
uniform float cloud_edge : hint_range(0.0, 1.0) = 0.3;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);

// Helper for cloud rotation
mat2 rot(float a) {
    return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// A simple high-frequency hash function
float hash(vec2 p) {
	p  = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// A more robust 3D Hash that handles large coordinates better
float stable_hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
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
	
	// --- IMPROVED STARS ---

	// 1. Create a stable grid in world space
	// Using a slightly lower scale (200 instead of 500) helps with precision/scrambling
	vec3 star_grid = EYEDIR * 250.0;
	vec3 id = floor(star_grid);
	vec3 f = fract(star_grid) - 0.5; // Center the star in the grid cell

	// 2. Unique ID for each star
	float star_noise = stable_hash3(id);

	// 3. Twinkle Logic 
	// We multiply the noise by a HUGE prime number so every star is on a different phase
	float twinkle = sin(TIME * star_twinkle_speed + (star_noise * 9876.54)) * 0.5 + 0.5;

	// 4. Star Shape and Glow
	// Distance from the pixel to the center of the grid cell
	float dist = length(f);

	// The Core: A very tight, bright spot
	float core = smoothstep(star_size, star_size * 0.5, dist);

	// The Glow: A wider, soft falloff using inverse square (more realistic)
	// We boost the glow so it's actually visible against the sky
	float glow = (0.02 / (dist + 0.05)) * star_glow_intensity;

	// 5. Thresholding
	// Only draw the star if the random noise for this cell is high enough
	float star_mask = step(star_threshold, star_noise);

	// 6. Final Integration
	// Increase the multiplier (e.g., 5.0) to make them pop!
	float day_fade = clamp(1.0 - (sun_direction.y * 4.0), 0.0, 1.0);
	vec3 final_stars = star_color * (core + glow) * star_mask * twinkle * day_fade * 5.0;
	
	// --- CLOUD LOGIC ---
	float cloud_density = 0.0;
	
	float vertical_squish = pow(max(EYEDIR.y, 0.0) + 0.3, 2);
	
	// We use EYEDIR.xz for the horizontal plane and project the sphere
	vec2 cloud_p = EYEDIR.xz / (vertical_squish);
	cloud_p *= cloud_scale;
	cloud_p.x += TIME * cloud_speed;

	// Iterative Sine-based Noise loop
	for(float s = 50.0; s > 10.0; s *= 0.8) {
	    cloud_p *= rot(s);
	    cloud_p += s;
	    // Accumulate sine waves
	    cloud_density += abs(dot(sin(cloud_p * s + TIME * 0.02) / s, vec2(1.65)));
	}

	// Shape the clouds (thresholding)
	float cloud_mask = cloud_density * smoothstep(cloud_edge + 0.1, cloud_edge, cloud_density - 0.095);
	// Fade clouds near horizon so they don't look like a flat cap
	float horizon_fade = smoothstep(0.05, 0.3, EYEDIR.y);
	
	// 1. Calculate a "daylight factor"
	// sun_direction.y is 1.0 at noon and -1.0 at midnight.
	// We use sat() or clamp() to keep the value between 0.0 and 1.0.
	float day_factor = clamp(sun_direction.y, 0.0, 1.0);

	// 2. Define your night and day transparency targets
	float night_trans = 0.03;
	float day_trans = 0.3;

	// 3. Interpolate between the two based on the sun's position
	float cloud_alpha = mix(night_trans, day_trans, day_factor);

	// 4. Apply this to your final cloud color
	// Use the flattened coordinates and horizon fade we discussed earlier
	vec3 final_clouds = cloud_mask * horizon_fade * cloud_color * cloud_alpha;

	// Make the final color
	COLOR = final_color + final_sun + final_moon + final_stars + final_clouds;
}