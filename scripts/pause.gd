extends Node
## Pauses and resumes the game from the pause button. While paused the
## button shows the play glyph. Everything else stops with the tree,
## music included; only this node, the buttons and their menus keep
## running (see Settings, Shop and Music).

const PAUSE_GLYPH := preload("res://visual assets/pauseglyph.png")
const PLAY_GLYPH := preload("res://visual assets/playglyph.png")

@export var button: Sprite2D
@export var glyph: Sprite2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(_toggle)


func _toggle() -> void:
	var tree := get_tree()
	tree.paused = not tree.paused
	glyph.texture = PLAY_GLYPH if tree.paused else PAUSE_GLYPH
	if tree.paused:
		Tips.event("paused")
