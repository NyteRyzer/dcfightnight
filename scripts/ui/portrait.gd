extends Control
## Clipped head-and-shoulders portrait of a fighter, drawn live by the rig.

const Rig = preload("res://scripts/combat/rig.gd")

var look: Dictionary = {}
var H := 170.0
var facing := 1
var bg := Color(0.12, 0.12, 0.2)
var caption := ""
var dim := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_fighter(f: Dictionary, use_alt: bool = false) -> void:
	if f.is_empty():
		look = {}
	else:
		look = f["alt_look"] if use_alt else f["look"]
		H = float(f.get("height", 170))
		var power: Color = look.get("power", Color.WHITE)
		bg = Color(power.r * 0.25, power.g * 0.25, power.b * 0.3)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if look.is_empty():
		return
	Rig.draw_portrait(self, Rect2(Vector2.ZERO, size), look, H, facing, {"tint": Color(0, 0, 0.05, 0.6)} if dim else {})
	if caption != "":
		var font: Font = Game.font
		var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		var p := Vector2((size.x - w) * 0.5, size.y - 3)
		draw_string_outline(font, p, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 2, Color.BLACK)
		draw_string(font, p, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
