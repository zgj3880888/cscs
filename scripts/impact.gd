extends Node3D
class_name Impact
## 子弹命中特效：贴在墙上的弹孔 + 命中敌人时的火花
##
## 每个实例自己计时间、到点自己 queue_free，调用方不需要管回收。
## 所有几何和材质都是代码生成的，不依赖任何图片文件。

## 弹孔最长存在时间（秒）。
const LIFETIME := 7.0
## 火花存活时间（秒）。
const SPARK_LIFETIME := 0.14

var _age := 0.0
var _has_spark := false
var _spark: MeshInstance3D


## 在命中点生成特效。必须在 add_child 之后调用（需要 global_position）。
func setup(hit_position: Vector3, hit_normal: Vector3, is_enemy: bool) -> void:
	global_position = hit_position
	# 让特效稍微离开表面，避免和墙面深度冲突（z-fighting）。
	global_position += hit_normal.normalized() * 0.012

	# 朝向：让方片的正面沿着法线方向。
	var up := Vector3.UP
	if absf(hit_normal.dot(Vector3.UP)) > 0.98:
		up = Vector3.FORWARD
	look_at_from_position(global_position, global_position + hit_normal, up)

	_build_decal(is_enemy)

	if is_enemy:
		_build_spark()


func _process(delta: float) -> void:
	_age += delta

	if _has_spark and _spark != null:
		var t := clampf(_age / SPARK_LIFETIME, 0.0, 1.0)
		# 火花迅速膨胀然后缩小，做出"爆一下"的感觉。
		var scale := sin(t * PI) * 0.09
		_spark.scale = Vector3.ONE * maxf(scale, 0.001)
		var material := _spark.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color.a = 1.0 - t

	if _age >= LIFETIME:
		queue_free()


## 弹孔：一个深色小方片。打中敌人时用亮色，方便确认命中。
func _build_decal(is_enemy: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.085, 0.085)
	mesh_instance.mesh = quad

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.92, 0.55, 0.95) if is_enemy else Color(0.03, 0.03, 0.04, 0.9)
	material.disable_receive_shadows = true
	if is_enemy:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


## 火花：一个自发光小球，快速缩放 + 淡出。
func _build_spark() -> void:
	_spark = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_spark.mesh = sphere

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.78, 0.35, 1.0)
	material.disable_receive_shadows = true
	_spark.material_override = material
	_spark.scale = Vector3.ONE * 0.01
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spark)

	_has_spark = true
