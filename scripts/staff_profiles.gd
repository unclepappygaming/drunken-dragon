# =====================================================================
# staff_profiles.gd  —  who your staff are: their type, trait, name and
# looks. Nothing here is a node; it's shared data plus helper functions,
# used as StaffProfiles.something() from anywhere.
#
# A PROFILE is a small Dictionary describing one person, so it can go
# straight into the save file:
#   {"uid": 7, "type": "dwarf_cook", "name": "Thrain", "skin": 2, "hair": 5}
# skin and hair are positions in SKIN_TONES and HAIR_COLORS.
# =====================================================================
class_name StaffProfiles
extends RefCounted

# Every staff type. Each look comes with a trait (what makes them good)
# and its own wage. hair_key is the hair (or beard) color in the sprite
# sheet that gets recolored; it must match tools/sprites/make_sprites.py.
const TYPES: Dictionary = {
	"chef": {
		"role": "cook", "title": "Classic Chef", "wage": 30,
		"trait": "Trained", "about": "Cooks every dish 25% faster.",
		"hair_key": Color8(110, 70, 40),
		"names": ["Pierre", "Odette", "Henri", "Margaux", "Gaston", "Celeste"],
	},
	"tavern_cook": {
		"role": "cook", "title": "Tavern Cook", "wage": 25,
		"trait": "Hearty Portions", "about": "Dishes they cook earn 15% more gold.",
		"hair_key": Color8(120, 80, 50),
		"names": ["Bess", "Martha", "Tom", "Wilda", "Gareth", "Nan"],
	},
	"dwarf_cook": {
		"role": "cook", "title": "Dwarf Cook", "wage": 27,
		"trait": "Roast Master", "about": "Roasts (Boar, Wings, Phoenix, Feast) cook 40% faster.",
		"hair_key": Color8(200, 110, 50),   # the beard
		"names": ["Thrain", "Brunhild", "Dorna", "Gimrik", "Hilda", "Borin"],
	},
	"barkeep": {
		"role": "waiter", "title": "Barkeep", "wage": 22,
		"trait": "Smooth Talker", "about": "Guests get 10 more seconds of patience when they order.",
		"hair_key": Color8(160, 100, 50),
		"names": ["Edric", "Rowan", "Mira", "Callum", "Jory", "Fen"],
	},
	"maid": {
		"role": "waiter", "title": "Serving Maid", "wage": 22,
		"trait": "Nimble", "about": "Walks 25% faster.",
		"hair_key": Color8(180, 120, 60),
		"names": ["Elsie", "Rosa", "Nell", "Ivy", "Greta", "Maud"],
	},
	"halfling": {
		"role": "waiter", "title": "Halfling Server", "wage": 18,
		"trait": "Lucky", "about": "1 in 3 guests leaves a big tip (+50%). Short legs: walks 10% slower.",
		"hair_key": Color8(95, 60, 35),
		"names": ["Pip", "Tansy", "Rosie", "Tobo", "Lily", "Fennick"],
	},
}

# Dishes the Dwarf Cook's Roast Master trait speeds up.
const ROAST_DISHES: Array[String] = ["boar", "wings", "phoenix", "feast"]

# The skin colors drawn in every sheet (keys for the palette swap).
const SKIN_KEY: Color = Color8(241, 194, 150)
const SKIN_DARK_KEY: Color = Color8(214, 160, 120)

const SKIN_TONES: Array[Color] = [
	Color8(250, 215, 185), Color8(241, 194, 150), Color8(224, 172, 125),
	Color8(198, 140, 95), Color8(160, 105, 70), Color8(120, 78, 52),
]
const HAIR_COLORS: Array[Color] = [
	Color8(35, 28, 26), Color8(70, 45, 30), Color8(110, 70, 40), Color8(150, 85, 45),
	Color8(200, 110, 50), Color8(225, 185, 110), Color8(170, 170, 175), Color8(130, 40, 35),
]

const SHADER: Shader = preload("res://shaders/palette_swap.gdshader")
const SHEETS: Dictionary = {
	"chef": preload("res://assets/sprites/staff/chef.png"),
	"tavern_cook": preload("res://assets/sprites/staff/tavern_cook.png"),
	"dwarf_cook": preload("res://assets/sprites/staff/dwarf_cook.png"),
	"barkeep": preload("res://assets/sprites/staff/barkeep.png"),
	"maid": preload("res://assets/sprites/staff/maid.png"),
	"halfling": preload("res://assets/sprites/staff/halfling.png"),
}
const FRAME_SIZE: Vector2i = Vector2i(32, 40)


# A random person for a role ("cook" or "waiter"), e.g. a job applicant.
static func random_profile(role: String) -> Dictionary:
	var types: Array = TYPES.keys().filter(func(t): return TYPES[t]["role"] == role)
	var type: String = types.pick_random()
	return {
		"type": type,
		"name": TYPES[type]["names"].pick_random(),
		"skin": randi() % SKIN_TONES.size(),
		"hair": randi() % HAIR_COLORS.size(),
	}


# Makes sure a profile from a save file is usable (unknown type, colors
# out of range...). Returns {} if it can't be saved.
static func clean(profile, role: String) -> Dictionary:
	if typeof(profile) != TYPE_DICTIONARY or not TYPES.has(profile.get("type", "")):
		return {}
	if TYPES[profile["type"]]["role"] != role:
		return {}
	return {
		"uid": int(profile.get("uid", 0)),
		"type": profile["type"],
		"name": str(profile.get("name", "Someone")),
		"skin": clampi(int(profile.get("skin", 1)), 0, SKIN_TONES.size() - 1),
		"hair": clampi(int(profile.get("hair", 2)), 0, HAIR_COLORS.size() - 1),
	}


static func role_of(profile: Dictionary) -> String:
	return TYPES[profile["type"]]["role"]


static func wage(profile: Dictionary) -> int:
	return TYPES[profile["type"]]["wage"]


# A ShaderMaterial that recolors the sheet with this person's colors.
# Each person gets their own, so changing one doesn't change the others.
static func material_for(profile: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var info: Dictionary = TYPES[profile["type"]]
	mat.set_shader_parameter("skin_key", _rgb(SKIN_KEY))
	mat.set_shader_parameter("skin_dark_key", _rgb(SKIN_DARK_KEY))
	mat.set_shader_parameter("hair_key", _rgb(info["hair_key"]))
	mat.set_shader_parameter("skin_color", _rgb(SKIN_TONES[profile["skin"]]))
	mat.set_shader_parameter("hair_color", _rgb(HAIR_COLORS[profile["hair"]]))
	return mat


# The front-facing standing frame, for pictures in menus.
static func portrait(profile: Dictionary) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEETS[profile["type"]]
	atlas.region = Rect2(Vector2.ZERO, FRAME_SIZE)
	return atlas


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
