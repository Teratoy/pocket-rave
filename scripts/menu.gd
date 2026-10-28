extends CanvasLayer
## A popup menu in the game's pixel style: a panel framed by a button's
## art, holding a title and a column of items. Picking an item or tapping
## outside the panel closes it.

const FONT := preload("res://fonts/Silkscreen-Regular.ttf")
## One game pixel in screen pixels; sizes are multiples of it so the menu
## matches the pixel art. Silkscreen is drawn on an 8 pixel em.
const PX := 10
const FONT_SIZE := 4 * PX
const TEXT_COLOR := Color(0.9, 0.9, 0.9)
## Tints of the button frame. Pressed and active items, and text fields,
## match a held button (see button.gd); the panel is darker so its items
## stand out.
const PANEL_TINT := Color(0.45, 0.45, 0.45)
const HOVER_TINT := Color(1.15, 1.15, 1.15)
const PRESSED_TINT := Color(0.75, 0.75, 0.75)
const ACTIVE_TINT := Color(0.6, 0.6, 0.6)
const SMOOTH_SHADER := preload("res://scripts/smooth_pixels.gdshader")

## The panel's rows, starting with the title.
var list: VBoxContainer

var _root: Control
## The button's art at screen scale, framing the menu and its items.
var _frame: Texture2D
var _frame_margins: Rect2i
## Smooths the frame's pixel edges, leaving the text drawn alongside it alone.
var _smooth: ShaderMaterial


## frame_source is the button art the panel and items are cut from.
func _init(frame_source: Texture2D, title: String) -> void:
	add_to_group("menus")
	# Menus work while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_frame(frame_source)
	_smooth = ShaderMaterial.new()
	_smooth.shader = SMOOTH_SHADER
	_smooth.set_shader_parameter("pixel_scale", float(PX))
	_smooth.set_shader_parameter("only_size", Vector2i(_frame.get_size()))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.theme = _make_theme()
	add_child(_root)

	# Tapping outside the panel closes the menu.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())
	_root.add_child(shade)

	# Centred on the game area, which sits at the top left of the window.
	var center := CenterContainer.new()
	center.size = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(48 * PX, 0)
	panel.add_theme_stylebox_override("panel", _box(PANEL_TINT, 4 * PX))
	panel.material = _smooth
	center.add_child(panel)

	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2 * PX)
	panel.add_child(list)

	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(label)


func open() -> void:
	_root.visible = true


func close() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root.visible


## Adds a button to parent (the panel's list by default) that closes the
## menu and calls action.
func add_item(text: String, action: Callable, active := false, parent: Control = list) -> Button:
	return add_button(text, func():
		close()
		action.call(), active, parent)


## Like add_item, but the menu stays open.
func add_button(text: String, action: Callable, active := false, parent: Control = list) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# Long names end in "..." instead of widening the menu.
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if active:
		b.add_theme_stylebox_override("normal", _box(ACTIVE_TINT, 3 * PX))
		b.add_theme_stylebox_override("hover", _box(ACTIVE_TINT, 3 * PX))
	b.material = _smooth
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Adds a column that scrolls (drag or wheel) once it holds more items
## than fit_scroll lets it show.
func add_scroll(parent: Control = list) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2 * PX)
	scroll.add_child(column)
	return column


## Sizes a column from add_scroll to show at most max_rows of its items and
## scrolls it back to the top. An empty column is hidden.
func fit_scroll(column: VBoxContainer, max_rows: int) -> void:
	var scroll: ScrollContainer = column.get_parent()
	var count := column.get_child_count()
	var rows := mini(count, max_rows)
	var row_height: float = column.get_child(0).get_combined_minimum_size().y if count > 0 else 0.0
	var gap := column.get_theme_constant("separation")
	scroll.custom_minimum_size.y = rows * row_height + maxi(rows - 1, 0) * gap
	scroll.visible = rows > 0
	scroll.scroll_vertical = 0


## A labelled text field.
func add_field(label: String, parent: Control = list) -> LineEdit:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var field := LineEdit.new()
	field.select_all_on_focus = true
	field.material = _smooth
	parent.add_child(field)
	return field


## A slider from 0 to 1 that calls changed with its value as it moves.
func add_slider(value: float, changed: Callable, parent: Control = list) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.material = _smooth
	s.value_changed.connect(changed)
	parent.add_child(s)
	return s


## Frees parent's children from index from on.
static func clear(parent: Node, from := 0) -> void:
	for c in parent.get_children().slice(from):
		parent.remove_child(c)
		c.queue_free()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT_COLOR)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", TEXT_COLOR)
	t.set_stylebox("normal", "Button", _box(Color.WHITE, 3 * PX))
	t.set_stylebox("hover", "Button", _box(HOVER_TINT, 3 * PX))
	t.set_stylebox("pressed", "Button", _box(PRESSED_TINT, 3 * PX))
	# Fields look like held buttons, so they read as something to fill in.
	for c in ["font_color", "caret_color"]:
		t.set_color(c, "LineEdit", TEXT_COLOR)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_COLOR * Color(1, 1, 1, 0.4))
	t.set_color("selection_color", "LineEdit", Color(1, 1, 1, 0.25))
	t.set_constant("caret_width", "LineEdit", PX / 2)
	t.set_stylebox("normal", "LineEdit", _box(ACTIVE_TINT, 3 * PX))
	t.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	# Sliders: a held button for the track, filled up to a plain grabber.
	var track := _box(ACTIVE_TINT, 0)
	track.content_margin_top = 3 * PX
	track.content_margin_bottom = 3 * PX
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(Color.WHITE, 0)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := Image.create_empty(3 * PX, 6 * PX, false, Image.FORMAT_RGBA8)
	knob.fill(TEXT_COLOR)
	var knob_tex := ImageTexture.create_from_image(knob)
	for icon in ["grabber", "grabber_highlight"]:
		t.set_icon(icon, "HSlider", knob_tex)
	return t


## Cuts the button art into four corners, split through its middle
## column and row, and scales it up to screen pixels. Drawn as a nine-patch
## the middle column and row repeat to fill the sides and centre, the same
## way the middle button grows by repeating its bottom row.
func _make_frame(source: Texture2D) -> void:
	var img := source.get_image()
	if img.is_compressed():
		img.decompress()
	img = img.get_region(img.get_used_rect())
	var w := img.get_width()
	var h := img.get_height()
	img.resize(w * PX, h * PX, Image.INTERPOLATE_NEAREST)
	_frame = ImageTexture.create_from_image(img)
	# Left/top corners keep the middle line; right/bottom get the rest.
	var left := w / 2
	var top := h / 2
	_frame_margins = Rect2i(left * PX, top * PX, (w - left - 1) * PX, (h - top - 1) * PX)


## The button frame, tinted, with pad screen pixels around its content.
func _box(tint: Color, pad: int) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _frame
	s.texture_margin_left = _frame_margins.position.x
	s.texture_margin_top = _frame_margins.position.y
	s.texture_margin_right = _frame_margins.size.x
	s.texture_margin_bottom = _frame_margins.size.y
	s.modulate_color = tint
	s.set_content_margin_all(pad)
	return s
