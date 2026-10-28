extends CanvasGroup
## Shadows for the sound, the booth and every human: a hard edged
## silhouette of each, mirrored straight down from its lowest pixel row,
## drawn under all of them. The sound's is mirrored column by column, each
## from its own lowest pixel; the booth's is mirrored whole and each column
## stretched up to the booth's lowest pixel there. Either way the whole top
## of the shadow meets its caster.
## The silhouettes are drawn opaque and the whole group is faded at once,
## so where shadows overlap they stay one even shade instead of stacking.
## Whether shadows show is a graphics setting, on until turned off and
## saved between runs.

const OPACITY := 0.3
const SILHOUETTE := preload("res://scripts/silhouette.gdshader")
const SETTINGS_FILE := "user://settings.cfg"

@export var sound: Sprite2D
## Its Sprite2D and AnimatedSprite2D children (the booth and the humans)
## all cast shadows, including ones spawned later.
@export var humans: Node2D

## Turns shadows on or off and remembers the choice.
var enabled := true:
	set(value):
		enabled = value
		visible = value
		set_process(value)
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_FILE)
		cfg.set_value("graphics", "shadows", value)
		cfg.save(SETTINGS_FILE)

var _material := ShaderMaterial.new()
var _shadows: Array[Sprite2D] = []
## Each texture's lowest opaque row + 1, the line its shadow mirrors about.
var _bases := {}
## Shadow images that meet their caster in every column, by
## [caster texture, mirrored column by column].
var _column_shadows := {}


func _ready() -> void:
	_material.shader = SILHOUETTE
	self_modulate = Color(0, 0, 0, OPACITY)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	enabled = cfg.get_value("graphics", "shadows", true)


func _process(_delta: float) -> void:
	var casters: Array[Node] = [sound]
	casters.append_array(humans.get_children())
	var used := 0
	for c in casters:
		var tex: Texture2D
		if c is AnimatedSprite2D:
			if c.sprite_frames == null or not c.sprite_frames.has_animation(c.animation):
				continue
			tex = c.sprite_frames.get_frame_texture(c.animation, c.frame)
		elif c is Sprite2D:
			tex = c.texture
		else:
			continue
		if tex == null or not c.is_visible_in_tree():
			continue
		if used == _shadows.size():
			var s := Sprite2D.new()
			s.material = _material
			add_child(s)
			_shadows.append(s)
		var s := _shadows[used]
		used += 1
		s.visible = true
		s.texture = tex
		s.centered = c.centered
		s.offset = c.offset
		s.flip_h = c.flip_h
		s.flip_v = c.flip_v
		if c == sound or c == humans.booth:
			s.texture = _column_shadow(tex, c == sound)
			s.centered = false
			s.offset = c.offset - (tex.get_size() / 2.0 if c.centered else Vector2.ZERO)
			s.global_transform = c.global_transform
			continue
		var top: float = c.offset.y - (tex.get_height() / 2.0 if c.centered else 0.0)
		var base := top + _base(tex)
		# Flip about the base line: y becomes 2 * base - y.
		s.global_transform = c.global_transform \
				* Transform2D(0.0, Vector2(1, -1), 0.0, Vector2(0, 2 * base))
	for i in range(used, _shadows.size()):
		_shadows[i].visible = false


func _base(tex: Texture2D) -> int:
	if not _bases.has(tex):
		_bases[tex] = tex.get_image().get_used_rect().end.y
	return _bases[tex]


## The texture's shadow on a canvas tall enough to hold it, meeting the
## texture's lowest opaque pixel in every column. Each column is either
## mirrored about its own lowest pixel, or mirrored with the whole texture
## about its lowest row and its top stretched up to that pixel.
func _column_shadow(tex: Texture2D, per_column: bool) -> Texture2D:
	var key := [tex, per_column]
	if not _column_shadows.has(key):
		var img := tex.get_image()
		img.decompress()
		var size := img.get_size()
		var whole_base := img.get_used_rect().end.y - 1
		var out := Image.create_empty(size.x, size.y * 2, false, Image.FORMAT_RGBA8)
		for x in size.x:
			var base := -1
			for y in range(size.y - 1, -1, -1):
				if img.get_pixel(x, y).a > 0.0:
					base = y
					break
			if base < 0:
				continue
			var mirror := base if per_column else whole_base
			for y in base + 1:
				if img.get_pixel(x, y).a > 0.0:
					out.set_pixel(x, 2 * mirror + 1 - y, Color.BLACK)
			# Fill from just under the caster down to the mirrored base pixel.
			for y in range(base + 1, 2 * mirror + 1 - base):
				out.set_pixel(x, y, Color.BLACK)
		_column_shadows[key] = ImageTexture.create_from_image(out)
	return _column_shadows[key]
