extends Node
## Plays DJ sets. Each track's artist (see track_info) is a DJ, playing
## all their tracks in title order once, then the music stops. Bundled
## tracks with no artist belong to their folder in res://music/; imported
## ones (in user://music/) to UNKNOWN_DJ. The music button opens a menu
## to pick a DJ; picking the current DJ again stops the set. A picked DJ is called to the booth
## and the set only starts once they get there (see start_set).
## On Android the set plays through the BackgroundMusic plugin instead, so
## it keeps going with the screen off (see addons/background_music).

signal playing_changed(playing: bool)
## A DJ was picked and should walk to the booth.
signal dj_called(dj: String)
## The current DJ is done (set over, stopped or replaced) and should leave.
signal dj_dismissed
## A track began, or the playing track's details were edited. artist and
## cover are "" and null when the track has none (see track_info).
signal track_started(dj: String, title: String, artist: String, cover: Texture2D)

const Tags := preload("res://scripts/tags.gd")

const MUSIC_DIR := "res://music/"
## Tracks the player imported.
const USER_MUSIC_DIR := "user://music/"
## Plays imported tracks that have no artist.
const UNKNOWN_DJ := "unknown"
const TRACK_EXTS := ["mp3", "ogg", "wav"]
## Where tracks are unpacked for the Android player, which can't read res://.
const NATIVE_DIR := "user://tracks/"
## The player's edits to track details, a section per track path, and the
## covers they picked.
const EDITS_FILE := "user://track_edits.cfg"
const COVERS_DIR := "user://covers/"

const Menu := preload("res://scripts/menu.gd")
## More DJs than this scroll inside the menu.
const MAX_VISIBLE_DJS := 6

@export var button: Sprite2D

## DJ name, lowercase so artists merge regardless of case -> track paths
## in play order.
var _djs := {}
## The picked DJ, on the way to the booth or playing.
var _dj := ""
var _live := false
var _queue: Array[String] = []
## The tracks handed to the native player, in its order (some may have
## been skipped while unpacking).
var _native_tracks: Array[String] = []
## Held still under the DJ's hand (see hold).
var _held := false
## The track current_stream last loaded, and its stream.
var _stream_path := ""
var _stream: AudioStream
## The playing track's path.
var _track := ""
var _edits := ConfigFile.new()
## Track path -> track_info, so tags are read once.
var _info := {}
var _player: AudioStreamPlayer
## The BackgroundMusic Android singleton, or null on other platforms.
var _native: Object
var _menu: Menu
var _dj_list: VBoxContainer


func _ready() -> void:
	_edits.load(EDITS_FILE)
	_load_djs()
	_player = AudioStreamPlayer.new()
	_player.finished.connect(_next_track)
	_player.bus = SoundSettings.BUS
	add_child(_player)
	_on_low_bit_changed(SoundSettings.low_bit)
	SoundSettings.low_bit_changed.connect(_on_low_bit_changed)
	if Engine.has_singleton("BackgroundMusic"):
		_native = Engine.get_singleton("BackgroundMusic")
	_build_menu()
	# The DJ menu works while paused (see Menu); the music itself doesn't.
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(_open_menu)


func is_playing() -> bool:
	return _live


## Seconds into the current track.
func playback_position() -> float:
	if not _live:
		return 0.0
	return _native.getPosition() if _native else _player.get_playback_position()


func track_length() -> float:
	var stream := current_stream()
	return stream.get_length() if stream else 0.0


## The playing track's audio, or null when nothing plays.
func current_stream() -> AudioStream:
	if not _live:
		return null
	if not _native:
		return _player.stream
	var i: int = _native.getTrackIndex()
	if i < 0 or i >= _native_tracks.size():
		return null
	if _native_tracks[i] != _stream_path:
		_stream_path = _native_tracks[i]
		_stream = _load_track(_stream_path)
	return _stream


## Stops the record where it is while the DJ's hand is on it (see
## Scratch), and lets it play on from there once held is false.
func hold(held: bool) -> void:
	if held == _held or not _live:
		return
	_held = held
	# Pausing the game stops the music already, and unpausing restarts it.
	if get_tree().paused:
		return
	if _native:
		if held:
			_native.pause()
		else:
			_native.resume()
	else:
		_player.stream_paused = held


## The DJs, by name.
func djs() -> Array:
	return _djs.keys()


## The DJ's tracks in play order; empty if there is no such DJ.
func dj_tracks(dj: String) -> Array[String]:
	return _djs.get(dj, [] as Array[String])


## The DJ playing the track at path, or "" if it isn't in the game.
func track_dj(path: String) -> String:
	for dj in _djs:
		if path in _djs[dj]:
			return dj
	return ""


## {title, artist, cover} for the track at path: the player's edits, else
## the track's own tags, else its file name for the title. artist may be
## "" and cover (a Texture2D) null.
func track_info(path: String) -> Dictionary:
	if path in _info:
		return _info[path]
	# Only bundled MP3s need loading; Tags reads the player's files itself.
	var info := Tags.read(path, _load_track(path) if path.begins_with("res://") else null)
	if info.title == "":
		info.title = path.get_file().get_basename()
	info.title = _edits.get_value(path, "title", info.title)
	info.artist = _edits.get_value(path, "artist", info.artist)
	var cover: String = _edits.get_value(path, "cover", "")
	if cover != "":
		info.cover = Tags.make_cover(Image.load_from_file(cover))
	_info[path] = info
	return info


## Saves the player's details for the track at path. An empty title goes
## back to the track's own; cover replaces the track's cover unless it is
## null.
func edit_track(path: String, title: String, artist: String, cover: Image = null) -> void:
	title = title.strip_edges()
	if title != "":
		_edits.set_value(path, "title", title)
	elif _edits.has_section_key(path, "title"):
		_edits.erase_section_key(path, "title")
	_edits.set_value(path, "artist", artist.strip_edges())
	if cover:
		DirAccess.make_dir_recursive_absolute(COVERS_DIR)
		var file := COVERS_DIR + path.md5_text() + ".png"
		Tags.make_cover(cover).get_image().save_png(file)
		_edits.set_value(path, "cover", file)
	_edits.save(EDITS_FILE)
	_info.erase(path)
	# A new artist moves the track to another DJ.
	_load_djs()
	if _live and path == _track:
		_announce_track()


## Takes the track at path out of the game. The player's imports are
## deleted; bundled tracks can't be, so they are marked removed and
## skipped. A DJ left with no tracks leaves the DJ menu.
func remove_track(path: String) -> void:
	var cover: String = _edits.get_value(path, "cover", "")
	if cover != "":
		DirAccess.remove_absolute(cover)
	if _edits.has_section(path):
		_edits.erase_section(path)
	if path.begins_with("res://"):
		_edits.set_value(path, "removed", true)
	else:
		DirAccess.remove_absolute(path)
	_edits.save(EDITS_FILE)
	_info.erase(path)
	_load_djs()
	_queue.erase(path)
	if _dj != "" and _dj not in _djs:
		stop()
	elif path == _track and not _native:
		_next_track()


func play_dj(dj: String) -> void:
	if dj == _dj:
		return
	stop()
	_queue.assign(_djs[dj])
	_dj = dj
	dj_called.emit(dj)
	Tips.event("dj_called", {"dj": dj})


## Called when the DJ reaches the booth.
func start_set() -> void:
	if _dj == "" or _live:
		return
	_live = true
	if _native:
		_native.playSet(_dj.to_upper(), _unpack_tracks(_queue, _native_tracks))
	else:
		_next_track()
	playing_changed.emit(true)
	Tips.event("set_started", {"dj": _dj})


func stop() -> void:
	if _dj == "":
		return
	var dj := _dj
	_dj = ""
	_track = ""
	_queue.clear()
	_native_tracks.clear()
	_held = false
	_player.stream_paused = false
	if _native:
		_native.stop()
	else:
		_player.stop()
	dj_dismissed.emit()
	if _live:
		_live = false
		playing_changed.emit(false)
		Tips.event("set_ended", {"dj": dj})


## On the web tracks normally play straight through the browser, skipping
## the bus effects the low-bit sound is made with; while it is on they go
## through Godot's mixer instead. The playing track carries on where it was.
func _on_low_bit_changed(on: bool) -> void:
	if not OS.has_feature("web"):
		return
	var pos := _player.get_playback_position()
	var was_playing := _player.playing
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM if on else AudioServer.PLAYBACK_TYPE_DEFAULT
	if was_playing:
		_player.play(pos)
		_player.stream_paused = _held


func _process(_delta: float) -> void:
	# The native player runs the set on its own; follow it here.
	if _native and _live and _native.isFinished():
		stop()


func _notification(what: int) -> void:
	# The Godot player pauses with the tree by itself; the native one doesn't.
	if not _native or not _live:
		return
	if what == NOTIFICATION_PAUSED:
		_native.pause()
	elif what == NOTIFICATION_UNPAUSED and not _held:
		_native.resume()


## Writes the tracks out as plain audio files for the native player and
## returns their absolute paths. Tracks already written are reused.
## played gets the tracks that made it, in the same order.
func _unpack_tracks(tracks: Array[String], played: Array[String]) -> PackedStringArray:
	played.clear()
	var out := PackedStringArray()
	var dir := NATIVE_DIR + _dj.validate_filename() + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	for track in tracks:
		# Imported tracks are plain files already.
		if not track.begins_with("res://"):
			out.append(ProjectSettings.globalize_path(track))
			played.append(track)
			continue
		var stream: AudioStream = load(track)
		var file := dir + track.get_file().get_basename()
		if stream is AudioStreamMP3:
			file += ".mp3"
			# Rewritten if missing or cut short (e.g. the app was killed).
			var old := FileAccess.open(file, FileAccess.READ)
			if not old or old.get_length() != stream.data.size():
				var f := FileAccess.open(file, FileAccess.WRITE)
				f.store_buffer(stream.data)
				f.close()
		elif stream is AudioStreamWAV:
			file += ".wav"
			if not FileAccess.file_exists(file):
				stream.save_to_wav(file)
		else:
			push_warning("Can't play %s in the background, skipping it" % track)
			continue
		out.append(ProjectSettings.globalize_path(file))
		played.append(track)
	return out


func _next_track() -> void:
	if _queue.is_empty():
		stop()
		return
	var path: String = _queue.pop_front()
	var stream := _load_track(path)
	if not stream:
		push_warning("Can't play %s, skipping it" % path)
		_next_track()
		return
	# Tracks play once; the set ends after the last one.
	if "loop" in stream:
		stream.loop = false
	_player.stream = stream
	_player.play()
	_track = path
	_announce_track()


func _announce_track() -> void:
	var info := track_info(_track)
	track_started.emit(_dj, info.title, info.artist, info.cover)


## Copies the audio files at paths (which may be Android content URIs)
## into the import DJ's folder and returns how many were added. Files
## Godot can't play are skipped.
func import_tracks(paths: PackedStringArray) -> int:
	var dir := USER_MUSIC_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var added := 0
	for path in paths:
		var data := FileAccess.get_file_as_bytes(path)
		# Picked files may have no extension (content URIs), so go by contents.
		var ext := _audio_format(data)
		if ext == "":
			push_warning("%s is not an MP3, Ogg or WAV file, skipping it" % path)
			continue
		var file := dir + "import." + ext
		var f := FileAccess.open(file, FileAccess.WRITE)
		if not f:
			push_warning("Can't write %s, skipping it" % file)
			continue
		f.store_buffer(data)
		f.close()
		var stream := _load_track(file)
		if not stream:
			push_warning("Can't play %s, skipping it" % path)
			DirAccess.remove_absolute(file)
			continue
		# Named after its tags where it has them; picked files can have
		# meaningless names (content URIs).
		var tags := Tags.read(file, stream)
		var name := path.uri_decode().get_file()
		if name.get_extension().to_lower() in TRACK_EXTS:
			name = name.get_basename()
		if tags.title != "":
			name = tags.title if tags.artist == "" else "%s - %s" % [tags.artist, tags.title]
		var dest := dir + name.validate_filename() + "." + ext
		DirAccess.remove_absolute(dest)
		DirAccess.rename_absolute(file, dest)
		_info.erase(dest)
		added += 1
	_load_djs()
	return added


## The extension for the audio in data, or "" if it isn't a track format.
static func _audio_format(d: PackedByteArray) -> String:
	if d.size() < 12:
		return ""
	if d.slice(0, 4).get_string_from_ascii() == "OggS":
		return "ogg"
	if d.slice(0, 4).get_string_from_ascii() == "RIFF" and d.slice(8, 12).get_string_from_ascii() == "WAVE":
		return "wav"
	# An ID3 tag, or straight into an MPEG frame sync.
	if d.slice(0, 3).get_string_from_ascii() == "ID3" or (d[0] == 0xFF and d[1] & 0xE0 == 0xE0):
		return "mp3"
	return ""


## Bundled tracks are imported resources; the player's own are plain files.
static func _load_track(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path)
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


func _load_djs() -> void:
	var djs := {}
	for root: String in [MUSIC_DIR, USER_MUSIC_DIR]:
		for path in _find_tracks(root):
			if _edits.get_value(path, "removed", false):
				continue
			var dj: String = track_info(path).artist
			if dj == "":
				dj = path.get_base_dir().get_file() if root == MUSIC_DIR else UNKNOWN_DJ
			dj = dj.to_lower()
			if dj not in djs:
				djs[dj] = [] as Array[String]
			djs[dj].append(path)
	var names := djs.keys()
	names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	_djs.clear()
	for dj in names:
		var tracks: Array[String] = djs[dj]
		tracks.sort_custom(func(a, b):
			return track_info(a).title.naturalnocasecmp_to(track_info(b).title) < 0)
		_djs[dj] = tracks


## The tracks in dir and its subfolders.
static func _find_tracks(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in _list_dir(dir, false):
		if file.get_extension().to_lower() in TRACK_EXTS:
			out.append(dir + file)
	for sub in _list_dir(dir, true):
		out.append_array(_find_tracks(dir + sub + "/"))
	return out


## The subfolders (dirs true) or files in dir. res:// is listed through
## the resource loader, which sees the exported pack.
static func _list_dir(dir: String, dirs: bool) -> PackedStringArray:
	if not dir.begins_with("res://"):
		if not DirAccess.dir_exists_absolute(dir):
			return PackedStringArray()
		return DirAccess.get_directories_at(dir) if dirs else DirAccess.get_files_at(dir)
	var out := PackedStringArray()
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/") == dirs:
			out.append(entry.trim_suffix("/"))
	return out


func _build_menu() -> void:
	_menu = Menu.new(button.texture, "CHOOSE A DJ")
	add_child(_menu)
	_dj_list = _menu.add_scroll()


func _open_menu() -> void:
	Tips.event("music_menu")
	Menu.clear(_dj_list)
	Menu.clear(_menu.list, 2)
	for dj in _djs:
		# Picking the current DJ again stops the set.
		var action := stop if dj == _dj else play_dj.bind(dj)
		_menu.add_item(dj.to_upper(), action, dj == _dj, _dj_list)
	_menu.fit_scroll(_dj_list, MAX_VISIBLE_DJS)
	_menu.add_item("CLOSE", func(): pass)
	_menu.open()
