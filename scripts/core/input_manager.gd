extends Node
## Builds the per-player input actions (keyboard + gamepad), supports keyboard
## remapping, and samples a compact per-frame input state for the fight loop.

const ACTIONS := ["up", "down", "left", "right", "light", "medium", "heavy", "special", "block"]
const ACTION_LABELS := {
	"up": "Up / Jump", "down": "Down / Crouch", "left": "Left", "right": "Right",
	"light": "Light Attack", "medium": "Medium Attack", "heavy": "Heavy Attack",
	"special": "Special", "block": "Block",
}
const DEFAULT_KEYS := {
	0: {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"light": KEY_J, "medium": KEY_K, "heavy": KEY_L, "special": KEY_U, "block": KEY_I},
	1: {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"light": KEY_KP_1, "medium": KEY_KP_2, "heavy": KEY_KP_3, "special": KEY_KP_4, "block": KEY_KP_5},
}
## Secondary P2 keys for keyboards without a numpad.
const ALT_KEYS := {
	1: {"light": KEY_DELETE, "medium": KEY_END, "heavy": KEY_PAGEDOWN, "special": KEY_INSERT, "block": KEY_HOME},
}
const PAD_BUTTONS := {
	"up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN], "left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"light": [JOY_BUTTON_X], "medium": [JOY_BUTTON_Y], "heavy": [JOY_BUTTON_B],
	"special": [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER], "block": [JOY_BUTTON_LEFT_SHOULDER],
}
const PAD_AXES := {
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0], "left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"special": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "block": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
const SHORT := {"up": "u", "down": "d", "left": "l", "right": "r", "light": "L", "medium": "M", "heavy": "H", "special": "S", "block": "B"}

var keys := {0: {}, 1: {}}
var pad_device := [0, 1]


func _ready() -> void:
	keys[0] = DEFAULT_KEYS[0].duplicate()
	keys[1] = DEFAULT_KEYS[1].duplicate()
	_ensure_action("pause", 0.5)
	InputMap.action_erase_events("pause")
	for k in [KEY_ESCAPE, KEY_P, KEY_BACKSPACE]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event("pause", e)
	var pb := InputEventJoypadButton.new()
	pb.button_index = JOY_BUTTON_START
	pb.device = -1
	InputMap.action_add_event("pause", pb)
	rebuild()


func action_name(pid: int, action: String) -> String:
	return "p%d_%s" % [pid + 1, action]


func _ensure_action(n: String, deadzone: float) -> void:
	if not InputMap.has_action(n):
		InputMap.add_action(n, deadzone)


func rebuild() -> void:
	for pid in [0, 1]:
		for a in ACTIONS:
			var n := action_name(pid, a)
			_ensure_action(n, 0.45)
			InputMap.action_erase_events(n)
			var e := InputEventKey.new()
			e.physical_keycode = keys[pid][a]
			InputMap.action_add_event(n, e)
			if ALT_KEYS.has(pid) and ALT_KEYS[pid].has(a):
				var e2 := InputEventKey.new()
				e2.physical_keycode = ALT_KEYS[pid][a]
				InputMap.action_add_event(n, e2)
			for b in PAD_BUTTONS.get(a, []):
				var jb := InputEventJoypadButton.new()
				jb.button_index = b
				jb.device = pad_device[pid]
				InputMap.action_add_event(n, jb)
			if PAD_AXES.has(a):
				var jm := InputEventJoypadMotion.new()
				jm.axis = PAD_AXES[a][0]
				jm.axis_value = PAD_AXES[a][1]
				jm.device = pad_device[pid]
				InputMap.action_add_event(n, jm)


func set_key(pid: int, action: String, keycode: int) -> void:
	# Swap with any action already using this key so nothing is double-bound.
	for other in ACTIONS:
		if other != action and keys[pid][other] == keycode:
			keys[pid][other] = keys[pid][action]
	keys[pid][action] = keycode
	rebuild()


func reset_defaults() -> void:
	keys[0] = DEFAULT_KEYS[0].duplicate()
	keys[1] = DEFAULT_KEYS[1].duplicate()
	rebuild()


func key_label(pid: int, action: String) -> String:
	return OS.get_keycode_string(keys[pid][action])


func export_keys() -> Dictionary:
	return {"p1": keys[0].duplicate(), "p2": keys[1].duplicate(), "pads": pad_device.duplicate()}


func import_keys(d: Dictionary) -> void:
	for i in 2:
		var src: Dictionary = d.get("p%d" % (i + 1), {})
		for a in ACTIONS:
			if src.has(a):
				keys[i][a] = int(src[a])
	var pads: Array = d.get("pads", [0, 1])
	if pads.size() == 2:
		pad_device = [int(pads[0]), int(pads[1])]
	rebuild()


func swap_pads() -> void:
	pad_device = [pad_device[1], pad_device[0]]
	rebuild()


## Held-state snapshot for one player. Opposite directions cancel (SOCD neutral).
func sample(pid: int) -> Dictionary:
	var s := {}
	for a in ACTIONS:
		s[SHORT[a]] = Input.is_action_pressed(action_name(pid, a))
	if s["l"] and s["r"]:
		s["l"] = false
		s["r"] = false
	if s["u"] and s["d"]:
		s["u"] = false
	return s


# --- Menu helpers (either player can drive menus) ---------------------------

func menu(dir: String, pid: int = -1) -> bool:
	var map := {"up": ["ui_up", "up"], "down": ["ui_down", "down"], "left": ["ui_left", "left"], "right": ["ui_right", "right"],
		"accept": ["ui_accept", "light"], "back": ["ui_cancel", "medium"]}
	var pair: Array = map[dir]
	if pid < 0 and Input.is_action_just_pressed(pair[0]):
		return true
	for p in ([0, 1] if pid < 0 else [pid]):
		if Input.is_action_just_pressed(action_name(p, pair[1])):
			return true
	if pid >= 0 and pair[0] == "ui_accept" and pid == 0 and Input.is_action_just_pressed("ui_accept"):
		return true
	return false
