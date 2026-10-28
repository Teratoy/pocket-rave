@tool
class_name MoonTip
extends Resource
## One thing the moon can say (see MoonTipLibrary). Repeatable tips come
## up whenever she's touched, weighted by chance; contextual ones are said
## when their trigger happens: once ever, the first time, unless they're
## said every time.

enum Kind { REPEATABLE, CONTEXTUAL }

## Remembers which contextual tips were said; set when the tip is made.
@export var id := ""
@export_multiline var text := ""
@export var kind := Kind.REPEATABLE:
	set(value):
		kind = value
		notify_property_list_changed()
## Off tips are never said.
@export var enabled := true
## Weight among the repeatable tips: one with chance 2 comes up twice as
## often as one with chance 1, and 0 never comes up.
@export_range(0.0, 100.0, 0.1, "or_greater") var chance := 1.0
## The event that says a contextual tip (see MoonTipLibrary.TRIGGERS).
@export var trigger := ""
## Says a contextual tip every time its trigger happens, not just the first.
@export var every_time := false


static func make(tip_kind: Kind) -> MoonTip:
	var tip := MoonTip.new()
	tip.id = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xffffffff]
	tip.kind = tip_kind
	if tip_kind == Kind.CONTEXTUAL:
		tip.trigger = MoonTipLibrary.TRIGGERS.keys()[0]
	return tip


## What remembers this tip was said, even for tips made without an id.
func key() -> String:
	return id if id != "" else str(text.hash())


func _validate_property(property: Dictionary) -> void:
	if property.name == "chance" and kind != Kind.REPEATABLE \
			or property.name in ["trigger", "every_time"] and kind != Kind.CONTEXTUAL:
		property.usage = PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_STORAGE
