extends Node2D

## Main场景脚本
## 负责场景初始化、petal圆形实例化和生成交互控制

@onready var signalbus: Node = %Signalbus
@onready var globalbgm: AudioStreamPlayer = %globalbgm

# WindManager引用
var wind_manager: Node2D

# 鼠标静止检测信号
signal mouse_stopped_moving
signal mouse_started_moving
signal instantiation_compeleted

# Petal场景引用
const PETAL_SCENE = preload("res://Scence/petal.tscn")

# Petal实例化参数
@export_group("Petal Generation", "petal_")
@export var petal_count: int = 5  # petal数量
@export var petal_radius: float = 30.0  # 实例化圆形半径
@export var petal_auto_generate: bool = true  # 是否在场景启动时自动生成
@export_range(-180.0, 180.0, 1.0) var petal_ring_rotation_degrees: float = - 15.0  # 花环整体旋转角度（度）

# 鼠标静止检测参数
@export_group("Mouse Detection", "mouse_")
@export var mouse_still_time: float = 2.0  # 鼠标静止多少秒后触发

# 背景音乐控制参数
@export_group("Background Music", "bgm_")
@export var bgm_enabled: bool = true  # 是否启用背景音乐
@export_range(0.0, 1.0, 0.1) var bgm_volume: float = 1.0  # 背景音乐音量
@export var bgm_loop_check_interval: float = 5.0  # 循环检查间隔（秒）

# 重要节点引用
var first_point: Node2D
var sub_viewport: SubViewport
var fruits_node: Node2D

# Petal基础信息（仅用于生成）
var petal_positions: Array[Vector2] = []  # 记录所有petal的原始位置

# 生成控制参数
@export_group("Generation Control", "gen_")
@export var default_trunk_count: int = 1  # 默认trunk生成数量
@export var default_branch_decoration_count: int = 1  # 默认branch装饰组生成数量

# 曲线控制生成数量
@export_group("Generation Curves", "curve_")
@export var trunk_generation_curve: Curve  # 控制trunk生成数量的曲线
@export var branch_generation_curve: Curve  # 控制branch生成数量的曲线

# 交互计数器
var interaction_counter: int = 0

# Petal group名称常量
const PETAL_GROUP_PREFIX = "petal_position_"

# 鼠标静止检测变量
var last_mouse_position: Vector2
var mouse_still_timer: float = 0.0
var is_mouse_still: bool = false

# 游戏状态控制
var gameover: bool = false  # 游戏结束状态，禁用所有交互

# 背景音乐检查计时器
var bgm_check_timer: float = 0.0

# ==================== 输入处理 ====================

func _input(_event):
	# 如果游戏结束，禁用所有输入处理
	if gameover:
		return
		
	# 响应generate输入映射（空格键：协调生成trunk和branch装饰）
	if Input.is_action_just_pressed("generate"):
		_execute_coordinated_generation()

## 执行协调生成（trunk组 + branch装饰组）
func _execute_coordinated_generation(_trunk_count: int = 0, _branch_decoration_count: int = 0):
	if not fruits_node:
		return
	
	# 增加交互计数器
	interaction_counter += 1
	
	# 根据曲线资源确定实际生成数量
	var actual_trunk_count = _get_curve_based_count(trunk_generation_curve, default_trunk_count)
	var actual_branch_count = _get_curve_based_count(branch_generation_curve, default_branch_decoration_count)
	
	# 记录生成前的统计数据
	var initial_trunk_count = _get_current_trunk_count()
	var initial_branch_count = _get_current_branch_count()
	
	# 使用步骤式生成：循环执行"1个trunk + 1个branch装饰组"
	var max_generations = max(actual_trunk_count, actual_branch_count)
	_execute_step_by_step_generation(actual_trunk_count, actual_branch_count, max_generations)
	
	# 统计生成后的数据并显示结果
	var final_trunk_count = _get_current_trunk_count()
	var final_branch_count = _get_current_branch_count()
	
	var generated_trunks = final_trunk_count - initial_trunk_count
	var generated_branches = final_branch_count - initial_branch_count
	
	print("=== 生成统计 (交互次数: %d) ===" % interaction_counter)
	print("本次生成trunk: ", generated_trunks, " 个，现有trunk总数: ", final_trunk_count, " 个")
	print("本次生成branch: ", generated_branches, " 个，现有branch总数: ", final_branch_count, " 个")
	instantiation_compeleted.emit()

## 获取当前trunk数量
func _get_current_trunk_count() -> int:
	if not fruits_node or not fruits_node.has_method("get_trunk_count"):
		return 0
	return fruits_node.get_trunk_count()

## 获取当前branch数量
func _get_current_branch_count() -> int:
	if not fruits_node or not fruits_node.has_method("get_branch_count"):
		return 0
	return fruits_node.get_branch_count()

## 根据曲线资源获取生成数量
func _get_curve_based_count(curve: Curve, default_count: int) -> int:
	if not curve:
		print("警告：曲线为空，使用默认数量 %d" % default_count)
		return default_count
	
	# 确保交互次数在合理范围内
	var x_input = float(interaction_counter)
	x_input = clamp(x_input, 1.0, 20.0)  # 限制在曲线定义的X范围内
	
	# 从曲线采样
	var curve_value = curve.sample(x_input)
	
	# 使用四舍五入而不是直接截断
	var final_count = max(1, int(round(curve_value)))
	

	
	return final_count

## 执行trunk生成组
func _execute_trunk_generation_group(count: int):
	if count <= 0:
		return
	
	for i in range(count):
		if fruits_node.has_method("execute_trunk_generation"):
			var success = fruits_node.execute_trunk_generation()
			if not success:
				break
		else:
			break

## 执行步骤式生成（trunk和branch交替进行）
func _execute_step_by_step_generation(trunk_count: int, branch_count: int, max_steps: int):
	var trunk_generated = 0
	var branch_generated = 0
	
	for step in range(max_steps):
		var step_had_success = false
		
		# 步骤1：如果还需要trunk，生成1个trunk
		if trunk_generated < trunk_count:
			if fruits_node.has_method("execute_trunk_generation"):
				var trunk_success = fruits_node.execute_trunk_generation()
				if trunk_success:
					trunk_generated += 1
					step_had_success = true
		
		# 步骤2：如果还需要branch，生成1个branch装饰组
		if branch_generated < branch_count:
			# 记录生成前的END_BRANCH点状态
			var initial_end_branch_points = _get_current_end_branch_points()
			
			if fruits_node.has_method("execute_branch_generation"):
				var branch_success = fruits_node.execute_branch_generation()
				if branch_success:
					branch_generated += 1
					step_had_success = true
					
								# 查找新生成的END_BRANCH点并生成装饰
			var new_end_branch_points = _get_new_end_branch_points(initial_end_branch_points)
			_generate_decorations_at_points(new_end_branch_points)
		
		# 如果本步骤没有任何成功，并且已经完成了所需数量，可以提前结束
		if not step_had_success and trunk_generated >= trunk_count and branch_generated >= branch_count:
			break

## 执行branch装饰组生成
func _execute_branch_decoration_group(count: int):
	if count <= 0:
		return
	
	# 记录生成前的END_BRANCH点状态
	var initial_end_branch_points = _get_current_end_branch_points()
	
	for i in range(count):
		# 执行branch生成
		if fruits_node.has_method("execute_branch_generation"):
			var branch_success = fruits_node.execute_branch_generation()
			if not branch_success:
				continue
		else:
			break
		
		# 查找新生成的END_BRANCH点
		var new_end_branch_points = _get_new_end_branch_points(initial_end_branch_points)
		
		# 在新的END_BRANCH点上生成bloodcut和fruit
		_generate_decorations_at_points(new_end_branch_points)
		
		# 更新初始状态，为下一轮准备
		initial_end_branch_points = _get_current_end_branch_points()

## 获取当前所有END_BRANCH状态的点
func _get_current_end_branch_points() -> Array[int]:
	var end_branch_points: Array[int] = []
	if fruits_node and fruits_node.has_method("get_end_branch_points"):
		end_branch_points = fruits_node.get_end_branch_points()
	return end_branch_points

## 获取新生成的END_BRANCH点
func _get_new_end_branch_points(initial_points: Array[int]) -> Array[int]:
	var current_points = _get_current_end_branch_points()
	var new_points: Array[int] = []
	
	for point in current_points:
		if point not in initial_points:
			new_points.append(point)
	
	return new_points

## 在指定点位生成装饰（bloodcut和fruit）
func _generate_decorations_at_points(point_indices: Array[int]):
	if point_indices.size() == 0:
		return
	
	for point_index in point_indices:
		# 生成bloodcut
		if fruits_node.has_method("generate_bloodcut_at_point"):
			fruits_node.generate_bloodcut_at_point(point_index)
		
		# 生成fruit
		if fruits_node.has_method("generate_fruit_at_point"):
			fruits_node.generate_fruit_at_point(point_index)
		


# ==================== 现有代码保持不变 ====================

func _ready():
	print("🚀 [Main] 游戏开始初始化...")
	
	# 首先查找SubViewport相关节点
	_find_subviewport_structure()
	print("📍 [Main] SubViewport查找完成 - sub_viewport: ", sub_viewport != null, " fruits_node: ", fruits_node != null)
	
	# 查找First_Point（支持SubViewport结构）
	_find_first_point()
	print("🎯 [Main] First_Point查找完成: ", first_point != null)
	
	# 创建并初始化WindManager
	_create_wind_manager()
	print("💨 [Main] WindManager创建完成")
	
	# 如果启用自动生成，初始化petal系统
	if petal_auto_generate and first_point:
		print("🌸 [Main] 开始初始化petal系统...")
		_initialize_petal_system()
	elif not first_point:
		print("❌ [Main] 错误：未找到First_Point，跳过petal初始化")
	
	# 连接signalbus信号
	if signalbus:
		print("📡 [Main] 连接signalbus信号...")
		mouse_stopped_moving.connect(signalbus._on_mouse_stopped_moving)
		mouse_started_moving.connect(signalbus._on_mouse_started_moving)
	else:
		print("⚠️ [Main] 警告：未找到signalbus")
	
	# 初始化鼠标位置
	last_mouse_position = get_global_mouse_position()
	print("🖱️ [Main] 鼠标位置初始化完成")
	
	if globalbgm and bgm_enabled:
		# 设置音量
		globalbgm.volume_db = linear_to_db(bgm_volume)
		
		# 连接音频播放完成信号，确保循环播放
		if not globalbgm.finished.is_connected(_on_globalbgm_finished):
			globalbgm.finished.connect(_on_globalbgm_finished)
		
		# 确保音频资源设置为循环播放
		if globalbgm.stream and globalbgm.stream.has_method("set_loop"):
			globalbgm.stream.set_loop(true)
			print("🎵 [Main] 音频资源已设置为循环模式")
		
		globalbgm.play()
		print("🎵 [Main] 背景音乐开始播放，已设置自动循环，音量: ", bgm_volume)
	elif globalbgm and not bgm_enabled:
		globalbgm.stop()
		print("🔇 [Main] 背景音乐已禁用")
	else:
		print("⚠️ [Main] 警告：未找到背景音乐")
	
	print("✅ [Main] 游戏初始化完成！")

func _process(delta):
	# 如果游戏结束，禁用鼠标检测
	if not gameover:
		_update_mouse_detection(delta)
	
	# 定期监测背景音乐状态，确保一直播放
	_check_background_music(delta)

## 更新鼠标静止检测
func _update_mouse_detection(delta: float):
	var current_mouse_pos = get_global_mouse_position()
	
	# 检查鼠标是否移动了
	if current_mouse_pos != last_mouse_position:
		# 鼠标移动了
		if is_mouse_still:
			# 如果之前是静止状态，发出移动信号
			mouse_started_moving.emit()
			is_mouse_still = false
		
		# 重置计时器
		mouse_still_timer = 0.0
		last_mouse_position = current_mouse_pos
	else:
		# 鼠标没有移动，累积时间
		mouse_still_timer += delta
		
		# 检查是否达到静止时间阈值
		if mouse_still_timer >= mouse_still_time and not is_mouse_still:
			is_mouse_still = true
			mouse_stopped_moving.emit()
			

## 查找SubViewport结构
func _find_subviewport_structure():
	# 查找SubViewportContainer/SubViewport结构
	var subviewport_container = get_node_or_null("SubViewportContainer")
	if subviewport_container:
		sub_viewport = subviewport_container.get_node_or_null("SubViewport")
		if sub_viewport:
			# 在SubViewport中查找Fruits节点
			fruits_node = sub_viewport.get_node_or_null("Fruits")
	else:
		# 降级到传统查找方式
		fruits_node = get_node_or_null("Fruits")

## 查找First_Point（支持SubViewport结构）
func _find_first_point():
	# 优先在SubViewport结构中查找
	if sub_viewport and fruits_node:
		first_point = fruits_node.get_node_or_null("First_Point")
		if first_point:
			return
	
	# 降级到传统查找方式
	if fruits_node:
		first_point = fruits_node.get_node_or_null("First_Point")
		if first_point:
			return
	
	# 最后尝试直接查找
	first_point = get_node_or_null("First_Point")

## 初始化petal系统
func _initialize_petal_system():
	# 计算并设置所有petal的预定位置
	_calculate_petal_positions()
	
	# 在预定位置生成petal直到数量达到上限
	_generate_petals_to_limit()
	
	# 通知signalbus初始化花瓣计数
	if signalbus:
		print("🌸 [Main] 初始化花瓣计数: ", petal_count)

## 计算petal的预定位置
func _calculate_petal_positions():
	if not first_point:
		return
	
	var center_pos = first_point.global_position
	
	# 清空现有位置记录
	petal_positions.clear()
	
	# 计算每个petal的角度间隔
	var angle_step = 2 * PI / petal_count
	
	# 将度数转换为弧度
	var ring_rotation_radians = deg_to_rad(petal_ring_rotation_degrees)
	
	# 计算所有预定位置（包含整体旋转）
	for i in range(petal_count):
		var base_angle = i * angle_step
		var final_angle = base_angle + ring_rotation_radians  # 添加整体旋转
		var offset = Vector2(cos(final_angle), sin(final_angle)) * petal_radius
		var petal_pos = center_pos + offset
		petal_positions.append(petal_pos)

## 生成petal直到达到数量上限
func _generate_petals_to_limit():
	# 在所有空位生成petal
	for i in range(petal_count):
		if _is_position_empty(i):
			_instantiate_petal_at_position(i)

## 检查指定位置是否为空
func _is_position_empty(position_index: int) -> bool:
	var group_name = PETAL_GROUP_PREFIX + str(position_index)
	var petals_at_position = get_tree().get_nodes_in_group(group_name)
	
	# 清理无效的节点
	for petal in petals_at_position:
		if not is_instance_valid(petal) or not petal.is_inside_tree():
			petal.remove_from_group(group_name)
	
	# 重新检查该位置是否有有效的petal
	petals_at_position = get_tree().get_nodes_in_group(group_name)
	return petals_at_position.size() == 0

## 检查是否还有空位
func _has_empty_positions() -> bool:
	for i in range(petal_count):
		if _is_position_empty(i):
			return true
	return false

## 在空位实例化petal（自动寻找空位）
func _instantiate_petal_at_empty_position():
	# 寻找第一个空位
	for i in range(petal_count):
		if _is_position_empty(i):
			_instantiate_petal_at_position(i)
			instantiation_compeleted.emit()
			return
	


## 在指定位置实例化petal
func _instantiate_petal_at_position(position_index: int):
	if position_index < 0 or position_index >= petal_positions.size():
		return
	
	if not _is_position_empty(position_index):
		return
	
	var petal_pos = petal_positions[position_index]
	var center_pos = first_point.global_position
	
	# 实例化petal
	var petal = PETAL_SCENE.instantiate()
	petal.global_position = petal_pos
	
	# 设置petal的旋转（让sprite指向圆心）
	var sprite2d = petal.get_node("Sprite2D")
	if sprite2d:
		# 计算指向圆心的方向
		var direction_to_center = (center_pos - petal_pos).normalized()
		# 计算旋转角度（sprite的默认方向是向上，加90度调整 + 180度翻转让头指向圆心）
		var rotation_angle = direction_to_center.angle() + PI/2 + PI  # +90度 + 180度
		sprite2d.rotation = rotation_angle
	
	# 添加到正确的父节点
	_add_petal_to_correct_parent(petal)
	
	# 将petal添加到对应位置的group中
	var group_name = PETAL_GROUP_PREFIX + str(position_index)
	petal.add_to_group(group_name)

## 智能选择petal的父节点
func _add_petal_to_correct_parent(petal: Node):
	# 优先添加到SubViewport
	if sub_viewport:
		sub_viewport.add_child(petal)
	# 降级到Fruits节点
	elif fruits_node:
		fruits_node.add_child(petal)
	# 最后降级到当前节点
	else:
		add_child(petal)

## 清理无效的petal节点引用
func _clean_invalid_petal_references():
	# 使用group系统，这个方法现在主要用于调试
	for i in range(petal_count):
		var group_name = PETAL_GROUP_PREFIX + str(i)
		var _petals_at_position = get_tree().get_nodes_in_group(group_name)
		# 这个方法主要用于调试，实际清理在_is_position_empty中进行

func _on_signalbus_fruit_picked_now() -> void:
	# 调试：显示当前状态
	_clean_invalid_petal_references()
	
	# 检查是否有空位
	if _has_empty_positions():
		_instantiate_petal_at_empty_position()

func _on_curtain_fade_in_completed() -> void:
	_execute_coordinated_generation() ## 现在由曲线资源控制生成数量

## 创建并初始化WindManager
func _create_wind_manager():
	# 加载WindManager脚本
	var wind_manager_script = preload("res://Script/wind_manager.gd")
	wind_manager = Node2D.new()
	wind_manager.set_script(wind_manager_script)
	wind_manager.name = "WindManager"
	
	# 添加到场景
	add_child(wind_manager)
	


## 设置游戏结束状态（供外部调用）
func set_gameover(state: bool):
	gameover = state
	if gameover:
		print("🎮 [Main] 游戏结束，输入和鼠标检测已禁用")

## 获取游戏结束状态（供外部调用）
func is_gameover() -> bool:
	return gameover

## 更新花环旋转角度（供运行时调用）
func update_petal_ring_rotation(new_rotation_degrees: float):
	petal_ring_rotation_degrees = new_rotation_degrees
	
	# 重新计算所有petal位置
	_calculate_petal_positions()
	
	# 更新现有petal的位置
	_update_existing_petal_positions()
	


## 更新现有petal的位置到新计算的位置
func _update_existing_petal_positions():
	for i in range(petal_count):
		if i >= petal_positions.size():
			continue
			
		var group_name = PETAL_GROUP_PREFIX + str(i)
		var petals_at_position = get_tree().get_nodes_in_group(group_name)
		
		for petal in petals_at_position:
			if is_instance_valid(petal) and petal.is_inside_tree():
				var new_position = petal_positions[i]
				var center_pos = first_point.global_position
				
				# 使用Tween创建平滑的位置过渡
				var position_tween = create_tween()
				position_tween.tween_property(petal, "global_position", new_position, 0.5)
				position_tween.set_ease(Tween.EASE_OUT)
				position_tween.set_trans(Tween.TRANS_CUBIC)
				
				# 同时更新petal的sprite旋转
				var sprite2d = petal.get_node("Sprite2D")
				if sprite2d:
					var direction_to_center = (center_pos - new_position).normalized()
					var new_rotation = direction_to_center.angle() + PI/2 + PI
					var rotation_tween = create_tween()
					rotation_tween.tween_property(sprite2d, "rotation", new_rotation, 0.5)
					rotation_tween.set_ease(Tween.EASE_OUT)
					rotation_tween.set_trans(Tween.TRANS_CUBIC)

## 监测背景音乐状态
func _check_background_music(delta: float):
	if not bgm_enabled or not globalbgm:
		return
	
	# 使用计时器减少检查频率，提高性能
	bgm_check_timer += delta
	if bgm_check_timer >= bgm_loop_check_interval:
		bgm_check_timer = 0.0
		
		if not globalbgm.playing:
			# 如果背景音乐停止了，重新播放
			globalbgm.play()


## 背景音乐播放完成时的回调
func _on_globalbgm_finished():
	if globalbgm and bgm_enabled:
		# 立即重新播放，实现无缝循环
		globalbgm.play()


## 动态控制背景音乐（供外部调用）
func set_background_music_enabled(enabled: bool):
	bgm_enabled = enabled
	if globalbgm:
		if enabled:
			if not globalbgm.playing:
				globalbgm.play()

		else:
			globalbgm.stop()


## 动态调整背景音乐音量（供外部调用）
func set_background_music_volume(volume: float):
	bgm_volume = clamp(volume, 0.0, 1.0)
	if globalbgm:
		globalbgm.volume_db = linear_to_db(bgm_volume)
