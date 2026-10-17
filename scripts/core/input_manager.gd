extends Node
## Input for both players: keyboard + gamepad actions, keyboard and controller
## remapping, controller hot-plug and auto-assignment, rumble, menu navigation
## with hold-to-repeat, and device-aware button prompts.

signal pad_connected(device: int, pad_name: String)
signal pad_disconnected(device: int)

const ACTIONS := ["up", "down", "left", "right", "light", "medium", "heavy", "special", "block", "throw"]
const FIGHT_BUTTONS := ["light", "medium", "heavy", "special", "block", "throw"]
const ACTION_LABELS := {
	"up": "Up / Jump", "down": "Down / Crouch", "left": "Left", "right": "Right",
	"light": "Light Attack", "medium": "Medium Attack", "heavy": "Heavy Attack",
	"special": "Special", "block": "Block / Amplify", "throw": "Throw",
}
const SHORT := {"up": "u", "down": "d", "left": "l", "right": "r", "light": "L", "medium": "M", "heavy": "H", "special": "S", "block": "B", "throw": "T"}
const DEFAULT_KEYS := {
	0: {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"light": KEY_J, "medium": KEY_K, "heavy": KEY_L, "special": KEY_U, "block": KEY_I, "throw": KEY_O},
	1: {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"light": KEY_KP_1, "medium": KEY_KP_2, "heavy": KEY_KP_3, "special": KEY_KP_4, "block": KEY_KP_5, "throw": KEY_KP_6},
}
## Secondary P2 keys for keyboards without a numpad (laptops, Mac keyboards).
const ALT_KEYS := {
	1: {"light": KEY_COMMA, "medium": KEY_PERIOD, "heavy": KEY_SLASH, "special": KEY_SEMICOLON, "block": KEY_APOSTROPHE, "throw": KEY_BRACKETRIGHT},
}
const MENU_KEYS := {
	0: {"accept": [KEY_J, KEY_ENTER, KEY_SPACE], "back": [KEY_K, KEY_ESCAPE, KEY_BACKSPACE], "costume": [KEY_U, KEY_L]},
	1: {"accept": [KEY_KP_1, KEY_COMMA, KEY_KP_ENTER], "back": [KEY_KP_2, KEY_PERIOD], "costume": [KEY_KP_4, KEY_SEMICOLON, KEY_KP_3]},
}
const MENU_PAD := {"accept": [JOY_BUTTON_A], "back": [JOY_BUTTON_B], "costume": [JOY_BUTTON_Y, JOY_BUTTON_X]}
const DEFAULT_PAD := {
	"up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN], "left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"light": [JOY_BUTTON_X], "medium": [JOY_BUTTON_Y], "heavy": [JOY_BUTTON_B],
	"special": [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER], "block": [JOY_BUTTON_LEFT_SHOULDER], "throw": [],
}
const PAD_AXES := {
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0], "left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"block": [JOY_AXIS_TRIGGER_LEFT, 1.0], "throw": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2", JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}
const PS_NAMES := {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options"}
const MENU_DIRS := ["up", "down", "left", "right"]
const REPEAT_DELAY := 0.36
const REPEAT_RATE := 0.085

var keys := {0: {}, 1: {}}
var pad_map := {0: {}, 1: {}}
## Which joypad device each player uses. -1 = any device (shared, single-player).
var pad_device := [0, 1]
var swapped := false
var shared := false
var using_pad := false
var last_pad := 0
var pad_style := "xbox"

var _hold := {}
var _fire := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	keys[0] = DEFAULT_KEYS[0].duplicate()
	keys[1] = DEFAULT_KEYS[1].duplicate()
	pad_map[0] = DEFAULT_PAD.duplicate(true)
	pad_map[1] = DEFAULT_PAD.duplicate(true)
	_ensure_action("pause", 0.5)
	InputMap.action_erase_events("pause")
	for k in [KEY_ESCAPE, KEY_P]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event("pause", e)
	var pb := InputEventJoypadButton.new()
	pb.button_index = JOY_BUTTON_START
	pb.device = -1
	InputMap.action_add_event("pause", pb)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_assign_pads()
	rebuild()


func action_name(pid: int, action: String) -> String:
	return "p%d_%s" % [pid + 1, action]


func _ensure_action(n: String, deadzone: float) -> void:
	if not InputMap.has_action(n):
		InputMap.add_action(n, deadzone)


func _key_event(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


func _pad_dev(pid: int) -> int:
	if shared:
		return -1 if pid == 0 else -99
	return pad_device[pid]


func rebuild() -> void:
	var dz: float = 0.45
	if has_node("/root/Game"):
		dz = float(get_node("/root/Game").settings.get("deadzone", 0.45))
	for pid in [0, 1]:
		var dev := _pad_dev(pid)
		for a in ACTIONS:
			var n := action_name(pid, a)
			_ensure_action(n, dz)
			InputMap.action_set_deadzone(n, dz)
			InputMap.action_erase_events(n)
			InputMap.action_add_event(n, _key_event(keys[pid][a]))
			if ALT_KEYS.has(pid) and ALT_KEYS[pid].has(a):
				InputMap.action_add_event(n, _key_event(ALT_KEYS[pid][a]))
			if dev == -99:
				continue
			for b in pad_map[pid].get(a, []):
				var jb := InputEventJoypadButton.new()
				jb.button_index = int(b)
				jb.device = dev
				InputMap.action_add_event(n, jb)
			if PAD_AXES.has(a):
				var jm := InputEventJoypadMotion.new()
				jm.axis = PAD_AXES[a][0]
				jm.axis_value = PAD_AXES[a][1]
				jm.device = dev
				InputMap.action_add_event(n, jm)
		for m in ["accept", "back", "costume"]:
			var n2 := action_name(pid, "m_" + m)
			_ensure_action(n2, 0.5)
			InputMap.action_erase_events(n2)
			for k in MENU_KEYS[pid][m]:
				InputMap.action_add_event(n2, _key_event(k))
			if dev != -99:
				for b in MENU_PAD[m]:
					var jb2 := InputEventJoypadButton.new()
					jb2.button_index = b
					jb2.device = dev
					InputMap.action_add_event(n2, jb2)


## Single-player modes let any connected controller drive Player 1.
func set_shared(value: bool) -> void:
	if value != shared:
		shared = value
		rebuild()


# --- Controllers ----------------------------------------------------------------------

func _assign_pads() -> void:
	var pads := Input.get_connected_joypads()
	var a: int = pads[0] if pads.size() > 0 else 0
	var b: int = pads[1] if pads.size() > 1 else (a + 1)
	pad_device = [b, a] if swapped else [a, b]


func _on_joy_changed(device: int, connected: bool) -> void:
	_assign_pads()
	rebuild()
	if connected:
		pad_connected.emit(device, Input.get_joy_name(device))
	else:
		pad_disconnected.emit(device)


func connected_pads() -> Array:
	return Input.get_connected_joypads()


func player_for_device(device: int) -> int:
	if shared:
		return 0
	return pad_device.find(device)


func swap_pads() -> void:
	swapped = not swapped
	_assign_pads()
	rebuild()


func pad_label(pid: int) -> String:
	var dev: int = pad_device[pid]
	if shared and pid == 0:
		return "ANY CONTROLLER"
	if dev in Input.get_connected_joypads():
		return Input.get_joy_name(dev).substr(0, 22)
	return "not connected"


func rumble(pid: int, strength: float, duration: float) -> void:
	if not has_node("/root/Game"):
		return
	var s: Dictionary = get_node("/root/Game").settings
	if not s.get("rumble", true):
		return
	var dev: int = last_pad if (shared and pid == 0) else pad_device[pid]
	if dev not in Input.get_connected_joypads():
		return
	var k := float(s.get("rumble_strength", 0.8))
	Input.start_joy_vibration(dev, clampf(strength * 0.6 * k, 0.0, 1.0), clampf(strength * k, 0.0, 1.0), duration)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pad = true
		last_pad = event.device
		var nm := Input.get_joy_name(event.device).to_lower()
		pad_style = "ps" if ("ps" in nm or "playstation" in nm or "dualsense" in nm or "dualshock" in nm) else "xbox"
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


# --- Remapping ---------------------------------------------------------------------------

func set_key(pid: int, action: String, keycode: int) -> void:
	# Swap with any action already using this key so nothing is double-bound.
	for other in ACTIONS:
		if other != action and keys[pid][other] == keycode:
			keys[pid][other] = keys[pid][action]
	keys[pid][action] = keycode
	rebuild()


func set_pad_button(pid: int, action: String, button: int) -> void:
	for other in FIGHT_BUTTONS:
		if other != action:
			var arr: Array = pad_map[pid].get(other, [])
			arr.erase(button)
	pad_map[pid][action] = [button]
	rebuild()


func reset_defaults() -> void:
	keys[0] = DEFAULT_KEYS[0].duplicate()
	keys[1] = DEFAULT_KEYS[1].duplicate()
	pad_map[0] = DEFAULT_PAD.duplicate(true)
	pad_map[1] = DEFAULT_PAD.duplicate(true)
	rebuild()


func key_label(pid: int, action: String) -> String:
	return OS.get_keycode_string(keys[pid][action])


func button_name(b: int) -> String:
	if pad_style == "ps" and PS_NAMES.has(b):
		return PS_NAMES[b]
	return BUTTON_NAMES.get(b, "Button %d" % b)


func pad_label_for(pid: int, action: String) -> String:
	var names: Array = []
	for b in pad_map[pid].get(action, []):
		names.append(button_name(int(b)))
	if action == "block":
		names.append("LT" if pad_style != "ps" else "L2")
	elif action == "throw":
		names.append("RT" if pad_style != "ps" else "R2")
	return " / ".join(names) if names.size() > 0 else "-"


## Short label for a prompt, matching the device the player last used.
func prompt(kind: String, pid: int = 0) -> String:
	if using_pad:
		match kind:
			"accept": return button_name(JOY_BUTTON_A)
			"back": return button_name(JOY_BUTTON_B)
			"costume": return button_name(JOY_BUTTON_Y)
			"pause": return button_name(JOY_BUTTON_START)
			"move": return "D-Pad"
		return pad_label_for(pid, kind)
	match kind:
		"accept": return OS.get_keycode_string(MENU_KEYS[pid]["accept"][0])
		"back": return OS.get_keycode_string(MENU_KEYS[pid]["back"][0])
		"costume": return OS.get_keycode_string(MENU_KEYS[pid]["costume"][0])
		"pause": return "Esc"
		"move": return "WASD" if pid == 0 else "Arrows"
	if keys[pid].has(kind):
		return key_label(pid, kind)
	return kind


func export_keys() -> Dictionary:
	return {"p1": keys[0].duplicate(), "p2": keys[1].duplicate(), "swapped": swapped,
		"pad1": pad_map[0].duplicate(true), "pad2": pad_map[1].duplicate(true)}


func import_keys(d: Dictionary) -> void:
	for i in 2:
		var src: Dictionary = d.get("p%d" % (i + 1), {})
		for a in ACTIONS:
			if src.has(a):
				keys[i][a] = int(src[a])
		var pm: Dictionary = d.get("pad%d" % (i + 1), {})
		for a in pm:
			if DEFAULT_PAD.has(a):
				var arr: Array = []
				for b in pm[a]:
					arr.append(int(b))
				pad_map[i][a] = arr
	swapped = bool(d.get("swapped", false))
	_assign_pads()
	rebuild()


## Held-state snapshot for one player. Opposite directions cancel (SOCD neutral).
## The dedicated Throw button presses Medium + Heavy together.
func sample(pid: int) -> Dictionary:
	var s := {}
	for a in ACTIONS:
		s[SHORT[a]] = Input.is_action_pressed(action_name(pid, a))
	if s["T"]:
		s["M"] = true
		s["H"] = true
	if s["l"] and s["r"]:
		s["l"] = false
		s["r"] = false
	if s["u"] and s["d"]:
		s["u"] = false
	return s


# --- Menu navigation ---------------------------------------------------------------------------

func _menu_held(dir: String, pid: int) -> bool:
	if pid < 0:
		return Input.is_action_pressed("ui_" + dir) or Input.is_action_pressed(action_name(0, dir)) or Input.is_action_pressed(action_name(1, dir))
	return Input.is_action_pressed(action_name(pid, dir))


func _process(delta: float) -> void:
	_fire.clear()
	for pid in [-1, 0, 1]:
		for d in MENU_DIRS:
			var key := "%s:%d" % [d, pid]
			if _menu_held(d, pid):
				var t: float = _hold.get(key, -1.0)
				if t < 0.0:
					_fire[key] = true
					_hold[key] = 0.0
				else:
					t += delta
					if t >= REPEAT_DELAY:
						_fire[key] = true
						t -= REPEAT_RATE
					_hold[key] = t
			else:
				_hold[key] = -1.0


## True when a menu input fires this frame. pid -1 = either player.
## dir: up/down/left/right (with hold-to-repeat), accept, back, costume.
func menu(dir: String, pid: int = -1) -> bool:
	if dir in MENU_DIRS:
		return _fire.get("%s:%d" % [dir, pid], false)
	var m := {"accept": "m_accept", "back": "m_back", "costume": "m_costume"}
	if not m.has(dir):
		return false
	if pid < 0:
		if dir == "accept" and Input.is_action_just_pressed("ui_accept"):
			return true
		if dir == "back" and Input.is_action_just_pressed("ui_cancel"):
			return true
		return Input.is_action_just_pressed(action_name(0, m[dir])) or Input.is_action_just_pressed(action_name(1, m[dir]))
	return Input.is_action_just_pressed(action_name(pid, m[dir]))
