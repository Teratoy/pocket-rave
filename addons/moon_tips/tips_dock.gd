@tool
extends EditorDock
## The Moon Tips dock: lists the tips in the library (see
## MoonTipLibrary) and edits the picked one, saving as you go. Repeatable
## tips get a chance, contextual ones a trigger. A preview shows the tip
## in the moon's balloon; click it to hurry it along like a touch would.

const SpeechBalloon := preload("res://scripts/speech_balloon.gd")
## The Tips autoload's script; the autoload itself only runs in the game.
const Tips := preload("res://addons/moon_tips/tips.gd")
const SAVE_DELAY := 0.5
## The preview's scale, and the rows of the game it shows.
const PREVIEW_PX := 4
const PREVIEW_ROWS := Vector2i(0, 64)
const CUSTOM_TRIGGER := "(custom)"

var _library: MoonTipLibrary
var _tip: MoonTip

var _list: ItemList
var _order: OptionButton
var _remove: Button
var _up: Button
var _down: Button
var _editor: Control
var _kind: OptionButton
var _enabled: CheckBox
var _text: TextEdit
var _chance_row: Control
var _chance: SpinBox
var _share: Label
var _trigger_row: Control
var _trigger: OptionButton
var _custom: LineEdit
var _trigger_info: Label
var _every_time: CheckBox
var _pages: Label
var _balloon: SpeechBalloon
var _save_timer: Timer
var _forget_dialog: ConfirmationDialog
## Set while filling the editor from a tip, so it isn't edited back.
var _filling := false


func _init() -> void:
	title = "Moon Tips"
	layout_key = "moon_tips"
	default_slot = EditorDock.DOCK_SLOT_BOTTOM
	available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL | EditorDock.DOCK_LAYOUT_FLOATING
	icon_name = &"RichTextEffect"


func _ready() -> void:
	_library = load(Tips.LIBRARY) if ResourceLoader.exists(Tips.LIBRARY) else MoonTipLibrary.new()
	_build()
	_refresh_list()
	_select(0)


func _build() -> void:
	custom_minimum_size.y = 300
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	# The list, with buttons to change it.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 320
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var bar := HBoxContainer.new()
	left.add_child(bar)
	_tool_button(bar, "Add", "Add a repeatable tip, said when the moon is touched",
			_add.bind(MoonTip.Kind.REPEATABLE)).text = "Repeatable"
	_tool_button(bar, "Add", "Add a contextual tip, said once when its trigger happens",
			_add.bind(MoonTip.Kind.CONTEXTUAL)).text = "Contextual"
	_tool_button(bar, "Duplicate", "Duplicate the tip", _duplicate)
	_remove = _tool_button(bar, "Remove", "Remove the tip", _remove_tip)
	_up = _tool_button(bar, "MoveUp", "Move the tip up", _move.bind(-1))
	_down = _tool_button(bar, "MoveDown", "Move the tip down", _move.bind(1))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	left.add_child(_list)
	var order_row := HBoxContainer.new()
	left.add_child(order_row)
	order_row.add_child(_label("Touches say repeatable tips"))
	_order = OptionButton.new()
	_order.add_item("at random, by chance", MoonTipLibrary.Order.RANDOM)
	_order.add_item("in order, top to bottom", MoonTipLibrary.Order.IN_ORDER)
	_order.selected = _library.order
	_order.item_selected.connect(func(i: int):
		_library.order = i
		_changed())
	order_row.add_child(_order)
	var forget := Button.new()
	forget.text = "Forget said tips"
	forget.tooltip_text = "Lets contextual tips be said again when you run the game here"
	forget.pressed.connect(func(): _forget_dialog.popup_centered())
	left.add_child(forget)
	_forget_dialog = ConfirmationDialog.new()
	_forget_dialog.dialog_text = "Forget which contextual tips were said?\nThey'll all be said again, as on a first launch.\n(Deletes %s.)" % Tips.SAVE_FILE
	_forget_dialog.confirmed.connect(_forget)
	add_child(_forget_dialog)

	# The picked tip.
	var middle := VBoxContainer.new()
	middle.custom_minimum_size.x = 360
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(middle)
	_editor = middle
	var top := HBoxContainer.new()
	middle.add_child(top)
	_kind = OptionButton.new()
	_kind.add_item("Repeatable", MoonTip.Kind.REPEATABLE)
	_kind.add_item("Contextual", MoonTip.Kind.CONTEXTUAL)
	_kind.tooltip_text = "Repeatable: said when the moon is touched.\nContextual: said once, the first time its trigger happens."
	_kind.item_selected.connect(_on_kind)
	top.add_child(_kind)
	_enabled = CheckBox.new()
	_enabled.text = "Enabled"
	_enabled.toggled.connect(func(on: bool): _edit("enabled", on))
	top.add_child(_enabled)
	_pages = _label("")
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_pages)

	_text = TextEdit.new()
	_text.placeholder_text = "What the moon says. A blank line starts a new balloon."
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.text_changed.connect(func():
		_edit("text", _text.text)
		_show_pages())
	middle.add_child(_text)

	_chance_row = HBoxContainer.new()
	middle.add_child(_chance_row)
	_chance_row.add_child(_label("Chance"))
	_chance = SpinBox.new()
	_chance.min_value = 0.0
	_chance.max_value = 100.0
	_chance.step = 0.1
	_chance.allow_greater = true
	_chance.tooltip_text = "Weight among the repeatable tips: 2 comes up twice as often as 1, 0 never."
	_chance.value_changed.connect(func(v: float):
		_edit("chance", v)
		_show_share())
	_chance_row.add_child(_chance)
	_share = _label("")
	_chance_row.add_child(_share)

	_trigger_row = VBoxContainer.new()
	middle.add_child(_trigger_row)
	var trigger_line := HBoxContainer.new()
	_trigger_row.add_child(trigger_line)
	trigger_line.add_child(_label("Trigger"))
	_trigger = OptionButton.new()
	for t in MoonTipLibrary.TRIGGERS:
		_trigger.add_item(t)
		_trigger.set_item_tooltip(_trigger.item_count - 1, MoonTipLibrary.TRIGGERS[t])
	_trigger.add_item(CUSTOM_TRIGGER)
	_trigger.item_selected.connect(_on_trigger)
	trigger_line.add_child(_trigger)
	_custom = LineEdit.new()
	_custom.placeholder_text = "your_event, fired with Tips.event(\"your_event\")"
	_custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom.text_changed.connect(func(t: String):
		_edit("trigger", t.strip_edges())
		_show_trigger_info())
	trigger_line.add_child(_custom)
	_every_time = CheckBox.new()
	_every_time.text = "Every time"
	_every_time.tooltip_text = "Said every time the trigger happens, not just the first time."
	_every_time.toggled.connect(func(on: bool):
		_edit("every_time", on)
		_show_trigger_info())
	trigger_line.add_child(_every_time)
	_trigger_info = _label("")
	_trigger_info.modulate = Color(1, 1, 1, 0.6)
	_trigger_row.add_child(_trigger_info)

	# The preview: the top of the game with the moon saying the tip.
	var right := VBoxContainer.new()
	split.add_child(right)
	var replay := Button.new()
	replay.text = "Preview"
	replay.tooltip_text = "Has the moon say the tip. Click the preview to hurry her along."
	replay.pressed.connect(_preview)
	right.add_child(replay)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(SpeechBalloon.SCREEN_WIDTH, PREVIEW_ROWS.y - PREVIEW_ROWS.x) * PREVIEW_PX
	container.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_balloon.advance())
	right.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(container.custom_minimum_size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	container.add_child(viewport)
	var scene := Node2D.new()
	scene.scale = Vector2.ONE * PREVIEW_PX
	scene.position.y = -PREVIEW_ROWS.x * PREVIEW_PX
	viewport.add_child(scene)
	var moon_base: Texture2D = load("res://visual assets/moonbase.png")
	for path in ["res://visual assets/skystarfield.png", "res://visual assets/sound.png",
			"res://visual assets/moonbase.png", "res://visual assets/moonface.png"]:
		var sprite := Sprite2D.new()
		sprite.texture = load(path)
		sprite.centered = false
		scene.add_child(sprite)
	_balloon = SpeechBalloon.new()
	_balloon.px = PREVIEW_PX
	var used := moon_base.get_image().get_used_rect()
	_balloon.anchor = Vector2i(used.get_center().x, used.end.y)
	scene.add_child(_balloon)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)


func _tool_button(parent: Control, icon: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.tooltip_text = tooltip
	b.icon = EditorInterface.get_editor_theme().get_icon(icon, &"EditorIcons")
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _refresh_list() -> void:
	var picked := _library.tips.find(_tip)
	_list.clear()
	for tip in _library.tips:
		var head := ""
		if tip.kind == MoonTip.Kind.REPEATABLE:
			head = "%3d%%" % roundi(_library.share(tip) * 100.0)
		else:
			head = "@%s%s" % [tip.trigger if tip.trigger != "" else "?", " (every time)" if tip.every_time else ""]
		var first_line := tip.text.strip_edges().get_slice("\n", 0)
		var i := _list.add_item("%s  %s" % [head, first_line if first_line != "" else "(empty)"])
		_list.set_item_tooltip(i, tip.text)
		if not tip.enabled:
			_list.set_item_custom_fg_color(i, Color(1, 1, 1, 0.35))
	if picked >= 0:
		_list.select(picked)
	_update_buttons()


func _select(index: int) -> void:
	_tip = _library.tips[index] if index >= 0 and index < _library.tips.size() else null
	if _tip:
		_list.select(index)
	_fill()
	_update_buttons()
	_preview()


func _update_buttons() -> void:
	var i := _library.tips.find(_tip)
	_remove.disabled = _tip == null
	_up.disabled = i <= 0
	_down.disabled = i < 0 or i >= _library.tips.size() - 1


## Shows the picked tip in the editor.
func _fill() -> void:
	_filling = true
	_editor.visible = _tip != null
	if _tip:
		_kind.select(_kind.get_item_index(_tip.kind))
		_enabled.button_pressed = _tip.enabled
		_every_time.button_pressed = _tip.every_time
		if _text.text != _tip.text:
			_text.text = _tip.text
		_chance.value = _tip.chance
		var known := MoonTipLibrary.TRIGGERS.keys().find(_tip.trigger)
		_trigger.select(known if known >= 0 else _trigger.item_count - 1)
		_custom.text = _tip.trigger
		_custom.visible = known < 0
		_show_kind()
		_show_share()
		_show_trigger_info()
		_show_pages()
	_filling = false


func _show_kind() -> void:
	_chance_row.visible = _tip.kind == MoonTip.Kind.REPEATABLE
	_trigger_row.visible = _tip.kind == MoonTip.Kind.CONTEXTUAL


func _show_share() -> void:
	var share := _library.share(_tip)
	if not _tip.enabled:
		_share.text = "(disabled)"
	elif _library.order == MoonTipLibrary.Order.IN_ORDER:
		_share.text = "said in order, chance unused"
	else:
		_share.text = "≈ %.1f%% of touches" % (share * 100.0)


func _show_trigger_info() -> void:
	var t := _tip.trigger
	var when := "Said every time" if _tip.every_time else "Said once, the first time"
	if t in MoonTipLibrary.TRIGGERS:
		_trigger_info.text = "%s: %s." % [when, MoonTipLibrary.TRIGGERS[t].to_lower()]
	elif t == "":
		_trigger_info.text = "Needs a trigger."
	else:
		_trigger_info.text = "%s the game calls Tips.event(\"%s\")." % [when, t]
	var names: Dictionary = MoonTipLibrary.PLACEHOLDERS.get(t, {})
	if not names.is_empty():
		var each := PackedStringArray()
		for n in names:
			each.append("{%s}" % n)
		_trigger_info.text += "\nIts text can say %s, filled in as it's said." % ", ".join(each)


func _show_pages() -> void:
	var pages := SpeechBalloon.paginate(_tip.text).size()
	_pages.text = "%d balloon%s" % [pages, "" if pages == 1 else "s"]


## Sets a property of the picked tip from the editor.
func _edit(property: String, value: Variant) -> void:
	if _filling or not _tip:
		return
	_tip.set(property, value)
	_changed()


func _on_kind(index: int) -> void:
	if _filling:
		return
	_tip.kind = _kind.get_item_id(index)
	if _tip.kind == MoonTip.Kind.CONTEXTUAL and _tip.trigger == "":
		_tip.trigger = MoonTipLibrary.TRIGGERS.keys()[0]
	_changed()
	_fill()


func _on_trigger(index: int) -> void:
	if _filling:
		return
	var custom := index == _trigger.item_count - 1
	_custom.visible = custom
	if custom:
		_custom.grab_focus()
	else:
		_edit("trigger", _trigger.get_item_text(index))
		_custom.text = _tip.trigger
		_preview()
	_show_trigger_info()


func _add(kind: MoonTip.Kind) -> void:
	var at := _library.tips.find(_tip) + 1 if _tip else _library.tips.size()
	_library.tips.insert(at, MoonTip.make(kind))
	_changed()
	_select(at)
	_text.grab_focus()


func _duplicate() -> void:
	if not _tip:
		return
	var copy := MoonTip.make(_tip.kind)
	for p in ["text", "enabled", "chance", "trigger", "every_time"]:
		copy.set(p, _tip.get(p))
	var at := _library.tips.find(_tip) + 1
	_library.tips.insert(at, copy)
	_changed()
	_select(at)


func _remove_tip() -> void:
	var i := _library.tips.find(_tip)
	if i < 0:
		return
	_library.tips.remove_at(i)
	_tip = null
	_changed()
	_select(mini(i, _library.tips.size() - 1))


func _move(by: int) -> void:
	var i := _library.tips.find(_tip)
	var to := i + by
	if i < 0 or to < 0 or to >= _library.tips.size():
		return
	_library.tips.remove_at(i)
	_library.tips.insert(to, _tip)
	_changed()


## Something changed: update what shows it, and save soon.
func _changed() -> void:
	_refresh_list()
	if _tip:
		_show_share()
	_save_timer.start()


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(Tips.LIBRARY.get_base_dir())
	var err := ResourceSaver.save(_library, Tips.LIBRARY)
	if err != OK:
		push_error("Moon Tips: can't save %s (%s)" % [Tips.LIBRARY, error_string(err)])


func _preview() -> void:
	if _tip and _tip.text.strip_edges() != "":
		_balloon.say(_tip.text.format(MoonTipLibrary.PLACEHOLDERS.get(_tip.trigger, {})))
	else:
		_balloon.close()


func _forget() -> void:
	DirAccess.remove_absolute(Tips.SAVE_FILE)


func _exit_tree() -> void:
	if _save_timer and not _save_timer.is_stopped():
		_save()
