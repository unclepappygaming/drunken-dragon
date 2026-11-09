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
#   Bard        plays while seated: guests nearby lose patience half as fast
#   Elf         only drinks Elven Wine (only comes when it's on the menu),
#               and pays double
#   Dwarf Miner orders a second dish after the first
#   Wizard      impatient, but tips well
#   Food Critic only on a Food Critic day (see GameManager.EVENTS)
#   Pixie, Dryad, Satyr  the fae, who visit on a Fae Night
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
	"bard": {
		"title": "Bard", "patience": 1.2, "speed": 1.0, "pay": 0.1,
		"looks": {"bard": Color8(200, 140, 70)},
	},
	"elf": {
		"title": "Elf", "patience": 1.0, "speed": 1.05, "pay": 1.0,
		"looks": {"elf": Color8(235, 225, 170)},
		"keep_hair": true,
	},
	"miner": {
		"title": "Dwarf Miner", "patience": 1.0, "speed": 0.85, "pay": 0.0,
		"looks": {"miner": Color8(150, 110, 70)},   # the beard
	},
	"wizard": {
		"title": "Wizard", "patience": 0.6, "speed": 0.9, "pay": 0.4,
		"looks": {"wizard": Color8(215, 215, 220)},
		"keep_hair": true,   # always white
	},
	"critic": {
		"title": "Food Critic", "patience": 0.8, "speed": 1.0, "pay": 0.0,
		"looks": {"critic": Color8(80, 60, 50)},
	},
	"fae": {
		"title": "Fae", "patience": 1.0, "speed": 1.1, "pay": 0.3,
		"looks": {"pixie": Color8(240, 170, 200), "dryad": Color8(90, 150, 70), "satyr": Color8(110, 70, 40)},
		"keep_hair": true,
	},
}

# How often each type walks in, out of the total, and the fame needed
# before they start coming. Nobles only come to banquets; the Old
# Regular comes at most once a day. A "pair" is two guests of one type
# (see PAIR_TYPES) who share a table, sitting across from each other:
# PAIR_SHARE of everyone who walks in comes as a pair.
const PAIR_SHARE: float = 0.6
const ARRIVALS: Array = [
	{"type": "farmer", "weight": 35, "fame": 0},
	{"type": "guard", "weight": 20, "fame": 0},
	{"type": "merchant", "weight": 15, "fame": 0},
	{"type": "regular", "weight": 8, "fame": 0},
	{"type": "adventurer", "weight": 12, "fame": 10},
	{"type": "bard", "weight": 6, "fame": 15},
	{"type": "miner", "weight": 6, "fame": 20},
	{"type": "elf", "weight": 5, "fame": 40},
	{"type": "wizard", "weight": 5, "fame": 55},
]

# Who comes as a pair: [weight, fame needed].
const PAIR_TYPES: Dictionary = {
	"farmer": [40, 0], "merchant": [22, 0], "guard": [18, 0],
	"miner": [8, 20], "elf": [7, 40], "wizard": [5, 55],
}


static func pick_pair_type(fame: int = 0) -> String:
	var choices: Array = PAIR_TYPES.keys().filter(func(t): return fame >= PAIR_TYPES[t][1] \
			and (t != "elf" or GameManager.menu.has("wine")))
	var total: int = 0
	for t in choices:
		total += PAIR_TYPES[t][0]
	var roll: int = randi() % total
	for t in choices:
		roll -= PAIR_TYPES[t][0]
		if roll < 0:
			return t
	return "farmer"


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
	"bard": preload("res://assets/sprites/guests/bard.png"),
	"elf": preload("res://assets/sprites/guests/elf.png"),
	"miner": preload("res://assets/sprites/guests/miner.png"),
	"wizard": preload("res://assets/sprites/guests/wizard.png"),
	"critic": preload("res://assets/sprites/guests/critic.png"),
	"pixie": preload("res://assets/sprites/guests/pixie.png"),
	"dryad": preload("res://assets/sprites/guests/dryad.png"),
	"satyr": preload("res://assets/sprites/guests/satyr.png"),
}


# Picks who walks in next. `regular_allowed` is false once the Old
# Regular has already been in today.
static func pick_arrival(fame: int, regular_allowed: bool) -> String:
	if randf() < PAIR_SHARE:
		return "pair"
	var choices: Array = ARRIVALS.filter(func(a): return fame >= a["fame"] \
			and (regular_allowed or a["type"] != "regular") \
			and (a["type"] != "elf" or GameManager.menu.has("wine")))   # elves only come for the wine
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
