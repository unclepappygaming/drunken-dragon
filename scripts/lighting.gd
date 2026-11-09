# =====================================================================
# lighting.gd  —  day turning to night. Created by main.gd.
#
# While the tavern is open, the light changes with the clock: plain
# daylight in the morning, warm late-afternoon sun, an orange dusk during
# the dinner rush, and a blue night before closing. Between days it's
# daylight again, so building is easy to see.
#
# Darkening is a CanvasModulate (it tints the whole room). Lights (the
# windows, lamp posts, candles on the tables) are soft glows drawn on a
# layer above it that follows the camera, so they shine through the
# dark. Their strength follows how dark it is.
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

var _tint: CanvasModulate
var _glows: Node2D


func setup(main: Node, tavern_grid: TavernGrid, around: Scenery) -> void:
	grid = tavern_grid
	scenery = around
	_tint = CanvasModulate.new()
	main.add_child(_tint)
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
	_tint.color = tint_at(hour)
	night = clampf((hour - LIGHT_FROM) / (LIGHT_FULL - LIGHT_FROM), 0.0, 1.0)
	_glows.queue_redraw()


# After closing time the last guests are still leaving: stay dark until
# the day summary shows.
func _closing() -> bool:
	return grid.get_tree().get_nodes_in_group("customers").size() > 0


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
	for light in grid.light_spots() + scenery.light_spots():
		var at: Vector2 = light[0]
		var radius: float = light[1]
		var color: Color = light[2]
		var strength: float = night * flicker
		# A few rings, faint at the edge and bright in the middle.
		for ring in 4:
			var r: float = radius * (1.0 - ring * 0.22)
			_glows.draw_circle(at, r, Color(color.r, color.g, color.b, 0.07 * strength))
		_glows.draw_circle(at, radius * 0.12, Color(color.r, color.g, color.b, 0.5 * strength))
