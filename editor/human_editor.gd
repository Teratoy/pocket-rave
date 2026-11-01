extends Control
## Dev tool for drawing and timing the humans (run this scene with F6; it
## never ships). The Draw tab edits res://humans/humans.json: skins, each
## action's takes, and each take's frames. Previews use the game's own
## loader, so what plays here is what plays in the crowd. The Behaviour tab
## edits res://humans/tuning.tres next to the running game (see
## behaviour_tab.gd). Ctrl+S saves both.
## New actions (beyond the built-in ones the game's code plays) are drawn
## like any other and get a "behaviours" entry: what sets them off and how
## long they last (see Humans._try_custom).
##
## Mouse: left paints, right erases. Keys: B pencil, F fill, I pick,
## , and . step frames, Ctrl+Z / Ctrl+Shift+Z undo and redo, Ctrl+S save.

const Humans := preload("res://scripts/humans.gd")
const BehaviourTab := preload("res://editor/behaviour_tab.gd")
const TINT_SHADER := preload("res://scripts/human_tint.gdshader")
const MANIFEST := Humans.MANIFEST
## The pathbase's ground, so sprites are judged against what they stand on.
const GROUND := Color8(68, 68, 68)
const UNDO_LIMIT := 200
const PREVIEW_ZOOM := 16
## Spare palette symbols, handed out to new colours in this order.
const SYMBOLS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
## What can set off a new action, as [trigger, label, help].
const TRIGGERS := [
	["idle", "While idle", "Rolled each time an idle human picks what to do next."],
	["dancing", "While dancing", "Rolled about once a second per dancer; they dance on after."],
	["meeting", "On meeting someone", "Instead of waving. Paired: both do it; otherwise the other waves back."],
	["erratic", "While erratic", "Rolled each time an erratic human picks what to do next."],
]

enum Tool { PENCIL, FILL, PICK }

var _m: Dictionary
var _skin: String
var _action: String
var _take := 0
var _frame := 0
## Palette symbol painted with the left button; "." is transparent.
var _color := "#"
var _tool := Tool.PENCIL
var _undo: Array[String] = []
var _redo: Array[String] = []
var _dirty := false
## Whether a paint stroke has already saved an undo step.
var _stroking := false
## Builds preview frames with the game's own code; never enters the tree.
var _loader: Node2D

var _skins_list: ItemList
var _skin_name: LineEdit
var _skin_weight: SpinBox
var _skin_base: OptionButton
var _actions_list: ItemList
var _override_btn: Button
var _use_base_btn: Button
var _delete_action_btn: Button
var _new_action_dialog: ConfirmationDialog
var _new_action_name: LineEdit
## The "When it happens" panel, for new actions only.
var _when_box: VBoxContainer
var _builtin_note: Label
var _trigger: OptionButton
var _trigger_help: Label
var _chance: SpinBox
var _time_from: SpinBox
var _time_to: SpinBox
var _wander: CheckBox
var _paired: CheckBox
var _takes_list: ItemList
var _take_name: LineEdit
var _take_weight: SpinBox
var _take_fps: SpinBox
var _take_loop: CheckBox
var _tool_buttons: Array[Button] = []
var _onion: CheckBox
var _canvas: PixelCanvas
var _palette_row: HBoxContainer
var _color_edit: ColorPickerButton
var _strip: HBoxContainer
var _hold: SpinBox
var _status: Label
var _inherit_note: Label
var _play: CheckBox
var _previews: Array[AnimatedSprite2D] = []
var _preview_box: Control
var _lift: HSlider
## The game's dresscodes, then a custom colour.
var _dresscode: OptionButton
var _tint: ColorPickerButton
var _import_dialog: FileDialog
var _export_dialog: FileDialog
var _quit_dialog: ConfirmationDialog
var _behaviour: BehaviourTab


func _ready() -> void:
	# The editor's Game tab keeps the phone's shape whatever this asks for,
	# so reopen in a window of its own.
	if Engine.is_embedded_in_editor():
		OS.create_process(OS.get_executable_path(), [
				"--path", ProjectSettings.globalize_path("res://"), scene_file_path])
		get_tree().quit()
		return
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.size = Vector2i(1500, 920)
	win.move_to_center()
	get_tree().auto_accept_quit = false
	set_anchors_preset(PRESET_FULL_RECT)
	_loader = Humans.new()
	_m = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_skin = _m.skins.keys()[0]
	_action = _action_names()[0]
	_build_ui()
	_refresh_all()


func _exit_tree() -> void:
	if _loader:
		_loader.free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _dirty or _behaviour.dirty:
			_quit_dialog.popup_centered()
		else:
			get_tree().quit()


# --- Manifest access -------------------------------------------------------

func _skins() -> Dictionary:
	return _m.skins


## Actions every skin has: the first skin's, in its order.
func _action_names() -> Array:
	return _skins()[_skins().keys()[0]].actions.keys()


## The skin that draws an action for skin: itself, or the nearest base.
func _owner_of(skin: String, action: String) -> String:
	var s: Dictionary = _skins()[skin]
	if s.get("actions", {}).has(action) or not s.has("base"):
		return skin
	return _owner_of(s.base, action)


func _editable() -> bool:
	return _owner_of(_skin, _action) == _skin


func _action_data() -> Dictionary:
	return _skins()[_owner_of(_skin, _action)].actions[_action]


func _takes() -> Array:
	return _action_data().takes


func _cur_take() -> Dictionary:
	return _takes()[_take]


func _frames() -> Array:
	return _cur_take().frames


func _cur_frame() -> Dictionary:
	return _frames()[_frame]


func _size() -> Vector2i:
	return Vector2i(int(_m.frame_size[0]), int(_m.frame_size[1]))


func _blank_rows() -> Array:
	var rows := []
	for y in _size().y:
		rows.append(".".repeat(_size().x))
	return rows


## Whether skin's chain of bases passes through other.
func _based_on(skin: String, other: String) -> bool:
	var s: Dictionary = _skins()[skin]
	if not s.has("base"):
		return false
	return s.base == other or _based_on(s.base, other)


func _clamp() -> void:
	if not _skins().has(_skin):
		_skin = _skins().keys()[0]
	_take = clampi(_take, 0, _takes().size() - 1)
	_frame = clampi(_frame, 0, _frames().size() - 1)
	if _color != "." and not _m.palette.has(_color):
		_color = "#"


# --- Undo and saving -------------------------------------------------------

## Call before every change, so it can be undone.
func _snapshot() -> void:
	_undo.append(JSON.stringify(_m))
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	_dirty = true


func _undo_step(from: Array[String], to: Array[String]) -> void:
	if from.is_empty():
		return
	to.append(JSON.stringify(_m))
	_m = JSON.parse_string(from.pop_back())
	_dirty = true
	_clamp()
	_refresh_all()


## Saves whichever of the manifest and the tuning have changes.
func _save() -> void:
	var said: PackedStringArray = []
	if _dirty:
		var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
		if not f:
			_status.text = "Couldn't save: %s" % error_string(FileAccess.get_open_error())
			return
		f.store_string(_to_json(_m, "") + "\n")
		f.close()
		_dirty = false
		said.append("Saved " + MANIFEST)
	if _behaviour.dirty:
		said.append(_behaviour.save())
	_status.text = ". ".join(said) if said else "Nothing to save."
	_refresh_status()


## Like JSON.stringify with tabs, but whole numbers print without ".0" and
## short number lists stay on one line, so the file diffs cleanly.
func _to_json(v: Variant, indent: String) -> String:
	var inner := indent + "\t"
	match typeof(v):
		TYPE_DICTIONARY:
			var parts := []
			for k: String in v:
				parts.append(inner + JSON.stringify(k) + ": " + _to_json(v[k], inner))
			return "{\n" + ",\n".join(parts) + "\n" + indent + "}" if parts else "{}"
		TYPE_ARRAY:
			if v.all(func(e): return typeof(e) in [TYPE_INT, TYPE_FLOAT]):
				return "[" + ", ".join(v.map(func(e): return _to_json(e, inner))) + "]"
			var parts := []
			for e: Variant in v:
				parts.append(inner + _to_json(e, inner))
			return "[\n" + ",\n".join(parts) + "\n" + indent + "]" if parts else "[]"
		TYPE_FLOAT:
			return str(int(v)) if v == floorf(v) else str(v)
	return JSON.stringify(v)


# --- Editing ---------------------------------------------------------------

func _pixel(c: Vector2i) -> String:
	return _cur_frame().px[c.y][c.x]


func _set_pixel(rows: Array, c: Vector2i, sym: String) -> void:
	var row: String = rows[c.y]
	rows[c.y] = row.substr(0, c.x) + sym + row.substr(c.x + 1)


## A press or drag on the canvas cell c; erase paints transparent.
func paint(c: Vector2i, erase: bool, first: bool) -> void:
	if not _editable():
		return
	var sym := "." if erase else _color
	if _tool == Tool.PICK and not erase:
		if first:
			_color = _pixel(c)
			_set_tool(Tool.PENCIL)
			_refresh_palette()
		return
	if _tool == Tool.FILL and not erase:
		if first and _pixel(c) != sym:
			_snapshot()
			_flood(c, _pixel(c), sym)
			_refresh_frames()
		return
	if _pixel(c) == sym:
		return
	if not _stroking:
		_snapshot()
		_stroking = true
	_set_pixel(_cur_frame().px, c, sym)
	_refresh_frames()


func end_stroke() -> void:
	_stroking = false


func _flood(start: Vector2i, from: String, to: String) -> void:
	var rows: Array = _cur_frame().px
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		if not Rect2i(Vector2i.ZERO, _size()).has_point(c) or rows[c.y][c.x] != from:
			continue
		_set_pixel(rows, c, to)
		todo.append_array([c + Vector2i.LEFT, c + Vector2i.RIGHT, c + Vector2i.UP, c + Vector2i.DOWN])


func _set_tool(t: Tool) -> void:
	_tool = t
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == t)


## The palette symbol for colour c, adding it if it's new.
func _symbol_for(c: Color) -> String:
	if c.a == 0.0:
		return "."
	var hex := c.to_html(c.a < 1.0)
	for sym: String in _m.palette:
		if (_m.palette[sym] as String).to_lower() == hex:
			return sym
	for sym in SYMBOLS:
		if not _m.palette.has(sym):
			_m.palette[sym] = hex
			return sym
	return "#"


# Skins.

func _new_skin(copy: bool) -> void:
	_snapshot()
	var name := _unique(_skin + "_copy" if copy else "skin", _skins().keys())
	var s: Dictionary
	if copy:
		s = _skins()[_skin].duplicate(true)
	else:
		s = {weight = 1, base = _skins().keys()[0], actions = {}}
	_skins()[name] = s
	_skin = name
	_refresh_all()


func _delete_skin() -> void:
	if _skin == _skins().keys()[0]:
		_status.text = "The first skin is everyone's base; it can't be deleted."
		return
	_snapshot()
	var gone: Dictionary = _skins()[_skin]
	for s: Dictionary in _skins().values():
		if s.get("base") == _skin:
			s.base = gone.base
	_skins().erase(_skin)
	_skin = _skins().keys()[0]
	_clamp()
	_refresh_all()


func _rename_skin(name: String) -> void:
	name = name.strip_edges()
	if name == _skin:
		return
	if not name.is_valid_identifier() or _skins().has(name):
		_status.text = "Skin names must be new and made of letters, digits and _."
		_skin_name.text = _skin
		return
	_snapshot()
	var renamed := {}
	for k: String in _skins():
		var s: Dictionary = _skins()[k]
		if s.get("base") == _skin:
			s.base = name
		renamed[name if k == _skin else k] = s
	_m.skins = renamed
	_skin = name
	_refresh_all()


func _set_skin_weight(v: float) -> void:
	_snapshot()
	_skins()[_skin].weight = v
	_refresh_status()


func _set_skin_base(idx: int) -> void:
	_snapshot()
	_skins()[_skin].base = _skin_base.get_item_text(idx)
	_clamp()
	_refresh_all()


# Actions.

## Copies what the base draws into this skin, so it can be changed here.
func _override_action() -> void:
	if _editable():
		return
	_snapshot()
	var s: Dictionary = _skins()[_skin]
	if not s.has("actions"):
		s.actions = {}
	s.actions[_action] = _action_data().duplicate(true)
	_refresh_all()


func _use_base_action() -> void:
	var s: Dictionary = _skins()[_skin]
	if not s.has("base") or not s.get("actions", {}).has(_action):
		return
	_snapshot()
	s.actions.erase(_action)
	_clamp()
	_refresh_all()


func _behaviours() -> Dictionary:
	if not _m.has("behaviours"):
		_m.behaviours = {}
	return _m.behaviours


func _is_custom(action: String) -> bool:
	return _m.get("behaviours", {}).has(action)


## A new action, drawn in the first skin (starting from its idle pose) and
## borrowed by the rest until they override it.
func _new_action(name: String) -> void:
	name = name.strip_edges()
	if not name.is_valid_identifier() or name in _action_names():
		_status.text = "Action names must be new and made of letters, digits and _."
		return
	_snapshot()
	var first: Dictionary = _skins()[_skins().keys()[0]]
	var idle: Dictionary = first.actions.idle.takes[0].frames[0]
	first.actions[name] = {takes = [{name = "a", weight = 1, fps = 8, loop = true,
			frames = [{px = idle.px.duplicate(), hold = 1}]}]}
	_behaviours()[name] = {trigger = "idle", chance = 0.05, time = [2, 4], move = "still", paired = false}
	_skin = _skins().keys()[0]
	_action = name
	_take = 0
	_frame = 0
	_refresh_all()


func _delete_action() -> void:
	if not _is_custom(_action):
		return
	_snapshot()
	for s: Dictionary in _skins().values():
		s.get("actions", {}).erase(_action)
	_behaviours().erase(_action)
	_action = _action_names()[0]
	_clamp()
	_refresh_all()


func _set_behaviour(key: String, v: Variant) -> void:
	if not _is_custom(_action):
		return
	_snapshot()
	_behaviours()[_action][key] = v
	_refresh_when()
	_refresh_status()


# Takes.

func _new_take(copy: bool) -> void:
	if not _editable():
		return
	_snapshot()
	var t: Dictionary = _cur_take().duplicate(true)
	t.name = _unique(t.name if copy else "a", _takes().map(func(x): return x.name))
	if not copy:
		t.weight = 1
		t.frames = [{px = _blank_rows(), hold = 1}]
	_takes().insert(_take + 1, t)
	_take += 1
	_frame = 0
	_refresh_all()


func _delete_take() -> void:
	if not _editable() or _takes().size() < 2:
		return
	_snapshot()
	_takes().remove_at(_take)
	_clamp()
	_refresh_all()


func _rename_take(name: String) -> void:
	name = name.strip_edges()
	if not _editable() or name == _cur_take().name:
		return
	if not name.is_valid_identifier() or _takes().any(func(t): return t.name == name):
		_status.text = "Take names must be new within the action and made of letters, digits and _."
		_take_name.text = _cur_take().name
		return
	_snapshot()
	_cur_take().name = name
	_refresh_all()


func _set_take(key: String, v: Variant) -> void:
	if not _editable():
		return
	_snapshot()
	_cur_take()[key] = v
	_refresh_takes()
	_refresh_frames()


# Frames.

func _new_frame(copy: bool) -> void:
	if not _editable():
		return
	_snapshot()
	var f: Dictionary = _cur_frame().duplicate(true) if copy else {px = _blank_rows(), hold = 1}
	_frames().insert(_frame + 1, f)
	_frame += 1
	_refresh_frames()


func _delete_frame() -> void:
	if not _editable() or _frames().size() < 2:
		return
	_snapshot()
	_frames().remove_at(_frame)
	_clamp()
	_refresh_frames()


func _move_frame(by: int) -> void:
	var to := _frame + by
	if not _editable() or to < 0 or to >= _frames().size():
		return
	_snapshot()
	var f: Dictionary = _frames().pop_at(_frame)
	_frames().insert(to, f)
	_frame = to
	_refresh_frames()


func _set_hold(v: float) -> void:
	if not _editable():
		return
	_snapshot()
	_cur_frame().hold = v
	_refresh_frames()


func _select_frame(i: int) -> void:
	_frame = clampi(i, 0, _frames().size() - 1)
	_refresh_frames()


# Palette.

func _add_color() -> void:
	_snapshot()
	var sym := ""
	for s in SYMBOLS:
		if not _m.palette.has(s):
			sym = s
			break
	if sym == "":
		return
	_m.palette[sym] = "808080"
	_color = sym
	_refresh_palette()


func _recolor(c: Color) -> void:
	if _color == ".":
		return
	_snapshot()
	_m.palette[_color] = c.to_html(c.a < 1.0)
	_refresh_palette()
	_refresh_frames()


# PNG in and out.

func _import_png(path: String) -> void:
	if not _editable():
		return
	var img := Image.load_from_file(path)
	if not img or img.get_size() != _size():
		_status.text = "PNGs must be exactly %dx%d." % [_size().x, _size().y]
		return
	img.convert(Image.FORMAT_RGBA8)
	_snapshot()
	var rows := _blank_rows()
	for y in _size().y:
		for x in _size().x:
			_set_pixel(rows, Vector2i(x, y), _symbol_for(img.get_pixel(x, y)))
	_cur_frame().px = rows
	_refresh_palette()
	_refresh_frames()


func _export_png(path: String) -> void:
	var err := frame_image(_cur_frame().px).save_png(path)
	_status.text = "Exported " + path if err == OK else "Couldn't export: " + error_string(err)


func frame_image(rows: Array) -> Image:
	var img := Image.create_empty(_size().x, _size().y, false, Image.FORMAT_RGBA8)
	for y in _size().y:
		for x in _size().x:
			var sym: String = rows[y][x]
			if sym != ".":
				img.set_pixel(x, y, color_of(sym))
	return img


func color_of(sym: String) -> Color:
	return Color.TRANSPARENT if sym == "." else Color.html(_m.palette.get(sym, "ff00ff"))


func _unique(base: String, taken: Array) -> String:
	if base not in taken:
		return base
	var i := 2
	while "%s%d" % [base, i] in taken:
		i += 1
	return "%s%d" % [base, i]


# --- Keys ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k or not k.pressed or k.echo and k.keycode != KEY_Z:
		return
	if k.is_command_or_control_pressed():
		match k.keycode:
			KEY_S:
				_save()
			KEY_Z:
				if k.shift_pressed:
					_undo_step(_redo, _undo)
				else:
					_undo_step(_undo, _redo)
			KEY_Y:
				_undo_step(_redo, _undo)
			_:
				return
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k.pressed or k.is_command_or_control_pressed() or not _canvas.is_visible_in_tree():
		return
	match k.keycode:
		KEY_B:
			_set_tool(Tool.PENCIL)
		KEY_F:
			_set_tool(Tool.FILL)
		KEY_I:
			_set_tool(Tool.PICK)
		KEY_COMMA:
			_select_frame(_frame - 1)
		KEY_PERIOD:
			_select_frame(_frame + 1)


# --- Refreshing the UI -----------------------------------------------------

func _refresh_all() -> void:
	_clamp()
	_refresh_skins()
	_refresh_actions()
	_refresh_takes()
	_refresh_palette()
	_refresh_frames()


func _refresh_skins() -> void:
	_skins_list.clear()
	var first: String = _skins().keys()[0]
	for k: String in _skins():
		var s: Dictionary = _skins()[k]
		var label := k if k == first else "%s  ← %s" % [k, s.get("base", "")]
		_skins_list.add_item(label)
		if k == _skin:
			_skins_list.select(_skins_list.item_count - 1)
	var s: Dictionary = _skins()[_skin]
	_skin_name.text = _skin
	_skin_weight.set_value_no_signal(s.get("weight", 1))
	_skin_base.clear()
	_skin_base.disabled = _skin == first
	if _skin == first:
		_skin_base.add_item("(none: first skin)")
		return
	for k: String in _skins():
		if k != _skin and not _based_on(k, _skin):
			_skin_base.add_item(k)
			if k == s.get("base"):
				_skin_base.select(_skin_base.item_count - 1)


func _refresh_actions() -> void:
	_actions_list.clear()
	for a: String in _action_names():
		var owner := _owner_of(_skin, a)
		var label := a + ("  ✦" if _is_custom(a) else "")
		var i := _actions_list.add_item(label if owner == _skin else "%s   (from %s)" % [label, owner])
		if owner != _skin:
			_actions_list.set_item_custom_fg_color(i, Color(1, 1, 1, 0.45))
		if a == _action:
			_actions_list.select(i)
	var has_base: bool = _skins()[_skin].has("base")
	_override_btn.disabled = _editable()
	_use_base_btn.disabled = not (has_base and _editable())
	_delete_action_btn.disabled = not _is_custom(_action)
	_refresh_when()


func _refresh_when() -> void:
	var custom := _is_custom(_action)
	_when_box.visible = custom
	_builtin_note.visible = not custom
	if not custom:
		return
	var b: Dictionary = _behaviours()[_action]
	var i := TRIGGERS.map(func(t): return t[0]).find(b.get("trigger", "idle"))
	_trigger.select(maxi(i, 0))
	_trigger_help.text = TRIGGERS[maxi(i, 0)][2]
	_chance.set_value_no_signal(b.get("chance", 0.0))
	var t: Array = b.get("time", [2, 4])
	_time_from.set_value_no_signal(t[0])
	_time_to.set_value_no_signal(t[1])
	_wander.set_pressed_no_signal(b.get("move", "still") == "wander")
	_paired.set_pressed_no_signal(b.get("paired", false))
	_paired.disabled = b.get("trigger") != "meeting"


func _refresh_takes() -> void:
	_takes_list.clear()
	var total := 0.0
	for t: Dictionary in _takes():
		total += t.get("weight", 1)
	for i in _takes().size():
		var t: Dictionary = _takes()[i]
		var share: float = 100.0 * t.get("weight", 1) / total if total > 0.0 else 0.0
		_takes_list.add_item("%s   %d frames, %d%%" % [t.name, t.frames.size(), roundi(share)])
	_takes_list.select(_take)
	var t := _cur_take()
	var ro := not _editable()
	_take_name.text = t.name
	_take_weight.set_value_no_signal(t.get("weight", 1))
	_take_fps.set_value_no_signal(t.fps)
	_take_loop.set_pressed_no_signal(t.loop)
	_take_name.editable = not ro
	_take_weight.editable = not ro
	_take_fps.editable = not ro
	_take_loop.disabled = ro
	_inherit_note.visible = ro
	_inherit_note.text = "Drawn by %s. Override to change it for %s." % [_owner_of(_skin, _action), _skin]


func _refresh_palette() -> void:
	for c in _palette_row.get_children():
		c.queue_free()
	for sym: String in ["."] + _m.palette.keys():
		var b := Swatch.new()
		b.editor = self
		b.sym = sym
		b.selected = sym == _color
		b.tooltip_text = "transparent (right button)" if sym == "." else "%s  #%s" % [sym, _m.palette[sym]]
		b.pressed.connect(func():
			_color = sym
			if _tool == Tool.PICK:
				_set_tool(Tool.PENCIL)
			_refresh_palette())
		_palette_row.add_child(b)
	_color_edit.disabled = _color == "."
	if _color != ".":
		_color_edit.color = color_of(_color)


func _refresh_frames() -> void:
	_clamp()
	_canvas.queue_redraw()
	for c in _strip.get_children():
		c.queue_free()
	for i in _frames().size():
		var t := FrameThumb.new()
		t.editor = self
		t.rows = _frames()[i].px
		t.hold = _frames()[i].get("hold", 1)
		t.selected = i == _frame
		t.pressed.connect(_select_frame.bind(i))
		_strip.add_child(t)
	_hold.set_value_no_signal(_cur_frame().get("hold", 1))
	_hold.editable = _editable()
	_refresh_preview()
	_refresh_status()


func _refresh_status() -> void:
	var unsaved := _dirty or (_behaviour and _behaviour.dirty)
	var title := "Human editor — %s / %s / %s, frame %d of %d%s" % [
			_skin, _action, _cur_take().name, _frame + 1, _frames().size(), "  •" if unsaved else ""]
	get_window().title = title


## Rebuilds every skin with the game's loader and shows the current take.
func _refresh_preview() -> void:
	_loader._skins.clear()
	_loader._skin_picks.clear()
	_loader._load_skins(_m)
	var frames: SpriteFrames = _loader._skins[_skin].frames
	var anim := StringName("%s:%s" % [_action, _cur_take().name])
	var manual: bool = _cur_take().fps <= 0.0
	for p in _previews:
		p.sprite_frames = frames
		if _play.button_pressed and not manual:
			if p.animation != anim or not p.is_playing():
				p.play(anim)
		else:
			p.animation = anim
			p.pause()
			p.frame = _frame
	_refresh_tint()


func _refresh_tint() -> void:
	for p in _previews:
		var mat := p.material as ShaderMaterial
		mat.set_shader_parameter("lift", _lift.value)
		var codes: Array = Humans.DRESSCODES.values()
		var i := _dresscode.selected
		var c: Color = codes[i] if i < codes.size() else _tint.color
		mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))


# --- Building the UI -------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color8(30, 30, 34)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var tabs := TabContainer.new()
	margin.add_child(tabs)
	var cols := HBoxContainer.new()
	cols.name = "Draw"
	cols.add_theme_constant_override("separation", 16)
	tabs.add_child(cols)
	cols.add_child(_build_left())
	cols.add_child(_build_centre())
	cols.add_child(_build_right())
	_behaviour = BehaviourTab.new()
	_behaviour.name = "Behaviour"
	_behaviour.changed.connect(_refresh_status)
	tabs.add_child(_behaviour)
	_build_dialogs()


func _build_left() -> Control:
	var box := _column(280)

	box.add_child(_heading("Skins"))
	_skins_list = _list(box, 4)
	_skins_list.item_selected.connect(func(i):
		_skin = _skins().keys()[i]
		_refresh_all())
	box.add_child(_buttons([["New", _new_skin.bind(false)], ["Duplicate", _new_skin.bind(true)], ["Delete", _delete_skin]]))
	_skin_name = LineEdit.new()
	_skin_name.text_submitted.connect(_rename_skin)
	_skin_name.focus_exited.connect(func(): _rename_skin(_skin_name.text))
	box.add_child(_field("Name", _skin_name))
	_skin_weight = _spin(0, 100, 1)
	_skin_weight.value_changed.connect(_set_skin_weight)
	box.add_child(_field("Spawn weight", _skin_weight))
	_skin_base = OptionButton.new()
	_skin_base.item_selected.connect(_set_skin_base)
	box.add_child(_field("Base", _skin_base))

	box.add_child(_heading("Actions"))
	_actions_list = _list(box, 8)
	# Every action always fits; the skin and take lists share what's left.
	_actions_list.auto_height = true
	_actions_list.size_flags_vertical = SIZE_FILL
	_actions_list.item_selected.connect(func(i):
		_action = _action_names()[i]
		_take = 0
		_frame = 0
		_refresh_all())
	_override_btn = Button.new()
	_override_btn.text = "Override here"
	_override_btn.tooltip_text = "Copy the base's drawing into this skin so it can be changed."
	_override_btn.pressed.connect(_override_action)
	_use_base_btn = Button.new()
	_use_base_btn.text = "Use base's"
	_use_base_btn.tooltip_text = "Drop this skin's drawing of the action and borrow the base's again."
	_use_base_btn.pressed.connect(_use_base_action)
	var row := HBoxContainer.new()
	for b in [_override_btn, _use_base_btn]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(b)
	box.add_child(row)
	var new_row := _buttons([["New action", func():
		_new_action_name.text = ""
		_new_action_dialog.popup_centered()
		_new_action_name.grab_focus()]])
	_delete_action_btn = Button.new()
	_delete_action_btn.text = "Delete action"
	_delete_action_btn.focus_mode = FOCUS_NONE
	_delete_action_btn.tooltip_text = "Delete this new action from every skin. Built-in ones can't be deleted."
	_delete_action_btn.pressed.connect(_delete_action)
	new_row.add_child(_delete_action_btn)
	box.add_child(new_row)

	box.add_child(_heading("Takes"))
	_takes_list = _list(box, 4)
	_takes_list.item_selected.connect(func(i):
		_take = i
		_frame = 0
		_refresh_takes()
		_refresh_frames())
	box.add_child(_buttons([["New", _new_take.bind(false)], ["Duplicate", _new_take.bind(true)], ["Delete", _delete_take]]))
	_take_name = LineEdit.new()
	_take_name.text_submitted.connect(_rename_take)
	_take_name.focus_exited.connect(func(): _rename_take(_take_name.text))
	box.add_child(_field("Name", _take_name))
	_take_weight = _spin(0, 100, 1)
	_take_weight.value_changed.connect(func(v): _set_take("weight", v))
	box.add_child(_field("Pick weight", _take_weight))
	_take_fps = _spin(0, 60, 0.5)
	_take_fps.tooltip_text = "Beats per second. 0 means frames are picked by the game (the DJ)."
	_take_fps.value_changed.connect(func(v): _set_take("fps", v))
	box.add_child(_field("FPS", _take_fps))
	_take_loop = CheckBox.new()
	_take_loop.text = "Loops"
	_take_loop.toggled.connect(func(on): _set_take("loop", on))
	box.add_child(_take_loop)
	return box


func _build_centre() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)

	var bar := HBoxContainer.new()
	var group := ButtonGroup.new()
	for t in [["Pencil (B)", Tool.PENCIL], ["Fill (F)", Tool.FILL], ["Pick (I)", Tool.PICK]]:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[1] == _tool
		b.pressed.connect(_set_tool.bind(t[1]))
		_tool_buttons.append(b)
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	_onion = CheckBox.new()
	_onion.text = "Onion skin"
	_onion.button_pressed = true
	_onion.toggled.connect(func(_on): _canvas.queue_redraw())
	bar.add_child(_onion)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_buttons([["Undo", _undo_step.bind(_undo, _redo)], ["Redo", _undo_step.bind(_redo, _undo)], ["Save", _save]]))
	box.add_child(bar)

	_inherit_note = Label.new()
	_inherit_note.modulate = Color(1, 0.8, 0.4)
	box.add_child(_inherit_note)

	_canvas = PixelCanvas.new()
	_canvas.editor = self
	_canvas.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(_canvas)

	var pal := HBoxContainer.new()
	_palette_row = HBoxContainer.new()
	pal.add_child(_palette_row)
	var add := Button.new()
	add.text = "+ colour"
	add.pressed.connect(_add_color)
	pal.add_child(add)
	_color_edit = ColorPickerButton.new()
	_color_edit.custom_minimum_size = Vector2(80, 0)
	_color_edit.tooltip_text = "Change the selected palette colour everywhere it's used."
	_color_edit.popup_closed.connect(func(): _recolor(_color_edit.color))
	pal.add_child(_color_edit)
	box.add_child(pal)

	var strip_scroll := ScrollContainer.new()
	strip_scroll.custom_minimum_size = Vector2(0, 100)
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip = HBoxContainer.new()
	strip_scroll.add_child(_strip)
	box.add_child(strip_scroll)

	var frame_bar := _buttons([
			["+ Blank", _new_frame.bind(false)], ["Duplicate", _new_frame.bind(true)],
			["Delete", _delete_frame], ["◀ Move", _move_frame.bind(-1)], ["Move ▶", _move_frame.bind(1)]])
	_hold = _spin(0.25, 32, 0.25)
	_hold.tooltip_text = "How many beats this frame stays up."
	_hold.value_changed.connect(_set_hold)
	frame_bar.add_child(_field("Hold", _hold))
	frame_bar.add_child(VSeparator.new())
	frame_bar.add_child(_buttons([["Import PNG", func(): _import_dialog.popup_centered_ratio(0.6)],
			["Export PNG", func(): _export_dialog.popup_centered_ratio(0.6)]]))
	box.add_child(frame_bar)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.text = "Left paints, right erases. B pencil, F fill, I pick. , and . step frames. Ctrl+Z / Ctrl+Shift+Z undo and redo, Ctrl+S save."
	box.add_child(_status)
	return box


func _build_right() -> Control:
	var box := _column(300)
	box.add_child(_heading("Preview"))
	_play = CheckBox.new()
	_play.text = "Play (off: shows the frame being drawn)"
	_play.button_pressed = true
	_play.toggled.connect(func(_on): _refresh_preview())
	box.add_child(_play)

	_preview_box = ColorRect.new()
	(_preview_box as ColorRect).color = GROUND
	_preview_box.custom_minimum_size = Vector2(300, 260)
	_preview_box.clip_contents = true
	box.add_child(_preview_box)
	# Big, facing right and left; then at game size, a few humans side by side.
	var spots := [[Vector2(30, 20), PREVIEW_ZOOM, false], [Vector2(170, 20), PREVIEW_ZOOM, true]]
	for i in 6:
		spots.append([Vector2(60 + i * 30, 160), 4, i % 2 == 1])
	for spot in spots:
		var p := AnimatedSprite2D.new()
		p.centered = false
		p.position = spot[0]
		p.scale = Vector2.ONE * spot[1]
		p.flip_h = spot[2]
		var mat := ShaderMaterial.new()
		mat.shader = TINT_SHADER
		p.material = mat
		_previews.append(p)
		_preview_box.add_child(p)
	var note := Label.new()
	note.text = "Bottom row: 4x, about as big as on a phone."
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.5)
	box.add_child(note)

	box.add_child(_heading("Look"))
	_lift = HSlider.new()
	_lift.max_value = 0.4
	_lift.step = 0.01
	_lift.value_changed.connect(func(_v): _refresh_tint())
	box.add_child(_field("Lift", _lift))
	_dresscode = OptionButton.new()
	for code: String in Humans.DRESSCODES:
		_dresscode.add_item(code.capitalize())
	_dresscode.add_item("Custom")
	_dresscode.item_selected.connect(func(i):
		_tint.disabled = i < Humans.DRESSCODES.size()
		_refresh_tint())
	box.add_child(_field("Dresscode", _dresscode))
	_tint = ColorPickerButton.new()
	_tint.color = Color.from_hsv(0.8, 1.0, 0.8)
	_tint.disabled = true
	_tint.custom_minimum_size = Vector2(0, 28)
	_tint.color_changed.connect(func(_c): _refresh_tint())
	box.add_child(_field("Custom", _tint))
	var colour_note := Label.new()
	colour_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	colour_note.modulate = Color(1, 1, 1, 0.5)
	colour_note.add_theme_font_size_override("font_size", 12)
	colour_note.text = "Black is the body: it takes the lift and the dresscode. Anything drawn in another colour stays as drawn."
	box.add_child(colour_note)
	box.add_child(_build_when())
	return box


func _build_when() -> Control:
	var outer := VBoxContainer.new()
	outer.add_child(_heading("When it happens"))
	_builtin_note = Label.new()
	_builtin_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_builtin_note.modulate = Color(1, 1, 1, 0.5)
	_builtin_note.text = "Built in: the game's code decides when this plays (tune it in the Behaviour tab). New actions (✦) set their own."
	outer.add_child(_builtin_note)
	_when_box = VBoxContainer.new()
	outer.add_child(_when_box)
	_trigger = OptionButton.new()
	for t: Array in TRIGGERS:
		_trigger.add_item(t[1])
	_trigger.item_selected.connect(func(i): _set_behaviour("trigger", TRIGGERS[i][0]))
	_when_box.add_child(_field("Set off", _trigger))
	_trigger_help = Label.new()
	_trigger_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	_trigger_help.modulate = Color(1, 1, 1, 0.5)
	_trigger_help.add_theme_font_size_override("font_size", 12)
	_when_box.add_child(_trigger_help)
	_chance = _spin(0, 1, 0.01)
	_chance.tooltip_text = "Chance each time it's rolled."
	_chance.value_changed.connect(func(v): _set_behaviour("chance", v))
	_when_box.add_child(_field("Chance", _chance))
	var time_row := HBoxContainer.new()
	_time_from = _spin(0, 120, 0.1)
	_time_to = _spin(0, 120, 0.1)
	for sb: SpinBox in [_time_from, _time_to]:
		sb.value_changed.connect(func(_v): _set_behaviour("time", [_time_from.value, _time_to.value]))
		sb.size_flags_horizontal = SIZE_EXPAND_FILL
		time_row.add_child(sb)
	time_row.tooltip_text = "Seconds, picked between the two. A take that doesn't loop plays once instead."
	_when_box.add_child(_field("Seconds", time_row))
	_wander = CheckBox.new()
	_wander.text = "Wanders a few steps while doing it"
	_wander.toggled.connect(func(on): _set_behaviour("move", "wander" if on else "still"))
	_when_box.add_child(_wander)
	_paired = CheckBox.new()
	_paired.text = "Paired: the other one joins in"
	_paired.toggled.connect(func(on): _set_behaviour("paired", on))
	_when_box.add_child(_paired)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.modulate = Color(1, 1, 1, 0.5)
	note.add_theme_font_size_override("font_size", 12)
	note.text = "Shared by every skin; each skin can draw it its own way. To see it in the crowd: save, then Restart in the Behaviour tab."
	_when_box.add_child(note)
	return outer


func _build_dialogs() -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = ["*.png"]
	_import_dialog.file_selected.connect(_import_png)
	add_child(_import_dialog)
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = ["*.png"]
	_export_dialog.file_selected.connect(_export_png)
	add_child(_export_dialog)
	_new_action_dialog = ConfirmationDialog.new()
	_new_action_dialog.title = "New action"
	_new_action_dialog.ok_button_text = "Add"
	_new_action_name = LineEdit.new()
	_new_action_name.placeholder_text = "name, like jump or hug"
	_new_action_name.text_submitted.connect(func(t):
		_new_action_dialog.hide()
		_new_action(t))
	_new_action_dialog.add_child(_new_action_name)
	_new_action_dialog.confirmed.connect(func(): _new_action(_new_action_name.text))
	add_child(_new_action_dialog)
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.dialog_text = "There are unsaved changes."
	_quit_dialog.ok_button_text = "Save and quit"
	_quit_dialog.add_button("Quit without saving", true, "discard")
	_quit_dialog.confirmed.connect(func():
		_save()
		if not _dirty and not _behaviour.dirty:
			get_tree().quit())
	_quit_dialog.custom_action.connect(func(_a): get_tree().quit())
	add_child(_quit_dialog)


func _column(width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 6)
	return box


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


func _list(parent: Control, rows: int) -> ItemList:
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(0, rows * 26)
	l.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _buttons(specs: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for s in specs:
		var b := Button.new()
		b.text = s[0]
		b.focus_mode = FOCUS_NONE
		b.pressed.connect(s[1])
		row.add_child(b)
	return row


func _field(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(100, 0)
	row.add_child(l)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return s


# --- Widgets ---------------------------------------------------------------

## The zoomed-in frame being drawn.
class PixelCanvas extends Control:
	var editor: Control

	func _cell_size() -> float:
		var fs := Vector2(editor._size())
		return floorf(minf(size.x / fs.x, size.y / fs.y))

	func _origin() -> Vector2:
		return ((size - Vector2(editor._size()) * _cell_size()) / 2).floor()

	func _draw() -> void:
		var fs: Vector2i = editor._size()
		var cs := _cell_size()
		var o := _origin()
		draw_rect(Rect2(o, Vector2(fs) * cs), GROUND)
		var frames: Array = editor._frames()
		var i: int = editor._frame
		# Previous frame in red, next in blue; looping takes wrap around.
		if editor._onion.button_pressed and frames.size() > 1:
			var loops: bool = editor._cur_take().loop
			if i > 0 or loops:
				_draw_rows(frames[i - 1].px, o, cs, Color(1, 0.4, 0.4, 0.35))
			if i + 1 < frames.size() or loops:
				_draw_rows(frames[(i + 1) % frames.size()].px, o, cs, Color(0.4, 0.7, 1, 0.35))
		_draw_rows(frames[i].px, o, cs, Color.WHITE)
		var line := Color(1, 1, 1, 0.12)
		for x in fs.x + 1:
			draw_line(o + Vector2(x * cs, 0), o + Vector2(x * cs, fs.y * cs), line)
		for y in fs.y + 1:
			draw_line(o + Vector2(0, y * cs), o + Vector2(fs.x * cs, y * cs), line)
		# The base pixel: the one that collides and that positions the human.
		var base := -Vector2(Humans.BASE_OFFSET)
		draw_rect(Rect2(o + base * cs, Vector2.ONE * cs), Color(1, 0.8, 0.2, 0.8), false, 2.0)

	## Onion layers tint the frame's own colours; black would vanish, so
	## it shows as the tint itself.
	func _draw_rows(rows: Array, o: Vector2, cs: float, tint: Color) -> void:
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == ".":
					continue
				var c: Color = editor.color_of(row[x])
				if tint != Color.WHITE:
					c = Color(tint, tint.a)
				draw_rect(Rect2(o + Vector2(x, y) * cs, Vector2.ONE * cs), c)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		var mm := event as InputEventMouseMotion
		if mb and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_paint_at(mb.position, mb.button_index == MOUSE_BUTTON_RIGHT, true)
			else:
				editor.end_stroke()
		elif mm and mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			_paint_at(mm.position, mm.button_mask & MOUSE_BUTTON_MASK_RIGHT != 0, false)

	func _paint_at(p: Vector2, erase: bool, first: bool) -> void:
		var c := Vector2i(((p - _origin()) / _cell_size()).floor())
		if Rect2i(Vector2i.ZERO, editor._size()).has_point(c):
			editor.paint(c, erase, first)


## One frame in the strip: a small drawing of it, with its hold.
class FrameThumb extends Button:
	var editor: Control
	var rows: Array
	var hold: float
	var selected := false

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 88)
		focus_mode = FOCUS_NONE

	func _draw() -> void:
		var cs := 10.0
		var o := Vector2(7, 6)
		draw_rect(Rect2(o, Vector2(editor._size()) * cs), GROUND)
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] != ".":
					draw_rect(Rect2(o + Vector2(x, y) * cs, Vector2.ONE * cs), editor.color_of(row[x]))
		var font := get_theme_default_font()
		var label := "×" + str(hold).trim_suffix(".0") if hold != 1.0 else ""
		draw_string(font, Vector2(8, 82), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		if selected:
			draw_rect(Rect2(Vector2.ONE * 2, size - Vector2.ONE * 4), Color(1, 0.8, 0.2), false, 2.0)


## A palette colour to paint with; "." is transparent, drawn as a checker.
class Swatch extends Button:
	var editor: Control
	var sym: String
	var selected := false

	func _ready() -> void:
		custom_minimum_size = Vector2(36, 36)
		focus_mode = FOCUS_NONE

	func _draw() -> void:
		var r := Rect2(Vector2.ONE * 6, size - Vector2.ONE * 12)
		if sym == ".":
			draw_rect(r, GROUND)
			draw_line(r.position, r.end, Color(1, 0.3, 0.3), 2.0)
		else:
			draw_rect(r, editor.color_of(sym))
		if selected:
			draw_rect(Rect2(Vector2.ONE * 2, size - Vector2.ONE * 4), Color(1, 0.8, 0.2), false, 2.0)
