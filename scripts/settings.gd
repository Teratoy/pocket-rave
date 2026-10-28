extends Node
## The settings button opens the settings menu, which can:
## - import tracks: the picked audio files are copied into the game and
##   played by the DJ named after their artist (see Music.import_tracks);
## - edit tracks: pick an author, then one of their tracks to change its name, author and cover (see
##   Music.edit_track), or remove it (see Music.remove_track);
## - change graphics: turn pixel edge smoothing (see SmoothPixels) and
##   shadows (see Shadows) on or off;
## - change sound: set the volume, and turn the low-bit effect that makes
##   the music sound 8-bit on or off (see SoundSettings);
## - set the dresscode: the colour humans arriving from now on wear, and how
##   much they stray from it (see Humans.dresscode). Those already here keep
##   their colours.
## On the web FileDialog can't reach the player's files, so the pickers are
## the page's own file input instead (see _web_pick).

const Menu := preload("res://scripts/menu.gd")
const Tags := preload("res://scripts/tags.gd")

## More tracks than this scroll in the track list.
const MAX_VISIBLE_TRACKS := 6
## Where files picked on the web are written so they can be read like
## any other path; emptied after each pick.
const WEB_PICKS_DIR := "user://picked/"

@export var button: Sprite2D
@export var music: Node
@export var shadows: CanvasGroup
@export var humans: Node2D

var _menu: Menu
## Says how the last import went; hidden until there was one.
var _status: Label
var _import_dialog: FileDialog

var _author_menu: Menu
var _author_list: VBoxContainer
## The author whose tracks _track_menu lists.
var _author := ""
var _track_menu: Menu
var _track_list: VBoxContainer

var _editor: Menu
## The track being edited, and the cover picked for it (null if unchanged).
var _track := ""
var _cover: Image
var _cover_view: TextureRect
var _title_field: LineEdit
var _artist_field: LineEdit
var _cover_dialog: FileDialog
## Asks before removing the track being edited.
var _confirm_remove: Menu
## The page's file picker (see _web_pick), and the JavaScript callback
## it hands files to, kept so it isn't freed.
var _web_picker: JavaScriptObject
var _web_callback: JavaScriptObject
## The picked files so far, and what gets them once all are in: their
## paths, or the one path if the pick was for a single file.
var _web_picks := PackedStringArray()
var _web_done: Callable
var _web_multiple := false

var _graphics_menu: Menu
var _smooth_button: Button
var _shadows_button: Button

var _sound_menu: Menu
var _volume_label: Label
var _low_bit_button: Button

var _dresscode_menu: Menu
var _dresscode_button: Button
var _variation_label: Label


func _ready() -> void:
	# Usable while paused; the menus and file pickers below inherit this.
	process_mode = Node.PROCESS_MODE_ALWAYS
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu = Menu.new(button.texture, "SETTINGS")
	add_child(_menu)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	_menu.list.add_child(_status)
	_menu.add_item("IMPORT", _pick_tracks)
	_menu.add_item("EDIT", _open_author_menu)
	_menu.add_item("GRAPHICS", func(): _graphics_menu.open())
	_menu.add_item("SOUND", func(): _sound_menu.open())
	_menu.add_item("DRESSCODE", func(): _dresscode_menu.open())
	_menu.add_item("CLOSE", func(): pass)
	_import_dialog = _add_dialog("Import tracks",
			"*.mp3,*.ogg,*.wav;Audio;audio/mpeg,audio/ogg,audio/x-wav,audio/wav",
			FileDialog.FILE_MODE_OPEN_FILES)
	_import_dialog.files_selected.connect(_on_tracks_selected)

	_author_menu = Menu.new(button.texture, "EDIT A TRACK")
	add_child(_author_menu)
	_author_list = _author_menu.add_scroll()
	_author_menu.add_item("BACK", _open)

	# Titled with the author's name when opened.
	_track_menu = Menu.new(button.texture, "")
	add_child(_track_menu)
	_track_list = _track_menu.add_scroll()
	_track_menu.add_item("BACK", _open_author_menu)

	_build_editor()
	_build_graphics()
	_build_sound()
	_build_dresscode()
	button.pressed.connect(_open)


func _open() -> void:
	Tips.event("settings")
	_status.visible = false
	_menu.open()


## The system picker where there is one (Android, desktop portals), else
## Godot's own.
func _add_dialog(title: String, filter: String, mode: FileDialog.FileMode) -> FileDialog:
	var d := FileDialog.new()
	d.use_native_dialog = true
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = mode
	d.title = title
	d.filters = PackedStringArray([filter])
	add_child(d)
	return d


func _pick_tracks() -> void:
	if OS.has_feature("web"):
		_web_pick("audio/*,.mp3,.ogg,.wav", true, _on_tracks_selected)
	else:
		_import_dialog.popup_centered_ratio()


## Opens the page's file picker and calls done with the picked files'
## paths, or not at all if the player cancels. Files come over as base64,
## as JavaScriptBridge can't hand over raw bytes.
func _web_pick(accept: String, multiple: bool, done: Callable) -> void:
	if not _web_picker:
		JavaScriptBridge.eval("""
			window.pocketRavePick = function (accept, multiple, send) {
				const input = document.createElement('input');
				input.type = 'file';
				input.accept = accept;
				input.multiple = multiple;
				input.onchange = async () => {
					const files = Array.from(input.files);
					for (let i = 0; i < files.length; i++) {
						const data = await new Promise((resolve) => {
							const reader = new FileReader();
							reader.onload = () => resolve(reader.result.split(',')[1] || '');
							reader.readAsDataURL(files[i]);
						});
						send(files[i].name, data, i === files.length - 1);
					}
				};
				input.click();
			};
		""", true)
		_web_picker = JavaScriptBridge.get_interface("window")
		_web_callback = JavaScriptBridge.create_callback(_on_web_file)
	DirAccess.make_dir_recursive_absolute(WEB_PICKS_DIR)
	for file in DirAccess.get_files_at(WEB_PICKS_DIR):
		DirAccess.remove_absolute(WEB_PICKS_DIR + file)
	_web_picks.clear()
	_web_done = done
	_web_multiple = multiple
	_web_picker.pocketRavePick(accept, multiple, _web_callback)


## Gets [name, base64 data, last] for each picked file. Names are kept,
## as an untagged track is named after its file.
func _on_web_file(args: Array) -> void:
	var path := WEB_PICKS_DIR + str(args[0]).validate_filename()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(Marshalls.base64_to_raw(args[1]))
		f.close()
		_web_picks.append(path)
	if not args[2]:
		return
	if _web_multiple:
		_web_done.call(_web_picks)
	elif not _web_picks.is_empty():
		_web_done.call(_web_picks[0])
	for picked in _web_picks:
		DirAccess.remove_absolute(picked)


func _on_tracks_selected(paths: PackedStringArray) -> void:
	var added: int = music.import_tracks(paths)
	if added == 0:
		_status.text = "NO TRACKS ADDED"
	else:
		_status.text = "ADDED %d TRACK%s" % [added, "" if added == 1 else "S"]
		Tips.event("tracks_imported", {"count": added})
	_status.visible = true
	_menu.open()


func _open_author_menu() -> void:
	Menu.clear(_author_list)
	for dj: String in music.djs():
		_author_menu.add_item(dj.to_upper(), _open_track_menu.bind(dj), false, _author_list)
	_author_menu.fit_scroll(_author_list, MAX_VISIBLE_TRACKS)
	_author_menu.open()


## Lists the author's tracks, or the authors if they have none left.
func _open_track_menu(author: String) -> void:
	var tracks: Array[String] = music.dj_tracks(author)
	if tracks.is_empty():
		_open_author_menu()
		return
	_author = author
	(_track_menu.list.get_child(0) as Label).text = author.to_upper()
	Menu.clear(_track_list)
	for path in tracks:
		_track_menu.add_item(music.track_info(path).title.to_upper(), _edit.bind(path), false, _track_list)
	_track_menu.fit_scroll(_track_list, MAX_VISIBLE_TRACKS)
	_track_menu.open()


func _build_editor() -> void:
	_editor = Menu.new(button.texture, "EDIT TRACK")
	add_child(_editor)
	# The cover at the size it shows on the middle button, on a dark square
	# that stands in when there is none.
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.35)
	back.custom_minimum_size = Vector2.ONE * Tags.SIZE * Menu.PX / 2
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_editor.list.add_child(back)
	_cover_view = TextureRect.new()
	_cover_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.add_child(_cover_view)
	_editor.add_button("COVER", _pick_cover)
	_title_field = _editor.add_field("NAME")
	_artist_field = _editor.add_field("AUTHOR")
	_editor.add_item("SAVE", _save)
	_editor.add_item("REMOVE", func(): _confirm_remove.open())
	_editor.add_item("CANCEL", func(): _open_track_menu(_author))
	_confirm_remove = Menu.new(button.texture, "REMOVE TRACK?")
	add_child(_confirm_remove)
	_confirm_remove.add_item("REMOVE", _remove)
	_confirm_remove.add_item("CANCEL", func(): _editor.open())
	_cover_dialog = _add_dialog("Pick a cover",
			"*.png,*.jpg,*.jpeg,*.webp;Images;image/png,image/jpeg,image/webp",
			FileDialog.FILE_MODE_OPEN_FILE)
	_cover_dialog.file_selected.connect(_on_cover_selected)


func _build_graphics() -> void:
	_graphics_menu = Menu.new(button.texture, "GRAPHICS")
	add_child(_graphics_menu)
	_smooth_button = _graphics_menu.add_button("", _toggle_smoothing)
	_show_smoothing()
	_shadows_button = _graphics_menu.add_button("", _toggle_shadows)
	_show_shadows()
	_graphics_menu.add_item("BACK", _open)


func _toggle_smoothing() -> void:
	SmoothPixels.enabled = not SmoothPixels.enabled
	_show_smoothing()


func _show_smoothing() -> void:
	_smooth_button.text = "SMOOTH: %s" % ("ON" if SmoothPixels.enabled else "OFF")


func _toggle_shadows() -> void:
	shadows.enabled = not shadows.enabled
	_show_shadows()


func _show_shadows() -> void:
	_shadows_button.text = "SHADOWS: %s" % ("ON" if shadows.enabled else "OFF")


func _build_sound() -> void:
	_sound_menu = Menu.new(button.texture, "SOUND")
	add_child(_sound_menu)
	_volume_label = Label.new()
	_sound_menu.list.add_child(_volume_label)
	_sound_menu.add_slider(SoundSettings.volume, _set_volume)
	_low_bit_button = _sound_menu.add_button("", _toggle_low_bit)
	_show_sound()
	_sound_menu.add_item("BACK", _open)


func _set_volume(value: float) -> void:
	SoundSettings.volume = value
	_show_sound()


func _toggle_low_bit() -> void:
	SoundSettings.low_bit = not SoundSettings.low_bit
	_show_sound()


func _show_sound() -> void:
	_volume_label.text = "VOLUME: %d%%" % roundi(SoundSettings.volume * 100)
	_low_bit_button.text = "LOW-BIT: %s" % ("ON" if SoundSettings.low_bit else "OFF")


func _build_dresscode() -> void:
	_dresscode_menu = Menu.new(button.texture, "DRESSCODE")
	add_child(_dresscode_menu)
	_dresscode_button = _dresscode_menu.add_button("", _next_dresscode)
	_variation_label = Label.new()
	_dresscode_menu.list.add_child(_variation_label)
	_dresscode_menu.add_slider(humans.variation, _set_variation)
	_show_dresscode()
	_dresscode_menu.add_item("BACK", _open)


## Cycles through the dresscodes.
func _next_dresscode() -> void:
	var codes: Array = humans.DRESSCODES.keys()
	humans.dresscode = codes[(codes.find(humans.dresscode) + 1) % codes.size()]
	_show_dresscode()


func _set_variation(value: float) -> void:
	humans.variation = value
	_show_dresscode()


func _show_dresscode() -> void:
	_dresscode_button.text = "WEAR: %s" % humans.dresscode
	_variation_label.text = "VARIATION: %d%%" % roundi(humans.variation * 100)


func _edit(path: String) -> void:
	_track = path
	_cover = null
	var info: Dictionary = music.track_info(path)
	_title_field.text = info.title
	_artist_field.text = info.artist
	_cover_view.texture = info.cover
	_editor.open()


func _pick_cover() -> void:
	if OS.has_feature("web"):
		_web_pick("image/png,image/jpeg,image/webp", false, _on_cover_selected)
	else:
		_cover_dialog.popup_centered_ratio()


func _on_cover_selected(path: String) -> void:
	var img := Tags.image_from_buffer(FileAccess.get_file_as_bytes(path))
	if not img:
		push_warning("%s is not a PNG, JPEG or WebP image" % path)
		return
	_cover = img
	_cover_view.texture = Tags.make_cover(img)


func _save() -> void:
	music.edit_track(_track, _title_field.text, _artist_field.text, _cover)
	Tips.event("track_edited")
	# A new author moves the track to their list.
	_open_track_menu(music.track_dj(_track))


func _remove() -> void:
	music.remove_track(_track)
	_open_track_menu(_author)
