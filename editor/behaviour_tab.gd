extends HBoxContainer
## The human editor's Behaviour tab: a row per value in humans/tuning.tres
## (see human_tuning.gd), next to the real game running in a box. The game
## reads the same tuning resource, so the crowd follows every change at
## once; values read when the crowd starts show after Restart.

signal changed

const Humans := preload("res://scripts/humans.gd")
const MAIN := "res://main.tscn"
const TUNING_SOURCE := "res://scripts/human_tuning.gd"
## So the crowd here doesn't mark the player's real tips as said.
const TIPS_SAVE := "user://editor_tips.cfg"
const SPEEDS := [1.0, 2.0, 4.0, 8.0]

var dirty := false

var _tuning: Resource = load(Humans.TUNING_FILE)
## Property name -> its doc comment, read from the tuning script.
var _docs := {}
## Property name -> the reset button beside it.
var _resets := {}
## Property name -> refreshes its row from the resource.
var _setters := {}
var _viewport: SubViewport
var _main: Node
var _music_btn: Button
var _speed: OptionButton
var _count: Label


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_read_docs()
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	add_child(scroll)
	_build_rows(rows)
	add_child(_build_crowd())
	visibility_changed.connect(_on_visibility_changed)


func save() -> String:
	var err := ResourceSaver.save(_tuning, Humans.TUNING_FILE)
	if err != OK:
		return "Couldn't save tuning: " + error_string(err)
	dirty = false
	changed.emit()
	return "Saved " + Humans.TUNING_FILE


func _process(_delta: float) -> void:
	if _main:
		var humans := _main.get_node("Humans")
		_count.text = "%d humans, %d dancing" % [humans._humans.size(),
				humans._humans.filter(func(h): return h.state == Humans.Human.State.DANCING).size()]
		var music := _main.get_node("Music")
		_music_btn.text = "Send the DJ home" if music._dj != "" else "Call a DJ"


# --- Rows ------------------------------------------------------------------

## The ## lines right above each property in the tuning script.
func _read_docs() -> void:
	var doc: PackedStringArray = []
	for line in FileAccess.get_file_as_string(TUNING_SOURCE).split("\n"):
		if line.begins_with("##"):
			doc.append(line.trim_prefix("##").strip_edges())
			continue
		var m := RegEx.create_from_string(r"^@export.*?\bvar (\w+)").search(line)
		if m:
			_docs[m.get_string(1)] = " ".join(doc)
		doc.clear()


func _build_rows(rows: VBoxContainer) -> void:
	var defaults: Script = _tuning.get_script()
	# A group's heading goes in with its first value, so Resource's own
	# group (with nothing of ours in it) never shows.
	var group := ""
	for p in _tuning.get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP:
			group = p.name
			continue
		if not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		if group != "":
			var h := Label.new()
			h.text = group
			h.add_theme_font_size_override("font_size", 18)
			if rows.get_child_count() > 0:
				h.custom_minimum_size = Vector2(0, 36)
				h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			rows.add_child(h)
			group = ""
		var row := HBoxContainer.new()
		var name: String = p.name
		var doc: String = _docs.get(name, "")
		var label := Label.new()
		label.text = name.capitalize() + ("  ⟳" if "Read when the crowd starts" in doc else "")
		label.custom_minimum_size = Vector2(240, 0)
		label.tooltip_text = doc
		label.mouse_filter = MOUSE_FILTER_PASS
		row.add_child(label)
		if p.type == TYPE_VECTOR2 or p.type == TYPE_VECTOR2I:
			_vector_editor(row, name, p.type == TYPE_VECTOR2I)
		else:
			_number_editor(row, name, p)
		var reset := Button.new()
		reset.text = "Reset"
		reset.focus_mode = FOCUS_NONE
		reset.tooltip_text = "Back to %s" % str(defaults.get_property_default_value(name))
		reset.pressed.connect(func():
			_set_value(name, defaults.get_property_default_value(name))
			_setters[name].call())
		row.add_child(reset)
		_resets[name] = reset
		rows.add_child(row)
		_update_reset(name)


func _number_editor(row: HBoxContainer, name: String, p: Dictionary) -> void:
	var hint: PackedStringArray = p.hint_string.split(",")
	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(110, 0)
	for r: Range in [slider, spin]:
		if p.hint == PROPERTY_HINT_RANGE and hint.size() >= 2:
			r.min_value = float(hint[0])
			r.max_value = float(hint[1])
			r.step = float(hint[2]) if hint.size() > 2 else 0.0
			r.allow_greater = "or_greater" in hint
		r.rounded = p.type == TYPE_INT
	slider.share(spin)
	spin.select_all_on_focus = true
	_setters[name] = func(): spin.set_value_no_signal(_tuning.get(name))
	_setters[name].call()
	spin.value_changed.connect(func(v): _set_value(name, int(v) if p.type == TYPE_INT else v))
	row.add_child(slider)
	row.add_child(spin)


## A from..to pair: two spin boxes.
func _vector_editor(row: HBoxContainer, name: String, ints: bool) -> void:
	var boxes: Array[SpinBox] = []
	for i in 2:
		var l := Label.new()
		l.text = "from" if i == 0 else "to"
		l.modulate = Color(1, 1, 1, 0.6)
		row.add_child(l)
		var s := SpinBox.new()
		s.size_flags_horizontal = SIZE_EXPAND_FILL
		s.max_value = 1000
		s.step = 1.0 if ints else 0.01
		s.select_all_on_focus = true
		s.value_changed.connect(func(_v):
			var v = Vector2i(int(boxes[0].value), int(boxes[1].value)) if ints \
					else Vector2(boxes[0].value, boxes[1].value)
			_set_value(name, v))
		boxes.append(s)
		row.add_child(s)
	_setters[name] = func():
		var v = _tuning.get(name)
		boxes[0].set_value_no_signal(v.x)
		boxes[1].set_value_no_signal(v.y)
	_setters[name].call()


func _set_value(name: String, v: Variant) -> void:
	if _tuning.get(name) == v:
		return
	_tuning.set(name, v)
	_update_reset(name)
	dirty = true
	changed.emit()


func _update_reset(name: String) -> void:
	var at_default: bool = _tuning.get(name) == _tuning.get_script().get_property_default_value(name)
	_resets[name].disabled = at_default


# --- The crowd -------------------------------------------------------------

func _build_crowd() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_viewport.audio_listener_enable_2d = true
	box.add_child(_viewport)
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical = SIZE_EXPAND_FILL
	# Keeps the pixel smoothing autoload from smoothing the whole screen again.
	view.material = CanvasItemMaterial.new()
	box.add_child(view)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_count)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_music_btn = Button.new()
	_music_btn.custom_minimum_size = Vector2(130, 0)
	_music_btn.pressed.connect(_toggle_music)
	bar.add_child(_music_btn)
	var restart := Button.new()
	restart.text = "Restart"
	restart.tooltip_text = "Start the crowd over; picks up values marked ⟳."
	restart.pressed.connect(_start_crowd)
	bar.add_child(restart)
	_speed = OptionButton.new()
	_speed.tooltip_text = "Runs the whole game faster, to see what the values add up to."
	for s: float in SPEEDS:
		_speed.add_item("%dx speed" % s)
	_speed.item_selected.connect(func(i): Engine.time_scale = SPEEDS[i])
	bar.add_child(_speed)
	box.add_child(bar)
	return box


## The real game, minus its title cards.
func _start_crowd() -> void:
	if _main:
		_main.queue_free()
		_main = null
	Tips.save_file = TIPS_SAVE
	_main = load(MAIN).instantiate()
	_main.get_node("Intro").free()
	_viewport.add_child(_main)


func _toggle_music() -> void:
	var music := _main.get_node("Music")
	if music._dj != "":
		music.stop()
	elif not music.djs().is_empty():
		music.play_dj(music.djs().pick_random())


## The crowd runs only while the tab is showing.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _main:
		_start_crowd()
	if _main:
		_main.process_mode = PROCESS_MODE_INHERIT if is_visible_in_tree() else PROCESS_MODE_DISABLED
	Engine.time_scale = SPEEDS[_speed.selected] if is_visible_in_tree() else 1.0
