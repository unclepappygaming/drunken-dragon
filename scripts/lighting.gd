# =====================================================================
# lighting.gd  —  day turning to night. Created by main.gd.
#
# While the tavern is open, the light OUTSIDE changes with the clock:
# plain daylight in the morning, warm late-afternoon sun, an orange dusk
# during the dinner rush, and a blue night before closing. Inside, the
# tavern stays lit (its windows show the night sky, and candles come out
# on the tables). Between days it's daylight again.
#
# Only the scenery is tinted (and the empty space beyond it). Its lights
# (lamp posts, house windows) are soft glows drawn on a layer above that
# follows the camera, so they shine through the dark.
# =====================================================================
class_name Lighting
extends Node

# [hour, tint]: the light at each time of day, blended in between.
const TINTS: Array = [
	[9.0, Color(1.0, 1.0, 1.0)],
	[15.0, Color(1.0, 0.97, 0.9)],
	[17.5, Color(1.0, 0.86, 0.72)],
	[19.0, Color(0.82, 0.68, 0.7)],
	[20.0, Color(0.58, 0.58, 0.78)],
	[21.0, Color(0.48, 0.5, 0.72)],
]
const LIGHT_FROM: float = 17.5   # lights start to show at this hour...
const LIGHT_FULL: float = 20.0   # ...and are at full strength by this one

var grid: TavernGrid
var scenery: Scenery
var night: float = 0.0           # 0 = full day, 1 = full night (lights at full strength)

var _glows: Node2D


func setup(main: Node, tavern_grid: TavernGrid, around: Scenery) -> void:
	grid = tavern_grid
	scenery = around
	var layer := CanvasLayer.new()
	layer.layer = 1                    # above the room, below the HUD (layer 2)
	layer.follow_viewport_enabled = true   # moves and zooms with the camera
	main.add_child(layer)
	_glows = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # light adds up, it doesn't cover
	_glows.material = add
	layer.add_child(_glows)
	_glows.draw.connect(_draw_glows)


func _process(_delta: float) -> void:
	var hour: float = GameManager.OPEN_HOUR + GameManager.minutes_since_open / 60.0
	if not GameManager.is_open and not _closing():
		hour = GameManager.OPEN_HOUR   # between days: daylight, to build by
	var tint: Color = tint_at(hour)
	if GameManager.today_event == "rain" and GameManager.is_open:
		tint *= Color(0.78, 0.8, 0.88)   # a grey, overcast sky
	scenery.modulate = tint
	RenderingServer.set_default_clear_color(scenery.base_color() * tint)
	night = night_at(hour)
	_glows.queue_redraw()


# After closing time the last guests are still leaving: stay dark until
# the day summary shows.
func _closing() -> bool:
	return grid.get_tree().get_nodes_in_group("customers").size() > 0


# 0 in the day, rising to 1 at full night.
static func night_at(hour: float) -> float:
	return clampf((hour - LIGHT_FROM) / (LIGHT_FULL - LIGHT_FROM), 0.0, 1.0)


static func tint_at(hour: float) -> Color:
	if hour <= TINTS[0][0]:
		return TINTS[0][1]
	for i in range(1, TINTS.size()):
		if hour <= TINTS[i][0]:
			var t: float = (hour - TINTS[i - 1][0]) / (TINTS[i][0] - TINTS[i - 1][0])
			return TINTS[i - 1][1].lerp(TINTS[i][1], t)
	return TINTS[-1][1]


func _draw_glows() -> void:
	if night <= 0.01:
		return
	var flicker: float = 0.92 + 0.08 * sin(Time.get_ticks_msec() / 130.0)
	for light in scenery.light_spots():
		var at: Vector2 = light[0]
		var radius: float = light[1]
		var color: Color = light[2]
		var strength: float = night * flicker
		# A few rings, faint at the edge and bright in the middle.
		for ring in 4:
			var r: float = radius * (1.0 - ring * 0.22)
			_glows.draw_circle(at, r, Color(color.r, color.g, color.b, 0.07 * strength))
		_glows.draw_circle(at, radius * 0.12, Color(color.r, color.g, color.b, 0.5 * strength))
