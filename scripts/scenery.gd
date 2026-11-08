# =====================================================================
# scenery.gd  —  the world around the tavern, so it doesn't float in an
# empty space. Created by main.gd and drawn behind everything else.
#
# Three looks (style):
#   "meadow"  green grass, a dirt path from the door, trees, a well, a cottage
#   "city"    a busy medieval town: cobbled streets, town houses, market
#             stalls, lamp posts and townsfolk walking past
#   "forest"  a fae clearing: dark grass, tall pines, glowing toadstools
#             and fireflies
#
# The layout is made up once (the same every time, for a given floor
# size and door) and rebuilt when the floor grows or the door moves.
# Tall things never stand in front of the tavern, where they'd hide it.
# =====================================================================
class_name Scenery
extends Node2D

const DEFAULT_STYLE: String = "meadow"   # the country tavern's surroundings
const MARGIN: int = 18          # squares of scenery around the floor
const CLEAR: int = 2            # squares next to the walls kept empty (the waiting line)
const SCALE: float = 2.0        # sprite pixels -> world pixels, like everything else

const ART: Dictionary = {
	"oak": preload("res://assets/sprites/outdoors/oak.png"),
	"pine": preload("res://assets/sprites/outdoors/pine.png"),
	"bush": preload("res://assets/sprites/outdoors/bush.png"),
	"rock": preload("res://assets/sprites/outdoors/rock.png"),
	"lamp": preload("res://assets/sprites/outdoors/lamp.png"),
	"well": preload("res://assets/sprites/outdoors/well.png"),
	"fence": preload("res://assets/sprites/outdoors/fence.png"),
	"cottage": preload("res://assets/sprites/outdoors/cottage.png"),
	"cottage_blue": preload("res://assets/sprites/outdoors/cottage_blue.png"),
	"cottage_ochre": preload("res://assets/sprites/outdoors/cottage_ochre.png"),
	"townhouse": preload("res://assets/sprites/outdoors/townhouse.png"),
	"townhouse_blue": preload("res://assets/sprites/outdoors/townhouse_blue.png"),
	"townhouse_rose": preload("res://assets/sprites/outdoors/townhouse_rose.png"),
	"stall_red": preload("res://assets/sprites/outdoors/stall_red.png"),
	"stall_blue": preload("res://assets/sprites/outdoors/stall_blue.png"),
	"stall_green": preload("res://assets/sprites/outdoors/stall_green.png"),
}
# Where the middle of the piece's square is in its picture (see
# tools/sprites/make_outdoors.py); anything not listed is (32, 58).
const ANCHORS: Dictionary = {
	"oak": Vector2(48, 116), "pine": Vector2(32, 116), "lamp": Vector2(32, 92),
	"cottage": Vector2(64, 120), "cottage_blue": Vector2(64, 120), "cottage_ochre": Vector2(64, 120),
	"townhouse": Vector2(64, 150), "townhouse_blue": Vector2(64, 150), "townhouse_rose": Vector2(64, 150),
}
const HOUSES: Array[String] = ["cottage", "cottage_blue", "cottage_ochre", "townhouse", "townhouse_blue", "townhouse_rose"]
const STALLS: Array[String] = ["stall_red", "stall_blue", "stall_green"]
const TOWNSFOLK: Array[String] = ["farmer", "merchant", "guard", "regular", "knight", "mage", "rogue", "lady", "lord"]

# Ground colours: [even square, odd square, detail]
const GROUND: Dictionary = {
	"meadow": [Color8(124, 172, 88), Color8(116, 164, 82), Color8(150, 196, 104)],
	"city": [Color8(152, 148, 140), Color8(142, 138, 131), Color8(118, 114, 108)],
	"forest": [Color8(66, 112, 70), Color8(60, 104, 66), Color8(90, 140, 86)],
}
const PATH_COLOR := Color8(196, 164, 112)
const STREET_COLOR := Color8(126, 122, 116)

var grid: TavernGrid
var style: String = "meadow"

var _items: Array = []      # [art name, cell, mirrored], back to front
var _path: Dictionary = {}  # squares of path / street
var _walkers: Array = []    # townsfolk: {sheet, a, b (squares), t, speed}
var _lights: Array = []     # fireflies: {spot, phase}
var _overlay: Node2D        # scenery pieces, walkers and fireflies, redrawn every frame


func _ready() -> void:
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_style(new_style: String) -> void:
	style = new_style
	rebuild()


# Called whenever the layout changes; only rebuilds if the floor size or
# the door moved (building tables doesn't change the scenery).
var _built_for: Array = []


func refresh() -> void:
	var key: Array = [style, grid.cols, grid.rows, grid.door_cell]
	if key != _built_for:
		rebuild()


# The look for where the tavern is: the Grand Hall is in the capital.
static func style_for_location() -> String:
	return "city" if GameManager.in_hall() else DEFAULT_STYLE


func base_color() -> Color:
	return GROUND[style][0]


# Lays everything out again (after the floor grows or the door moves).
func rebuild() -> void:
	_built_for = [style, grid.cols, grid.rows, grid.door_cell]
	position = grid.position
	_items.clear()
	_path.clear()
	_walkers.clear()
	_lights.clear()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = hash([style, grid.cols, grid.rows, grid.door_cell])
	# The path (or main street) runs out from the door.
	var out: Vector2 = TavernGrid.OUTWARD[grid.door_side]
	var step := Vector2i(int(out.x), int(out.y))
	for k in range(1, MARGIN + 1):
		_path[grid.door_cell + step * k] = true
	match style:
		"meadow": _lay_out_meadow(rnd)
		"city": _lay_out_city(rnd)
		"forest": _lay_out_forest(rnd)
	# Back to front, so nearer things are drawn over farther ones.
	_items.sort_custom(func(a, b): return a[1].x + a[1].y < b[1].x + b[1].y)
	queue_redraw()


func _process(delta: float) -> void:
	for w in _walkers:
		w["t"] += delta * w["speed"]
	_overlay.queue_redraw()


# ---------------------------------------------------------------------
# Layouts
# ---------------------------------------------------------------------
func _lay_out_meadow(rnd: RandomNumberGenerator) -> void:
	_try_add("well", grid.door_cell + Vector2i(3, 3), rnd)
	_try_add("cottage", Vector2i(-6, 2), rnd)
	_try_add("cottage_ochre", Vector2i(3, -7), rnd)
	for cell in _all_cells(rnd):
		var roll: float = rnd.randf()
		if roll < 0.05:
			_try_add("oak", cell, rnd)
		elif roll < 0.07:
			_try_add("pine", cell, rnd)
		elif roll < 0.11:
			_try_add("bush", cell, rnd)
		elif roll < 0.13:
			_try_add("rock", cell, rnd)
	# A fence along both sides of the path, a little way out.
	for cell in _path:
		var side := Vector2i(_path_dir().y, _path_dir().x)
		if (cell - grid.door_cell).length() > CLEAR + 1:
			for s in [-1, 1]:
				_try_add("fence", cell + side * s, rnd, _path_dir().x == 0)


func _lay_out_city(rnd: RandomNumberGenerator) -> void:
	# Streets: one along each front wall a little way out, one along each
	# back wall, and the main street from the door.
	for k in range(-MARGIN, maxi(grid.cols, grid.rows) + MARGIN):
		for lane in [grid.rows + 3, -4]:
			_path[Vector2i(k, lane)] = true
		for lane in [grid.cols + 3, -4]:
			_path[Vector2i(lane, k)] = true
	# Houses on 3 x 3 plots (a 2 x 2 house and an alley), wherever they fit.
	for x in range(-MARGIN, grid.cols + MARGIN, 3):
		for y in range(-MARGIN, grid.rows + MARGIN, 3):
			if rnd.randf() < 0.85:
				_try_add(HOUSES[rnd.randi() % HOUSES.size()], Vector2i(x, y), rnd, rnd.randf() < 0.5, 2)
	# Market stalls and lamp posts beside the streets.
	for cell in _path:
		var roll: float = rnd.randf()
		if roll < 0.10:
			_try_add(STALLS[rnd.randi() % STALLS.size()], cell + Vector2i(1, 1), rnd, rnd.randf() < 0.5)
		elif roll < 0.16:
			_try_add("lamp", cell + Vector2i(-1, 1), rnd)
	_try_add("well", grid.door_cell + Vector2i(4, 4), rnd)
	# Townsfolk walking up and down every street, and along the main street.
	var lanes: Array = [
		[Vector2(-MARGIN, grid.rows + 3.5), Vector2(grid.cols + MARGIN, grid.rows + 3.5)],
		[Vector2(grid.cols + 3.5, -MARGIN), Vector2(grid.cols + 3.5, grid.rows + MARGIN)],
		[Vector2(-MARGIN, -3.5), Vector2(grid.cols + MARGIN, -3.5)],
		[Vector2(-3.5, -MARGIN), Vector2(-3.5, grid.rows + MARGIN)],
		[Vector2(grid.door_cell) + Vector2(0.5, 0.5) + Vector2(_path_dir()) * (CLEAR + 1),
				Vector2(grid.door_cell) + Vector2(0.5, 0.5) + Vector2(_path_dir()) * MARGIN],
	]
	for i in 32:
		var lane: Array = lanes[i % lanes.size()]
		_walkers.append({"sheet": GuestTypes.SHEETS[TOWNSFOLK[rnd.randi() % TOWNSFOLK.size()]],
				"a": lane[0], "b": lane[1], "t": rnd.randf() * 2.0,
				"speed": rnd.randf_range(0.6, 1.2) / lane[0].distance_to(lane[1])})


func _lay_out_forest(rnd: RandomNumberGenerator) -> void:
	for cell in _all_cells(rnd):
		var roll: float = rnd.randf()
		if roll < 0.14:
			_try_add("pine", cell, rnd)
		elif roll < 0.17:
			_try_add("oak", cell, rnd)
		elif roll < 0.22:
			_try_add("bush", cell, rnd)
		elif roll < 0.25:
			_try_add("rock", cell, rnd)
	# Fireflies drifting over the clearing.
	for i in 40:
		var cell := Vector2i(rnd.randi_range(-8, grid.cols + 8), rnd.randi_range(-8, grid.rows + 8))
		if not _on_floor(cell):
			_lights.append({"spot": grid.iso(Vector2(cell) + Vector2(rnd.randf(), rnd.randf())) + Vector2(0, -rnd.randf_range(10, 60)),
					"phase": rnd.randf() * TAU})


func _path_dir() -> Vector2i:
	var out: Vector2 = TavernGrid.OUTWARD[grid.door_side]
	return Vector2i(int(out.x), int(out.y))


func _all_cells(rnd: RandomNumberGenerator) -> Array:
	var cells: Array = []
	for x in range(-MARGIN, grid.cols + MARGIN):
		for y in range(-MARGIN, grid.rows + MARGIN):
			cells.append(Vector2i(x, y))
	return cells


func _on_floor(cell: Vector2i) -> bool:
	return cell.x >= -CLEAR and cell.y >= -CLEAR and cell.x < grid.cols + CLEAR and cell.y < grid.rows + CLEAR


# Adds a piece if its squares are free, off the path, away from the walls,
# and (if it's in front of the tavern) it wouldn't cover the tavern.
func _try_add(art: String, cell: Vector2i, _rnd: RandomNumberGenerator, mirror: bool = false, size: int = 1) -> void:
	for dx in size:
		for dy in size:
			var c: Vector2i = cell + Vector2i(dx, dy)
			if _on_floor(c) or _path.has(c) or _taken(c):
				return
	var middle: Vector2 = grid.iso(Vector2(cell) + Vector2(size, size) * 0.5)
	var tex: Texture2D = ART[art]
	var anchor: Vector2 = ANCHORS.get(art, Vector2(32, 58))
	var box := Rect2(middle - anchor * SCALE, tex.get_size() * SCALE)
	var tavern: Rect2 = grid.play_rect()
	tavern.position -= grid.position
	var in_front: bool = cell.x + size > grid.cols or cell.y + size > grid.rows
	if in_front and box.intersects(tavern):
		return
	_items.append([art, cell, mirror, size])


func _taken(cell: Vector2i) -> bool:
	for item in _items:
		var s: int = item[3]
		if cell.x >= item[1].x and cell.y >= item[1].y and cell.x < item[1].x + s and cell.y < item[1].y + s:
			return true
	return false


# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------
func _draw() -> void:
	var colors: Array = GROUND[style]
	for x in range(-MARGIN, grid.cols + MARGIN):
		for y in range(-MARGIN, grid.rows + MARGIN):
			var cell := Vector2i(x, y)
			if x >= 0 and y >= 0 and x < grid.cols and y < grid.rows:
				continue   # the tavern floor is drawn by the grid
			var tile := PackedVector2Array([grid.iso(Vector2(x, y)), grid.iso(Vector2(x + 1, y)),
					grid.iso(Vector2(x + 1, y + 1)), grid.iso(Vector2(x, y + 1))])
			var color: Color = colors[(x + y) % 2]
			if _path.has(cell):
				color = STREET_COLOR if style == "city" else PATH_COLOR
			draw_colored_polygon(tile, color)
			_draw_ground_detail(cell, tile, color)


# Little touches that make the ground look less flat: blades of grass and
# flowers, the lines between cobbles, toadstools in the forest.
func _draw_ground_detail(cell: Vector2i, tile: PackedVector2Array, color: Color) -> void:
	var h: int = absi(hash(cell))
	var middle: Vector2 = (tile[0] + tile[2]) / 2.0
	match style:
		"meadow", "forest":
			if _path.has(cell):
				return
			for k in 3:
				var spot: Vector2 = middle + Vector2(((h >> (k * 4)) % 60) - 30, ((h >> (k * 4 + 2)) % 24) - 12)
				draw_rect(Rect2(spot, Vector2(2, 4)), GROUND[style][2])
			if style == "meadow" and h % 7 == 0:
				var flower: Color = [Color8(240, 220, 90), Color8(240, 240, 240), Color8(220, 120, 160)][h % 3]
				draw_rect(Rect2(middle + Vector2((h % 30) - 15, 2), Vector2(4, 4)), flower)
			if style == "forest" and h % 11 == 0:   # a glowing toadstool
				var at: Vector2 = middle + Vector2((h % 30) - 15, 0)
				draw_rect(Rect2(at + Vector2(-1, -4), Vector2(3, 6)), Color8(225, 230, 220))
				draw_rect(Rect2(at + Vector2(-4, -8), Vector2(9, 4)), Color8(80, 210, 220))
				draw_circle(at + Vector2(0, -6), 9.0, Color(0.4, 0.9, 1.0, 0.18))
		"city":
			# Four cobbles per square
			var line: Color = color.darkened(0.18)
			draw_line((tile[0] + tile[1]) / 2.0, (tile[2] + tile[3]) / 2.0, line, 1.0)
			draw_line((tile[1] + tile[2]) / 2.0, (tile[3] + tile[0]) / 2.0, line, 1.0)
			draw_polyline(tile + PackedVector2Array([tile[0]]), line, 1.0)


func _draw_art(canvas: CanvasItem, tex: Texture2D, at: Vector2, anchor: Vector2, mirror: bool = false) -> void:
	canvas.draw_set_transform(at, 0.0, Vector2(-1, 1) if mirror else Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-anchor * SCALE, tex.get_size() * SCALE), false)
	canvas.draw_set_transform(Vector2.ZERO)


# Scenery pieces and townsfolk, back to front together, so a house in
# front of a street hides the people walking behind it.
func _draw_overlay() -> void:
	var drawn: Array = []   # [depth, kind, data]
	for item in _items:
		drawn.append([item[1].x + item[1].y + item[3], 0, item])
	for w in _walkers:
		var leg: float = fmod(w["t"], 2.0)
		var spot: Vector2 = w["a"].lerp(w["b"], leg if leg < 1.0 else 2.0 - leg)
		drawn.append([spot.x + spot.y, 1, w])
	drawn.sort_custom(func(a, b): return a[0] < b[0])
	var frame := Vector2(StaffProfiles.FRAME_SIZE)
	for entry in drawn:
		if entry[1] == 0:
			var item: Array = entry[2]
			var middle: Vector2 = grid.iso(Vector2(item[1]) + Vector2(item[3], item[3]) * 0.5)
			_draw_art(_overlay, ART[item[0]], middle, ANCHORS.get(item[0], Vector2(32, 58)), item[2])
			continue
		# Townsfolk walk from a to b and back again, in step.
		var w: Dictionary = entry[2]
		var leg: float = fmod(w["t"], 2.0)
		var forward: bool = leg < 1.0
		var at: Vector2 = grid.iso(w["a"].lerp(w["b"], leg if forward else 2.0 - leg))
		var heading: Vector2 = grid.iso(w["b"]) - grid.iso(w["a"])
		if not forward:
			heading = -heading
		var column: int = 4 + int(w["t"] / w["speed"] * 4.0) % 2   # side-view walking frames
		var source := Rect2(Vector2(column * frame.x, 0), frame)
		_overlay.draw_set_transform(at, 0.0, Vector2(-1, 1) if heading.x < 0 else Vector2.ONE)
		_overlay.draw_texture_rect_region(w["sheet"], Rect2(Vector2(-frame.x, 18 - frame.y * 2), frame * 2), source)
	_overlay.draw_set_transform(Vector2.ZERO)
	# Fireflies blink on and off.
	var now: float = Time.get_ticks_msec() / 1000.0
	for light in _lights:
		var glow: float = maxf(0.0, sin(now * 1.7 + light["phase"]))
		if glow > 0.05:
			var spot: Vector2 = light["spot"] + Vector2(sin(now + light["phase"]) * 6, cos(now * 0.8 + light["phase"]) * 4)
			_overlay.draw_circle(spot, 6.0, Color(0.9, 1.0, 0.5, 0.18 * glow))
			_overlay.draw_rect(Rect2(spot - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 1.0, 0.7, glow))
