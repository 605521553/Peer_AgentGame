extends Node
const RIG_SCENE := "res://assets/monkey_rig.tscn"
var controller: MonkeyClimbController
var rig: MonkeyRig
var ladder: MonkeyLadder
var body: MonkeyBodyPose
var solvers: Array[MonkeyLimbIK] = []
var viewport: SubViewport
var camera: MonkeyCamera
var achievements: MonkeyAchievements
var achievement_toast: AchievementToast

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	viewport = SubViewport.new()
	viewport.name = "RetroViewport"
	viewport.size = Vector2i(384, 288)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	var display := TextureRect.new()
	display.name = "PixelDisplay"
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var retro := ShaderMaterial.new()
	retro.shader = preload("res://shaders/retro.gdshader")
	display.material = retro
	add_child(display)
	var world := Node3D.new()
	world.name = "ForestWorld"
	viewport.add_child(world)
	world.add_child(preload("res://scenes/forest.tscn").instantiate())
	ladder = preload("res://scenes/ladder.tscn").instantiate()
	ladder.name = "Ladder"
	world.add_child(ladder)
	if ResourceLoader.exists(RIG_SCENE):
		rig = load(RIG_SCENE).instantiate()
	else:
		rig = MonkeyRig.new()
	rig.name = "MonkeyRig"
	world.add_child(rig)
	controller = MonkeyClimbController.new()
	controller.name = "ClimbStateMachine"
	add_child(controller)
	controller.setup(rig, ladder)
	body = MonkeyBodyPose.new()
	body.name = "BodyAndExpression"
	body.controller = controller
	body.rig = rig
	rig.skeleton.add_child(body)
	for limb: String in MonkeyClimbController.LIMBS:
		var solver := MonkeyLimbIK.new()
		solver.name = limb + "_TwoBoneIK"
		solver.setup(rig, controller, limb)
		rig.skeleton.add_child(solver)
		solvers.append(solver)
	camera = preload("res://scenes/camera.tscn").instantiate()
	camera.name = "FollowCamera"
	camera.controller = controller
	world.add_child(camera)
	achievement_toast = AchievementToast.new()
	achievement_toast.name = "AchievementOverlay"
	achievement_toast.profile = preload("res://resources/achievement_profile.tres")
	viewport.add_child(achievement_toast)
	achievements = MonkeyAchievements.new()
	achievements.name = "ClimbAchievements"
	world.add_child(achievements)
	achievements.setup(controller, body, ladder, achievement_toast, solvers[-1])
	if "--verify" in args or "--capture" in args:
		var harness: Node = load("res://tools/verification.gd").new()
		harness.game = self
		harness.capture_only = "--capture" in args
		add_child(harness)
	if "--verify-rewards" in args or "--capture-rewards" in args:
		var rewards_harness: Node = load("res://tools/reward_verification.gd").new()
		rewards_harness.game = self
		rewards_harness.capture_images = "--capture-rewards" in args
		add_child(rewards_harness)
