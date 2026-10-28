// palette_swap.gdshader  —  gives each staff member their own skin tone
// and hair color from one shared sprite sheet.
//
// The sheets are drawn with fixed "key" colors for skin and hair
// (see tools/sprites/make_sprites.py). Every pixel that matches a key
// color is swapped for this person's color; everything else is untouched.
shader_type canvas_item;

uniform vec3 skin_key;        // the sheet's skin color
uniform vec3 skin_dark_key;   // its darker skin shade
uniform vec3 hair_key;        // this type's hair (or beard) color
uniform vec3 skin_color;      // this person's colors
uniform vec3 hair_color;

// How close (0-1 per channel) counts as "the same color".
const float CLOSE = 0.02;

void fragment() {
	// In a canvas_item shader, COLOR already holds the texture's color
	// (times any modulate), so we recolor it in place.
	vec3 c = COLOR.rgb;
	if (distance(c, skin_key) < CLOSE) {
		COLOR.rgb = skin_color;
	} else if (distance(c, skin_dark_key) < CLOSE) {
		COLOR.rgb = skin_color * 0.88;
	} else if (distance(c, hair_key) < CLOSE) {
		COLOR.rgb = hair_color;
	} else if (distance(c, hair_key * 0.8) < CLOSE) {
		COLOR.rgb = hair_color * 0.8;   // the hair's shadow shade
	}
}
