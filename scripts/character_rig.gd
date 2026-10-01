extends Node3D
class_name CharacterRig
## 骨骼角色装配：加载 CC0 角色模型、播放动画、处理材质
##
## 模型来源：KayKit Adventurers Character Pack（CC0，见 assets/licenses/）
## 每个角色模型自带 76 个动画，本文件只用其中 5 个。
##
## ── 两个要处理的模型特性 ──
##
## 1) 模型里塞了整套道具
##    Knight.glb 除了角色本体，还把 2 把剑挂在右手、4 个盾挂在左手上，
##    全部同时渲染会互相穿插。所以这里「每只手上只留一件，其余隐藏」。
##
## 2) 模型比真人高
##    按骨骼量原始高度约 2.3m（KayKit 是夸张比例）。这里不写死缩放值，
##    而是量出模型实际包围盒再按 TARGET_HEIGHT 换算，换别的 KayKit 包也能用。
##
## 材质全部 duplicate：模型自带的材质是共享的，直接改 albedo_color
## 会让场上所有敌人一起变色（受击闪白就会变成全体闪白）。

## 目标身高（米）。和敌人胶囊高度对齐。
const TARGET_HEIGHT := 1.80

# ---- 用到的动画名（已核对与模型内名称完全一致）----
const ANIM_IDLE := "Idle"
const ANIM_RUN := "Running_A"
const ANIM_ATTACK := "1H_Melee_Attack_Slice_Horizontal"
const ANIM_ATTACK_FALLBACK := "Unarmed_Melee_Attack_Punch_A"
const ANIM_HIT := "Hit_A"
const ANIM_DEATH := "Death_A"

## 需要循环播放的动画。
const LOOPING := [ANIM_IDLE, ANIM_RUN]

var _model: Node3D
var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _materials: Array[StandardMaterial3D] = []
var _current_anim := ""
var _attack_anim := ANIM_ATTACK
var _tint := Color.WHITE
var _scale_applied := 1.0
var _measured_height := 0.0


# =============================================================================
# 装配
# =============================================================================

## 载入角色模型并做缩放。返回是否成功。
func setup(model_path: String) -> bool:
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("[CharacterRig] 载入模型失败: %s" % model_path)
		return false

	_model = packed.instantiate() as Node3D
	if _model == null:
		push_error("[CharacterRig] 模型不是 Node3D: %s" % model_path)
		return false
	add_child(_model)

	_anim_player = _find_first(_model, "AnimationPlayer") as AnimationPlayer
	_skeleton = _find_first(_model, "Skeleton3D") as Skeleton3D

	_clean_up_props(_model)
	_prepare_materials(_model)
	_apply_auto_scale()

	if _anim_player != null:
		_enable_looping()
		# 攻击动画优先用挥剑，没有就退回到空手出拳
		if not _anim_player.has_animation(ANIM_ATTACK):
			_attack_anim = ANIM_ATTACK_FALLBACK
	return true


func _find_first(node: Node, class_name_str: String) -> Node:
	for child in node.get_children():
		if child.is_class(class_name_str):
			return child
		var found := _find_first(child, class_name_str)
		if found != null:
			return found
	if node.is_class(class_name_str):
		return node
	return null


## 手部挂点下同时挂了多件道具，只保留第一件。
func _clean_up_props(node: Node) -> void:
	if node is BoneAttachment3D:
		var attachment_name := node.name.to_lower()
		if attachment_name.begins_with("handslot"):
			var kept := false
			for child in node.get_children():
				if child is MeshInstance3D:
					if kept:
						(child as MeshInstance3D).visible = false
					kept = true
	for child in node.get_children():
		_clean_up_props(child)


## 复制材质，避免多个敌人共享同一份材质导致一起变色。
func _prepare_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := 0
		if mesh_instance.mesh != null:
			surface_count = mesh_instance.mesh.get_surface_count()
		for i in surface_count:
			var source := mesh_instance.get_active_material(i)
			if source is StandardMaterial3D:
				var copy := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				mesh_instance.set_surface_override_material(i, copy)
				_materials.append(copy)
	for child in node.get_children():
		_prepare_materials(child)


## 量出模型高度，据此缩放到 TARGET_HEIGHT。
func _apply_auto_scale() -> void:
	_model.scale = Vector3.ONE
	_measured_height = _measure_height(_model)
	if _measured_height <= 0.01:
		return
	var factor := TARGET_HEIGHT / _measured_height
	_model.scale = Vector3.ONE * factor
	_scale_applied = factor


## 合并角色本体网格的包围盒，得到模型空间里的总高度。
##
## 两个必须注意的点：
##   1) 手部挂点上的剑和盾不能算进去 —— 那把双手剑竖着高达 1.7m，
##      会把"人有多高"算成两米七。所以挂在 BoneAttachment3D 下的网格全部跳过。
##   2) GDScript 的 float 是值传递，递归累加必须靠返回值，不能传引用。
func _measure_height(root: Node) -> float:
	var box := _body_bounds(root, Transform3D(), false)
	if box.size.y <= 0.0:
		return 0.0
	return box.size.y


func _body_bounds(node: Node, xform: Transform3D, under_attachment: bool) -> AABB:
	var current := xform
	if node is Node3D:
		current = current * (node as Node3D).transform
	if node is BoneAttachment3D:
		under_attachment = true

	var result := AABB()
	var has := false

	if node is MeshInstance3D and not under_attachment:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			result = current * mesh_instance.get_aabb()
			has = true

	for child in node.get_children():
		var child_box := _body_bounds(child, current, under_attachment)
		if child_box.size == Vector3.ZERO:
			continue
		result = child_box if not has else result.merge(child_box)
		has = true

	return result if has else AABB()


## 供敌人启动时打印，方便核对缩放是否合理。
func measure_report() -> String:
	var box := _body_bounds(_model, Transform3D(), false)
	return "本体包围盒高 %.3f m，缩放 %.3f 倍 → 实际身高 %.2f m" % [
		_measured_height, _scale_applied, _measured_height * _scale_applied]


# =============================================================================
# 动画
# =============================================================================

func play_idle() -> void:
	play(ANIM_IDLE)


func play_run(speed_ratio: float = 1.0) -> void:
	play(ANIM_RUN)
	set_speed(speed_ratio)


func play_attack() -> void:
	play(_attack_anim, 0.08)


func play_hit() -> void:
	play(ANIM_HIT, 0.05)


func play_death() -> void:
	play(ANIM_DEATH, 0.10)


## 播放一个动画（同名则不重播，避免每帧重置）。
func play(anim_name: String, blend: float = 0.18) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	if _current_anim == anim_name and _anim_player.is_playing():
		return
	_current_anim = anim_name
	_anim_player.play(anim_name, blend)


## 调整播放速度，让跑步动画和实际移动速度对得上，脚不打滑。
func set_speed(scale: float) -> void:
	if _anim_player == null:
		return
	_anim_player.speed_scale = clampf(scale, 0.35, 2.4)


func get_current_animation() -> String:
	return _current_anim


## 攻击动画本身的时长（秒）。敌人用它决定挥剑动作持续多久。
func get_attack_length() -> float:
	if _anim_player == null:
		return 0.9
	var anim := _anim_player.get_animation(_attack_anim)
	if anim == null:
		anim = _anim_player.get_animation(ANIM_ATTACK_FALLBACK)
	if anim == null:
		return 0.9
	return maxf(anim.length, 0.25)


## 攻击动画是否已经放完（敌人用它判断能不能再次出手）。
func is_attack_finished() -> bool:
	if _anim_player == null or _current_anim != _attack_anim:
		return true
	var anim := _anim_player.get_animation(_attack_anim)
	if anim == null:
		return true
	return _anim_player.current_animation_position >= anim.length - 0.05


func _enable_looping() -> void:
	for anim_name in LOOPING:
		var anim := _anim_player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR


# =============================================================================
# 材质
# =============================================================================

## 取一个骨骼挂点（模型里自带 head / chest / handslot.r 等挂点）。
## 返回 null 表示模型里没有这个挂点。
func get_attachment(bone_name: String) -> BoneAttachment3D:
	return _find_attachment(_model, bone_name)


func _find_attachment(node: Node, bone_name: String) -> BoneAttachment3D:
	for child in node.get_children():
		if child is BoneAttachment3D and child.name == bone_name:
			return child as BoneAttachment3D
		var found := _find_attachment(child, bone_name)
		if found != null:
			return found
	return null


## 设置整体色调（用于按波次区分敌人强度）。
func set_tint(color: Color) -> void:
	_tint = color
	_apply_tint()


func _apply_tint() -> void:
	for material in _materials:
		material.albedo_color = _tint


## 受击闪白。传入大于 1 的颜色值会得到 HDR 过曝效果，比单纯变白更扎眼。
func flash() -> void:
	for material in _materials:
		material.albedo_color = Color(3.0, 3.0, 3.0)


func restore_tint() -> void:
	_apply_tint()


func get_scale_factor() -> float:
	return _scale_applied
