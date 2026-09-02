shader_type spatial;
// cull_disabled ensures you can see the leaves from underneath
// depth_draw_opaque is required for clean alpha scissor shadows
render_mode cull_disabled, depth_draw_opaque;

// Expose texture slots to the inspector
uniform sampler2D color_texture : source_color, filter_linear_mipmap;
uniform sampler2D alpha_mask : hint_default_black, filter_linear_mipmap;

// Expose the clipping threshold
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // Read the color texture using UV 1
    vec4 albedo = texture(color_texture, UV);
    
    // Read the black and white mask using UV 2 (extracting just the red channel)
    float alpha = texture(alpha_mask, UV2).r;
    
    // Apply the values
    ALBEDO = albedo.rgb;
    ALPHA = alpha;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}