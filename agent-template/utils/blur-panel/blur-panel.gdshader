shader_type canvas_item;

uniform float darken_amount: hint_range(1.0, 5.0) = 1.0;
uniform float blur_amount: hint_range(0.0, 5.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 color = texture(SCREEN_TEXTURE, SCREEN_UV, blur_amount);
	COLOR = vec4(color.r / darken_amount, color.g / darken_amount, color.b / darken_amount, 1.0);
}