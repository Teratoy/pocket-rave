extends Node
## Touching the DJ or their decks scratches the record. The music stops
## under the DJ's hand and the slice of track around the needle is
## dragged back and forth like vinyl: its pitch follows the hand's speed,
## and it goes quiet and dull as the hand slows to turn around. The
## longer the touch, the harder the scratch: strokes get quicker, jerkier
## and further apart in pitch, and the crossfader starts cutting them
## (chirps, then transforms). Letting go finishes the stroke back to where
## the needle was grabbed, and the music plays on from there.

enum Move { BABY, CHIRP, TRANSFORM }

## Seconds of track kept before and after where the needle was grabbed.
const BEFORE := 1.5
const AFTER := 0.5
## Seconds of holding to reach full intensity.
const RAMP_TIME := 3.0
## Seconds a stroke takes, at no and at full intensity.
const STROKE_TIME := Vector2(0.28, 0.07)
## Seconds of record a back stroke drags, at no and at full intensity.
const STROKE_LENGTH := Vector2(0.22, 0.15)
## Seconds the hand rests between strokes, at no and at full intensity.
const STROKE_GAP := Vector2(0.08, 0.0)
## How much strokes vary at full intensity, as a fraction.
const STROKE_JITTER := 0.35
## Intensity from which chirps, then transforms, join the baby scratches.
const CHIRP_FROM := 0.35
const TRANSFORM_FROM := 0.7
## A chirp's fader stays open for this much of each stroke.
const CHIRP_OPEN := 0.55
## Transform cuts a second, as transforms start and at full intensity.
const TRANSFORM_RATE := Vector2(10.0, 22.0)
## Seconds the fader takes to open or close, so cuts don't click.
const FADER_TIME := 0.003
## Hand speed (1 is normal playback) from which the record is fully loud
## and bright.
const FULL_SPEED := 0.8
## Level of the stylus noise under the scratch.
const NOISE_LEVEL := 0.03
const OUTPUT_BUFFER := 0.06

@export var music: Node
@export var humans: Node2D

var _player: AudioStreamPlayer
var _out: AudioStreamGeneratorPlayback
var _rate: float
## The track around the needle, at the mix rate.
var _buf: PackedVector2Array
## Frames into _buf where the needle was grabbed, and where it is now.
var _base := 0.0
var _needle := 0.0
var _active := false
var _touching := false
var _held_time := 0.0

## The stroke under way: its direction (+1 forward), frames of record
## it moves, seconds it takes and has taken, and where it ends.
var _dir := 1.0
var _length := 0.0
var _time := 0.0
var _t := 0.0
var _target := 0.0
## Seconds of rest left before the next stroke.
var _gap := 0.0
var _move := Move.BABY
var _transform_rate := 0.0
var _fader := 1.0
## Low-pass state, dulling the record as it slows.
var _dull := Vector2.ZERO


func _ready() -> void:
	_rate = AudioServer.get_mix_rate()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = OUTPUT_BUFFER
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = SoundSettings.BUS
	add_child(_player)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		_touching = false
	elif not _active and humans.dj_touched(event.position) and _grab():
		get_viewport().set_input_as_handled()
		Tips.event("scratch")


func _notification(what: int) -> void:
	# The game pausing lifts the hand off; unpausing restarts the music.
	if what == NOTIFICATION_PAUSED and _active:
		_finish()


func _process(delta: float) -> void:
	if not _active:
		return
	if not music.is_playing():
		_finish()
		return
	if _touching:
		_held_time += delta
	_fill()


## Stops the record under the hand and starts scratching it. False when
## there is no track to scratch.
func _grab() -> bool:
	var stream: AudioStream = music.current_stream()
	if not stream:
		return false
	var pos: float = music.playback_position()
	var from := maxf(pos - BEFORE, 0.0)
	var playback := stream.instantiate_playback()
	playback.start(from)
	_buf = playback.mix_audio(1.0, int((pos - from + AFTER) * _rate))
	playback.stop()
	if _buf.size() < 2:
		return false
	music.hold(true)
	_base = minf((pos - from) * _rate, _buf.size() - 2)
	_needle = _base
	_active = true
	_touching = true
	_held_time = 0.0
	_dir = 1.0
	_gap = 0.0
	_fader = 1.0
	_dull = Vector2.ZERO
	_next_stroke()
	_player.play()
	_out = _player.get_stream_playback()
	_fill()
	return true


## Lets go of the record: the music plays on from the needle.
func _finish() -> void:
	_active = false
	_player.stop()
	music.hold(false)


## Starts the stroke after the one that just ended, back after forward
## and forward after back. False once the hand has let go and the needle
## is back where it was grabbed.
func _next_stroke() -> bool:
	var back := _dir > 0.0
	if back and not _touching:
		return false
	var i := clampf(_held_time / RAMP_TIME, 0.0, 1.0)
	var jitter := STROKE_JITTER * i
	_time = lerpf(STROKE_TIME.x, STROKE_TIME.y, i) * (1.0 + randf_range(-jitter, jitter))
	var length := lerpf(STROKE_LENGTH.x, STROKE_LENGTH.y, i) * _rate
	if back:
		_target = _needle - length * (1.0 + randf_range(-jitter, jitter))
		# Each back-and-forth is one move, harder ones unlocking with time.
		var moves := [Move.BABY]
		if i >= CHIRP_FROM:
			moves.append(Move.CHIRP)
		if i >= TRANSFORM_FROM:
			moves.append(Move.TRANSFORM)
		_move = moves.pick_random()
		_transform_rate = lerpf(TRANSFORM_RATE.x, TRANSFORM_RATE.y,
				inverse_lerp(TRANSFORM_FROM, 1.0, maxf(i, TRANSFORM_FROM)))
	else:
		# Pushed back to about the grab point, exactly once letting go.
		_target = _base
		if _touching:
			_target += length * randf_range(-jitter, jitter) * 0.5
	_target = clampf(_target, 0.0, _buf.size() - 2)
	_length = absf(_target - _needle)
	_dir = -1.0 if back else 1.0
	_t = 0.0
	humans.dj_scratch_stroke()
	return true


## Writes the scratch out as far as the output buffer has room.
func _fill() -> void:
	var dt := 1.0 / _rate
	var fade := dt / FADER_TIME
	var gap := lerpf(STROKE_GAP.x, STROKE_GAP.y, clampf(_held_time / RAMP_TIME, 0.0, 1.0))
	for n in _out.get_frames_available():
		var speed := 0.0
		var open := false
		if _gap > 0.0:
			_gap -= dt
			if _gap <= 0.0 and not _next_stroke():
				_finish()
				return
		else:
			_t += dt
			if _t >= _time:
				_needle = _target
				_gap = gap
				if _gap <= 0.0 and not _next_stroke():
					_finish()
					return
			else:
				# The hand speeds up then slows down over each stroke.
				var phase := _t / _time
				speed = _length / _time * PI * 0.5 * sin(PI * phase) * dt
				_needle = clampf(_needle + _dir * speed, 0.0, _buf.size() - 2)
				match _move:
					Move.BABY:
						open = true
					Move.CHIRP:
						open = phase < CHIRP_OPEN
					Move.TRANSFORM:
						open = fmod(_t * _transform_rate, 1.0) < 0.5
		_fader = move_toward(_fader, 1.0 if open else 0.0, fade)
		var at := int(_needle)
		var s := _buf[at].lerp(_buf[at + 1], _needle - at)
		# Barely moving, the record is quiet and muffled.
		var level := clampf(speed / FULL_SPEED, 0.0, 1.0)
		_dull = _dull.lerp(s, 0.05 + 0.95 * level * level)
		var hiss := randf_range(-NOISE_LEVEL, NOISE_LEVEL) * level
		_out.push_frame((_dull * level + Vector2(hiss, hiss)) * _fader)
