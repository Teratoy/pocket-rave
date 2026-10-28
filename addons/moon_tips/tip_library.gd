@tool
class_name MoonTipLibrary
extends Resource
## Everything the moon can say, edited in the Moon Tips dock and said
## through the Tips autoload (see tips.gd).

enum Order {
	## Weighted by each tip's chance, never the same one twice in a row.
	RANDOM,
	## One after another, top to bottom, then round again.
	IN_ORDER,
}

## The triggers game code fires through Tips.event(), with what they mean.
## Contextual tips are said the first time their trigger happens, or
## every time if they're set to.
const TRIGGERS := {
	"launch": "The game is launched, once the intro is over",
	"moon_touched": "The moon is touched",
	"music_menu": "The music button is pressed",
	"dj_called": "A DJ is picked and walks to the booth",
	"set_started": "A DJ starts their set",
	"set_ended": "A set ends or is stopped",
	"scratch": "The record is scratched",
	"paused": "The game is paused",
	"settings": "The settings button is pressed",
	"tracks_imported": "Tracks are imported",
	"track_edited": "A track's details are saved",
	"shop": "The shop button is pressed",
	"shop_item_picked": "A shop item is picked and put to use",
}

## What triggers fill in: a tip's text can say {name} for any of its
## trigger's names, replaced as it's said. Each comes with an example for
## the dock's preview.
const PLACEHOLDERS := {
	"dj_called": {"dj": "NOVA"},
	"set_started": {"dj": "NOVA"},
	"set_ended": {"dj": "NOVA"},
	"tracks_imported": {"count": 3},
	"shop_item_picked": {"item": "NEON", "category": "UI"},
}

## How repeatable tips are picked when the moon is touched.
@export var order := Order.RANDOM
@export var tips: Array[MoonTip] = []


## The repeatable tips that can come up, in order.
func repeatable() -> Array[MoonTip]:
	return tips.filter(func(t: MoonTip):
		return t.enabled and t.kind == MoonTip.Kind.REPEATABLE and t.text.strip_edges() != "" \
				and (order == Order.IN_ORDER or t.chance > 0.0))


## The share (0 to 1) of touches that say tip, when picked at random.
func share(tip: MoonTip) -> float:
	var pool := repeatable()
	if tip not in pool:
		return 0.0
	if order == Order.IN_ORDER:
		return 1.0 / pool.size()
	var total := 0.0
	for t in pool:
		total += t.chance
	return tip.chance / total
