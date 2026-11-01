extends Node2D
## Spawns humans under the UI and lets them stroll around the pathbase,
## more of them while music plays and fewer the longer it stays quiet,
## dance near the sound while music plays and rest away from it when tired.
## Humans that meet wave at each other. When a DJ is picked, a DJ human
## walks in from the side to the booth and leaves when the set is done.
## Now and then someone walks up to the booth to check on the DJ.
## A few humans are dealers: their waves sometimes end with a deal handed
## over, which the holder may later stop to take and then act erratic.
## Everything works on the 72x156 pixel grid. Walkers plan their whole
## route with A* and only replan around others when someone is in the way. Each step onto a pathbase
## pixel lightens it by one shade, drawn on the Paths layer.

const Human := preload("res://scripts/human.gd")
const TINT_SHADER := preload("res://scripts/human_tint.gdshader")
## Every human animation: frames as palette rows, with fps and looping.
const MANIFEST := "res://humans/humans.json"
const Tuning := preload("res://scripts/human_tuning.gd")
## The crowd's chances, timings and distances (see human_tuning.gd).
const TUNING_FILE := "res://humans/tuning.tres"

const MAX_SHADE := 254
## Base pixel offset inside the 5x6 sprite (bottom centre).
const BASE_OFFSET := Vector2(-2, -5)

## The DJ walks in along this many rows below the booth, then up to it.
const DJ_LANE_DROP := 2
## Cells off either side of the grid where DJs enter and leave.
const DJ_OFFSCREEN := 3

## How far around the booth's clear space counts as "around the DJ".
const DJ_CROWD_MARGIN := 1
## Pixels around the booth and DJ that still count as touching them.
const SCRATCH_SLACK := 1
## Humans below the booth may stand this many pixels closer than the
## point where their sprite would touch the booth or DJ.
const BOOTH_BOTTOM_SLACK := 2
## How far (in pixels) a human strays doing one of the manifest's own
## actions that wanders ("move": "wander").
const ACT_WANDER := 8

## Dresscodes: the colour every new human wears, by name. BLACK is the
## sprites' own colour.
const DRESSCODES := {
	"BLACK": Color.BLACK,
	"WHITE": Color(0.8, 0.8, 0.8),
	"RED": Color(0.8, 0.0, 0.0),
	"ORANGE": Color(0.8, 0.4, 0.0),
	"YELLOW": Color(0.8, 0.8, 0.0),
	"GREEN": Color(0.0, 0.8, 0.0),
	"CYAN": Color(0.0, 0.8, 0.8),
	"BLUE": Color(0.0, 0.0, 0.8),
	"PURPLE": Color(0.5, 0.0, 0.8),
	"PINK": Color(0.8, 0.0, 0.5),
}
## How much new humans stray from the dresscode (0..1). At the default the
## lift and chance of a random colour are tuning.color_variation and
## tuning.tint_chance; the lift grows with it, the chance with its square.
const DEFAULT_VARIATION := 0.25
const SETTINGS_FILE := "user://settings.cfg"

@export var path_base: Sprite2D
@export var paths: Sprite2D
@export var sound: Sprite2D
@export var ui: Sprite2D
@export var music: Node
@export var booth: Sprite2D

var tuning: Tuning = load(TUNING_FILE)

var _base_img: Image
var _sound_img: Image
var _paths_img: Image
var _paths_tex: ImageTexture
var _paths_dirty := false
var _size: Vector2i
var _ui_top: int
## Lowest row of the sound; humans stand below it, never beside or behind.
var _sound_base: int
## Distance from each walkable pixel to the nearest sound pixel, row-major.
var _sound_dist := PackedFloat32Array()
var _dance_spots: Array[Vector2i] = []
var _occupied := {}
var _humans: Array[Human] = []
## Per skin: its SpriteFrames, its spawn weight, and for each action the
## takes to pick from as [animation, weight] pairs.
var _skins := {}
## Skins to spawn humans in, as [skin, weight] pairs.
var _skin_picks: Array = []
## The manifest's own actions (its "behaviours"), by what sets them off:
## trigger -> [[action, behaviour], ...], tried in order.
var _custom := {}
## The first skin in the manifest; its idle pose shapes the booth's no-go cells.
var _base_skin: String
## The booth plus room so no sprite overlaps its box; the visitor spots
## and the zone around the DJ are measured from it.
var _booth_rect: Rect2i
## Cells the crowd can't stand on: the booth's box, and anywhere a human's
## sprite would overlap the booth or the DJ. Shaped by both sprites, so the
## booth's corners stay walkable.
var _booth_cells := {}
## Walk planners over the static map: one keeps to above the UI, for
## humans that have entered, the other also crosses under it.
var _grid_above: AStarGrid2D
var _grid_any: AStarGrid2D
## Around the booth, where only tuning.dj_crowd_max humans may be.
var _dj_zone: Rect2i
## Where the DJ stands: the booth's bottom centre.
var _dj_spot: Vector2i
## The booth's opaque box, touched (with the DJ) to scratch.
var _booth_used: Rect2i
## The DJ walking to or standing at the booth.
var _dj: Human
var _djs: Array[Human] = []
## How many humans the walkable area fits.
var _max_humans: int
## Seconds since the music stopped.
var _silence := 0.0
var _mood := 1.0
var _mood_left := 0.0
## Humans ever spawned; every tuning.dealer_every-th is a dealer.
var _spawned := 0
## Humans that walked off this frame, freed once the frame's loop is done.
var _gone: Array[Human] = []

## What humans spawned from now on wear (a DRESSCODES key), and how much
## they stray from it. Changing either leaves those already here alone.
## Both are remembered between runs.
var dresscode := "BLACK":
	set(value):
		dresscode = value
		_save_setting("dresscode", value)
var variation := DEFAULT_VARIATION:
	set(value):
		variation = clampf(value, 0.0, 1.0)
		_save_setting("variation", variation)


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	var code: String = cfg.get_value("dresscode", "dresscode", "BLACK")
	dresscode = code if code in DRESSCODES else "BLACK"
	variation = cfg.get_value("dresscode", "variation", DEFAULT_VARIATION)
	_base_img = _rgba(path_base.texture.get_image())
	_sound_img = _rgba(sound.texture.get_image())
	_size = _base_img.get_size()
	# Paths starts empty each run; wear is painted into it.
	_paths_img = _rgba(paths.texture.get_image())
	_paths_img.fill(Color(0, 0, 0, 0))
	_paths_tex = ImageTexture.create_from_image(_paths_img)
	paths.texture = _paths_tex
	_ui_top = _find_ui_top(_rgba(ui.texture.get_image()))
	_sound_base = _find_bottom(_sound_img)
	var booth_used := _rgba(booth.texture.get_image()).get_used_rect()
	_dj_spot = Vector2i(booth_used.get_center().x, booth_used.end.y - 1)
	_booth_used = booth_used
	_booth_rect = booth_used.grow_individual(
			-int(BASE_OFFSET.x), 0, -int(BASE_OFFSET.x),
			-int(BASE_OFFSET.y) - BOOTH_BOTTOM_SLACK)
	_dj_zone = _booth_rect.grow(DJ_CROWD_MARGIN)
	_load_skins(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)))
	_build_booth_cells(booth_used)
	_build_sound_map()
	_grid_above = _make_grid(true)
	_grid_any = _make_grid(false)
	_max_humans = _fit_count()
	_spawn(_start_count())
	music.playing_changed.connect(_on_music_changed)
	music.dj_called.connect(_call_dj)
	music.dj_dismissed.connect(_dismiss_dj)


func _process(delta: float) -> void:
	_update_crowd(delta)
	for h in _humans:
		if h.state == Human.State.DANCING:
			h.fatigue += delta
			h.dance_left -= delta
		elif h.tired:
			h.rest += delta
			if h.rest >= tuning.rest_time:
				h.tired = false
				h.fatigue = 0.0
		if h.erratic > 0.0:
			h.erratic -= delta
			if h.erratic <= 0.0 and randf() < tuning.erratic_tired_chance:
				h.tired = true
				h.rest = 0.0
		h.greet_cooldown -= delta
		h.timer -= delta
		if h.timer > 0.0:
			continue
		match h.state:
			Human.State.WAITING:
				if _try_place(h):
					_pick_entry_target(h)
					_start_walking(h, Human.Goal.STROLL)
				else:
					h.timer = randf_range(tuning.spawn_retry.x, tuning.spawn_retry.y)
			Human.State.WALKING:
				_step(h)
			Human.State.IDLE:
				_choose(h)
			Human.State.DANCING:
				_dance_tick(h)
			Human.State.GREETING:
				_end_greet(h)
			Human.State.HANDOFF:
				_cancel_handoff(h)
			Human.State.RECEIVING:
				_start_idle(h)
			Human.State.TAKING:
				_take_tick(h)
			Human.State.ACTING:
				_end_custom(h)
	for h in _gone:
		_humans.erase(h)
		h.queue_free()
	_gone.clear()
	_process_djs(delta)
	if _paths_dirty:
		_paths_tex.update(_paths_img)
		_paths_dirty = false


## Silence sends humans home, more often the longer it lasts and the more
## are left; music draws them in, more often the bigger the crowd.
func _update_crowd(delta: float) -> void:
	_mood_left -= delta
	if _mood_left <= 0.0:
		_mood = exp(randf_range(-log(tuning.mood_swing), log(tuning.mood_swing)))
		_mood_left = randf_range(tuning.mood_time.x, tuning.mood_time.y)
	if music.is_playing():
		_silence = 0.0
		if _humans.size() >= _max_humans:
			return
		var rate := tuning.arrive_base + tuning.arrive_per_human * _humans.size()
		if _humans.is_empty() or randf() < rate * _mood * delta:
			_spawn(1)
		return
	_silence += delta
	var staying := _humans.filter(func(h): return h.goal != Human.Goal.LEAVE)
	var rate := minf(tuning.leave_rate_growth * _silence, tuning.leave_rate_max) * staying.size()
	if randf() < rate * _mood * delta:
		var free := staying.filter(_can_leave)
		if not free.is_empty():
			_start_leave(free.pick_random())


## Strolling or idling, with no deal being handed over.
func _can_leave(h: Human) -> bool:
	return h.entered and not h.partner and (h.state == Human.State.IDLE \
			or h.state == Human.State.WALKING and h.goal == Human.Goal.STROLL)


## Back down under the UI, the way they came.
func _start_leave(h: Human) -> void:
	h.entered = false
	h.wave_dj = false
	_pick_exit_target(h)
	_start_walking(h, Human.Goal.LEAVE)


## Gone once the UI hides the whole sprite.
func _depart(h: Human) -> void:
	_occupied.erase(h.cell)
	h.visible = false
	_gone.append(h)


## Exit target: a spot on the bottom row, near where the human is.
func _pick_exit_target(h: Human) -> void:
	for i in 30:
		var c := Vector2i(clampi(h.cell.x + randi_range(-6, 6), 2, _size.x - 3), _size.y - 1)
		if _is_walkable(c, false) and not _occupied.has(c):
			h.target = c
			return
	h.target = Vector2i(clampi(h.cell.x, 2, _size.x - 3), _size.y - 1)


## Walkable pixels above the UI, shared out tuning.area_per_human each.
func _fit_count() -> int:
	var area := 0
	for y in _ui_top:
		for x in _size.x:
			if _is_walkable(Vector2i(x, y), true):
				area += 1
	return maxi(1, roundi(area / tuning.area_per_human))


## Starting crowd, from the sound's size (see tuning.start_extra_per).
func _start_count() -> int:
	var px := 0
	for y in _sound_img.get_height():
		for x in _sound_img.get_width():
			if _sound_img.get_pixel(x, y).a > 0.0:
				px += 1
	var n := 0
	while 3 * (n + 1) * (n + 1) - 5 * (n + 1) + 3 <= px:
		n += 1
	return mini(randi_range(n, n + tuning.start_extra_per * n), _max_humans)


## Humans start off the grid and step onto a free spot on the bottom row
## when their timer runs out, so there can be more humans than spots.
func _spawn(count: int) -> void:
	for i in count:
		var h := _new_human()
		h.dealer = _spawned % tuning.dealer_every == 0
		_spawned += 1
		h.material = _dress()
		h.visible = false
		h.timer = randf() * tuning.spawn_delay
		_act(h, &"idle")
		_humans.append(h)
		add_child(h)


## A new human's colours: the dresscode, strayed from by the variation.
func _dress() -> ShaderMaterial:
	var spread := variation / DEFAULT_VARIATION
	var tint := ShaderMaterial.new()
	tint.shader = TINT_SHADER
	tint.set_shader_parameter("lift", randf() * tuning.color_variation * spread)
	var c: Color = DRESSCODES[dresscode]
	if randf() < tuning.tint_chance * spread * spread:
		c = Color.from_hsv(randf(), 1.0, tuning.tint_strength)
	elif c.s > 0.0:
		c.h = fposmod(c.h + randf_range(-1.0, 1.0) * tuning.dresscode_hue_spread * variation, 1.0)
	tint.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	return tint


func _save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("dresscode", key, value)
	cfg.save(SETTINGS_FILE)


func _new_human() -> Human:
	var h := Human.new()
	h.skin = _pick_weighted(_skin_picks)
	h.sprite_frames = _skins[h.skin].frames
	h.centered = false
	h.offset = BASE_OFFSET
	return h


## The DJ walks in from a random side along a lane below the booth,
## then straight up to the spot. DJs ignore the crowd.
func _call_dj(_name: String) -> void:
	var lane := _dj_spot.y + DJ_LANE_DROP
	var x := -DJ_OFFSCREEN if randf() < 0.5 else _size.x - 1 + DJ_OFFSCREEN
	_dj = _new_human()
	_dj.cell = Vector2i(x, lane)
	_dj.position = Vector2(_dj.cell)
	_dj.path = [Vector2i(_dj_spot.x, lane), _dj_spot]
	_act(_dj, &"walk")
	_djs.append(_dj)
	add_child(_dj)


## Back down to the lane and off a random side.
func _dismiss_dj() -> void:
	if not _dj:
		return
	for h in _humans:
		h.wave_dj = false
		if h.goal == Human.Goal.VISIT_DJ:
			_pick_target(h)
			h.goal = Human.Goal.STROLL
	var lane := _dj_spot.y + DJ_LANE_DROP
	var x := -DJ_OFFSCREEN if randf() < 0.5 else _size.x - 1 + DJ_OFFSCREEN
	_dj.path = [Vector2i(_dj.cell.x, lane), Vector2i(x, lane)]
	_dj.timer = 0.0
	_act(_dj, &"walk")
	_dj = null


func _dj_at_booth() -> bool:
	return _dj != null and _dj.path.is_empty()


## A free spot just in front of the booth, near the DJ.
func _pick_visit_target(h: Human) -> bool:
	for i in 30:
		var c := Vector2i(
				_dj_spot.x + randi_range(-tuning.dj_visit_spread, tuning.dj_visit_spread),
				_booth_rect.end.y + randi_range(0, tuning.dj_visit_depth))
		if _is_walkable(c, true) and not _occupied.has(c):
			h.target = c
			return true
	return false


## Faces the DJ and watches for a bit before maybe waving.
func _start_visit(h: Human) -> void:
	_start_idle(h)
	if _dj.cell.x != h.cell.x:
		h.flip_h = _dj.cell.x < h.cell.x
	h.wave_dj = true
	h.timer = randf_range(tuning.dj_visit_look.x, tuning.dj_visit_look.y)


func _process_djs(delta: float) -> void:
	for d: Human in _djs.duplicate():
		if d.path.is_empty():
			_dj_tick(d, delta)
			continue
		d.timer -= delta
		if d.timer > 0.0:
			continue
		d.timer = tuning.step_time
		var to := d.path[0]
		var c := d.cell + (to - d.cell).sign()
		if c.x != d.cell.x:
			d.flip_h = c.x < d.cell.x
		d.cell = c
		d.position = Vector2(c)
		if _is_walkable(c, false):
			_wear(c)
		if c != to:
			continue
		d.path.pop_front()
		if not d.path.is_empty():
			continue
		if d == _dj:
			_act(d, &"idle")
			music.start_set()
		else:
			_djs.erase(d)
			d.queue_free()


## True when a touch at screen point lands on the DJ playing at the
## booth, or on their decks.
func dj_touched(screen_point: Vector2) -> bool:
	if not _dj_at_booth() or not music.is_playing():
		return false
	var p := to_local(get_canvas_transform().affine_inverse() * screen_point)
	var dj := Rect2i(_dj.cell + Vector2i(BASE_OFFSET), Vector2i(5, 6))
	# A pixel of slack around them, as a fingertip covers several.
	return Rect2(_booth_used.merge(dj).grow(SCRATCH_SLACK)).has_point(p)


## Each scratch stroke jerks the DJ to another frame, held a moment so
## the set's frame changes don't cut in.
func dj_scratch_stroke() -> void:
	if not _dj_at_booth() or _dj.action != &"dj":
		return
	var f := randi_range(0, _dj.sprite_frames.get_frame_count(_dj.animation) - 2)
	_dj.frame = f + 1 if f >= _dj.frame else f
	_dj.timer = tuning.dj_frame_time.x


## At the booth, while the set plays, the DJ shows a random DJ frame
## for a few seconds, then switches to a different one.
func _dj_tick(d: Human, delta: float) -> void:
	if not music.is_playing():
		_act(d, &"idle")
		return
	if d.action != &"dj":
		_act(d, &"dj")
		d.timer = 0.0
	d.timer -= delta
	if d.timer > 0.0:
		return
	d.timer = randf_range(tuning.dj_frame_time.x, tuning.dj_frame_time.y)
	var f := randi_range(0, d.sprite_frames.get_frame_count(d.animation) - 2)
	d.frame = f + 1 if f >= d.frame else f


## Puts a waiting human on a random free bottom-row spot, if there is one.
func _try_place(h: Human) -> bool:
	if h.visible:
		return true
	var xs := range(2, _size.x - 2)
	xs.shuffle()
	for x in xs:
		var c := Vector2i(x, _size.y - 1)
		if not _occupied.has(c):
			h.cell = c
			h.position = Vector2(c)
			_occupied[c] = h
			h.visible = true
			return true
	return false


## Builds every skin's animations from the manifest, one animation per
## take, named "action:take". A skin with a base borrows the base's
## actions it doesn't draw itself. Manual takes (the DJ's) have fps 0:
## their frames are picked by hand, so they never advance.
func _load_skins(manifest: Dictionary) -> void:
	var size := Vector2i(int(manifest.frame_size[0]), int(manifest.frame_size[1]))
	var palette := {}
	for sym: String in manifest.palette:
		palette[sym] = Color.html(manifest.palette[sym])
	var skins: Dictionary = manifest.skins
	_base_skin = skins.keys()[0]
	for skin: String in skins:
		var frames := SpriteFrames.new()
		frames.remove_animation(&"default")
		var takes := {}
		var actions := _skin_actions(skins, skin)
		for action: String in actions:
			takes[StringName(action)] = []
			for take: Dictionary in actions[action].takes:
				var anim := "%s:%s" % [action, take.name]
				frames.add_animation(anim)
				frames.set_animation_speed(anim, take.fps)
				frames.set_animation_loop(anim, take.loop)
				for f: Dictionary in take.frames:
					frames.add_frame(anim, _frame_texture(f.px, size, palette), f.get("hold", 1))
				takes[StringName(action)].append([StringName(anim), take.get("weight", 1)])
		var weight: float = skins[skin].get("weight", 1)
		_skins[skin] = {frames = frames, takes = takes}
		if weight > 0.0:
			_skin_picks.append([skin, weight])
	_custom.clear()
	var behaviours: Dictionary = manifest.get("behaviours", {})
	for action: String in behaviours:
		var b: Dictionary = behaviours[action]
		if not _custom.has(b.trigger):
			_custom[b.trigger] = []
		_custom[b.trigger].append([StringName(action), b])


## A skin's own actions on top of its base's, following bases all the way down.
func _skin_actions(skins: Dictionary, skin: String) -> Dictionary:
	var own: Dictionary = skins[skin].get("actions", {})
	if not skins[skin].has("base"):
		return own
	return _skin_actions(skins, skins[skin].base).merged(own, true)


## Plays one of the action's takes, picked by weight. A human already
## doing the action keeps its take and only changes speed.
func _act(h: Human, action: StringName, speed := 1.0) -> void:
	var anim := h.animation
	if h.action != action:
		h.action = action
		anim = _pick_weighted(_skins[h.skin].takes[action])
	h.play(anim, speed)


## Picks the first of a random [value, weight] pair, likelier the heavier.
func _pick_weighted(pairs: Array) -> Variant:
	var total := 0.0
	for p: Array in pairs:
		total += p[1]
	var r := randf() * total
	for p: Array in pairs:
		r -= p[1]
		if r < 0.0:
			return p[0]
	return pairs[-1][0]


func _frame_texture(rows: Array, size: Vector2i, palette: Dictionary) -> ImageTexture:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		var row: String = rows[y]
		for x in size.x:
			if row[x] != ".":
				img.set_pixel(x, y, palette[row[x]])
	return ImageTexture.create_from_image(img)


## Seconds the human's current take lasts at speed 1, holds included.
func _anim_length(h: Human) -> float:
	var frames := h.sprite_frames
	var beats := 0.0
	for i in frames.get_frame_count(h.animation):
		beats += frames.get_frame_duration(h.animation, i)
	return beats / frames.get_animation_speed(h.animation)


## Decides what an idle human does next.
func _choose(h: Human) -> void:
	if h.erratic > 0.0:
		_erratic_choose(h)
		return
	if h.has_deal and randf() < tuning.deal_take_chance:
		_go_take_deal(h)
		return
	if h.tired:
		_pick_rest_target(h)
		_start_walking(h, Human.Goal.STROLL)
		return
	if _crowding_dj(h):
		h.wave_dj = false
		_pick_target(h)
		_start_walking(h, Human.Goal.STROLL)
		return
	if h.wave_dj:
		h.wave_dj = false
		if _dj_at_booth() and randf() < tuning.dj_visit_wave_chance:
			_start_greet(h, _dj)
			return
	if _try_custom(h, "idle"):
		return
	if _dj_at_booth() and randf() < tuning.dj_visit_chance and not _dj_zone_full(h) \
			and _pick_visit_target(h):
		_start_walking(h, Human.Goal.VISIT_DJ)
		return
	if not music.is_playing():
		_pick_target(h)
		_start_walking(h, Human.Goal.STROLL)
		return
	var dancers := _humans.filter(func(o): return o.state == Human.State.DANCING).size()
	var chance := minf(tuning.dance_chance_base + tuning.dance_chance_per_dancer * dancers, tuning.dance_chance_max)
	if randf() < chance:
		_pick_dance_target(h)
		_start_walking(h, Human.Goal.DANCE)
	else:
		_pick_target(h)
		_start_walking(h, Human.Goal.STROLL)


func _start_walking(h: Human, goal: Human.Goal) -> void:
	h.state = Human.State.WALKING
	h.goal = goal
	h.stuck = 0
	h.path.clear()
	h.timer = 0.0
	_act(h, h.walk_as if goal == Human.Goal.ACT else &"walk")


func _start_idle(h: Human) -> void:
	h.state = Human.State.IDLE
	h.goal = Human.Goal.STROLL
	var t := tuning.tired_idle_time if h.tired else tuning.idle_time
	h.timer = randf_range(t.x, t.y)
	_act(h, &"idle")


func _start_dance(h: Human) -> void:
	h.state = Human.State.DANCING
	h.dance_left = randf_range(tuning.dance_time.x, tuning.dance_time.y)
	h.timer = tuning.dance_wear_time
	_act(h, &"dance")


func _dance_tick(h: Human) -> void:
	if h.fatigue >= tuning.tired_after or h.tired:
		h.tired = true
		h.rest = 0.0
		_pick_rest_target(h)
		_start_walking(h, Human.Goal.STROLL)
	elif h.dance_left <= 0.0:
		# Pick again right away; a busy floor often pulls them back in.
		h.state = Human.State.IDLE
		h.timer = 0.0
		_act(h, &"idle")
	else:
		_wear(h.cell)
		h.timer = tuning.dance_wear_time
		_try_custom(h, "dancing")


## When the music stops, dancers and those heading to dance wander off.
func _on_music_changed(playing: bool) -> void:
	if playing:
		return
	for h in _humans:
		if h.state == Human.State.DANCING:
			h.state = Human.State.IDLE
			h.timer = randf_range(0.0, tuning.idle_time.x)
			_act(h, &"idle")
		elif h.goal == Human.Goal.DANCE:
			_pick_target(h)
			h.goal = Human.Goal.STROLL


## One pixel along the planned path. The path is planned when the target
## changes; if someone stands on the next cell, it is replanned around
## everyone in the way. A path that ends short of an unreachable target
## counts as arriving.
func _step(h: Human) -> void:
	h.timer = tuning.step_time
	if h.erratic > 0.0:
		var s := randf_range(tuning.erratic_step.x, tuning.erratic_step.y)
		h.timer *= s
		_act(h, h.walk_as if h.goal == Human.Goal.ACT else &"walk", 1.0 / s)
	if h.path.is_empty() or h.path_to != h.target:
		_plan(h, false)
	if h.cell == h.target or h.path.is_empty():
		_arrive(h)
		return
	if _occupied.has(h.path[0]):
		_plan(h, true)
		if h.path.is_empty() or _occupied.has(h.path[0]):
			_blocked(h)
			return
	var veer := _wobble(h, h.path[0])
	if veer != h.cell:
		# Off the plan now; walk back on from wherever this lands.
		h.path.clear()
		_move(h, veer)
	else:
		_move(h, h.path.pop_front())
	if h.goal == Human.Goal.LEAVE and h.cell.y + int(BASE_OFFSET.y) >= _ui_top:
		_depart(h)
		return
	_try_greet(h)


## Where a tired or erratic walker staggers to instead of next, or its own
## cell if it keeps to the path this step.
func _wobble(h: Human, next: Vector2i) -> Vector2i:
	var chance := tuning.erratic_wobble_chance if h.erratic > 0.0 \
			else tuning.tired_wobble_chance if h.tired else 0.0
	if randf() >= chance:
		return h.cell
	var d := next - h.cell
	var turns := [1, -1]
	if h.erratic > 0.0:
		turns += [2, -2]
	turns.shuffle()
	var grid := _grid_above if h.entered else _grid_any
	for t: int in turns:
		var v := d
		for i in absi(t):
			# One eighth of a turn on the 8-neighbour ring.
			v = Vector2i(signi(v.x - v.y), signi(v.x + v.y)) if t > 0 \
					else Vector2i(signi(v.x + v.y), signi(v.y - v.x))
		var c := h.cell + v
		if grid.is_in_boundsv(c) and not grid.is_point_solid(c) and not _occupied.has(c):
			return c
	return h.cell


func _arrive(h: Human) -> void:
	if h.goal == Human.Goal.LEAVE:
		# Fell short of the exit; try another.
		_pick_exit_target(h)
	elif h.goal == Human.Goal.DANCE and h.cell == h.target:
		_start_dance(h)
	elif h.goal == Human.Goal.HANDOFF:
		_arrive_handoff(h)
	elif h.goal == Human.Goal.TAKE_DEAL:
		_start_take(h)
	elif h.goal == Human.Goal.VISIT_DJ and _dj_at_booth():
		_start_visit(h)
	elif h.goal == Human.Goal.ACT:
		h.goal = Human.Goal.STROLL
		_end_custom(h)
	elif h.entered:
		_start_idle(h)
	else:
		# Still under the UI; keep heading up.
		_pick_entry_target(h)


## No way past the others right now: wait, then give up after a while.
func _blocked(h: Human) -> void:
	h.stuck += 1
	if h.stuck < tuning.give_up_after:
		return
	h.stuck = 0
	if h.goal == Human.Goal.HANDOFF:
		# Close enough; hand it over from here.
		_arrive_handoff(h)
	elif h.goal == Human.Goal.LEAVE:
		_pick_exit_target(h)
	elif h.entered and _crowding_dj(h):
		# Don't settle by the booth just because the way was blocked.
		_pick_target(h)
		h.goal = Human.Goal.STROLL
	elif h.entered:
		_start_idle(h)
	else:
		_pick_entry_target(h)


## Plans h's path to its target, or as close as it can get. With
## avoid_crowd, cells other humans stand on are kept out of the way.
func _plan(h: Human, avoid_crowd: bool) -> void:
	var grid := _grid_above if h.entered else _grid_any
	var blocked: Array[Vector2i] = []
	if avoid_crowd:
		for c: Vector2i in _occupied:
			if c != h.cell and grid.is_in_boundsv(c) and not grid.is_point_solid(c):
				grid.set_point_solid(c)
				blocked.append(c)
	h.path = grid.get_id_path(h.cell, h.target, true)
	for c in blocked:
		grid.set_point_solid(c, false)
	if not h.path.is_empty():
		h.path.pop_front()
	h.path_to = h.target


## A walker that steps near another strolling or resting human waves at
## them and they wave back.
func _try_greet(h: Human) -> void:
	if not _can_greet(h):
		return
	for o in _humans:
		if o != h and _can_greet(o) and _dist(h.cell, o.cell) <= tuning.greet_radius:
			_greet_pair(h, o)
			return


## Both wave; when one is a dealer, a deal may change hands after.
func _greet_pair(h: Human, o: Human) -> void:
	if _try_custom(h, "meeting", o):
		for x: Human in [h, o]:
			x.greet_cooldown = randf_range(tuning.greet_cooldown.x, tuning.greet_cooldown.y)
		if o.state != Human.State.ACTING and o.goal != Human.Goal.ACT:
			_start_greet(o, h)
		return
	_start_greet(h, o)
	_start_greet(o, h)
	var d := h if h.dealer else o
	var r := o if d == h else h
	if d.dealer and not r.dealer and not r.has_deal and not d.partner \
			and randf() < tuning.deal_chance:
		d.partner = r
		r.partner = d


func _can_greet(h: Human) -> bool:
	# Passers-by don't stop for a chat by the booth.
	return h.entered and h.greet_cooldown <= 0.0 and not _dj_zone.has_point(h.cell) \
			and (h.state == Human.State.WALKING or h.state == Human.State.IDLE) \
			and h.goal != Human.Goal.ACT


## With no other, the human waves at nobody.
func _start_greet(h: Human, other: Human) -> void:
	h.resume_state = h.state
	h.state = Human.State.GREETING
	if other:
		_face(h, other.cell)
	var rate := tuning.dealer_greet_rate if h.dealer else 1.0
	h.greet_cooldown = randf_range(tuning.greet_cooldown.x, tuning.greet_cooldown.y) / rate
	_act(h, &"wave", rate)
	h.timer = _anim_length(h) / rate


## Walkers carry on to their target; everyone else goes back to idling.
## A deal about to change hands goes to the handoff instead.
func _end_greet(h: Human) -> void:
	if h.partner and h.dealer:
		_start_handoff_walk(h)
	elif h.partner:
		_wait_handoff(h)
	elif h.resume_state == Human.State.WALKING:
		h.state = Human.State.WALKING
		h.timer = 0.0
		_act(h, &"walk")
	else:
		_start_idle(h)


## The dealer steps up right next to the receiver.
func _start_handoff_walk(d: Human) -> void:
	var r := d.partner as Human
	var best := d.cell
	if _dist(d.cell, r.cell) > 1.5:
		var best_score := INF
		for y in range(-1, 2):
			for x in range(-1, 2):
				var c := r.cell + Vector2i(x, y)
				if c == r.cell or not _is_walkable(c, true) or _occupied.has(c):
					continue
				# Side by side rather than above or below.
				var score := _dist(c, d.cell) + absi(y)
				if score < best_score:
					best_score = score
					best = c
	d.target = best
	_start_walking(d, Human.Goal.HANDOFF)


func _arrive_handoff(d: Human) -> void:
	var r := d.partner as Human
	if not r:
		_start_idle(d)
		return
	_wait_handoff(d)
	_face(d, r.cell)


## Stands waiting for the other side; the deal changes hands once both are.
func _wait_handoff(h: Human) -> void:
	h.state = Human.State.HANDOFF
	h.goal = Human.Goal.STROLL
	h.timer = tuning.handoff_wait
	_act(h, &"idle")
	var p := h.partner as Human
	if p.state != Human.State.HANDOFF:
		return
	var r := h if p.dealer else p
	_start_idle(p if r == h else h)
	h.partner = null
	p.partner = null
	r.has_deal = true
	r.state = Human.State.RECEIVING
	r.timer = tuning.deal_receive_time
	_act(r, &"dealinhand")


## Waited too long at the handoff; both sides drop it.
func _cancel_handoff(h: Human) -> void:
	var p := h.partner as Human
	h.partner = null
	_start_idle(h)
	if p and p.partner == h:
		p.partner = null
		if p.state == Human.State.HANDOFF:
			_start_idle(p)


## Stops to take the deal, mostly stepping off the dance floor first.
func _go_take_deal(h: Human) -> void:
	if _on_dance_floor(h.cell) and randf() < tuning.deal_leave_floor_chance:
		_pick_off_floor_target(h)
		_start_walking(h, Human.Goal.TAKE_DEAL)
	else:
		_start_take(h)


func _start_take(h: Human) -> void:
	h.state = Human.State.TAKING
	h.goal = Human.Goal.STROLL
	h.timer = tuning.deal_hold_time
	_act(h, &"dealinhand")


## In hand, brought in, done; then the human goes erratic.
func _take_tick(h: Human) -> void:
	if h.action == &"dealinhand":
		_act(h, &"deal_in")
		h.timer = _anim_length(h)
	elif h.action == &"deal_in":
		_act(h, &"doingthedeal")
		h.timer = tuning.deal_time
	else:
		h.has_deal = false
		h.erratic = randf_range(tuning.erratic_time.x, tuning.erratic_time.y)
		_start_idle(h)
		h.timer = 0.0


## Erratic humans do anything at random, ignoring the usual rules.
func _erratic_choose(h: Human) -> void:
	if _try_custom(h, "erratic"):
		return
	match randi() % 5:
		0:
			_start_dance(h)
			h.dance_left = randf_range(tuning.erratic_dance_time.x, tuning.erratic_dance_time.y)
			return
		1:
			_start_idle(h)
			h.timer = randf_range(tuning.erratic_idle_time.x, tuning.erratic_idle_time.y)
			return
		2:
			var near := _humans.filter(func(o): return o != h and _can_greet(o) \
					and _dist(h.cell, o.cell) <= tuning.erratic_greet_radius)
			if near.is_empty():
				_start_greet(h, null)
			else:
				_greet_pair(h, near.pick_random())
			return
		3:
			if _dj_at_booth() and _pick_visit_target(h):
				_start_walking(h, Human.Goal.VISIT_DJ)
				return
	for i in 30:
		var c := Vector2i(randi_range(0, _size.x - 1), randi_range(0, _ui_top - 1))
		if _is_walkable(c, true) and not _occupied.has(c):
			h.target = c
			break
	_start_walking(h, Human.Goal.STROLL)


## Rolls the manifest's own actions for trigger ("idle", "dancing",
## "meeting" or "erratic"; see "behaviours" in humans.json) and starts the
## first that comes up. Meeting other, a paired action has them join in.
func _try_custom(h: Human, trigger: String, other: Human = null) -> bool:
	for pair: Array in _custom.get(trigger, []):
		var b: Dictionary = pair[1]
		if randf() >= b.get("chance", 0.0):
			continue
		_start_custom(h, pair[0], b, other)
		if other and b.get("paired", false):
			_start_custom(other, pair[0], b, h)
		return true
	return false


## Plays the action on the spot for its time, or once through when its
## take doesn't loop. One that wanders walks a few pixels as the action
## instead, and ends on arrival.
func _start_custom(h: Human, action: StringName, b: Dictionary, other: Human) -> void:
	h.resume_state = h.state
	if other:
		_face(h, other.cell)
	if b.get("move", "still") == "wander" and _pick_wander_target(h):
		h.walk_as = action
		_start_walking(h, Human.Goal.ACT)
		return
	h.state = Human.State.ACTING
	_act(h, action)
	var t: Array = b.get("time", [2.0, 4.0])
	var once := not h.sprite_frames.get_animation_loop(h.animation) \
			and h.sprite_frames.get_animation_speed(h.animation) > 0.0
	h.timer = _anim_length(h) if once else randf_range(t[0], t[1])


## Back to what the human was doing; dancers dance on if the music does.
func _end_custom(h: Human) -> void:
	if h.resume_state == Human.State.DANCING and music.is_playing():
		h.state = Human.State.DANCING
		h.timer = tuning.dance_wear_time
		_act(h, &"dance")
	elif h.resume_state == Human.State.WALKING:
		h.state = Human.State.WALKING
		h.timer = 0.0
		_act(h, &"walk")
	else:
		_start_idle(h)


func _pick_wander_target(h: Human) -> bool:
	for i in 20:
		var c := h.cell + Vector2i(randi_range(-ACT_WANDER, ACT_WANDER), randi_range(-ACT_WANDER, ACT_WANDER))
		if c != h.cell and _is_walkable(c, true) and not _occupied.has(c):
			h.target = c
			return true
	return false


func _face(h: Human, c: Vector2i) -> void:
	if c.x != h.cell.x:
		h.flip_h = c.x < h.cell.x


func _move(h: Human, c: Vector2i) -> void:
	if c.x != h.cell.x:
		h.flip_h = c.x < h.cell.x
	_occupied.erase(h.cell)
	h.cell = c
	_occupied[c] = h
	h.position = Vector2(c)
	h.stuck = 0
	if c.y < _ui_top and h.goal != Human.Goal.LEAVE:
		h.entered = true
	_wear(c)


## Lightens one pathbase pixel by the smallest step, never reaching white.
func _wear(c: Vector2i) -> void:
	var col := _paths_img.get_pixelv(c)
	if col.a == 0.0:
		col = _base_img.get_pixelv(c)
	col = Color8(
		mini(col.r8 + 1, MAX_SHADE),
		mini(col.g8 + 1, MAX_SHADE),
		mini(col.b8 + 1, MAX_SHADE),
		col.a8)
	_paths_img.set_pixelv(c, col)
	_paths_dirty = true


## Entry target: a spot just above the UI, near where the human is.
func _pick_entry_target(h: Human) -> void:
	for i in 30:
		var c := Vector2i(h.cell.x + randi_range(-4, 4), _ui_top - randi_range(1, 10))
		if _is_walkable(c, true):
			h.target = c
			return
	h.target = Vector2i(h.cell.x, _ui_top - 1)


## Mostly heads near another human so they drift into groups.
func _pick_target(h: Human) -> void:
	var others := _humans.filter(func(o): return o != h and o.entered)
	var zone_full := _dj_zone_full(h)
	for i in 30:
		var c: Vector2i
		if not others.is_empty() and randf() < tuning.group_chance:
			var o: Human = others.pick_random()
			var r := randi_range(tuning.group_radius.x, tuning.group_radius.y)
			c = o.cell + Vector2i(randi_range(-r, r), randi_range(-r, r))
		else:
			c = Vector2i(randi_range(0, _size.x - 1), randi_range(0, _ui_top - 1))
		if _is_walkable(c, true) and not _occupied.has(c) \
				and not (zone_full and _dj_zone.has_point(c)):
			h.target = c
			return
	h.target = h.cell


## True when h is around the booth with tuning.dj_crowd_max others already there.
func _crowding_dj(h: Human) -> bool:
	return _dj_zone.has_point(h.cell) and _dj_zone_full(h)


## True when tuning.dj_crowd_max others already stand around the booth or are
## on their way there.
func _dj_zone_full(h: Human) -> bool:
	var n := 0
	for o in _humans:
		if o == h or not o.visible:
			continue
		var spot := o.target if o.state == Human.State.WALKING else o.cell
		if _dj_zone.has_point(spot):
			n += 1
			if n >= tuning.dj_crowd_max:
				return true
	return false


## A spot near the dancer's preferred distance from the sound that keeps a
## gap from other dancers. The gap shrinks as more humans dance, so the floor
## gets crowded. The preferred distance, each gap and the noise are rolled per
## pick, so the crowd stays loose instead of settling into a grid.
func _pick_dance_target(h: Human) -> void:
	var others: Array[Vector2i] = []
	for o in _humans:
		if o == h:
			continue
		if o.state == Human.State.DANCING:
			others.append(o.cell)
		elif o.state == Human.State.WALKING and o.goal == Human.Goal.DANCE:
			others.append(o.target)
	var spacing := maxf(tuning.dance_spacing_min, tuning.dance_spacing_max - others.size())
	var gaps: Array[float] = []
	for o in others:
		gaps.append(spacing * randf_range(tuning.dance_gap_jitter.x, tuning.dance_gap_jitter.y))
	var radius := _dance_radius()
	var reach := randf() * randf() * radius * tuning.dance_reach_max
	var zone_full := _dj_zone_full(h)
	var best := h.cell
	var best_score := INF
	for c in _dance_spots:
		if c != h.cell and _occupied.has(c):
			continue
		if zone_full and _dj_zone.has_point(c):
			continue
		var sd := _sound_dist[c.y * _size.x + c.x]
		if sd > radius:
			continue
		var score := absf(sd - reach) \
				+ randf() * tuning.dance_score_noise
		for i in others.size():
			score += maxf(0.0, gaps[i] - _dist(c, others[i])) * tuning.crowd_weight
		if score < best_score:
			best_score = score
			best = c
	h.target = best


## The nearest free spot off the dance floor and away from the booth.
func _pick_off_floor_target(h: Human) -> void:
	var best := h.cell
	var best_d := INF
	for i in 60:
		var c := Vector2i(randi_range(0, _size.x - 1), randi_range(0, _ui_top - 1))
		if not _is_walkable(c, true) or _occupied.has(c) or _on_dance_floor(c) \
				or _dj_zone.has_point(c):
			continue
		var d := _dist(c, h.cell)
		if d < best_d:
			best_d = d
			best = c
	h.target = best


func _on_dance_floor(c: Vector2i) -> bool:
	return _sound_dist[c.y * _size.x + c.x] <= _dance_radius()


## How far from the sound the floor reaches with the current crowd.
func _dance_radius() -> float:
	return minf(tuning.dance_radius_max, tuning.dance_radius + tuning.dance_radius_per_human * _humans.size())


## A spot far from the sound; wanders nearby if already far enough.
func _pick_rest_target(h: Human) -> void:
	var far := _sound_dist[h.cell.y * _size.x + h.cell.x] >= tuning.rest_distance
	for i in 30:
		var c: Vector2i
		if far:
			c = h.cell + Vector2i(randi_range(-tuning.rest_wander, tuning.rest_wander), randi_range(-tuning.rest_wander, tuning.rest_wander))
		else:
			c = Vector2i(randi_range(0, _size.x - 1), randi_range(0, _ui_top - 1))
		if _is_walkable(c, true) and not _occupied.has(c) \
				and _sound_dist[c.y * _size.x + c.x] >= tuning.rest_distance:
			h.target = c
			return
	h.target = h.cell


func _build_sound_map() -> void:
	# Only the sound's edge pixels matter for nearest distance.
	var edge: Array[Vector2i] = []
	for y in _size.y:
		for x in _size.x:
			var c := Vector2i(x, y)
			if _is_sound(c) and not (_is_sound(c + Vector2i.LEFT) and _is_sound(c + Vector2i.RIGHT)
					and _is_sound(c + Vector2i.UP) and _is_sound(c + Vector2i.DOWN)):
				edge.append(c)
	_sound_dist.resize(_size.x * _size.y)
	_sound_dist.fill(INF)
	for y in _size.y:
		for x in _size.x:
			var c := Vector2i(x, y)
			if not _is_walkable(c, false):
				continue
			var d2 := 1 << 30
			for s in edge:
				d2 = mini(d2, (c - s).length_squared())
			var d := sqrt(d2)
			_sound_dist[y * _size.x + x] = d
			if d <= tuning.dance_radius_max and c.y < _ui_top:
				_dance_spots.append(c)


func _is_sound(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= _size.x or c.y >= _size.y:
		return false
	return _sound_img.get_pixelv(c).a > 0.0


func _is_walkable(c: Vector2i, above_ui: bool) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= _size.x or c.y >= _size.y:
		return false
	if above_ui and c.y >= _ui_top:
		return false
	return _base_img.get_pixelv(c).a > 0.0 and c.y > _sound_base \
			and not _booth_cells.has(c)


func _build_booth_cells(booth_used: Rect2i) -> void:
	var idle: StringName = _skins[_base_skin].takes[&"idle"][0][0]
	var body := _rgba(_skins[_base_skin].frames.get_frame_texture(idle, 0).get_image())
	var shape: Array[Vector2i] = []
	for y in body.get_height():
		for x in body.get_width():
			if body.get_pixel(x, y).a > 0.0:
				shape.append(Vector2i(x, y) + Vector2i(BASE_OFFSET))
	# The booth's pixels, plus the DJ standing at their spot.
	var booth_img := _rgba(booth.texture.get_image())
	var solid: Array[Vector2i] = []
	for y in range(booth_used.position.y, booth_used.end.y):
		for x in range(booth_used.position.x, booth_used.end.x):
			_booth_cells[Vector2i(x, y)] = true
			if booth_img.get_pixel(x, y).a > 0.0:
				solid.append(Vector2i(x, y))
	for o in shape:
		solid.append(_dj_spot + o)
	for c in solid:
		for o in shape:
			_booth_cells[c - o] = true
	# Let humans come BOOTH_BOTTOM_SLACK closer from below: free the lowest
	# blocked cells of each column, outside the booth's own box.
	var bottom := {}
	for c in _booth_cells:
		bottom[c.x] = maxi(bottom.get(c.x, c.y), c.y)
	for x in bottom:
		for i in BOOTH_BOTTOM_SLACK:
			var c := Vector2i(x, bottom[x] - i)
			if not booth_used.has_point(c):
				_booth_cells.erase(c)


func _make_grid(above_ui: bool) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(Vector2i.ZERO, _size)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for y in _size.y:
		for x in _size.x:
			var c := Vector2i(x, y)
			g.set_point_solid(c, not _is_walkable(c, above_ui))
	var clear := _clearance(g)
	for y in _size.y:
		for x in _size.x:
			var d: float = clear[y * _size.x + x]
			if d > 0.0:
				g.set_point_weight_scale(Vector2i(x, y), 1.0 + tuning.stroll_pull / d)
	return g


## Distance from each cell to the nearest solid cell or the map edge
## (0 on solid cells), by a two-pass chamfer over the grid.
func _clearance(g: AStarGrid2D) -> PackedFloat32Array:
	var w := _size.x
	var d := PackedFloat32Array()
	d.resize(w * _size.y)
	for y in _size.y:
		for x in w:
			d[y * w + x] = 0.0 if g.is_point_solid(Vector2i(x, y)) else INF
	var fwd: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	var bwd: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1)]
	for pass_ in 2:
		var offs := fwd if pass_ == 0 else bwd
		var ys := range(_size.y) if pass_ == 0 else range(_size.y - 1, -1, -1)
		var xs := range(w) if pass_ == 0 else range(w - 1, -1, -1)
		for y in ys:
			for x in xs:
				var i: int = y * w + x
				if d[i] == 0.0:
					continue
				for o in offs:
					var n := Vector2i(x, y) + o
					var step := 1.0 if o.x == 0 or o.y == 0 else sqrt(2.0)
					# Off the map counts as an edge.
					var nd := 0.0 if not g.is_in_boundsv(n) else d[n.y * w + n.x]
					d[i] = minf(d[i], nd + step)
	return d


func _find_bottom(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				return y
	return -1


func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()


func _find_ui_top(img: Image) -> int:
	for y in img.get_height():
		if img.get_pixel(0, y).a > 0.0:
			return y
	return img.get_height()


func _rgba(img: Image) -> Image:
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img
