extends Node
## The sound settings, saved between runs: the volume of everything the
## game plays, and the low-bit effect, which crushes the music (and its
## scratches) down to a few bits at a low sample rate so it sounds like
## an old console.
## Music and scratches play on BUS. While low-bit is on that bus is muted
## and what it plays is captured, crushed here and played on the master
## bus instead. On Android the music plays outside Godot, so both settings
## are passed on to the BackgroundMusic plugin, which crushes the same way
## (see TrackPlayer.java).

signal low_bit_changed(on: bool)

const SETTINGS_FILE := "user://settings.cfg"
## The bus music and scratches play on.
const BUS := &"Music"
## Crushed sound: bits per sample, and samples a second.
const CRUSH_BITS := 4
const CRUSH_RATE := 5000.0
## Seconds of sound the capture and its replay can hold, so a slow frame
## doesn't drop any.
const BUFFER := 0.25

## From 0 (silent) to 1. Heard as the square of this, which sounds more
## even across the slider than the raw gain.
var volume := 1.0:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		AudioServer.set_bus_volume_linear(0, gain())
		if _native:
			_native.setVolume(gain())
		_save_setting("volume", volume)
var low_bit := false:
	set(value):
		low_bit = value
		var bus := AudioServer.get_bus_index(BUS)
		AudioServer.set_bus_mute(bus, value)
		AudioServer.set_bus_effect_enabled(bus, 0, value)
		_capture.clear_buffer()
		if value:
			_player.play()
			_out = _player.get_stream_playback()
		else:
			_player.stop()
			_out = null
		set_process(value)
		if _native:
			_native.setLowBit(value)
		_save_setting("low_bit", value)
		low_bit_changed.emit(value)

var _capture := AudioEffectCapture.new()
## Plays the crushed sound on the master bus.
var _player: AudioStreamPlayer
var _out: AudioStreamGeneratorPlayback
## The BackgroundMusic Android singleton, or null on other platforms.
var _native: Object
## The crushed frame held until the next is due, and how far along to it
## (a next one is due at 1).
var _held := Vector2.ZERO
var _phase := 1.0
var _step: float
var _levels: float


func _ready() -> void:
	# Pausing stops the music, but what was already captured plays out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, BUS)
	_capture.buffer_length = BUFFER
	AudioServer.add_bus_effect(bus, _capture)
	var rate := AudioServer.get_mix_rate()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = BUFFER
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_step = CRUSH_RATE / rate
	_levels = pow(2.0, CRUSH_BITS - 1)
	if Engine.has_singleton("BackgroundMusic"):
		_native = Engine.get_singleton("BackgroundMusic")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	volume = cfg.get_value("sound", "volume", 1.0)
	low_bit = cfg.get_value("sound", "low_bit", false)


## What volume multiplies the sound by.
func gain() -> float:
	return volume * volume


## Crushes what BUS played since the last frame: each frame is held until
## the next one at CRUSH_RATE is due, rounded to CRUSH_BITS.
func _process(_delta: float) -> void:
	var frames := mini(_capture.get_frames_available(), _out.get_frames_available())
	if frames == 0:
		return
	var buf := _capture.get_buffer(frames)
	for i in frames:
		_phase += _step
		if _phase >= 1.0:
			_phase -= 1.0
			_held = (buf[i] * _levels).round() / _levels
		buf[i] = _held
	_out.push_buffer(buf)


func _save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("sound", key, value)
	cfg.save(SETTINGS_FILE)
