extends CharacterBody3D
class_name Enemy
## 敌人：追击玩家 + 近身攻击
##
## AI 刻意做得很简单——直线朝玩家走，靠物理碰撞自己绕开箱子。
## 好处是完全不需要烘焙导航网格（NavMesh），关卡可以随便改，
## 想升级成寻路 AI 时，只要把 _steer() 里的方向换成 NavigationAgent3D 的输出。

signal died(enemy: Enemy)

# ---- 可调参数 ----
const MAX_HEALTH_BASE := 60
const HEALTH_PER_WAVE := 14          ## 每波增加的血量
const MOVE_SPEED := 3.3
const ACCEL := 9.0
const GRAVITY := 22.0
const ATTACK_RANGE := 1.9
const ATTACK_DAMAGE := 11
const ATTACK_INTERVAL := 1.15
const TURN_SPEED := 7.0
const HEIGHT := 1.8

var health: int
var max_health: int
var is_dead := false

var _player: Player
var _attack_cooldown := 0.0
var _body_material: StandardMaterial3D
var _flash_timer := 0.0


func setup(player: Player, wave_index: int) -> void:
	_player = player
	max_health = MAX_HEALTH_BASE + HEALTH_PER_WAVE * maxi(wave_index - 1, 0)
	health = max_health


func _ready() -> void:
	add_to_group("enemies")

	# 碰撞层：自己在 ENEMY 层；和世界、玩家、其他敌人碰撞。
	collision_layer = GameConfig.LAYER_ENEMY
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_PLAYER | GameConfig.LAYER_ENEMY
	floor_snap_length = 0.35

	_build_body()

	# 出场动画：从地面"长"出来。
	scale = Vector3(0.2, 0.05, 0.2)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and _body_material != null:
			_body_material.albedo_color = _body_color()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)

	if _player == null or _player.is_dead:
		# 玩家没了就停下，只保留重力。
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	_try_attack(distance)

	if distance > ATTACK_RANGE * 0.75:
		_steer(to_player.normalized(), delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * 2.0 * delta)

	move_and_slide()

	# 面朝玩家（只转 Y 轴）。
	if to_player.length_squared() > 0.01:
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _steer(direction: Vector3, delta: float) -> void:
	var target := direction * MOVE_SPEED
	velocity.x = lerpf(velocity.x, target.x, clampf(ACCEL * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target.z, clampf(ACCEL * delta, 0.0, 1.0))


func _try_attack(distance: float) -> void:
	if distance > ATTACK_RANGE or _attack_cooldown > 0.0:
		return
	_attack_cooldown = ATTACK_INTERVAL
	_player.take_damage(ATTACK_DAMAGE)
	# 攻击时向前一顶，给玩家一个"被打"的视觉反馈。
	velocity += -global_transform.basis.z * 1.4


# =============================================================================
# 受击与死亡
# =============================================================================

func take_damage(amount: int, _hit_position: Vector3, hit_direction: Vector3) -> void:
	if is_dead:
		return

	health -= amount
	_flash_timer = 0.09
	if _body_material != null:
		_body_material.albedo_color = Color(1.0, 1.0, 1.0)

	if health <= 0:
		_die()
		return

	# 中弹后退一点，让射击有推背感。
	var push := -hit_direction
	push.y = 0.0
	velocity += push.normalized() * 0.9


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	remove_from_group("enemies")

	# 关掉碰撞，尸体不再挡路。
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)

	died.emit(self)

	# 死亡动画：压扁 + 下沉，然后回收。
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.25, 0.06, 1.25), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", position.y - 0.55, 0.26)
	tween.set_parallel(false)
	tween.tween_interval(0.05)
	tween.tween_callback(queue_free)


# =============================================================================
# 外观（代码生成，无需外部模型）
# =============================================================================

func _body_color() -> Color:
	return Color(0.62, 0.16, 0.18)

func _build_body() -> void:
	# ---- 碰撞体 ----
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.42
	capsule_shape.height = HEIGHT
	collision.shape = capsule_shape
	collision.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(collision)

	# ---- 躯干 ----
	var body := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.42
	capsule_mesh.height = HEIGHT
	body.mesh = capsule_mesh

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _body_color()
	_body_material.roughness = 0.6
	_body_material.metallic = 0.15
	body.material_override = _body_material
	body.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(body)

	# ---- 发光"眼睛"：暗环境里也能看清敌人在哪 ----
	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.11
	eye_mesh.height = 0.22
	eye.mesh = eye_mesh

	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(1.0, 0.42, 0.16)
	eye_material.emission_enabled = true
	eye_material.emission = Color(1.0, 0.38, 0.1)
	eye_material.emission_energy_multiplier = 2.2
	eye.material_override = eye_material
	# 放在身体前上方（-Z 是 Godot 里的"前方"）。
	eye.position = Vector3(0.0, HEIGHT * 0.78, -0.32)
	add_child(eye)

	# ---- 肩部两个更小的灯，增加辨识度 ----
	for side: float in [-1.0, 1.0]:
		var shoulder := MeshInstance3D.new()
		var shoulder_mesh := BoxMesh.new()
		shoulder_mesh.size = Vector3(0.14, 0.07, 0.07)
		shoulder.mesh = shoulder_mesh
		var shoulder_material := StandardMaterial3D.new()
		shoulder_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shoulder_material.albedo_color = Color(1.0, 0.55, 0.2)
		shoulder.material_override = shoulder_material
		shoulder.position = Vector3(side * 0.3, HEIGHT * 0.72, -0.24)
		add_child(shoulder)
