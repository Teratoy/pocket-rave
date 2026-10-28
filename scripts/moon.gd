extends Node2D
## The moon talks, in a speech balloon under her (see speech_balloon.gd).
## Touching her says a repeatable tip; touching her or the balloon while
## she talks hurries her along. Contextual tips the game triggers (see
## Tips.event) wait their turn and she says them as soon as she can: once
## the intro is gone, between other tips and while no menu is open.
## Her face plays its "talk" animation while the balloon types, and she
## keeps going while the game is paused.

const SpeechBalloon := preload("res://scripts/speech_balloon.gd")

## Her art; touching its opaque pixels touches her.
@export var base: Sprite2D
@export var face: AnimatedSprite2D
## She stays quiet until the intro is gone.
@export var intro: Node

var _balloon: SpeechBalloon
var _awake := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var img := base.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	_cut_talk_frames(img)
	_balloon = SpeechBalloon.new()
	# Just under the middle of her bottom edge.
	_balloon.anchor = Vector2i(used.get_center().x, used.end.y)
	add_child(_balloon)
	if is_instance_valid(intro):
		await intro.tree_exited
	_awake = true
	Tips.event("launch")


func _process(_delta: float) -> void:
	var animation := &"talk" if _balloon.is_typing() else &"default"
	if face.animation != animation:
		face.play(animation)
	if _awake and Tips.has_pending() and not _balloon.is_talking() and not _menu_open():
		_say(Tips.take_pending())


func _unhandled_input(event: InputEvent) -> void:
	if not _awake or not event is InputEventMouseButton \
			or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var p: Vector2 = get_canvas_transform().affine_inverse() * event.position
	if _balloon.has_point(to_local(p)):
		_balloon.advance()
	elif base.is_pixel_opaque(base.to_local(p)):
		if _balloon.is_talking():
			_balloon.advance()
		else:
			Tips.event("moon_touched")
			_say(Tips.take_pending() if Tips.has_pending() else Tips.random_tip())
	else:
		return
	get_viewport().set_input_as_handled()


## Says text, unless there's nothing to say.
func _say(text: String) -> void:
	if text.strip_edges() == "":
		return
	_balloon.say(text)


func _menu_open() -> bool:
	for menu in get_tree().get_nodes_in_group("menus"):
		if menu.is_open():
			return true
	return false


## The talking frames may be drawn over the whole scene; keeps only the
## pixels on her disc (base_img's opaque ones) so the rest shows through.
func _cut_talk_frames(base_img: Image) -> void:
	var frames := face.sprite_frames
	for i in frames.get_frame_count(&"talk"):
		var img := frames.get_frame_texture(&"talk", i).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				if base_img.get_pixel(x, y).a == 0.0:
					img.set_pixel(x, y, Color.TRANSPARENT)
		frames.set_frame(&"talk", i, ImageTexture.create_from_image(img))
