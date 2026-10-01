extends CharacterBody3D
class_name Enemy
## 敌人：骨骼角色 + 追击 AI + 近身挥剑
##
## ── 相比第一版的变化 ──
## 外观从「代码搭的胶囊 + 发光球」换成了 CC0 骨骼角色（KayKit Adventurers），
## 并且有真的动画：待机、奔跑、挥剑、受击、倒地。
## 追击逻辑本身没变 —— 仍然是直线朝玩家走，靠物理碰撞绕开箱子，
## 所以关卡随便改都不用重新烘焙导航网格。
##
## ── 动画与逻辑怎么对上 ──
##   * 奔跑动画的播放速度跟着实际移动速度走，脚不打滑
##   * 挥剑伤害不是在开始挥的时候结算，而是在动画进度 45% 那一帧结算，
##     这样"看到剑砍到身上才掉血"，而不是一抬手就掉血
##   * 受击播 Hit_A 并短暂僵直，形成"打中了有反馈"的手感

signal died(enemy: Enemy)

# ---- 可调参数 ----
const MAX_HEALTH_BASE := 60
const HEALTH_PER_WAVE := 14          ## 每波增加的血量
const MOVE_SPEED := 3.3
const ACCEL := 9.0
const GRAVITY := 22.0
const ATTACK_RANGE := 2.1
const ATTACK_DAMAGE := 11
const ATTACK_INTERVAL := 1.45        ## 两次挥剑之间的间隔
const TURN_SPEED := 7.0
const HEIGHT := 1.8

## 挥剑动画进行到这个比例时结算伤害（0 = 起手，1 = 收招）。
const ATTACK_IMPACT_AT := 0.45
## 受击僵直时长（秒）。
const HIT_STUN := 0.28

const MODEL_KNIGHT := "res://assets/characters/knight.glb"
const MODEL_BARBARIAN := "res://assets/characters/barbarian.glb"

enum State { CHASE, ATTACK, HIT, DEAD }

var health: int
var max_health: int
var is_dead := false

var _state: State = State.CHASE
var _player: Player
var _rig: CharacterRig
var _attack_cooldown := 0.0
var _attack_elapsed := 0.0
var _attack_duration := 1.0
var _attack_landed := false
var _stun_timer := 0.0


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

	_build_collision()
	_build_visual()

	# 出场动画：从地面"长"出来。缩放做在自身节点上，不影响 rig 内部的自适应缩放。
	scale = Vector3(0.2, 0.05, 0.2)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# =============================================================================
# 外观
# =============================================================================

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = HEIGHT
	collision.shape = capsule
	collision.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(collision)


func _build_visual() -> void:
	_rig = CharacterRig.new()
	_rig.name = "Rig"
	add_child(_rig)

	# 两种模型交替出现，让一波敌人不至于长得一模一样。
	var model_path := MODEL_KNIGHT if (max_health % 2 == 0) else MODEL_BARBARIAN
	if not _rig.setup(model_path):
		push_warning("[Enemy] 角色模型载入失败，敌人将没有外观")

	# 血量越高越偏红：玩家一眼能看出哪个更硬。
	var tier := clampf(float(max_health - MAX_HEALTH_BASE) / 90.0, 0.0, 1.0)
	_rig.set_tint(Color(1.0, 1.0 - tier * 0.30, 1.0 - tier * 0.38))

	_attach_eyes()


## 给敌人加一对发光眼睛。竞技场偏暗，靠这个在远处也能一眼看到敌人。
## 眼睛挂在模型自带的 head 骨骼挂点上，所以会跟着头部动作一起动。
func _attach_eyes() -> void:
	var host: Node3D = _rig.get_attachment("head")
	if host == null:
		host = _rig

	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.10
		eye.mesh = sphere

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.42, 0.16)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.38, 0.1)
		material.emission_energy_multiplier = 2.4
		eye.material_override = material
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# head 挂点在模型空间里，半径 0.05 是相对模型原始尺寸；
		# rig 内部会整体缩放，所以这里的偏移量也跟着一起缩。
		eye.position = Vector3(side * 0.13, 0.0, -0.16)
		host.add_child(eye)


# =============================================================================
# 每帧
# =============================================================================

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
		_rig.play_idle()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	match _state:
		State.HIT:
			_tick_hit(delta)
		State.ATTACK:
			_tick_attack(delta, to_player)
		_:
			_tick_chase(delta, to_player, distance)

	move_and_slide()

	# 面朝玩家（只转 Y 轴）。挥剑和受击时也保持朝向，不然动作会看着别扭。
	if to_player.length_squared() > 0.01:
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _tick_chase(delta: float, to_player: Vector3, distance: float) -> void:
	if distance <= ATTACK_RANGE and _attack_cooldown <= 0.0:
		_enter_attack()
		return

	if distance > ATTACK_RANGE * 0.75:
		_steer(to_player.normalized(), delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * 2.0 * delta)

	# 奔跑动画速度跟着实际速度走，快跑时腿摆得也快。
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if horizontal > 0.25:
		_rig.play_run(clampf(horizontal / MOVE_SPEED, 0.5, 1.6))
	else:
		_rig.play_idle()


func _tick_attack(delta: float, to_player: Vector3) -> void:
	# 出招时站定，只保留很小的前冲。
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * 3.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, ACCEL * 3.0 * delta)

	_attack_elapsed += delta
	var progress := _attack_elapsed / _attack_duration

	# 伤害在挥到身上的那一刻结算，而不是一起手就结算。
	if not _attack_landed and progress >= ATTACK_IMPACT_AT:
		_attack_landed = true
		_land_attack(to_player)

	if _attack_elapsed >= _attack_duration:
		_state = State.CHASE


func _tick_hit(delta: float) -> void:
	_stun_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, ACCEL * 4.0 * delta)
	if _stun_timer <= 0.0:
		_state = State.CHASE


func _enter_attack() -> void:
	_state = State.ATTACK
	_attack_elapsed = 0.0
	_attack_landed = false
	_attack_duration = 0.9 if _rig == null else _rig.get_attack_length()
	_rig.play_attack()


## 真正把伤害打出去。
func _land_attack(to_player: Vector3) -> void:
	_attack_cooldown = ATTACK_INTERVAL + _attack_duration

	if _player == null or _player.is_dead:
		return
	if to_player.length() > ATTACK_RANGE * 1.35:
		# 挥剑过程中玩家跑开了就落空 —— 会走位是能躲的。
		return

	_player.take_damage(ATTACK_DAMAGE)
	_player.add_camera_shake(0.05)
	# 命中时向前一顶，给玩家一个"被打"的视觉反馈。
	velocity += -global_transform.basis.z * 1.2


func _steer(direction: Vector3, delta: float) -> void:
	var target := direction * MOVE_SPEED
	velocity.x = lerpf(velocity.x, target.x, clampf(ACCEL * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target.z, clampf(ACCEL * delta, 0.0, 1.0))


# =============================================================================
# 受击与死亡
# =============================================================================

func take_damage(amount: int, _hit_position: Vector3, hit_direction: Vector3) -> void:
	if is_dead:
		return

	health -= amount
	if _rig != null:
		_rig.flash()

	if health <= 0:
		_die()
		return

	# 中弹后退一点，让射击有推背感。
	var push := -hit_direction
	push.y = 0.0
	velocity += push.normalized() * 0.9

	# 打断出招并僵直，让连射有"压制感"。
	_state = State.HIT
	_stun_timer = HIT_STUN
	_rig.play_hit()

	# 闪白只持续很短，用计时器还原。
	var timer := get_tree().create_timer(0.09, false, false, true)
	timer.timeout.connect(_restore_tint_if_alive)


func _restore_tint_if_alive() -> void:
	if not is_dead and _rig != null:
		_rig.restore_tint()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_state = State.DEAD
	remove_from_group("enemies")

	# 关掉碰撞，尸体不再挡路。
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)

	if _rig != null:
		_rig.play_death()

	died.emit(self)

	# 倒地后沉入地面再回收。死亡动画本身约 0.8 秒，先让它播完。
	var tween := create_tween()
	tween.tween_interval(0.75)
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 0.6, 0.5)
	tween.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
