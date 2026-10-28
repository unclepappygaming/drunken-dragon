# =====================================================================
# floor_prop.gd  —  one piece of the room that people can be in front of
# or behind: a table, a Hearth, or a stretch of low front wall.
#
# In the isometric view, something lower on the screen is closer to us
# and must be drawn on top. Godot's Y-SORT does exactly that: children
# of a node with y_sort_enabled are drawn in order of their y position.
# The Props node and the Customers and Staff nodes are all y-sorted
# together (see main.tscn), so a guest standing behind a table is hidden
# by it, and one standing in front of it overlaps it.
#
# The grid does the actual drawing (draw_prop), since it knows the room.
# =====================================================================
class_name FloorProp
extends Node2D

var grid: TavernGrid
var cell: Vector2i
var kind: String = ""        # "table", "kitchen" or "wall"
var edges: Array = []        # walls only: which outer edges ("bottom", "right")


func _draw() -> void:
	grid.draw_prop(self)
