extends Node3D
class_name Weapon
## 武器系统：多武器切换 + 射击逻辑
##
## 职责划分：
##   * 本文件  —— 弹药、射速、换弹、射线命中、切枪流程（"逻辑"）
##   * WeaponView（子节点）—— 模型、机械骨骼动画、整枪姿态（"画面"）
##   * WeaponData —— 每把枪的数值与动作时间轴（"数据"）
##
## 三把枪的手感差异不是靠改代码，而是靠 weapon_data.gd 里的数值：
## 步枪中庸、冲锋枪快而散、霰弹枪一发多弹丸、手枪慢而准而疼。

signal ammo_changed(magazine: int, reserve: int)
## 切枪完成（index 从 0 开始）。
signal weapon_changed(index: int, display_name: String)
signal reload_started(duration: float)
signal reload_finished()
signal hit_target(is_enemy: bool)

# ---- 换弹时丢弃弹匣里剩余子弹会被这个小常数惩罚，鼓励玩家打空再换 ----
## 换弹过程前 12% 时间内取消，不消耗备弹（手感上"刚动手就反悔"）。
const CANCEL_GRACE := 0.12

@onready var _player: Player = _find_player()

var _weapons: Array[WeaponData] = []
var _view: WeaponView

## 每把枪独立的弹药状态，下标和 _weapons 对齐。
var _magazines: Array[int] = []
var _reserves: Array[int] = []
var _index := 0

var _fire_cooldown := 0.0
var _reload_timer := 0.0
var _is_reloading := false
var _reload_total := 0.0
var _spread := 0.0
var _enabled := true
## 上一帧扳机是否按着。半自动武器靠它把"按住"变成"一次一扣"。
var _trigger_held := false

var _muzzle_flash: MeshInstance3D
var _muzzle_flash_timer := 0.0


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	# 本节点的 transform 交给 WeaponView 全权管理，自己保持在相机原点。
	transform = Transform3D()

	_weapons = WeaponData.build_all()
	for weapon_data in _weapons:
		_magazines.append(weapon_data.magazine_size)
		_reserves.append(weapon_data.reserve_ammo)

	_view = WeaponView.new()
	_view.name = "View"
	add_child(_view)

	_build_muzzle_flash()
	_equip(0, false)
	_spread = current().spread_base
	ammo_changed.emit(get_magazine(), get_reserve())


func _find_player() -> Player:
	var node := get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


# =============================================================================
# 查询
# =============================================================================

func current() -> WeaponData:
	return _weapons[_index]


func weapon_count() -> int:
	return _weapons.size()


func get_weapon_index() -> int:
	return _index


func get_weapon_name() -> String:
	return current().display_name


func get_magazine() -> int:
	return _magazines[_index]


func get_reserve() -> int:
	return _reserves[_index]


func get_spread() -> float:
	return _spread


func is_reloading() -> bool:
	return _is_reloading


func get_reload_progress() -> float:
	if not _is_reloading or _reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - _reload_timer / _reload_total, 0.0, 1.0)


# =============================================================================
# 每帧
# =============================================================================

func _process(delta: float) -> void:
	_tick_timers(delta)

	var speed_ratio := 0.0
	if _player != null:
		speed_ratio = _player.get_horizontal_speed() / GameConfig.MOVE_SPEED

	_view.update(delta, speed_ratio, get_reload_progress() if _is_reloading else -1.0)
	_update_spread(delta)
	_update_muzzle_flash()

	# 切枪输入统一走 InputMap 动作，键盘数字键和触屏按钮都能触发。
	if _enabled and _player != null and not _player.is_dead:
		_check_switch_input()

	# 扳机状态每帧都要更新，即使这一帧不能开火（换弹中 / 正在举枪）。
	# 否则"举枪过程中一直按着扳机"会在举完的瞬间凭空多打一发。
	var trigger_down := Input.is_action_pressed("fire")
	var trigger_pulled := trigger_down and (current().is_automatic or not _trigger_held)
	_trigger_held = trigger_down

	if not _enabled or _player == null or _player.is_dead:
		return
	if _is_reloading or not _view.is_drawn():
		return

	if trigger_pulled and _fire_cooldown <= 0.0:
		_fire()
	if Input.is_action_just_pressed("reload"):
		start_reload()


# =============================================================================
# 切枪
# =============================================================================

## 切到第 index 把枪。begin_draw=true 时播放举枪动作。
func switch_to(index: int) -> void:
	if _weapons.is_empty():
		return
	var wrapped := posmod(index, _weapons.size())
	if wrapped == _index and _view.is_drawn():
		return
	_equip(wrapped, true)


## 切下一把枪（触屏的"换枪"按钮用）。
func switch_next() -> void:
	switch_to(_index + 1)


## 读取切枪输入：数字键 1-4 直选，滚轮 / Q 键循环。
func _check_switch_input() -> void:
	if Input.is_action_just_pressed("weapon_next"):
		switch_next()
		return
	if Input.is_action_just_pressed("weapon_prev"):
		switch_to(_index - 1)
		return
	for i in _weapons.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_to(i)
			return


func _equip(index: int, animate: bool) -> void:
	# 换枪时中断换弹，但把已经装进弹匣的部分保留（不退还备弹），
	# 否则玩家可以靠切枪反复取消来刷弹药。
	if _is_reloading:
		_is_reloading = false
		reload_finished.emit()

	_index = index
	var weapon_data := current()
	_spread = weapon_data.spread_base
	_fire_cooldown = maxf(_fire_cooldown, weapon_data.fire_interval)

	if _view.setup(weapon_data):
		if animate:
			_view.begin_draw()
		else:
			# 开局第一次装备不需要"举枪"，直接就是举起状态
			_view.snap_drawn()
		# 立刻按当前状态摆一次姿势，避免新枪以默认姿势闪一帧
		_view.update(0.0, 0.0, -1.0)

	weapon_changed.emit(_index, weapon_data.display_name)
	ammo_changed.emit(get_magazine(), get_reserve())


func set_enabled(value: bool) -> void:
	_enabled = value
	if _view != null:
		_view.set_ready(value)


# =============================================================================
# 开火
# =============================================================================

func _fire() -> void:
	var weapon_data := current()

	if get_magazine() <= 0:
		# 空仓自动换弹，手机上少按一次按钮。
		start_reload()
		return

	_magazines[_index] -= 1
	_fire_cooldown = weapon_data.fire_interval
	ammo_changed.emit(get_magazine(), get_reserve())

	# ---- 视觉与手感反馈 ----
	_view.add_recoil_kick()
	_view.play_fire()
	_show_muzzle_flash()
	_recoil_for_player(weapon_data)

	# ---- 弹道 ----
	var hits_enemy := false
	for i in weapon_data.pellets:
		if _fire_one_pellet(weapon_data):
			hits_enemy = true
	hit_target.emit(hits_enemy)

	_spread = minf(_spread + weapon_data.spread_per_shot, weapon_data.spread_max)


func _recoil_for_player(weapon_data: WeaponData) -> void:
	if _player == null:
		return
	_player.add_recoil(
		weapon_data.recoil_pitch * (0.7 + randf() * 0.6),
		randf_range(-weapon_data.recoil_yaw, weapon_data.recoil_yaw)
	)


## 打出一颗弹丸。返回是否命中敌人。
func _fire_one_pellet(weapon_data: WeaponData) -> bool:
	var camera := _get_camera()
	if camera == null:
		return false

	var origin := camera.global_position
	var direction := _direction_with_spread(camera, _spread)
	var target := origin + direction * weapon_data.max_range

	# 只打世界和敌人两层：掩体和敌人。
	var mask := GameConfig.LAYER_WORLD | GameConfig.LAYER_ENEMY
	var query := PhysicsRayQueryParameters3D.create(origin, target, mask, [_player.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false

	var hit_position: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var collider: Object = result["collider"]
	var distance: float = origin.distance_to(hit_position)

	var is_enemy := collider is Enemy
	if is_enemy:
		(collider as Enemy).take_damage(
			damage_at_distance(weapon_data, distance), hit_position, direction)

	_spawn_impact(hit_position, hit_normal, is_enemy)
	return is_enemy


## 在准星方向上加一个圆锥内的随机偏移。
func _direction_with_spread(camera: Camera3D, spread: float) -> Vector3:
	var basis := camera.global_transform.basis
	var forward := -basis.z
	if spread <= 0.0:
		return forward.normalized()

	var angle := randf() * TAU
	# sqrt 让散布在圆面上均匀分布，而不是挤在圆心。
	var radius := sqrt(randf()) * spread
	var offset := basis.x * cos(angle) + basis.y * sin(angle)
	return (forward + offset * tan(radius)).normalized()


## 距离伤害衰减。霰弹枪的衰减曲线比步枪陡得多（见 weapon_data.gd）。
func damage_at_distance(weapon_data: WeaponData, distance: float) -> int:
	if distance <= weapon_data.falloff_start:
		return weapon_data.damage
	if distance >= weapon_data.falloff_end:
		return int(round(weapon_data.damage * weapon_data.falloff_min_mult))
	var t := (distance - weapon_data.falloff_start) \
		/ (weapon_data.falloff_end - weapon_data.falloff_start)
	return int(round(weapon_data.damage * lerpf(1.0, weapon_data.falloff_min_mult, t)))


func _get_camera() -> Camera3D:
	var node := get_parent()
	if node is Camera3D:
		return node as Camera3D
	return get_viewport().get_camera_3d()


# =============================================================================
# 换弹
# =============================================================================

func start_reload() -> void:
	var weapon_data := current()
	if _is_reloading or get_magazine() >= weapon_data.magazine_size or get_reserve() <= 0:
		return
	_is_reloading = true
	_reload_total = weapon_data.reload_time
	_reload_timer = _reload_total
	_view.play_reload(weapon_data.reload_time)
	reload_started.emit(_reload_total)


## 补给弹药（波次开始时调用）。所有武器都补满。
func refill_ammo() -> void:
	for i in _weapons.size():
		_magazines[i] = _weapons[i].magazine_size
		_reserves[i] = _weapons[i].reserve_ammo
	ammo_changed.emit(get_magazine(), get_reserve())


# =============================================================================
# 计时器 / 散布 / 枪口火光
# =============================================================================

func _tick_timers(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	if not _is_reloading:
		return

	_reload_timer -= delta
	if _reload_timer > 0.0:
		return

	# 换弹完成：从备弹里补满弹匣。
	_is_reloading = false
	var weapon_data := current()
	var needed := weapon_data.magazine_size - get_magazine()
	var taken := mini(needed, get_reserve())
	_magazines[_index] += taken
	_reserves[_index] -= taken
	ammo_changed.emit(get_magazine(), get_reserve())
	reload_finished.emit()


func _update_spread(delta: float) -> void:
	var weapon_data := current()
	var target := weapon_data.spread_base
	if _player != null:
		target += _player.get_horizontal_speed() * weapon_data.spread_move_factor
		if not _player.is_on_floor():
			target += weapon_data.spread_base * 2.7
	target = minf(target, weapon_data.spread_max)

	# 只回落，不在这里增长（增长在开火时做）。
	if _spread > target:
		_spread = maxf(target, _spread - weapon_data.spread_recovery * delta * weapon_data.spread_max)
	else:
		_spread = target


func _build_muzzle_flash() -> void:
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1.0, 0.86, 0.5, 0.95)
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.disable_receive_shadows = true

	_muzzle_flash = MeshInstance3D.new()
	_muzzle_flash.name = "MuzzleFlash"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	_muzzle_flash.mesh = quad
	_muzzle_flash.material_override = flash_material
	_muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_flash.visible = false
	# 挂在 View 下，位置每帧从模型的枪口骨骼同步过来。
	_view.add_child(_muzzle_flash)


func _show_muzzle_flash() -> void:
	_muzzle_flash_timer = 0.045
	_muzzle_flash.visible = true
	_update_muzzle_flash()


## 把火光贴到模型真实的枪口骨骼上（比写死坐标更准）。
func _update_muzzle_flash() -> void:
	if _muzzle_flash == null or not _muzzle_flash.visible:
		return
	if _view != null:
		_muzzle_flash.global_transform = _view.get_muzzle_transform()


# =============================================================================
# 命中特效
# =============================================================================

func _spawn_impact(hit_position: Vector3, hit_normal: Vector3, is_enemy: bool) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	# 弹孔特效自己管生命周期（见 impact.gd），打一枪一个，用完自己回收。
	var impact := Impact.new()
	host.add_child(impact)
	impact.setup(hit_position, hit_normal, is_enemy)
