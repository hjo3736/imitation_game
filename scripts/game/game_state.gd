class_name GameState
extends RefCounted
## The state of a game in progress (docs/roles/leader/outputs/13 design, 5.2).
## Screens only read it. Only GameCore changes it.

const PHASE_PLAYING: StringName = &"playing"
const PHASE_SUMMARY: StringName = &"summary"

## The day, starting at 1.
var day: int = 1
## The length of a day in seconds.
var day_length: float = 0.0
## The time left in the day in seconds. Never below 0.
var day_time_left: float = 0.0
## &"playing" or &"summary".
var phase: StringName = PHASE_PLAYING
## The summary of the day that ended, while phase is &"summary". Empty otherwise.
var last_summary: Dictionary = {}
