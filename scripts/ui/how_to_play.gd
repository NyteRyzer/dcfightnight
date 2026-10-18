extends Control
## How to Play: controls (keyboard and controller) and fighting systems.

var page := 0
var t := 0.0
const PAGES := [
	{"title": "CONTROLS", "lines": [
		["", "KEYBOARD (P1 / P2)", "CONTROLLER"],
		["Move / Jump / Crouch", "WASD  /  Arrows", "D-Pad or Left Stick"],
		["Light Attack", "J  /  Num1 or ,", "X  (Square)"],
		["Medium Attack", "K  /  Num2 or .", "Y  (Triangle)"],
		["Heavy Attack", "L  /  Num3 or /", "B  (Circle)"],
		["Special", "U  /  Num4 or ;", "A or RB  (Cross / R1)"],
		["Block (hold)", "I  /  Num5 or '", "LB or LT  (L1 / L2)"],
		["Throw (up close)", "O  /  Num6 or ]", "RT  (R2), or Medium + Heavy"],
		["Pause", "Esc / P", "Start  (Options)"],
		["", "", ""],
		["Controllers are detected automatically. In single-player modes any controller controls Player 1.", "", ""],
		["Remap keys and controller buttons in Options > Controls & Controllers.", "", ""],
	]},
	{"title": "SPECIAL MOVES", "lines": [
		["Every fighter has three specials and a super:", "", ""],
		["", "", ""],
		["Neutral special", "Special", ""],
		["Forward special", "Toward + Special", ""],
		["Back special", "Away + Special", ""],
		["SUPER (3 bars)", "Down + Special", ""],
		["", "", ""],
		["Chains", "Light > Medium > Heavy", "Down+Light > Down+Medium > Down+Heavy"],
		["Cancels", "A normal that connects can be cancelled into a special. A special can be cancelled into a super.", ""],
		["Dash", "Double-tap forward or back (back-dash briefly avoids hits)", ""],
		["Full move lists with frame data: Pause > Move List.", "", ""],
	]},
	{"title": "FIGHTING SYSTEMS", "lines": [
		["Super meter", "3 bars. Fills when you deal or take damage.", ""],
		["AMPLIFY (1 bar)", "Press Block during a special's start-up: more damage,", ""],
		["", "an extra hit, faster projectiles and 1 hit of armor.", ""],
		["BREAKER (2 bars)", "While being comboed, hold Toward + press Block to blast", ""],
		["", "the opponent away. Once per round.", ""],
		["Counter Hit", "Hitting an opponent during their start-up: +20% damage.", ""],
		["Punish", "Hitting an opponent during their recovery: +10% damage.", ""],
		["Wall Bounce", "Hard launchers into the screen edge bounce the opponent back.", ""],
		["Quick Rise", "Press any button while knocked down. Hold Back to roll away.", ""],
		["Blocking", "Standing block stops jump-ins. Crouching block stops sweeps.", ""],
		["Throw Break", "Press Throw right after being grabbed.", ""],
	]},
	{"title": "BEAT 'EM UP MODE", "lines": [
		["Fight through 5 levels of enemy waves with 1 or 2 players.", "", ""],
		["", "", ""],
		["Walk in depth", "Up / Down", "Only enemies in your lane can be hit"],
		["Jump", "Throw button (away from enemies)", ""],
		["Grab & throw", "Throw button next to an enemy", ""],
		["Block", "Hold Block", "Amplify and Breaker work as in versus"],
		["SUPER (3 bars)", "Light + Heavy together", "Hits everything in your lane"],
		["Pickups", "Burgers and medkits heal, Speed Force cells give 1 bar", ""],
		["Lives", "3 lives each. Continue restarts the current level.", ""],
		["GO!", "When an area is clear, walk right to move on", ""],
		["Each level ends with a boss from the roster.", "", ""],
	]},
]


func _process(delta: float) -> void:
	t += delta
	if InputManager.menu("left") or InputManager.menu("up"):
		page = wrapi(page - 1, 0, PAGES.size())
		Sound.play("menu_move")
	elif InputManager.menu("right") or InputManager.menu("down") or InputManager.menu("accept"):
		page = wrapi(page + 1, 0, PAGES.size())
		Sound.play("menu_move")
	elif InputManager.menu("back") or Input.is_action_just_pressed("pause"):
		Sound.play("menu_back")
		Game.goto("menu")
	queue_redraw()


func _draw() -> void:
	var font: Font = Game.font
	draw_rect(Rect2(0, 0, 640, 360), Color("0a0c18"))
	draw_rect(Rect2(20, 20, 600, 316), Color(0.04, 0.04, 0.1, 0.9))
	draw_rect(Rect2(20, 20, 600, 316), Color(1, 0.8, 0.25, 0.7), false, 1.0)
	var p: Dictionary = PAGES[page]
	var title := "HOW TO PLAY - %s  (%d/%d)" % [p["title"], page + 1, PAGES.size()]
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string_outline(font, Vector2(320 - tw * 0.5, 44), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
	draw_string(font, Vector2(320 - tw * 0.5, 44), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.25))
	var y := 70.0
	for line in p["lines"]:
		var a: String = line[0]
		var b: String = line[1]
		var c: String = line[2]
		if b == "" and c == "" and a != "":
			draw_string(font, Vector2(36, y), a, HORIZONTAL_ALIGNMENT_LEFT, 568, 9, Color(0.75, 0.9, 1.0))
		else:
			draw_string(font, Vector2(36, y), a, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.85, 0.4))
			draw_string(font, Vector2(186, y), b, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1))
			draw_string(font, Vector2(420, y), c, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 1, 0.8))
		y += 21.0
	var hint := "LEFT/RIGHT: page    %s: back" % InputManager.prompt("back")
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(320 - hw * 0.5, 350), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.8))
