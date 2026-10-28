extends Node
## Gives every sprite and texture rect the pixel smoothing shader as it
## enters the tree, so each asset is smoothed on its own as it's drawn.
## Items that already have a material keep it (humans smooth in their tint).
## Whether smoothing is on is a graphics setting, off until turned on and
## saved between runs.

const SHADER := preload("res://scripts/smooth_pixels.gdshader")
const SETTINGS_FILE := "user://settings.cfg"

## Turns smoothing on or off everywhere at once and remembers the choice.
var enabled := false:
	set(value):
		enabled = value
		RenderingServer.global_shader_parameter_set("pixel_smoothing", value)
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_FILE)
		cfg.set_value("graphics", "smooth_pixels", value)
		cfg.save(SETTINGS_FILE)

var _material := ShaderMaterial.new()


func _enter_tree() -> void:
	_material.shader = SHADER
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	enabled = cfg.get_value("graphics", "smooth_pixels", false)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Sprite2D or node is AnimatedSprite2D or node is TextureRect:
		if node.material == null:
			node.material = _material
