extends Control
## Scrolling credits, asset licensing and rights notes.

var t := 0.0
var lines := [
	["DC'S ARROWVERSE: FIGHT NIGHT", 22, Color(1, 0.85, 0.25)],
	["A personal, noncommercial fan project", 10, Color(0.85, 0.85, 1)],
	["", 10, Color.WHITE],
	["DESIGN", 14, Color(1, 0.6, 0.3)],
	["Game bible & creative direction: the project owner", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["PROGRAMMING", 14, Color(1, 0.6, 0.3)],
	["Godot 4 engine code, combat system, AI, menus", 10, Color.WHITE],
	["Built with Claude Code", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["ART", 14, Color(1, 0.6, 0.3)],
	["All fighters, arenas and effects are original procedural", 10, Color.WHITE],
	["pixel art drawn in code at 640x360 (scripts/combat/rig.gd,", 10, Color.WHITE],
	["scripts/arenas/arena.gd). No sprites, screenshots or logos", 10, Color.WHITE],
	["were copied from any show, film or game.", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["AUDIO", 14, Color(1, 0.6, 0.3)],
	["All sound effects and music are synthesized at runtime", 10, Color.WHITE],
	["(scripts/audio/sound_manager.gd). No recorded audio,", 10, Color.WHITE],
	["soundtrack cues or voice clips are included.", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["FONT", 14, Color(1, 0.6, 0.3)],
	["Godot's built-in default font (Open Sans, OFL 1.1)", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["ENGINE", 14, Color(1, 0.6, 0.3)],
	["Godot Engine 4.3 - MIT License - godotengine.org", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["RIGHTS NOTE", 14, Color(1, 0.6, 0.3)],
	["DC, the Arrowverse and all related characters and names", 10, Color.WHITE],
	["are trademarks and copyrights of DC and their owners.", 10, Color.WHITE],
	["This fan project is not affiliated with or endorsed by them.", 10, Color.WHITE],
	["", 10, Color.WHITE],
	["THANKS FOR PLAYING", 18, Color(1, 0.85, 0.25)],
]


func _ready() -> void:
	Sound.play_music("victory")


func _process(delta: float) -> void:
	t += delta
	if InputManager.menu("accept") or InputManager.menu("back") or Input.is_action_just_pressed("pause"):
		Game.goto("menu")
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("06060e"))
	var font: Font = Game.font
	var y := 380.0 - t * 28.0
	if y < -lines.size() * 18.0:
		t = 0.0
	for l in lines:
		var s: String = l[0]
		var size: int = l[1]
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if y > -20 and y < 380:
			draw_string_outline(font, Vector2(320 - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color.BLACK)
			draw_string(font, Vector2(320 - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, l[2])
		y += size + 9
