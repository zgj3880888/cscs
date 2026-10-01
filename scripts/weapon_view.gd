extends Node3D
class_name WeaponView
## 第一人称武器视图：加载模型 + 驱动机械骨骼 + 整枪姿态动作
##
## 这一层只负责「看起来怎么样」，不开枪、不管弹药（那些在 weapon.gd）。
##
## ── 两层动画 ──
##
## 1) 机械动作（骨骼级）
##    模型自带骨骼，枪机、拉机柄、弹匣、套筒、泵这些是独立骨骼。
##    按 weapon_data.gd 里的时间轴去推这些骨骼，所以能看到零件真的在动。
##
##    难点是骨骼的局部坐标轴各不相同（实测：Body 的局部 Y 轴指向枪口，
##    Magazine 的局部 Z 轴指向枪口……）。所以位移方向不能直接当成局部方向用，
##    要先把「模型空间的方向」换算到「父骨骼空间」：
##        local_dir = 父骨骼静止基向量的逆 × 模型空间方向
##    这样一套代码适配所有骨骼，不用给每根骨骼手工配轴。
##
## 2) 整枪姿态（节点级）
##    呼吸晃动、走动摇摆、视角拖拽滞后、开火后坐、换弹下沉、切枪举起/收起。
##    这些直接作用在本节点的 transform 上。

# ---- 整枪动作参数（想调手感改这里）----
## 待机呼吸晃动幅度（米）与频率。
const IDLE_SWAY_AMPLITUDE := 0.0022
const IDLE_SWAY_FREQUENCY := 1.35
## 走动摇摆幅度（米）与频率倍率。
const BOB_AMPLITUDE := 0.011
const BOB_FREQUENCY := 1.55
## 视角拖拽时枪的滞后幅度（米 / 弧度）。
const LOOK_LAG_POS := 0.075
## 视角拖拽时枪的偏转幅度（度 / 弧度）。
const LOOK_LAG_ROT := 30.0
## 换弹时枪下沉多少（米）与下倾多少（度）。
const RELOAD_DROP := 0.150
const RELOAD_TILT := 24.0
const RELOAD_ROLL := 14.0
## 切枪时枪从画面外升起来的距离（米）与角度（度）。
const DRAW_DROP := 0.320
const DRAW_TILT := 34.0
## 开火后坐的回落速度。
const RECOIL_RECOVERY := 15.0

var data: WeaponData

var _model: Node3D
var _skeleton: Skeleton3D
var _muzzle_attachment: Node3D
var _bone_index := {}          ## 骨骼名 -> 索引
var _rest := {}                ## 骨骼名 -> 父空间静止变换
var _parent_basis := {}        ## 骨骼名 -> 父骨骼在骨架空间的静止基向量

# 机械动作播放状态
var _anim := {}
var _anim_time := 0.0
var _anim_length := 0.0
var _anim_bones: Array[String] = []
## 换弹时间轴按实际换弹时长拉伸的倍率（时间轴是照 2 秒写的，
## 换弹改成 3 秒时动作会自动跟着放慢，不用再改一遍关键帧）。
var _timeline_scale := 1.0

# 整枪动作状态
var _recoil := 0.0
var _reload_curve := 0.0       ## 0..1，换弹过程中 0→1→0
var _draw_t := 1.0             ## 0 = 完全收起，1 = 完全举起
var _look_lag := Vector2.ZERO
var _bob_time := 0.0
var _sway_time := 0.0
var _ready_flag := false


# =============================================================================
# 装配
# =============================================================================

## 载入一把枪。返回是否成功。
func setup(weapon_data: WeaponData) -> bool:
	data = weapon_data

	if _model != null:
		_model.queue_free()
		_model = null
	_skeleton = null
	_muzzle_attachment = null
	_bone_index.clear()
	_rest.clear()
	_parent_basis.clear()

	var packed := load(data.model_path) as PackedScene
	if packed == null:
		push_error("[WeaponView] 载入模型失败: %s" % data.model_path)
		return false

	_model = packed.instantiate() as Node3D
	if _model == null:
		push_error("[WeaponView] 模型不是 Node3D: %s" % data.model_path)
		return false
	add_child(_model)

	# 视角模型不投影阴影：贴着相机的物体投阴影会出现很脏的条纹。
	_disable_shadows(_model)

	_skeleton = _find_skeleton(_model)
	if _skeleton != null:
		_cache_bones()
	_muzzle_attachment = _find_node_named(_model, "Attach_Muzzle")

	_recoil = 0.0
	_anim = {}
	_anim_time = 0.0
	_anim_length = 0.0
	_draw_t = 1.0
	_ready_flag = true
	_apply_pose(0.0, 0.0)
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_node_named(node: Node, target: String) -> Node3D:
	if node.name == target and node is Node3D:
		return node as Node3D
	for child in node.get_children():
		var found := _find_node_named(child, target)
		if found != null:
			return found
	return null


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


## 缓存每根骨骼的静止变换与父骨骼基向量。
func _cache_bones() -> void:
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		_bone_index[bone_name] = i
		_rest[bone_name] = _skeleton.get_bone_rest(i)

		var parent := _skeleton.get_bone_parent(i)
		if parent >= 0:
			_parent_basis[bone_name] = _skeleton.get_bone_global_rest(parent).basis
		else:
			_parent_basis[bone_name] = Basis()


# =============================================================================
# 对外接口
# =============================================================================

## 播放开火机械动作。
func play_fire() -> void:
	_start_anim(data.mech_fire)


## 播放换弹机械动作。duration 是实际换弹时长，时间轴会按比例拉伸去对齐。
func play_reload(duration: float) -> void:
	_start_anim(data.mech_reload, duration)


## 开始举枪（切枪时调用）。
func begin_draw() -> void:
	_draw_t = 0.0


func is_drawn() -> bool:
	return _draw_t >= 1.0


## 跳过举枪动画，直接进入举起状态（开局第一次装备时用）。
func snap_drawn() -> void:
	_draw_t = 1.0


func set_ready(value: bool) -> void:
	_ready_flag = value


## 供玩家调用：把本帧实际转过的角度喂进来（弧度，x = 偏航，y = 俯仰），
## 枪会滞后一拍再跟上，转身越快枪摆得越明显。
func notify_look(look_delta_rad: Vector2) -> void:
	if data == null:
		return
	_look_lag += look_delta_rad


## 枪口在世界空间的位置与朝向（枪口火光用）。
func get_muzzle_transform() -> Transform3D:
	if _muzzle_attachment != null:
		return _muzzle_attachment.global_transform
	if _model != null:
		return _model.global_transform
	return global_transform


# =============================================================================
# 每帧更新
# =============================================================================

## speed_ratio: 玩家当前速度 / 基础速度，用于走路摆动强度。
## reload_progress: 换弹进度 0..1，不在换弹时传 -1。
func update(delta: float, speed_ratio: float, reload_progress: float) -> void:
	_tick_anim(delta)

	# 后坐回落（指数，手感比线性自然）
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-RECOIL_RECOVERY * delta))

	# 视角滞后慢慢回中
	_look_lag = _look_lag.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))

	# 换弹下沉曲线：0 → 1 → 0
	var reload_target := 0.0
	if reload_progress >= 0.0:
		reload_target = sin(clampf(reload_progress, 0.0, 1.0) * PI)
	_reload_curve = lerpf(_reload_curve, reload_target, clampf(delta * 14.0, 0.0, 1.0))

	# 切枪举起进度
	if _draw_t < 1.0:
		_draw_t = minf(_draw_t + delta * 4.2, 1.0)

	# 摆动相位
	var clamped_ratio := clampf(speed_ratio, 0.0, 1.8)
	_bob_time += delta * BOB_FREQUENCY * maxf(clamped_ratio, 0.12)
	_sway_time += delta * IDLE_SWAY_FREQUENCY

	_apply_pose(clamped_ratio, reload_progress)


## 把两层动画合成到本节点的 transform 上。
func _apply_pose(speed_ratio: float, _reload_progress: float) -> void:
	if data == null:
		return

	# ---- 基准握持姿势（相机空间）----
	var pos := data.hold_offset
	var rot := Vector3(
		deg_to_rad(data.hold_rotation_deg.x),
		deg_to_rad(data.hold_rotation_deg.y),
		deg_to_rad(data.hold_rotation_deg.z)
	)

	# ---- 待机呼吸：轻微上下 + 左右，幅度很小，让枪"活着" ----
	var breath := sin(_sway_time)
	pos += Vector3(breath * IDLE_SWAY_AMPLITUDE, cos(_sway_time * 0.7) * IDLE_SWAY_AMPLITUDE * 0.8, 0.0)

	# ---- 走动摇摆：8 字形，横摆比纵摆大 ----
	if speed_ratio > 0.05:
		var amount := minf(speed_ratio, 1.5) * BOB_AMPLITUDE
		pos += Vector3(sin(_bob_time) * amount, -absf(sin(_bob_time * 2.0)) * amount * 0.7, 0.0)
		rot.z += sin(_bob_time) * 0.020 * amount * 10.0

	# ---- 视角拖拽滞后：转身时枪跟不上手 ----
	pos += Vector3(-_look_lag.x * LOOK_LAG_POS, _look_lag.y * LOOK_LAG_POS, 0.0)
	rot.y += -_look_lag.x * deg_to_rad(LOOK_LAG_ROT)
	rot.x += _look_lag.y * deg_to_rad(LOOK_LAG_ROT * 0.6)
	rot.z += _look_lag.x * deg_to_rad(LOOK_LAG_ROT * 0.5)

	# ---- 开火后坐：枪往后退 + 枪口上抬 ----
	pos.z += _recoil * data.view_kick
	rot.x += _recoil * data.view_kick * 3.2
	# 后坐带一点随机偏转，连射时更"活"
	rot.y += _recoil * data.recoil_yaw * 2.0

	# ---- 换弹：整枪下沉、向外翻 ----
	pos += Vector3(0.0, -RELOAD_DROP * _reload_curve, 0.055 * _reload_curve)
	rot.x += deg_to_rad(-RELOAD_TILT * _reload_curve)
	rot.z += deg_to_rad(RELOAD_ROLL * _reload_curve)

	# ---- 切枪：从画面外升起来 ----
	if _draw_t < 1.0:
		var hidden := 1.0 - _draw_t
		hidden = hidden * hidden          # 前段慢、后段快，更像是"甩"出来的
		pos.y -= DRAW_DROP * hidden
		rot.x -= deg_to_rad(DRAW_TILT * hidden)
		rot.z += deg_to_rad(18.0 * hidden)
		# 举枪过程中枪口朝下，快到位时才抬平

	transform = Transform3D(Basis.from_euler(rot), pos)


# =============================================================================
# 机械动作（骨骼级）
# =============================================================================

## 记录当前开火后坐强度，供 _apply_pose 使用。
func add_recoil_kick() -> void:
	_recoil = minf(_recoil + 1.0, 1.35)


func _start_anim(timeline: Dictionary, stretch_to: float = -1.0) -> void:
	if timeline.is_empty() or _skeleton == null:
		return
	_anim = timeline
	_anim_time = 0.0
	# 找出时间轴里最大的时间点作为长度；如果指定了 stretch_to，就按比例拉伸
	_anim_length = _timeline_length(timeline)
	if stretch_to > 0.0 and _anim_length > 0.0:
		_timeline_scale = stretch_to / _anim_length
	else:
		_timeline_scale = 1.0
	_anim_bones.clear()
	for bone_name in timeline:
		_anim_bones.append(bone_name)


func _timeline_length(timeline: Dictionary) -> float:
	var longest := 0.0
	for bone_name in timeline:
		var keys: Array = timeline[bone_name]
		if not keys.is_empty():
			longest = maxf(longest, float(keys[keys.size() - 1][0]))
	return longest


func _tick_anim(delta: float) -> void:
	if _anim_length <= 0.0:
		return
	_anim_time += delta
	if _anim_time >= _anim_length:
		_finish_anim()
		return
	_apply_mech(_anim_time)


func _finish_anim() -> void:
	# 回到静止姿势：用 reset 而不是设成 rest，避免浮点误差累积
	if _skeleton != null:
		for bone_name in _anim_bones:
			var idx: int = _bone_index.get(bone_name, -1)
			if idx >= 0:
				_skeleton.reset_bone_pose(idx)
	_anim = {}
	_anim_bones.clear()
	_anim_length = 0.0
	_anim_time = 0.0


## 按时间轴把各骨骼推到指定时刻的样子。
func _apply_mech(time: float) -> void:
	for bone_name in _anim:
		var keys: Array = _anim[bone_name]
		if keys.is_empty():
			continue
		var sample := _sample_keys(keys, time / _timeline_scale)
		_set_bone(bone_name, sample[0], sample[1])


## 在关键帧之间线性插值，返回 [位移, 旋转角度]。
func _sample_keys(keys: Array, t: float) -> Array:
	if t <= float(keys[0][0]):
		return [keys[0][1], keys[0][2]]
	var last: Array = keys[keys.size() - 1]
	if t >= float(last[0]):
		return [last[1], last[2]]

	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		var ta := float(a[0])
		var tb := float(b[0])
		if t >= ta and t <= tb:
			var f := 0.0 if tb <= ta else (t - ta) / (tb - ta)
			# 用 smoothstep 让动作起停柔和一点，不像机器
			f = f * f * (3.0 - 2.0 * f)
			return [(a[1] as Vector3).lerp(b[1] as Vector3, f),
					(a[2] as Vector3).lerp(b[2] as Vector3, f)]
	return [last[1], last[2]]


## 把一根骨骼按「模型空间」的位移与旋转推到目标姿势。
func _set_bone(bone_name: String, offset_model: Vector3, rot_deg_model: Vector3) -> void:
	var idx: int = _bone_index.get(bone_name, -1)
	if idx < 0:
		# 模型里没有这根骨骼很正常（比如手枪没有 Pump），静默跳过
		return

	var rest: Transform3D = _rest[bone_name]
	var parent_basis: Basis = _parent_basis[bone_name]
	var to_parent := parent_basis.inverse()

	var basis := rest.basis
	if rot_deg_model != Vector3.ZERO:
		# 绕模型空间的任意轴旋转：把轴换算到父空间，再左乘（在父空间里转）
		var axis_local := (to_parent * rot_deg_model.normalized()).normalized()
		var angle := deg_to_rad(rot_deg_model.length())
		if axis_local.length_squared() > 0.0001:
			basis = Basis(axis_local, angle) * basis

	_skeleton.set_bone_pose_position(idx, rest.origin + to_parent * offset_model)
	_skeleton.set_bone_pose_rotation(idx, basis.get_rotation_quaternion())
