extends Node3D
class_name Weapon
## 枪械 / 射击系统
##
## 功能：
##   * 射线命中检测（hitscan），带随移动/跳跃/连射增长的散布
##   * 弹匣 + 备弹 + 换弹，射速限制，按住自动连发
##   * 后坐力（交给 Player 施加到视角上）
##   * 枪口火光、命中弹孔、命中火花
##   * 距离伤害衰减
##
## 视角模型（枪的模型）是用代码搭的方块，不依赖任何外部模型文件，
## 这样工程 clone 下来就能直接跑，不用配资源导入。

signal ammo_changed(mag: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished()
signal hit_target(is_enemy: bool)

# ---- 可调参数 ----
const MAG_SIZE := 30
const RESERVE_AMMO := 240
const FIRE_INTERVAL := 0.095          ## 两发之间最小间隔（秒），约 630 发/分
const RELOAD_TIME := 1.55             ## 换弹耗时（秒）
const DAMAGE := 24                    ## 基础伤害
const MAX_RANGE := 120.0              ## 最大射程（米）
const FALLOFF_START := 28.0           ## 超过这个距离开始衰减
const FALLOFF_END := 80.0             ## 到这个距离衰减到最小值
const FALLOFF_MIN_MULT := 0.45        ## 最小伤害倍率

const SPREAD_BASE := 0.0045           ## 静止时的基础散布（弧度）
const SPREAD_PER_SHOT := 0.0032       ## 每开一枪增加
const SPREAD_MAX := 0.055             ## 散布上限
const SPREAD_RECOVERY := 3.2          ## 散布回落速度
const SPREAD_MOVE_FACTOR := 0.010     ## 移动带来的额外散布

const RECOIL_PITCH := 0.010           ## 每发上抬（弧度）
const RECOIL_YAW_RANGE := 0.005       ## 每发左右随机（弧度）

@onready var _player: Player = _find_player()

var magazine: int = MAG_SIZE
var reserve: int = RESERVE_AMMO

var _fire_cooldown := 0.0
var _reload_timer := 0.0
var _is_reloading := false
var _spread := SPREAD_BASE
var _enabled := true

# 视角模型动画状态
var _viewmodel_home := Vector3.ZERO
var _kick := 0.0
var _muzzle_flash: MeshInstance3D
var _muzzle_flash_timer := 0.0


func _ready() -> void:
	_viewmodel_home = position
	_build_viewmodel()
	ammo_changed.emit(magazine, reserve)


func _find_player() -> Player:
	var node := get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


func _process(delta: float) -> void:
	_tick_timers(delta)
	_update_spread(delta)
	_update_viewmodel(delta)

	if not _enabled or _player == null or _player.is_dead:
		return

	if _is_reloading:
		return

	# 按住自动连发；按 R 换弹。
	if Input.is_action_pressed("fire") and _fire_cooldown <= 0.0:
		_fire()
	if Input.is_action_just_pressed("reload"):
		start_reload()


# =============================================================================
# 对外接口
# =============================================================================

func set_enabled(value: bool) -> void:
	_enabled = value


## 当前散布（弧度）。准星用它来决定张开多少。
func get_spread() -> float:
	return _spread


## 是否正在换弹，以及换弹进度（0..1）。给 UI 画进度条用。
func get_reload_progress() -> float:
	if not _is_reloading:
		return 1.0
	return clampf(1.0 - _reload_timer / RELOAD_TIME, 0.0, 1.0)


func is_reloading() -> bool:
	return _is_reloading


func get_magazine() -> int:
	return magazine


func get_reserve() -> int:
	return reserve


func start_reload() -> void:
	if _is_reloading or magazine >= MAG_SIZE or reserve <= 0:
		return
	_is_reloading = true
	_reload_timer = RELOAD_TIME
	reload_started.emit(RELOAD_TIME)


## 补给弹药（比如波次间隔时调用）。
func refill_ammo() -> void:
	magazine = MAG_SIZE
	reserve = RESERVE_AMMO
	ammo_changed.emit(magazine, reserve)


# =============================================================================
# 开火
# =============================================================================

func _fire() -> void:
	if magazine <= 0:
		# 空仓自动换弹，手机上少按一次按钮。
		start_reload()
		return

	magazine -= 1
	_fire_cooldown = FIRE_INTERVAL
	ammo_changed.emit(magazine, reserve)

	_muzzle_flash_timer = 0.045
	if _muzzle_flash != null:
		_muzzle_flash.visible = true

	# 枪的后坐动画 + 玩家视角上抬
	_kick = minf(_kick + 0.035, 0.075)
	_recoil_for_player()

	_perform_raycast()
	_spread = minf(_spread + SPREAD_PER_SHOT, SPREAD_MAX)


func _recoil_for_player() -> void:
	if _player == null:
		return
	_player.add_recoil(
		RECOIL_PITCH * (0.7 + randf() * 0.6),
		randf_range(-RECOIL_YAW_RANGE, RECOIL_YAW_RANGE)
	)


func _perform_raycast() -> void:
	var camera := _get_camera()
	if camera == null:
		return

	var origin := camera.global_position
	var direction := _direction_with_spread(camera)
	var target := origin + direction * MAX_RANGE

	# 只打世界和敌人两层：掩体和敌人。
	var mask := GameConfig.LAYER_WORLD | GameConfig.LAYER_ENEMY
	var query := PhysicsRayQueryParameters3D.create(origin, target, mask, [_player.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_position: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var collider: Object = result["collider"]
	var distance: float = origin.distance_to(hit_position)

	var is_enemy := collider is Enemy
	if is_enemy:
		var damage := _damage_at_distance(distance)
		(collider as Enemy).take_damage(damage, hit_position, direction)
		hit_target.emit(true)
	else:
		hit_target.emit(false)

	_spawn_impact(hit_position, hit_normal, is_enemy)


## 在准星方向上加一个圆锥内的随机偏移。
func _direction_with_spread(camera: Camera3D) -> Vector3:
	var basis := camera.global_transform.basis
	var forward := -basis.z
	if _spread <= 0.0:
		return forward.normalized()

	var angle := randf() * TAU
	# sqrt 让散布在圆面上均匀分布，而不是挤在圆心。
	var radius := sqrt(randf()) * _spread
	var offset := basis.x * cos(angle) + basis.y * sin(angle)
	return (forward + offset * tan(radius)).normalized()


func _damage_at_distance(distance: float) -> int:
	if distance <= FALLOFF_START:
		return DAMAGE
	if distance >= FALLOFF_END:
		return int(round(DAMAGE * FALLOFF_MIN_MULT))
	var t := (distance - FALLOFF_START) / (FALLOFF_END - FALLOFF_START)
	return int(round(DAMAGE * lerpf(1.0, FALLOFF_MIN_MULT, t)))


func _get_camera() -> Camera3D:
	var node := get_parent()
	if node is Camera3D:
		return node as Camera3D
	return get_viewport().get_camera_3d()


# =============================================================================
# 计时器与散布
# =============================================================================

func _tick_timers(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer -= delta
		if _muzzle_flash_timer <= 0.0 and _muzzle_flash != null:
			_muzzle_flash.visible = false

	if not _is_reloading:
		return
	_reload_timer -= delta
	if _reload_timer > 0.0:
		return

	# 换弹完成：从备弹里补满弹匣。
	_is_reloading = false
	var needed := MAG_SIZE - magazine
	var taken := mini(needed, reserve)
	magazine += taken
	reserve -= taken
	ammo_changed.emit(magazine, reserve)
	reload_finished.emit()


func _update_spread(delta: float) -> void:
	var target := SPREAD_BASE
	if _player != null:
		target += _player.get_horizontal_speed() * SPREAD_MOVE_FACTOR
		if not _player.is_on_floor():
			target += 0.012
	# 只回落，不在这里增长（增长在开火时做）。
	if _spread > target:
		_spread = maxf(target, _spread - SPREAD_RECOVERY * delta * SPREAD_MAX)
	else:
		_spread = target


func _update_viewmodel(delta: float) -> void:
	# 后坐：枪往后退，然后归位。
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-16.0 * delta))
	position = _viewmodel_home + Vector3(0.0, _kick * 0.25, _kick)

	# 走动时轻微摆动，增强"手里有东西"的感觉。
	if _player != null:
		var sway := sin(_player.get_horizontal_speed() * 1.6) * 0.006
		position += Vector3(sway, absf(sway) * 0.5, 0.0)


# =============================================================================
# 视角模型（代码搭建，无需外部模型文件）
# =============================================================================

func _build_viewmodel() -> void:
	var body := _box(Vector3(0.075, 0.115, 0.34), Color(0.14, 0.145, 0.16))
	body.position = Vector3.ZERO
	add_child(body)

	var barrel := _box(Vector3(0.038, 0.038, 0.30), Color(0.09, 0.095, 0.105))
	barrel.position = Vector3(0.0, 0.022, -0.29)
	add_child(barrel)

	var handguard := _box(Vector3(0.055, 0.055, 0.12), Color(0.2, 0.205, 0.22))
	handguard.position = Vector3(0.0, 0.008, -0.18)
	add_child(handguard)

	var magazine := _box(Vector3(0.055, 0.17, 0.075), Color(0.18, 0.185, 0.2))
	magazine.position = Vector3(0.0, -0.13, 0.02)
	magazine.rotation_degrees = Vector3(12.0, 0.0, 0.0)
	add_child(magazine)

	var grip := _box(Vector3(0.05, 0.12, 0.06), Color(0.16, 0.165, 0.18))
	grip.position = Vector3(0.0, -0.085, 0.13)
	grip.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	add_child(grip)

	var sight := _box(Vector3(0.03, 0.05, 0.05), Color(0.22, 0.225, 0.24))
	sight.position = Vector3(0.0, 0.085, -0.06)
	add_child(sight)

	# 枪口火光：默认隐藏，开火时亮 45 毫秒。
	_muzzle_flash = MeshInstance3D.new()
	var flash_mesh := QuadMesh.new()
	flash_mesh.size = Vector2(0.16, 0.16)
	_muzzle_flash.mesh = flash_mesh
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1.0, 0.85, 0.45, 0.95)
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.disable_receive_shadows = true
	_muzzle_flash.material_override = flash_material
	_muzzle_flash.position = Vector3(0.0, 0.022, -0.46)
	_muzzle_flash.visible = false
	add_child(_muzzle_flash)


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	material.metallic = 0.35
	mesh_instance.material_override = material

	# 视角模型不能被场景光照和阴影干扰，否则在某些角度会突然变黑。
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


func _spawn_impact(hit_position: Vector3, hit_normal: Vector3, is_enemy: bool) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	# 弹孔特效自己管生命周期（见 impact.gd），打一枪一个，用完自己回收。
	var impact := Impact.new()
	host.add_child(impact)
	impact.setup(hit_position, hit_normal, is_enemy)
