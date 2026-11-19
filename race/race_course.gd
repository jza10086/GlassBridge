class_name GlassBridgeCourse
extends Node3D

const Settings = preload("../settings.gd")

enum Phase { COUNTDOWN, RUNNING, COMPLETE }
@export var course_title := "障碍竞速"
@export_range(1, 8) var player_count := 2
@export_range(0.0, 10.0) var countdown := 3.0
@export_range(0.0, 1200.0) var time_limit := 0.0
## Zero means every entrant can finish.
@export_range(0, 8) var qualification_slots := 0
@export var racer_scene: PackedScene = preload("res://games/minigame/GP_glass_bridge/race/race_player.tscn")
## Progress gates can remain mandatory while every death returns to the starting grid.
@export var checkpoint_respawn_enabled := true

@export_group("Player Movement")
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m/s") var walk_speed := 1.3
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m/s") var run_speed: float = Settings.DEFAULT_RUN_SPEED
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m/s") var sprint_speed: float = Settings.DEFAULT_SPRINT_SPEED
## 从静止地面起跳时，脚底到最高点的垂直距离。平台速度和弹射可改变实际高度。
@export_range(0.05, 15.0, 0.001, "or_greater", "suffix:m") var jump_height: float = Settings.DEFAULT_JUMP_HEIGHT
## 松开方向键后在地面减速的快慢。值越小，滑行越远。
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:m/s²") var ground_braking := 60.0
## 空中没有有效方向输入时的水平减速度。设为 0 可完整保留水平速度。
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:m/s²") var air_braking := 0.0
## 离台时继承全部平台速度、忽略向下分量，或不继承。
@export var platform_momentum: CharacterBody3D.PlatformOnLeave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
## 关闭后，空中方向输入不改变运动轨迹。碰撞与机关弹射仍可改变速度。
@export var allow_air_steering := true

@onready var finish: ParkourGate = $FinishGate
var checkpoints: Array[ParkourGate] = []
var racers: Array[GlassBridgeRacer] = []
var results: Array[GlassBridgeRacer] = []
var phase := Phase.COUNTDOWN
var elapsed := 0.0
var remaining: float
var focused := 0
var view: StandardViewRig
var items: Array[ParkourItem] = []

const PreviewInput = preload("res://games/minigame/GP_glass_bridge/preview_input.gd")
var preview_input: PreviewInput = PreviewInput.new()

func _enter_tree() -> void:
	preview_input.install()

func _exit_tree() -> void:
	preview_input.restore()

signal completed()
signal race_started()
var api: PartyAPI
var roster: Array[Dictionary] = []
var local_index: int = -1
var playing: bool = false

func _ready() -> void:
	if api == null:
		playing = true
		_start_course()
		_focus(0)
	else:
		player_count = roster.size()
		_start_course()
		set_physics_process(false)

func start_round() -> void:
	playing = true
	_focus(maxi(0, local_index))
	racers[focused].input_enabled = false
	if api.is_host():
		set_physics_process(true)

func stop_round() -> void:
	playing = false
	process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _start_course() -> void:
	process_physics_priority = 120
	remaining = countdown
	for gate: ParkourGate in $Checkpoints.get_children():
		checkpoints.append(gate)
	for node in find_children("*", "Area3D", true, false):
		if node is ParkourItem and node.activation == ParkourItem.Activation.INTERACT:
			items.append(node)
	for i in player_count:
		var marker: Marker3D = $StartGrid.get_child(i)
		var racer: GlassBridgeRacer = racer_scene.instantiate()
		racer.name = "P%d" % (i + 1)
		racer.transform = global_transform.affine_inverse() * marker.global_transform
		racer.input_enabled = api == null and i == 0
		add_child(racer)
		_apply_player_movement(racer)
		racer.set_paused(true)
		racer.get_node("Nameplate").text = racer.name if api == null else roster[i].name
		if api != null:
			if roster[i].is_local:
				local_index = i
			if not api.is_host():
				racer.collision_layer = 0
				racer.collision_mask = 0
				racer.set_physics_process(false)
		racers.append(racer)

func _apply_player_movement(racer: GlassBridgeRacer) -> void:
	# The player owns an instance copy of the character preset after entering the tree.
	var movement := racer.settings
	movement.walk_speed = walk_speed
	movement.run_speed = run_speed
	movement.sprint_speed = sprint_speed
	movement.jump_speed = sqrt(2.0 * movement.gravity * jump_height)
	movement.deceleration = ground_braking
	movement.apply_to(racer)
	racer.character.jump_ascent_seconds = movement.jump_speed / movement.gravity
	racer.air_braking = air_braking
	racer.allow_air_steering = allow_air_steering
	racer.platform_on_leave = platform_momentum

func _focus(index: int) -> void:
	if view:
		var old := racers[focused]
		if racers.size() > 1:
			racers[(focused + 1) % racers.size()].release_motion_input()
		old.input_enabled = false
		old.character.set_first_person(false)
		old.instant_facing = false
		old.face_camera = false
		old.aim_gait_override = &""
		old.sprint_allowed = true
		remove_child(view)
		view.free()
	focused = index
	var target := racers[index]
	target.release_motion_input()
	target.controls_active = true
	target.input_enabled = true
	view = StandardViewRig.new()
	view.actor = target
	view.yaw = target.global_rotation.y
	add_child(view)
	view.set_process_unhandled_input(false)

## Receive local camera motion before GUI controls consume the event.
func _input(event: InputEvent) -> void:
	if not playing or view == null:
		return
	if api != null and (local_index < 0 or api.input.input_blocked):
		return
	if api == null and view.inputs.pressed(event, &"release_controls"):
		view.suspend_controls()
	elif event is InputEventMouseMotion and view.controls_active():
		view._unhandled_input(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			view._unhandled_input(event)
		elif event.button_index == MOUSE_BUTTON_LEFT and not view.controls_active():
			view.resume_controls()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if api != null:
		return
	if racers.size() > 1 and event.is_action_pressed(&"parkour_switch_racer"):
		_focus((focused + 1) % racers.size())
	elif event.is_action_pressed(&"platformer_interact") and view.controls_active():
		interact(racers[focused])
	elif event.is_action_pressed(&"parkour_partner_interact") and racers.size() > 1:
		interact(racers[(focused + 1) % racers.size()])

func nearest_item(racer: GlassBridgeRacer) -> ParkourItem:
	var best: ParkourItem
	var best_distance := INF
	for item in items:
		if item.available(racer.receiver):
			var distance := racer.global_position.distance_squared_to(item.global_position)
			if distance < best_distance:
				best = item
				best_distance = distance
	return best

func interact(racer: GlassBridgeRacer) -> void:
	var item := nearest_item(racer)
	if item:
		item.collect(racer.receiver)

## Finishers come first in crossing order, followed by personal score.
## Equal scores use entrant order for stable display; the HUD can show a shared place.
func ranked_racers() -> Array[GlassBridgeRacer]:
	var standings: Array[GlassBridgeRacer] = racers.duplicate()
	standings.sort_custom(func(a: GlassBridgeRacer, b: GlassBridgeRacer) -> bool:
		if a.withdrawn != b.withdrawn:
			return not a.withdrawn
		if a.rank > 0 and b.rank > 0:
			return a.rank < b.rank
		if a.rank > 0 or b.rank > 0:
			return a.rank > 0
		if a.tokens != b.tokens:
			return a.tokens > b.tokens
		return a.get_index() < b.get_index())
	return standings

## Finishers have unique places. Unfinished racers with equal scores share a place.
func standing_places(standings: Array[GlassBridgeRacer]) -> Array[int]:
	var places: Array[int] = []
	for i: int in standings.size():
		var racer: GlassBridgeRacer = standings[i]
		var place: int = i + 1
		if racer.withdrawn:
			place = 0
		elif i > 0 and racer.rank == 0 and standings[i - 1].rank == 0 and racer.tokens == standings[i - 1].tokens:
			place = places[i - 1]
		places.append(place)
	return places

func _physics_process(delta: float) -> void:
	if phase == Phase.COUNTDOWN:
		remaining -= delta
		if remaining <= 0.0:
			phase = Phase.RUNNING
			race_started.emit()
			for racer in racers:
				if racer.withdrawn:
					continue
				racer.active = true
				racer.set_paused(false)
		return
	if phase == Phase.COMPLETE:
		return
	var arrivals: Array[GlassBridgeRacer] = []
	for racer in racers:
		if not racer.active:
			continue
		if racer.checkpoint_count < checkpoints.size():
			var gate := checkpoints[racer.checkpoint_count]
			if gate.crossing(racer.previous_position, racer.global_position) >= 0.0:
				racer.checkpoint_count += 1
				if checkpoint_respawn_enabled:
					racer.spawn_position = gate.get_node("Respawn").global_position
		if racer.checkpoint_count == checkpoints.size():
			var fraction := finish.crossing(racer.previous_position, racer.global_position)
			if fraction >= 0.0:
				var crossing_time := elapsed + fraction * delta
				if time_limit == 0.0 or crossing_time <= time_limit:
					racer.finish_time = crossing_time
					arrivals.append(racer)
	arrivals.sort_custom(func(a: GlassBridgeRacer, b: GlassBridgeRacer) -> bool:
		return a.finish_time < b.finish_time if a.finish_time != b.finish_time else a.get_index() < b.get_index())
	var slots := racers.size() if qualification_slots == 0 else mini(qualification_slots, racers.size())
	for racer in arrivals:
		if results.size() == slots:
			break
		results.append(racer)
		racer.rank = results.size()
		racer.active = false
		racer.set_paused(true)
	elapsed += delta
	if not racers.any(func(racer: GlassBridgeRacer) -> bool: return racer.active) or results.size() == slots or (time_limit > 0.0 and elapsed >= time_limit):
		phase = Phase.COMPLETE
		for racer in racers:
			racer.active = false
			racer.set_paused(true)
		completed.emit()
		return
	if api == null and racers.size() > 1:
		var partner := racers[(focused + 1) % racers.size()]
		if partner.active:
			partner.view_yaw = view.actor.view_yaw
			var movement := Input.get_vector(&"parkour_left", &"parkour_right", &"parkour_forward", &"parkour_back")
			partner.set_motion_input(movement, &"Sprint" if Input.is_action_pressed(&"parkour_partner_sprint") else &"Run", Input.is_action_just_pressed(&"parkour_partner_jump"))
