extends AnimatedSprite2D
## One human. Its position is its base pixel, the only pixel that collides.
## Movement is decided by the Humans manager.

enum State { WAITING, WALKING, IDLE, DANCING, GREETING, HANDOFF, RECEIVING, TAKING }
## Why the human is walking: what it does on arrival.
enum Goal { STROLL, DANCE, VISIT_DJ, HANDOFF, TAKE_DEAL, LEAVE }

var cell: Vector2i
var state := State.WAITING
var goal := Goal.STROLL
var timer := 0.0
var target: Vector2i
var stuck := 0
## Becomes true once the human has walked up out from under the UI.
var entered := false

var dance_left := 0.0
## Seconds danced since last rest.
var fatigue := 0.0
var tired := false
## Seconds rested while tired.
var rest := 0.0

## Seconds until the human will wave at someone again.
var greet_cooldown := 0.0
## State to go back to once the wave is over.
var resume_state := State.IDLE

## Standing by the booth, deciding whether to wave at the DJ.
var wave_dj := false

## Dealers look like everyone else, but wave more and hand out deals.
var dealer := false
## The other side of a deal being handed over, until it changes hands.
var partner: AnimatedSprite2D
var has_deal := false
## Seconds left acting erratic after taking a deal.
var erratic := 0.0

## Cells still to walk to, in order. Crowd humans plan theirs to target;
## a DJ's are the corners of its route.
var path: Array[Vector2i] = []
## The target the planned path leads to; a new target means a new plan.
var path_to: Vector2i
