class_name MonkeyClimbController
extends Node
## Contact ownership is separate from animation. Only airborne limbs move targets.
## Releasing a key / reversing / taunting completes the current half-step first.
enum State { ClimbIdle, ClimbUp, ClimbDown, ClimbTransition, TauntTurn, TauntPlay, TauntReturn }
const LIMBS := ["LH", "RH", "LF", "RF"]
var profile: ClimbProfile = preload("res://resources/climb_profile.tres")
var ladder: MonkeyLadder
var rig: MonkeyRig
var state: State = State.ClimbIdle
var targets: Dictionary = {}
var pelvis := Vector3.ZERO
var support_height: float = 0.0
var phase: float = 0.0
var clock: float = 0.0
var step_direction: int = 0
var active_pair: int = 0
var next_pair: int = 0
var hand_limb: String = "RH"
var foot_limb: String = "LF"
var body_start: float
var body_finish: float
var step_running: bool = false
var taunt_pending: bool = false
var taunt_blend: float = 0.0
var expression: float = 0.0
var taunt_clock: float = 0.0
var diagnostic_input: int = 99
var completed_steps: int = 0
var completed_taunts: int = 0
var turn_anchor := Vector3.ZERO
var initialized: bool = false

func setup(monkey: MonkeyRig, bars: MonkeyLadder) -> void:
	rig = monkey
	ladder = bars
	process_priority = -20
	for limb: String in LIMBS:
		var rung := 5 if limb.ends_with("H") else 2
		targets[limb] = {"rung": rung, "position": ladder.contact(limb, rung), "moving": false, "grip": 1.0, "basis": Basis.IDENTITY}
	support_height = (targets.LF.position.y + targets.RF.position.y) * 0.5 + 0.59
	pelvis = Vector3(0, support_height, profile.body_distance)
	initialized = true

func requested_direction() -> int:
	if diagnostic_input != 99:
		return diagnostic_input
	return int(Input.is_action_pressed("climb_up")) - int(Input.is_action_pressed("climb_down"))

func request_taunt() -> void:
	if state <= State.ClimbTransition:
		taunt_pending = true

func _process(delta: float) -> void:
	if not initialized:
		return
	clock += delta
	if Input.is_action_just_pressed("taunt"):
		request_taunt()
	if state >= State.TauntTurn:
		update_taunt(delta)
		return
	if step_running:
		if requested_direction() != step_direction or taunt_pending:
			state = State.ClimbTransition
		phase = minf(1.0, phase + delta / (profile.up_step_duration if step_direction > 0 else profile.down_step_duration))
		update_step()
		if phase >= 1.0:
			finish_step()
	else:
		if taunt_pending:
			begin_taunt()
		elif requested_direction() != 0:
			begin_step(requested_direction())
		else:
			state = State.ClimbIdle
			pelvis = Vector3(0, support_height + 0.003 * sin(clock * 2.0), profile.body_distance)

func begin_step(direction: int) -> void:
	# Choose the lagging pair on ascent, the higher pair on descent. Direction
	# changes therefore undo an unfinished rung stagger before adding another.
	if direction > 0:
		active_pair = 0 if targets.RH.rung < targets.LH.rung else (1 if targets.LH.rung < targets.RH.rung else next_pair)
	else:
		active_pair = 0 if targets.LF.rung > targets.RF.rung else (1 if targets.RF.rung > targets.LF.rung else next_pair)
	hand_limb = "RH" if active_pair == 0 else "LH"
	foot_limb = "LF" if active_pair == 0 else "RF"
	for limb: String in [hand_limb, foot_limb]:
		var next_rung: int = targets[limb].rung + direction
		if next_rung < 0 or next_rung >= ladder.rung_count:
			state = State.ClimbIdle
			return
	step_direction = direction
	state = State.ClimbUp if direction > 0 else State.ClimbDown
	phase = 0.0
	body_start = support_height
	body_finish = support_height + direction * ladder.rung_spacing * 0.5
	for limb: String in [hand_limb, foot_limb]:
		targets[limb].from = targets[limb].position
		targets[limb].destination_rung = targets[limb].rung + direction
		targets[limb].to = ladder.contact(limb, targets[limb].destination_rung)
	step_running = true
	update_step()

static func smooth5(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

static func window(t: float, start: float, end: float) -> float:
	return clampf((t - start) / (end - start), 0.0, 1.0)

func update_step() -> void:
	# Descent is foot-led, with an earlier controlled lowering of the pelvis.
	var hand_phase := window(phase, 0.0, 0.58) if step_direction > 0 else window(phase, 0.32, 0.88)
	var foot_phase := window(phase, 0.16, 0.72) if step_direction > 0 else window(phase, 0.0, 0.57)
	move_limb(hand_limb, hand_phase, profile.hand_clearance, 0.025)
	move_limb(foot_limb, foot_phase, profile.foot_clearance, 0.080)
	var lift := smooth5(window(phase, 0.28, 1.0)) if step_direction > 0 else smooth5(window(phase, 0.06, 0.88))
	var sway := sin(PI * phase) * sin(PI * phase)
	var side := -1.0 if active_pair == 0 else 1.0
	pelvis = Vector3(side * profile.weight_shift * sway, lerpf(body_start, body_finish, lift), profile.body_distance + 0.028 * sway * (-1.0 if step_direction > 0 else 1.0))

func move_limb(limb: String, t: float, clearance: float, lift: float) -> void:
	var u := smooth5(t)
	var arc := pow(sin(PI * u), 2.0)
	var data: Dictionary = targets[limb]
	data.position = data.from.lerp(data.to, u) + Vector3(0, lift * arc, clearance * arc)
	data.moving = t > 0.0 and t < 1.0
	if t >= 1.0:
		data.rung = data.destination_rung
	data.grip = 1.0 - sin(PI * u)
	data.basis = Basis(Vector3.RIGHT, (-0.32 if limb.ends_with("F") else -0.18) * arc)

func finish_step() -> void:
	for limb: String in [hand_limb, foot_limb]:
		targets[limb].rung = targets[limb].destination_rung
		targets[limb].position = ladder.contact(limb, targets[limb].rung)
		targets[limb].moving = false
		targets[limb].grip = 1.0
		targets[limb].basis = Basis.IDENTITY
	support_height = body_finish
	pelvis = Vector3(0, support_height, profile.body_distance)
	next_pair = 1 - active_pair
	step_running = false
	completed_steps += 1
	state = State.ClimbIdle
	# Transition begins from precisely the final pose, on the following tick.

func begin_taunt() -> void:
	taunt_pending = false
	taunt_clock = 0.0
	state = State.TauntTurn
	turn_anchor = targets.RH.position

func update_taunt(delta: float) -> void:
	taunt_clock += delta
	match state:
		State.TauntTurn:
			taunt_blend = smooth5(taunt_clock / profile.turn_duration)
			expression = smooth5(window(taunt_blend, 0.60, 1.0))
			if taunt_clock >= profile.turn_duration:
				state = State.TauntPlay
				taunt_clock = 0.0
		State.TauntPlay:
			taunt_blend = 1.0
			expression = 1.0
			if taunt_clock >= profile.taunt_duration:
				state = State.TauntReturn
				taunt_clock = 0.0
		State.TauntReturn:
			taunt_blend = 1.0 - smooth5(taunt_clock / profile.return_duration)
			expression = smooth5(window(taunt_blend, 0.45, 1.0))
			if taunt_clock >= profile.return_duration:
				taunt_blend = 0.0
				expression = 0.0
				targets.RH.position = turn_anchor
				targets.RH.basis = Basis.IDENTITY
				targets.RH.moving = false
				targets.RH.grip = 1.0
				state = State.ClimbIdle
				completed_taunts += 1
	pelvis = Vector3(-0.045 * taunt_blend, support_height, profile.body_distance + 0.015 * taunt_blend)
	targets.RH.moving = taunt_blend > 0.0
	targets.RH.grip = 1.0 - taunt_blend
	# The body modifier computes the facial hand target from the actual head
	# pose. LH and both feet remain at their original world-space contacts.

func state_name() -> String:
	return State.keys()[state]
