extends Node
## The Tips autoload: hands out what the moon says (see moon.gd) from the
## library the Moon Tips dock edits.
## Game code calls event() as things happen; each enabled contextual tip
## for that trigger is queued to be said (once ever, unless it's said
## every time), with any {name}
## placeholders in it filled in from the event's values. Which were said, and
## where in-order tips are up to, is saved between runs.

const LIBRARY := "res://tips/tips.tres"
const SAVE_FILE := "user://tips.cfg"

## Where progress is saved; tests point this somewhere else.
var save_file := SAVE_FILE

var _library: MoonTipLibrary
var _save := ConfigFile.new()
## Contextual tips waiting to be said, oldest first, each as
## {tip = MoonTip, values = Dictionary}.
var _pending: Array[Dictionary] = []
var _last: MoonTip


func _ready() -> void:
	_library = load(LIBRARY)
	_save.load(save_file)


## Queues the contextual tips for trigger that haven't been said yet, or
## are said every time. A tip already waiting is said once, with the
## latest values. values fill in their placeholders, e.g. {"dj": "NOVA"} turns "{dj} is
## up!" into "NOVA is up!" (see MoonTipLibrary.PLACEHOLDERS).
func event(trigger: String, values := {}) -> void:
	for tip in _library.tips:
		if tip.enabled and tip.kind == MoonTip.Kind.CONTEXTUAL and tip.trigger == trigger \
				and tip.text.strip_edges() != "" and (tip.every_time or not was_said(tip)):
			var waiting := _pending.filter(func(p: Dictionary): return p.tip == tip)
			if waiting.is_empty():
				_pending.append({tip = tip, values = values})
			else:
				waiting[0].values = values


func has_pending() -> bool:
	return not _pending.is_empty()


## The oldest queued contextual tip's text, now counted as said; "" if
## none are queued.
func take_pending() -> String:
	if _pending.is_empty():
		return ""
	var next: Dictionary = _pending.pop_front()
	var tip: MoonTip = next.tip
	_save.set_value("said", tip.key(), true)
	_save.save(save_file)
	return tip.text.format(next.values)


func was_said(tip: MoonTip) -> bool:
	return _save.get_value("said", tip.key(), false)


## A repeatable tip's text, picked as the library's order says; "" if
## there are none.
func random_tip() -> String:
	var pool := _library.repeatable()
	if pool.is_empty():
		return ""
	var tip: MoonTip
	if _library.order == MoonTipLibrary.Order.IN_ORDER:
		var i: int = _save.get_value("order", "next", 0) % pool.size()
		tip = pool[i]
		_save.set_value("order", "next", i + 1)
		_save.save(save_file)
	else:
		if pool.size() > 1:
			pool.erase(_last)
		var total := 0.0
		for t in pool:
			total += t.chance
		var roll := randf() * total
		for t in pool:
			tip = t
			roll -= t.chance
			if roll < 0.0:
				break
	_last = tip
	return tip.text
