extends Resource
## How the crowd behaves: chances, timings and distances, read by
## humans.gd as tuning.x. The values in humans/tuning.tres are the ones
## that play; the defaults here are where they started. Edit them in the
## human editor's Behaviour tab (or the inspector) and the crowd there
## follows at once. Ones marked "Read when the crowd starts" show after
## a restart.

@export_group("Crowd size")
## The crowd starts with at least n humans once the sound has 3n² - 5n + 3
## pixels (1 → 1, 5 → 2, 15 → 3, 31 → 4...), plus up to this many times n more.
## Read when the crowd starts.
@export_range(0, 20, 1, "or_greater") var start_extra_per := 5
## Walkable pixels above the UI per human; sets how big the crowd can get.
## Read when the crowd starts.
@export_range(0, 500, 1, "or_greater") var area_per_human := 120
## In silence, each human's chance per second to head home grows by this
## much for every second without music, up to leave_rate_max.
@export_range(0.0, 0.001, 1e-06, "or_greater") var leave_rate_growth := 1.5e-4
@export_range(0.0, 0.2, 0.001, "or_greater") var leave_rate_max := 0.05
## While music plays, humans arrive at this many per second, plus
## arrive_per_human for each one already there: a crowd draws a crowd.
## Someone always comes when nobody is there.
@export_range(0.0, 0.1, 0.001, "or_greater") var arrive_base := 0.02
@export_range(0.0, 0.1, 0.001, "or_greater") var arrive_per_human := 0.016
## Arrivals and leavings are both scaled by a mood picked between
## 1 / mood_swing and mood_swing, held for mood_time seconds.
@export_range(0.0, 20, 0.1, "or_greater") var mood_swing := 3.0
@export var mood_time := Vector2(20.0, 60.0)
@export_range(0.0, 20, 0.1, "or_greater") var spawn_delay := 4.0
## Seconds a human waits before trying again when every spawn spot is taken.
@export var spawn_retry := Vector2(0.3, 1.0)

@export_group("Walking")
@export_range(0.0, 1, 0.01, "or_greater") var step_time := 0.2
@export var idle_time := Vector2(1.0, 4.0)
@export_range(0.0, 1.0, 0.01) var group_chance := 0.7
@export var group_radius := Vector2i(2, 5)
@export_range(0, 20, 1, "or_greater") var give_up_after := 5
## Strolling, not racing: a step costs 1 + stroll_pull / clearance, where
## clearance is the distance to the nearest edge or obstacle. Walkers drift
## toward the middle of open ground instead of shaving corners.
## Read when the crowd starts.
@export_range(0.0, 20, 0.1, "or_greater") var stroll_pull := 4.0
## Chance per step that a walker veers off its path instead. Tired ones
## drift 45 degrees aside; erratic ones may also lurch fully sideways.
@export_range(0.0, 1.0, 0.01) var tired_wobble_chance := 0.15
@export_range(0.0, 1.0, 0.01) var erratic_wobble_chance := 0.35

@export_group("Dancing")
## Chance to dance = base + per_dancer * dancers, capped.
@export_range(0.0, 1.0, 0.01) var dance_chance_base := 0.10
@export_range(0.0, 1.0, 0.01) var dance_chance_per_dancer := 0.15
@export_range(0.0, 1.0, 0.01) var dance_chance_max := 0.80
@export var dance_time := Vector2(5.0, 15.0)
## Dancing wears the spot under the dancer once per this many seconds.
@export_range(0.0, 5, 0.01, "or_greater") var dance_wear_time := 1.0
## Dance spots are within this many pixels of the sound; the floor grows by
## dance_radius_per_human for each human on screen, up to dance_radius_max
## (kept under rest_distance so resting humans stay off the floor).
@export_range(0.0, 200, 0.1, "or_greater") var dance_radius := 30.0
@export_range(0.0, 2, 0.01, "or_greater") var dance_radius_per_human := 0.5
## Read when the crowd starts.
@export_range(0.0, 200, 0.1, "or_greater") var dance_radius_max := 45.0
## Preferred gap between dancers; shrinks by one per extra dancer.
@export_range(0.0, 50, 0.1, "or_greater") var dance_spacing_max := 8.0
@export_range(0.0, 20, 0.1, "or_greater") var dance_spacing_min := 3.0
@export_range(0.0, 10, 0.1, "or_greater") var crowd_weight := 2.0
## Each pick wants to be this far from the sound, as a fraction of
## the current dance radius, skewed toward the front; keeps the crowd from forming rings.
@export_range(0.0, 1.0, 0.01) var dance_reach_max := 0.7
## Each neighbour's gap is the spacing scaled by a random factor in this
## range, so some dance in pairs and others keep their distance.
@export var dance_gap_jitter := Vector2(0.4, 1.5)
## Random score noise in pixels; breaks the lattice the crowding term forms.
@export_range(0.0, 20, 0.1, "or_greater") var dance_score_noise := 4.0

@export_group("Tired")
@export_range(0.0, 200, 0.1, "or_greater") var tired_after := 30.0
@export_range(0.0, 100, 0.1, "or_greater") var rest_time := 20.0
@export var tired_idle_time := Vector2(4.0, 8.0)
## Tired humans keep at least this far from the sound.
@export_range(0.0, 200, 0.1, "or_greater") var rest_distance := 50.0
@export_range(0, 30, 1, "or_greater") var rest_wander := 6

@export_group("Waving")
## Humans this close (in pixels) to a walker who just stepped wave at each other.
@export_range(0.0, 20, 0.1, "or_greater") var greet_radius := 3.0
## Seconds a human waits before waving again.
@export var greet_cooldown := Vector2(15.0, 30.0)

@export_group("DJ")
## Chance an idle human goes to check on the DJ while one is at the booth.
@export_range(0.0, 1.0, 0.01) var dj_visit_chance := 0.05
## Visitors stand this far (in pixels) to either side of the DJ...
@export_range(0, 20, 1, "or_greater") var dj_visit_spread := 5
## ...and up to this many rows below the space kept clear around the booth.
@export_range(0, 10, 1, "or_greater") var dj_visit_depth := 2
## Seconds a visitor watches the DJ before maybe waving.
@export var dj_visit_look := Vector2(1.0, 3.0)
@export_range(0.0, 1.0, 0.01) var dj_visit_wave_chance := 0.6
## At most this many humans stand (or are headed) around the booth,
## whether visiting, dancing or idling there.
@export_range(0, 20, 1, "or_greater") var dj_crowd_max := 3
## While the set plays, the DJ holds each random DJ frame this many seconds.
@export var dj_frame_time := Vector2(1.0, 4.0)

@export_group("Deals")
## One human in this many is a dealer. They look like everyone else.
@export_range(0, 100, 1, "or_greater") var dealer_every := 15
## Dealers wave this many times as often, and this many times as fast.
@export_range(0.0, 10, 0.1, "or_greater") var dealer_greet_rate := 2.0
## Chance a dealer's wave ends with a deal handed over.
@export_range(0.0, 1.0, 0.01) var deal_chance := 0.35
## Seconds either side waits at the handoff for the other before giving up.
@export_range(0.0, 20, 0.1, "or_greater") var handoff_wait := 3.0
## Seconds the receiver shows the deal in hand.
@export_range(0.0, 2, 0.01, "or_greater") var deal_receive_time := 0.5
## Chance an idle human holding a deal takes it.
@export_range(0.0, 1.0, 0.01) var deal_take_chance := 0.5
## Chance someone on the dance floor walks off it before taking the deal.
@export_range(0.0, 1.0, 0.01) var deal_leave_floor_chance := 0.9
## Taking the deal: in hand, brought in, then done.
@export_range(0.0, 20, 0.1, "or_greater") var deal_hold_time := 3.0
@export_range(0.0, 10, 0.1, "or_greater") var deal_time := 2.0

@export_group("Erratic")
@export var erratic_time := Vector2(13.0, 17.0)
## Each erratic step takes this many times step_time, picked per step.
@export var erratic_step := Vector2(0.3, 3.0)
@export var erratic_idle_time := Vector2(0.5, 4.0)
@export var erratic_dance_time := Vector2(1.0, 6.0)
## Erratic humans wave at someone this close (in pixels), or at nobody.
@export_range(0.0, 50, 0.1, "or_greater") var erratic_greet_radius := 8.0
## Chance a human is tired once the erratic spell wears off.
@export_range(0.0, 1.0, 0.01) var erratic_tired_chance := 0.5

@export_group("Looks")
## Each human is brightened by up to this fraction at spawn, at the
## default dresscode variation, so no two look quite alike.
@export_range(0.0, 1.0, 0.01) var color_variation := 0.20
## Chance a human also spawns with a strong random colour, at the
## default dresscode variation.
@export_range(0.0, 1.0, 0.01) var tint_chance := 0.04
## Brightness of that colour (0..1).
@export_range(0.0, 1.0, 0.01) var tint_strength := 0.8
## A coloured dresscode's hue strays by up to this much at full variation.
@export_range(0.0, 1.0, 0.01) var dresscode_hue_spread := 0.15
