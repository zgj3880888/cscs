extends Node
## 无头自检：改完代码跑一遍，确认武器系统整条链路还是好的
##
##   C:\...\Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 \
##       --path . res://tools/selftest.tscn
##
## 退出码 0 = 全过；1 = 有失败项。可以直接挂到 CI 上做回归。
##
## 分两段：
##   [自检 1] 机械骨骼动画 —— 同步跑完，不依赖帧号。
##            除了"模型能不能载入"，更关键的是验证**骨骼坐标轴换算**：
##            枪机/套筒/泵只能沿枪管方向往复。如果换算写错了，零件会斜着飞出去
##            —— 那种错在编辑器里不盯着看根本发现不了。
##   [自检 2] 端到端流程 —— 真的加载 main.tscn，按时间轴推一遍
##            波次 → 敌人外观 → 切枪 → 半自动/全自动 → 换弹 → 受击 → 死亡 → 计分
##
## ── 为什么不写成 `extends SceneTree` + `--script` ──
## `--script` 模式下 autoload 会被实例化，但**不会注册成编译期标识符**，
## player.gd 里写着的 `GameConfig` 会直接编译失败，整条链路全崩。
## 所以改成「把本场景当主场景跑」，autoload 的解析方式就和真机完全一致。
## `--fixed-fps 60` 让帧号和秒数严格对应，时间轴才可预测。
##
## 本文件不参与正式游戏，也不会打进 APK —— 见 export_presets.cfg 的 exclude_filter。

var _frames := 0
var _main: Node
var _player: Player
var _weapon: Weapon
var _mark := 0            ## 本阶段的弹匣数，用来算消耗
var _spent := 0           ## 本阶段实际消耗的弹药数
var _problems: Array[String] = []


func _ready() -> void:
	print("\n==================== MobileFPS 自检 ====================")
	_check_mech()
	_check_integration_setup()


func _ok(condition: bool, message: String) -> void:
	if condition:
		print("    ✓ %s" % message)
	else:
		print("    ✗ %s" % message)
		_problems.append(message)


# =============================================================================
# 自检 1：机械骨骼动画
# =============================================================================

func _check_mech() -> void:
	print("\n[自检 1] 机械骨骼动画")
	var holder := Node3D.new()
	add_child(holder)

	for data in WeaponData.build_all():
		_check_one_weapon(holder, data)

	holder.queue_free()


func _check_one_weapon(holder: Node3D, data: WeaponData) -> void:
	var view := WeaponView.new()
	holder.add_child(view)

	if not view.setup(data):
		_ok(false, "%s 模型载入失败（%s）" % [data.display_name, data.model_path])
		view.queue_free()
		return

	var skeleton: Skeleton3D = view._skeleton
	if skeleton == null:
		_ok(false, "%s 模型里没有 Skeleton3D，机械动画无从谈起" % data.display_name)
		view.queue_free()
		return

	# 时间轴里写的骨骼名必须在模型里真的存在 —— 名字写错是静默跳过的，只能靠这里发现
	var missing: Array[String] = []
	for timeline in [data.mech_fire, data.mech_reload]:
		for bone_name in timeline:
			if skeleton.find_bone(bone_name) < 0 and not missing.has(bone_name):
				missing.append(bone_name)
	_ok(missing.is_empty(), "%s：时间轴骨骼名全部存在（模型共 %d 根骨骼%s）"
		% [data.display_name, skeleton.get_bone_count(),
		   "" if missing.is_empty() else "，缺失 " + str(missing)])

	_check_bone_axis(view, data)
	view.queue_free()


## 播放一次开火动作，沿时间轴采样「位移最大的那根骨骼」，
## 确认它只在时间轴声明的那个轴向上移动。
func _check_bone_axis(view: WeaponView, data: WeaponData) -> void:
	var bone_name := _dominant_key(data.mech_fire)
	if bone_name == "":
		return

	var skeleton: Skeleton3D = view._skeleton
	var idx := skeleton.find_bone(bone_name)
	if idx < 0:
		return

	# 时间轴声明的位移方向（模型空间）
	var declared := Vector3.ZERO
	for key in data.mech_fire[bone_name]:
		var offset: Vector3 = key[1]
		if offset.length() > declared.length():
			declared = offset
	if declared.length() <= 0.001:
		return

	skeleton.reset_bone_pose(idx)
	var start: Vector3 = skeleton.get_bone_global_pose(idx).origin

	view.play_fire()
	var lo := start
	var hi := start
	# 用很小的步长把整条时间轴扫一遍（时间轴长度约 0.06~0.56 秒）
	for i in 240:
		view.update(1.0 / 480.0, 0.0, -1.0)
		var p: Vector3 = skeleton.get_bone_global_pose(idx).origin
		lo = lo.min(p)
		hi = hi.max(p)

	var travel := hi - lo
	var declared_axis := _dominant_axis(declared)
	var actual_axis := _dominant_axis(travel)

	_ok(travel.length() > 0.008,
		"%s：开火时 %s 有位移（%.1f mm）" % [data.display_name, bone_name, travel.length() * 1000.0])
	_ok(actual_axis == declared_axis,
		"%s：%s 只沿 %s 轴动（时间轴声明 %s 轴，实测 %s）"
			% [data.display_name, bone_name,
			   AXIS_NAMES[actual_axis], AXIS_NAMES[declared_axis], AXIS_NAMES[actual_axis]])


const AXIS_NAMES := ["X", "Y", "Z"]


## 取时间轴里位移最大的一根骨骼（步枪是 Bolt，霰弹枪是 Pump，手枪是 Slide）。
func _dominant_key(timeline: Dictionary) -> String:
	var best := ""
	var best_amount := 0.0
	for bone_name in timeline:
		for key in timeline[bone_name]:
			var amount: float = (key[1] as Vector3).length()
			if amount > best_amount:
				best_amount = amount
				best = bone_name
	return best


func _dominant_axis(v: Vector3) -> int:
	var a := absf(v.x)
	var b := absf(v.y)
	var c := absf(v.z)
	if a >= b and a >= c:
		return 0
	if b >= c:
		return 1
	return 2


# =============================================================================
# 自检 2：端到端流程
# =============================================================================

func _check_integration_setup() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_main = packed.instantiate()
	add_child(_main)
	print("\n[自检 2] 端到端流程")


func _process(_delta: float) -> void:
	_frames += 1
	if _main == null:
		return
	_player = _main._player
	if _player == null:
		return
	_weapon = _player.weapon
	if _weapon == null:
		return

	match _frames:
		120:
			print("\n  [120 帧 / 2.0s] 开局与波次")
			print("      阶段=%s  波次=%d  场上敌人=%d  玩家=%s"
				% [_main._phase, GameState.wave, _main._enemies_root.get_child_count(),
				   str(_player.global_position.snapped(Vector3.ONE * 0.1))])
			_ok(_weapon.weapon_count() == 4, "武器表加载了 4 把枪")
			_ok(_weapon.get_weapon_name() != "", "初始武器名非空：%s" % _weapon.get_weapon_name())
			_ok(_weapon.get_magazine() == 30, "初始弹匣 30（实际 %d）" % _weapon.get_magazine())

		400:
			print("\n  [400 帧 / 6.7s] 敌人外观与自动缩放")
			var enemies: Array[Node] = (_main._enemies_root as Node3D).get_children()
			_ok(enemies.size() > 0, "场上刷出了敌人（%d 个）" % enemies.size())
			for i in mini(enemies.size(), 2):
				var enemy: Enemy = enemies[i] as Enemy
				if enemy == null:
					continue
				var rig: CharacterRig = enemy._rig
				if rig == null:
					_problems.append("敌人没有挂上 CharacterRig")
					continue
				var height: float = rig._measured_height * rig._scale_applied
				print("      敌人 #%d  %s" % [i + 1, rig.measure_report()])
				print("          动画=%s  血量=%d/%d  模型=%s"
					% [rig.get_current_animation(), enemy.health, enemy.max_health,
					   rig._model.name])
				_ok(absf(height - CharacterRig.TARGET_HEIGHT) < 0.05,
					"敌人 #%d 身高缩放到 %.2fm" % [i + 1, height])
				_ok(rig.get_current_animation() == CharacterRig.ANIM_RUN,
					"敌人 #%d 正在播奔跑动画" % [i + 1])
				_ok(rig.get_attachment("head") != null, "敌人 #%d 有 head 挂点" % [i + 1])

		520:
			print("\n  [520 帧 / 8.7s] 切枪")
			print("      切枪前：%s" % _weapon.get_weapon_name())
			_weapon.switch_to(2)
			print("      切枪后：%s [%s]  弹匣=%d/%d  自动=%s"
				% [_weapon.get_weapon_name(), _weapon.current().id,
				   _weapon.get_magazine(), _weapon.get_reserve(),
				   str(_weapon.current().is_automatic)])
			_ok(_weapon.get_weapon_index() == 2, "切到第 3 把枪（霰弹枪）")
			_ok(_weapon.get_magazine() == 6, "霰弹枪弹匣 6（实际 %d）" % _weapon.get_magazine())
			_ok(not _weapon.current().is_automatic, "霰弹枪标记为半自动")

		600:
			print("\n  [600 帧 / 10.0s] 半自动：轻扣一下")
			_mark = _weapon.get_magazine()
			Input.action_press("fire")

		604:
			Input.action_release("fire")
			_spent = _mark - _weapon.get_magazine()
			print("      按 4 帧（0.067s）后弹匣 %d → %d" % [_mark, _weapon.get_magazine()])
			_ok(_spent == 1, "轻扣只打 1 发（实际 %d 发）" % _spent)

		660:
			print("\n  [660 帧 / 11.0s] 半自动：一直按住")
			# 600 帧那一发的 0.75s 冷却到 645 帧才结束，所以此刻枪已经就绪。
			# 按住 90 帧 = 1.5s = 两个射速周期：全自动会打出 3 发，半自动只该有 1 发。
			_mark = _weapon.get_magazine()
			Input.action_press("fire")

		750:
			Input.action_release("fire")
			_spent = _mark - _weapon.get_magazine()
			print("      按住 90 帧（1.5s，两个射速周期）后弹匣 %d → %d"
				% [_mark, _weapon.get_magazine()])
			_ok(_spent == 1, "按住也只打 1 发（实际 %d 发）" % _spent)

		780:
			print("\n  [780 帧 / 13.0s] 换弹")
			_mark = _weapon.get_magazine()
			_weapon.start_reload()
			print("      弹匣 %d  是否在换弹=%s  进度 %.0f%%"
				% [_mark, str(_weapon.is_reloading()), _weapon.get_reload_progress() * 100.0])
			_ok(_weapon.is_reloading(), "换弹已启动")
			_ok(_weapon.get_reload_progress() < 0.2, "换弹刚起步（进度 %.0f%%）"
				% (_weapon.get_reload_progress() * 100.0))

		800:
			print("\n  [800 帧 / 13.3s] 敌人受击与死亡")
			var enemies800: Array[Node] = (_main._enemies_root as Node3D).get_children()
			if enemies800.is_empty():
				_problems.append("800 帧时场上没有敌人")
			else:
				var enemy: Enemy = enemies800[0] as Enemy
				var hp_before: int = enemy.health
				var dir: Vector3 = (enemy.global_position - _player.global_position).normalized()
				enemy.take_damage(25, enemy.global_position, dir)
				print("      受击后血量 %d → %d  动画=%s"
					% [hp_before, enemy.health, enemy._rig.get_current_animation()])
				_ok(enemy.health == hp_before - 25, "受击扣了 25 血")
				_ok(enemy._rig.get_current_animation() == CharacterRig.ANIM_HIT,
					"受击播放 Hit_A")
				enemy.take_damage(9999, enemy.global_position, dir)
				print("      致命伤害后 is_dead=%s  动画=%s"
					% [str(enemy.is_dead), enemy._rig.get_current_animation()])
				_ok(enemy.is_dead, "致命伤害触发死亡")
				_ok(enemy._rig.get_current_animation() == CharacterRig.ANIM_DEATH,
					"死亡播放 Death_A")

		1020:
			print("\n  [1020 帧 / 17.0s] 换弹结果")
			# 780 帧起算 3.2s = 192 帧，应在 972 帧完成
			print("      弹匣=%d/%d  是否在换弹=%s"
				% [_weapon.get_magazine(), _weapon.get_reserve(), str(_weapon.is_reloading())])
			_ok(not _weapon.is_reloading(), "换弹在 3.2s 内完成")
			_ok(_weapon.get_magazine() == 6, "弹匣已补满到 6（实际 %d）" % _weapon.get_magazine())
			_ok(_weapon.get_reserve() == 34, "备弹按缺口扣掉 2 发（实际 %d）" % _weapon.get_reserve())
			_ok(GameState.score >= GameConfig.SCORE_PER_KILL,
				"击杀加分生效（分数 %d）" % GameState.score)
			print("      场上敌人数=%d（被击杀的那个已回收）"
				% (_main._enemies_root as Node3D).get_child_count())

		1060:
			print("\n  [1060 帧 / 17.7s] 全自动：切回步枪按住")
			_weapon.switch_to(0)
			_mark = _weapon.get_magazine()
			print("      切到 %s  弹匣=%d  自动=%s"
				% [_weapon.get_weapon_name(), _mark, str(_weapon.current().is_automatic)])

		1090:
			Input.action_press("fire")

		1150:
			Input.action_release("fire")
			_spent = _mark - _weapon.get_magazine()
			print("      按住 60 帧（1.0s / 射速 0.095s）后弹匣 %d → %d"
				% [_mark, _weapon.get_magazine()])
			_ok(_spent >= 5, "全自动连发打出了 %d 发" % _spent)

		1200:
			print("\n--- 汇总 ---")
			if _problems.is_empty():
				print("  全部检查通过 ✓")
			else:
				for p in _problems:
					print("  ✗ %s" % p)
			print("=======================================================\n")
			get_tree().quit(0 if _problems.is_empty() else 1)
