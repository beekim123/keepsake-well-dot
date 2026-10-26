shader_type canvas_item;
uniform float outlined = 0.0;
uniform float flash_amount = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
// CanvasItem fragment COLOR already includes the texture. Preserve only the
// vertex tint so source pixels, fades and transparent-edge outlines multiply once.
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float nearby = texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x,0.0)).a;
	nearby = max(nearby, texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x,0.0)).a);
	nearby = max(nearby, texture(TEXTURE, UV + vec2(0.0,TEXTURE_PIXEL_SIZE.y)).a);
	nearby = max(nearby, texture(TEXTURE, UV - vec2(0.0,TEXTURE_PIXEL_SIZE.y)).a);
	vec4 out_color = vec4(mix(pixel.rgb, flash_color.rgb, flash_amount),pixel.a);
	if (pixel.a < 0.1 && nearby > 0.1 && outlined > 0.5) { out_color = vec4(1.0,0.98,0.91,1.0); }
	COLOR = out_color * vertex_tint;
}
