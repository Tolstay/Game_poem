extends Sprite2D

# 血滴掉落系统参数
@export_group("Blood Drop Settings")
@export var drop_frequency: float = 5.0  # 血滴掉落频率（秒）
@export var drop_speed: float = 300.0  # 血滴掉落速度（像素/秒）
@export var drop_gravity: float = 980.0  # 重力加速度（像素/秒²）
@export var drop_randomness: float = 0.2  # 掉落位置随机性

# 血滴场景引用
const BLOODDROP_SCENE = preload("res://Scence/blooddrop.tscn")

# 状态变量
var point_index: int = -1  # 当前bloodcut所属的点索引
var is_bleeding: bool = false  # 是否正在流血
var fruit_removed: bool = false  # fruit是否已被摘除
var generation_count: int = 0  # 经历过的生成次数（生成bloodcut的当次不算）

# 内部节点引用
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var drop_timer: Timer = Timer.new()

# 血滴容器
var blooddrop_container: Node2D

func _ready():
	print("🩸 [DEBUG] bloodcut._ready() 开始 - point_index:", point_index, " visible:", visible)
	
	# 设置计时器
	add_child(drop_timer)
	drop_timer.wait_time = drop_frequency
	drop_timer.timeout.connect(_generate_blood_drop)
	
	# 查找或创建血滴容器
	_setup_blooddrop_container()
	
	# 连接fruit摘除信号
	_connect_fruit_signals()
	
	# 连接全局生成信号
	_connect_generation_signals()
	
	print("🩸 [DEBUG] bloodcut._ready() 完成 - final visible:", visible)

## 设置point_index（由fruits.gd调用）
func set_point_index(index: int):
	point_index = index

## 开始流血（由fruits.gd调用）
func start_bleeding():
	if is_bleeding:
		print("🩸 [DEBUG] start_bleeding() 已经在流血中 - point_index:", point_index)
		return
	
	print("🩸 [DEBUG] start_bleeding() 开始流血 - point_index:", point_index)
	is_bleeding = true
	
	# 播放动画（如果有的话）
	if animation_player and animation_player.has_animation("bleeding"):
		animation_player.play("bleeding")
		print("🩸 [DEBUG] 播放bleeding动画")
	
	# 开始生成血滴
	drop_timer.start()
	print("🩸 [DEBUG] 血滴计时器已启动，频率:", drop_frequency)

## 停止流血
func stop_bleeding():
	if not is_bleeding:
		return
	
	is_bleeding = false
	
	# 停止动画
	if animation_player:
		animation_player.stop()
	
	# 停止生成血滴
	drop_timer.stop()

## 设置血滴容器
func _setup_blooddrop_container():
	# 查找场景中是否有Fruitlayer
	var parent_node = get_parent()
	while parent_node and parent_node.name != "Fruitlayer":
		parent_node = parent_node.get_parent()
		if parent_node == get_tree().current_scene:
			break
	
	if parent_node and parent_node.name == "Fruitlayer":
		blooddrop_container = parent_node
	else:
		# 如果没找到Fruitlayer，使用父节点
		blooddrop_container = get_parent()

## 连接fruit摘除相关信号
func _connect_fruit_signals():
	# 查找signalbus节点并连接fruit_picked信号
	var signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
	if signalbus and signalbus.has_signal("fruit_picked_now"):
		if not signalbus.fruit_picked_now.is_connected(_on_fruit_picked):
			signalbus.fruit_picked_now.connect(_on_fruit_picked)

## 连接全局生成相关信号
func _connect_generation_signals():
	# 连接main.gd的instantiation_compeleted信号来检测全局生成动作
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_signal("instantiation_compeleted"):
		if not main_scene.instantiation_compeleted.is_connected(_on_global_generation_completed):
			main_scene.instantiation_compeleted.connect(_on_global_generation_completed)

## fruit被摘除时的处理（由pickoff直接调用）
func on_fruit_removed():
	print("🩸 [DEBUG] bloodcut.on_fruit_removed() 被调用 - point_index:", point_index)
	fruit_removed = true
	_check_bleeding_conditions()

## fruit被摘除时的处理（通过信号）
func _on_fruit_picked():
	# 检查是否是当前位置的fruit被摘除
	if _is_current_position_fruit_picked():
		fruit_removed = true
		_check_bleeding_conditions()

## 检查是否当前位置的fruit被摘除
func _is_current_position_fruit_picked() -> bool:
	# 这里需要与pickoff系统配合
	# 简化版本：检查当前位置是否还有fruit
	if point_index == -1:
		return false
	
	# 通过fruits管理器检查
	var fruits_manager = _get_fruits_manager()
	if fruits_manager and fruits_manager.has_method("is_fruit_at_position"):
		return not fruits_manager.is_fruit_at_position(point_index)
	
	return false

## 获取fruits管理器
func _get_fruits_manager():
	# 查找fruits管理器（通常是场景中的fruits节点）
	var current_scene = get_tree().current_scene
	return current_scene.get_node_or_null("fruits")

## 检查是否应该开始流血
func _check_bleeding_conditions():
	print("🩸 [DEBUG] _check_bleeding_conditions() - point_index:", point_index, " fruit_removed:", fruit_removed, " generation_count:", generation_count)
	# 需要同时满足：fruit被摘除 && 经历过至少1次生成（生成bloodcut的当次不算）
	if fruit_removed and generation_count >= 1:
		print("🩸 [DEBUG] 条件满足! 显示bloodcut并开始流血 - point_index:", point_index)
		visible = true  # 显示bloodcut
		start_bleeding()
	else:
		print("🩸 [DEBUG] 条件不满足 - point_index:", point_index)

## 生成血滴
func _generate_blood_drop():
	if not is_bleeding or not blooddrop_container:
		print("🩸 [DEBUG] _generate_blood_drop() 跳过 - is_bleeding:", is_bleeding, " blooddrop_container:", blooddrop_container != null)
		return
	
	print("🩸 [DEBUG] _generate_blood_drop() 生成血滴 - point_index:", point_index)
	
	# 实例化血滴
	var blooddrop = BLOODDROP_SCENE.instantiate()
	
	# 设置血滴起始位置（完全对应bloodcut位置，无随机性）
	var drop_position = global_position
	blooddrop.global_position = drop_position
	
	print("🩸 [DEBUG] 血滴位置:", drop_position, " (与bloodcut位置完全一致)")
	
	# 添加到容器
	blooddrop_container.add_child(blooddrop)
	
	# 设置血滴的物理属性
	_setup_blooddrop_physics(blooddrop)

## 设置血滴物理属性
func _setup_blooddrop_physics(blooddrop: Node2D):
	# 如果血滴有RigidBody2D组件
	var rigid_body = blooddrop as RigidBody2D
	if rigid_body:
		# 设置初始速度
		var initial_velocity = Vector2(0, drop_speed)
		rigid_body.linear_velocity = initial_velocity
		# 设置重力
		rigid_body.gravity_scale = drop_gravity / 980.0  # 标准化重力
		return
	
	# 如果血滴是Sprite2D或其他Node2D，使用Tween实现掉落
	_animate_blooddrop_fall(blooddrop)

## 使用Tween动画实现血滴掉落
func _animate_blooddrop_fall(blooddrop: Node2D):
	var tween = create_tween()
	
	# 计算掉落目标位置（4倍屏幕高度距离）
	var viewport_size = get_viewport().get_visible_rect().size
	var fall_distance = viewport_size.y * 4  # 延长为4倍距离
	var target_position = blooddrop.global_position + Vector2(0, fall_distance)
	
	# 计算掉落时间（考虑重力加速度）
	var fall_time = sqrt(2 * fall_distance / drop_gravity)
	if fall_time <= 0:
		fall_time = 2.0  # 最少2秒的掉落时间
	
	print("🩸 [DEBUG] blooddrop掉落: 距离=", fall_distance, " 时间=", fall_time, "秒")
	
	# 执行掉落动画，完成后自动销毁
	tween.tween_property(blooddrop, "global_position", target_position, fall_time)
	tween.tween_callback(func(): 
		print("🩸 [DEBUG] blooddrop到达目标位置，销毁")
		if is_instance_valid(blooddrop):
			blooddrop.queue_free()
	)

## 当全局生成完成时调用（通过信号）
func _on_global_generation_completed():
	print("🩸 [DEBUG] bloodcut._on_global_generation_completed() 被调用 - point_index:", point_index)
	generation_count += 1
	print("🩸 [DEBUG] 生成次数更新为:", generation_count)
	_check_bleeding_conditions()

## 当branch生成时调用（外部调用，保留兼容性）
func on_branch_generated():
	generation_count += 1
	print("🩸 [DEBUG] 外部调用生成次数更新为:", generation_count)
	_check_bleeding_conditions()

## 手动触发检查（调试用）
func force_check_conditions():
	fruit_removed = true
	generation_count = 1
	_check_bleeding_conditions()

## 强制开始流血（调试用）
func force_start_bleeding():
	visible = true
	start_bleeding()

## 测试生成单个血滴（调试用）
func test_generate_single_drop():
	if not blooddrop_container:
		_setup_blooddrop_container()
	_generate_blood_drop()

func _on_animation_finished(anim_name: String):
	# 动画结束时的处理
	if anim_name == "bleeding" and is_bleeding:
		# 如果需要循环播放动画
		animation_player.play("bleeding")
