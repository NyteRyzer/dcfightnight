extends Control
## Keyboard / gamepad / mouse driven vertical menu with optional value columns.

signal chosen(id: String)
signal adjusted(id: String, dir: int)
signal cancelled

var items: Array = []   # [{id, label, value?, disabled?}]
var index := 0
var active := true
var font_size := 12
var item_h := 18.0
var title := ""
var width := 220.0
var pid := -1
var panel := true
var value_x := 0.0
var cooldown := 6
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_items(arr: Array) -> void:
	items = arr
	index = clampi(index, 0, maxi(0, items.size() - 1))
	_skip_disabled(1)
	custom_minimum_size = Vector2(width, _header_h() + items.size() * item_h + 8)
	size = custom_minimum_size
	queue_redraw()


func current_id() -> String:
	return items[index]["id"] if items.size() > 0 else ""


func _header_h() -> float:
	return 24.0 if title != "" else 6.0


func _skip_disabled(dir: int) -> void:
	for _i in items.size():
		if not items[index].get("disabled", false):
			return
		index = wrapi(index + dir, 0, items.size())


func _move(dir: int) -> void:
	if items.is_empty():
		return
	index = wrapi(index + dir, 0, items.size())
	_skip_disabled(dir)
	Sound.play("menu_move")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if not active or not is_visible_in_tree() or items.is_empty():
		return
	if cooldown > 0:
		cooldown -= 1
		return
	if InputManager.menu("up", pid):
		_move(-1)
	elif InputManager.menu("down", pid):
		_move(1)
	elif InputManager.menu("left", pid):
		adjusted.emit(current_id(), -1)
		Sound.play("menu_move")
	elif InputManager.menu("right", pid):
		adjusted.emit(current_id(), 1)
		Sound.play("menu_move")
	elif InputManager.menu("accept", pid):
		_accept()
	elif InputManager.menu("back", pid):
		Sound.play("menu_back")
		cancelled.emit()


func _accept() -> void:
	if items[index].get("disabled", false):
		return
	Sound.play("menu_ok")
	chosen.emit(current_id())


func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var y: float = event.position.y - _header_h()
		var i := int(floorf(y / item_h))
		if i >= 0 and i < items.size() and not items[i].get("disabled", false):
			if i != index:
				index = i
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					_accept()
				elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
					adjusted.emit(current_id(), -1)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					adjusted.emit(current_id(), 1)


func _draw() -> void:
	var font: Font = Game.font
	var h := _header_h() + items.size() * item_h + 8
	if panel:
		draw_rect(Rect2(0, 0, width, h), Color(0.03, 0.03, 0.08, 0.86))
		draw_rect(Rect2(0, 0, width, h), Color(1, 0.8, 0.25, 0.7), false, 1.0)
	if title != "":
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, Vector2((width - tw) * 0.5, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
		draw_string(font, Vector2((width - tw) * 0.5, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.3))
	for i in items.size():
		var it: Dictionary = items[i]
		var y := _header_h() + i * item_h
		var sel := i == index and active
		var dis: bool = it.get("disabled", false)
		if sel:
			var pulse := 0.25 + 0.1 * sin(_t * 6.0)
			draw_rect(Rect2(4, y + 1, width - 8, item_h - 2), Color(1, 0.75, 0.2, pulse))
			draw_rect(Rect2(4, y + 1, 3, item_h - 2), Color(1, 0.85, 0.3))
		var col := Color(1, 1, 1) if sel else Color(0.78, 0.8, 0.9)
		if dis:
			col = Color(0.45, 0.45, 0.5)
		var base := y + item_h * 0.5 + font_size * 0.38
		draw_string(font, Vector2(14, base), str(it.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
		if it.has("value"):
			var v := str(it["value"])
			var vx := value_x if value_x > 0.0 else width - 14.0 - font.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var vs := "< %s >" % v if sel else v
			if sel and value_x <= 0.0:
				vx -= font.get_string_size("<  >", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, Vector2(vx, base), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.9, 0.5) if sel else Color(0.7, 0.75, 0.85))
