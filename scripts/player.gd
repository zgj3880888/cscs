extends CharacterBody3D
class_name Player
## 第一人称玩家控制器
##
## 设计要点：
##   * 移动/视角有两套输入源，互不干扰：
##       - 桌面：WASD + 鼠标（MOUSE_MODE_CAPTURED 锁定鼠标）
##       - 手机：左半屏虚拟摇杆（touch_move）+ 右半屏拖拽（add_look_delta）
##     两种输入都最终走 InputMap 动作（fire / jump / reload），
##     所以武器和移动逻辑不用关心玩家用的是手机还是电脑。
##
##   * 视角旋转：本体（CharacterBody3D）只转 Y 轴（水平），
##     抬头低头在 Head 节点上做，这样碰撞体永远是竖直的，不会歪。

## 血量变化（当前值, 上限）
signal health_changed(current: int, maximum: int)
## 受到伤害（供 UI 做红屏闪烁）
signal damaged(amount: int)
## 玩家死亡
signal died()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/Weapon

## 摇杆输入（-1..1）。由触屏控件写入；为零时回退到键盘/手柄。
var touch_move := Vector2.ZERO

var health: int = GameConfig.PLAYER_MAX_HEALTH
var is_dead := false

## 本帧累积的视角增量（像素）。桌面鼠标和触屏拖拽都往这里加，
## 统一在 _process 里消费掉，保证两种设备的视角手感一致。
var _look_delta := Vector2.ZERO

var _pitch := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _head_base_y := 0.0
var _bob_time := 0.0
var _time_since_damage := 999.0
var _shake_amount := 0.0


func _ready() -> void:
	# 触屏控件和主控脚本都靠这个组来找玩家。
	add_to_group("player")

	# 碰撞层：自己在 PLAYER 层；和世界、敌人发生碰撞。
	collision_layer = GameConfig.LAYER_PLAYER
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_ENEMY

	# 贴地吸附，避免走下小台阶时"跳一下"。
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)

	_head_base_y = head.position.y
	camera.fov = GameConfig.CAMERA_FOV

	health = GameConfig.PLAYER_MAX_HEALTH
	health_changed.emit(health, GameConfig.PLAYER_MAX_HEALTH)

	_setup_mouse_mode()


func _setup_mouse_mode() -> void:
	# 只在桌面锁定鼠标指针；手机上不涉及这个概念。
	if OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =============================================================================
# 输入
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# 启用触屏控件时（手机上），视角由触屏层负责，这里不处理鼠标，
	# 否则鼠标和手指会同时转视角。
	if GameConfig.should_use_touch_controls():
		return

	# 桌面：鼠标相对位移直接累积。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += (event as InputEventMouseMotion).relative
		return

	# 桌面：ESC 释放鼠标（暂停由 main.gd 处理）。
	if event.is_action_pressed("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 供触屏控件调用：往视角里注入一段像素位移。
func add_look_delta(delta_px: Vector2) -> void:
	if is_dead:
		return
	_look_delta += delta_px


## 供武器调用：开火后坐力（弧度）。
func add_recoil(pitch_amount: float, yaw_amount: float) -> void:
	_recoil_pitch += pitch_amount
	_recoil_yaw += yaw_amount


## 供敌人/爆炸调用：屏幕震动。
func add_camera_shake(amount: float) -> void:
	_shake_amount = minf(_shake_amount + amount, 0.5)


# =============================================================================
# 每帧逻辑
# =============================================================================

func _process(delta: float) -> void:
	if not is_dead:
		_apply_look(delta)
		_regenerate_health(delta)

	_recover_recoil(delta)
	_apply_head_bob(delta)
	_apply_camera_shake(delta)


func _physics_process(delta: float) -> void:
	_apply_movement(delta)


# ---------------------------------------------------------------------------
# 视角
# ---------------------------------------------------------------------------

func _apply_look(delta: float) -> void:
	if _look_delta == Vector2.ZERO:
		return

	# 灵敏度：基础值 x 玩家在设置里调的倍率。
	var base := GameConfig.MOUSE_SENSITIVITY
	if OS.has_feature("mobile") or GameConfig.FORCE_TOUCH_CONTROLS:
		base = GameConfig.TOUCH_LOOK_SENSITIVITY
	var sens := base * GameState.sensitivity_scale

	# 水平：转本体。注意鼠标右移应该是视角右转 → 减去。
	rotate_y(-_look_delta.x * sens)

	# 垂直：只动 Head，不动碰撞体。
	_pitch = clampf(_pitch - _look_delta.y * sens, -GameConfig.PITCH_LIMIT, GameConfig.PITCH_LIMIT)

	_look_delta = Vector2.ZERO


func _recover_recoil(delta: float) -> void:
	# 后坐力指数回落，手感比线性更自然。
	var recover := 1.0 - exp(-12.0 * delta)
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, recover)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, recover)

	head.rotation.x = _pitch + _recoil_pitch
	head.rotation.y = _recoil_yaw


func _apply_head_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := clampf(horizontal_speed / GameConfig.MOVE_SPEED, 0.0, 1.6)

	if is_on_floor() and speed_ratio > 0.12:
		_bob_time += delta * GameConfig.HEAD_BOB_FREQUENCY * speed_ratio
	else:
		# 停下时轻微回中，而不是硬切。
		_bob_time = lerpf(_bob_time, 0.0, 1.0 - exp(-8.0 * delta))

	var bob := sin(_bob_time) * GameConfig.HEAD_BOB_AMPLITUDE * minf(speed_ratio, 1.0)
	head.position.y = _head_base_y + bob


func _apply_camera_shake(delta: float) -> void:
	if _shake_amount <= 0.0001:
		return
	_shake_amount = lerpf(_shake_amount, 0.0, 1.0 - exp(-9.0 * delta))
	# 随机抖动直接叠加在 FOV 和倾角上，简单但有效。
	head.rotation.z = randf_range(-_shake_amount, _shake_amount) * 0.35


# ---------------------------------------------------------------------------
# 移动
# ---------------------------------------------------------------------------

func _apply_movement(delta: float) -> void:
	if is_dead:
		# 死亡后只保留重力和摩擦，让摄像机自然下落。
		velocity.x = move_toward(velocity.x, 0.0, GameConfig.GROUND_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, GameConfig.GROUND_FRICTION * delta)
		velocity.y -= GameConfig.GRAVITY * delta
		move_and_slide()
		return

	# 1) 重力
	if not is_on_floor():
		velocity.y -= GameConfig.GRAVITY * delta

	# 2) 跳跃
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = GameConfig.JUMP_VELOCITY

	# 3) 水平移动
	var wish_input := _read_move_input()
	var wish_dir := global_transform.basis * Vector3(wish_input.x, 0.0, wish_input.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized()

	var sprinting := Input.is_action_pressed("sprint") and wish_input.length() > 0.3
	var speed := GameConfig.MOVE_SPEED * (GameConfig.SPRINT_MULTIPLIER if sprinting else 1.0)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir.length_squared() > 0.001:
		var rate := GameConfig.GROUND_ACCEL
		if not is_on_floor():
			rate *= GameConfig.AIR_CONTROL
		horizontal = horizontal.lerp(wish_dir * speed, clampf(rate * delta, 0.0, 1.0))
	elif is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, GameConfig.GROUND_FRICTION * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# 4) 交给物理引擎
	move_and_slide()


## 读取移动输入。触屏摇杆有输入时优先用摇杆，否则用键盘/手柄。
func _read_move_input() -> Vector2:
	if touch_move.length() > 0.15:
		return touch_move.limit_length(1.0)

	var input := Vector2.ZERO
	input.x = Input.get_axis("move_left", "move_right")
	input.y = Input.get_axis("move_forward", "move_back")
	return input.limit_length(1.0)


## 当前水平速度（米/秒），武器用它决定散布。
func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# ---------------------------------------------------------------------------
# 生命值
# ---------------------------------------------------------------------------

func _regenerate_health(delta: float) -> void:
	_time_since_damage += delta
	if health >= GameConfig.PLAYER_MAX_HEALTH:
		return
	if _time_since_damage < GameConfig.HEALTH_REGEN_DELAY:
		return
	health = mini(health + int(ceil(GameConfig.HEALTH_REGEN_RATE * delta)), GameConfig.PLAYER_MAX_HEALTH)
	health_changed.emit(health, GameConfig.PLAYER_MAX_HEALTH)


func take_damage(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	health = maxi(0, health - amount)
	_time_since_damage = 0.0
	add_camera_shake(0.06)
	damaged.emit(amount)
	health_changed.emit(health, GameConfig.PLAYER_MAX_HEALTH)
	if health <= 0:
		_die()


func heal_full() -> void:
	health = GameConfig.PLAYER_MAX_HEALTH
	health_changed.emit(health, GameConfig.PLAYER_MAX_HEALTH)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	if weapon != null:
		weapon.set_enabled(false)
	died.emit()
