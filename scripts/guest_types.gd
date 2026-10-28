# =====================================================================
# guest_types.gd  —  the kinds of guests who visit, how they behave and
# what they look like. Shared data plus helpers, used as
# GuestTypes.something() from anywhere (like StaffProfiles).
#
#   Farmer      the everyday guest
#   Town Guard  in a hurry: low patience, wants Ale, tips if served fast
#   Merchant    patient, only orders tier 2 dishes, pays 20% more
#   Old Regular walks slowly, always orders their favorite dish
#   Adventurers a party of 2-3 sharing one table; impatient as a group,
#               tip 25%
#   Noble       only comes to Noble Banquets (see GameManager)
#
# Which dish each type orders is decided by GameManager.pick_order().
# =====================================================================
class_name GuestTypes
extends RefCounted

# patience/speed/pay are multipliers on a normal guest's. looks are the
# sprite sheets this type can use (one is picked at random); hair_key is
# each sheet's hair color for the palette swap (must match
# tools/sprites/make_sprites.py).
const TYPES: Dictionary = {
	"farmer": {
		"title": "Farmer", "patience": 1.0, "speed": 1.0, "pay": 0.0,
		"looks": {"farmer": Color8(130, 85, 50)},
	},
	"guard": {
		"title": "Town Guard", "patience": 0.6, "speed": 1.15, "pay": 0.0,
		"looks": {"guard": Color8(90, 60, 40)},
	},
	"merchant": {
		"title": "Merchant", "patience": 1.4, "speed": 0.95, "pay": 0.2,
		"looks": {"merchant": Color8(60, 40, 30)},
	},
	"regular": {
		"title": "Old Regular", "patience": 1.2, "speed": 0.7, "pay": 0.0,
		"looks": {"regular": Color8(205, 205, 210)},
		"keep_hair": true,   # always grey
	},
	"adventurer": {
		"title": "Adventurer", "patience": 0.8, "speed": 1.0, "pay": 0.25,
		"looks": {"knight": Color8(150, 95, 50), "mage": Color8(175, 110, 60), "rogue": Color8(70, 50, 35)},
	},
	"noble": {
		"title": "Noble", "patience": 1.0, "speed": 0.9, "pay": 0.0,
		"looks": {"lord": Color8(95, 65, 40), "lady": Color8(190, 140, 70)},
	},
}

# How often each type walks in, out of the total, and the fame needed
# before they start coming. Nobles only come to banquets; the Old
# Regular comes at most once a day.
const ARRIVALS: Array = [
	{"type": "farmer", "weight": 45, "fame": 0},
	{"type": "guard", "weight": 20, "fame": 0},
	{"type": "merchant", "weight": 15, "fame": 0},
	{"type": "regular", "weight": 8, "fame": 0},
	{"type": "adventurer", "weight": 12, "fame": 10},
]

# Guard tip for fast service: served with more than half their patience left.
const GUARD_TIP: float = 0.3

const SHEETS: Dictionary = {
	"farmer": preload("res://assets/sprites/guests/farmer.png"),
	"guard": preload("res://assets/sprites/guests/guard.png"),
	"merchant": preload("res://assets/sprites/guests/merchant.png"),
	"regular": preload("res://assets/sprites/guests/regular.png"),
	"knight": preload("res://assets/sprites/guests/knight.png"),
	"mage": preload("res://assets/sprites/guests/mage.png"),
	"rogue": preload("res://assets/sprites/guests/rogue.png"),
	"lord": preload("res://assets/sprites/guests/lord.png"),
	"lady": preload("res://assets/sprites/guests/lady.png"),
}


# Picks who walks in next. `regular_allowed` is false once the Old
# Regular has already been in today.
static func pick_arrival(fame: int, regular_allowed: bool) -> String:
	var choices: Array = ARRIVALS.filter(func(a): return fame >= a["fame"] \
			and (regular_allowed or a["type"] != "regular"))
	var total: int = 0
	for a in choices:
		total += a["weight"]
	var roll: int = randi() % total
	for a in choices:
		roll -= a["weight"]
		if roll < 0:
			return a["type"]
	return "farmer"


# A random look for a guest of this type: which sheet, and their colors
# (reusing the staff palettes).
static func random_look(type: String) -> Dictionary:
	var info: Dictionary = TYPES[type]
	var sheet: String = info["looks"].keys().pick_random()
	var look: Dictionary = {
		"sheet": sheet,
		"skin": randi() % StaffProfiles.SKIN_TONES.size(),
		"hair": randi() % StaffProfiles.HAIR_COLORS.size(),
	}
	if info.get("keep_hair", false):
		look["hair"] = -1   # keep the sheet's own hair
	return look


# A ShaderMaterial that recolors a guest's sheet with their skin and hair.
static func material_for(type: String, look: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = StaffProfiles.SHADER
	var hair_key: Color = TYPES[type]["looks"][look["sheet"]]
	var hair: Color = hair_key if look["hair"] < 0 else StaffProfiles.HAIR_COLORS[look["hair"]]
	mat.set_shader_parameter("skin_key", StaffProfiles._rgb(StaffProfiles.SKIN_KEY))
	mat.set_shader_parameter("skin_dark_key", StaffProfiles._rgb(StaffProfiles.SKIN_DARK_KEY))
	mat.set_shader_parameter("hair_key", StaffProfiles._rgb(hair_key))
	mat.set_shader_parameter("skin_color", StaffProfiles._rgb(StaffProfiles.SKIN_TONES[look["skin"]]))
	mat.set_shader_parameter("hair_color", StaffProfiles._rgb(hair))
	return mat
