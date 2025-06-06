extends Node2D

## WindManager脚本
## 负责管理树的Line2D节点（trunk、branch）的协调风抖动效果
## petal和fruit的风抖动效果由pickoff脚本独立管理

# 风抖动参数（与pickoff保持一致）
var wind_duration: float = 5.0
var wind_intensity: float = 1.0
var wind_frequency: float = 0.3
var wind_horizontal_bias: float = 0.2
var wind_randomness: float = 0.3
var wind_fade_in_time: float = 2.0
var wind_fade_out_time: float = 2.0

# 管理变量
var is_wind_active: bool = false
var wind_start_time: float = 0.0
var current_wind_intensity: float = 0.0
var wind_tween: Tween
var is_fading_out: bool = false

# 需要抖动的节点列表
var shakeable_nodes: Array[Dictionary] = []  # 存储 {node: Node2D, original_pos: Vector2, type: String}

# 引用
var fruits_controller: Node2D
var signalbus: Node

func _ready():
	# 查找SignalBus并连接信号
	signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
	if signalbus:
		if signalbus.has_signal("wind_shake_start"):
			signalbus.wind_shake_start.connect(_on_wind_shake_start)
		# 注意：不再连接wind_shake_stop信号，完全依赖duration参数控制
		print("WindManager: SignalBus连接成功")
	else:
		print("WindManager: 警告 - 未找到SignalBus")
	
	# 查找Fruits控制器
	fruits_controller = _find_fruits_controller()
	if fruits_controller:
		print("WindManager: 找到Fruits控制器: ", fruits_controller.name, " 路径: ", fruits_controller.get_path())
	else:
		print("WindManager: 警告 - 未找到Fruits控制器")
	
	print("WindManager初始化完成")

## 查找FruitLayer控制器
func _find_fruits_controller() -> Node2D:
	# 尝试多种可能的路径指向fruitlayer
	var possible_paths = [
		"../SubViewportContainer/SubViewport/Fruitlayer",  # 正确的fruitlayer路径（大写F）
		"/root/Main/SubViewportContainer/SubViewport/Fruitlayer",  # 绝对路径
		"../SubViewportContainer/SubViewport/fruitlayer",  # 小写版本
		"/root/Main/SubViewportContainer/SubViewport/fruitlayer",  # 小写绝对路径
		"../Fruitlayer",  # 简化路径（大写）
		"../fruitlayer",  # 简化路径（小写）
		"Fruitlayer",     # 直接路径（大写）
		"fruitlayer"     # 直接路径（小写）
	]
	
	print("WindManager: 开始查找FruitLayer控制器...")
	for path in possible_paths:
		print("WindManager: 尝试路径: ", path)
		var node = get_node_or_null(path)
		if node:
			print("WindManager: 在路径 '", path, "' 找到FruitLayer控制器")
			return node
		else:
			print("WindManager: 路径 '", path, "' 未找到节点")
	
	print("WindManager: 所有路径都未找到FruitLayer控制器")
	return null

## 响应风抖动开始信号
func _on_wind_shake_start(duration: float, intensity: float, frequency: float, horizontal_bias: float, randomness: float):
	print("WindManager: 接收到风抖动开始信号")
	
	# 更新参数
	wind_duration = duration
	wind_intensity = intensity
	wind_frequency = frequency
	wind_horizontal_bias = horizontal_bias
	wind_randomness = randomness
	
	# 收集所有需要抖动的节点
	_collect_shakeable_nodes()
	
	# 开始风抖动
	_start_wind_effect()

# 注意：已移除_on_wind_shake_stop方法，完全依赖duration参数控制

## 收集所有需要抖动的节点（仅trunk和branch）
func _collect_shakeable_nodes():
	shakeable_nodes.clear()
	
	print("WindManager: 开始收集可抖动节点（仅树的Line2D节点）...")
	
	# 收集trunk和branch的Line2D节点
	if fruits_controller:
		print("WindManager: 从FruitLayer控制器收集树的Line2D节点...")
		var tree_count_before = shakeable_nodes.size()
		_collect_line2d_from_node(fruits_controller, "Tree")
		var tree_count_after = shakeable_nodes.size()
		print("WindManager: 从树中收集到 ", tree_count_after - tree_count_before, " 个Line2D节点")
	else:
		print("WindManager: 跳过树节点收集（未找到FruitLayer控制器）")
	
	print("WindManager: 总共收集到 ", shakeable_nodes.size(), " 个可抖动节点")
	
	# 打印所有收集到的节点信息
	for i in range(shakeable_nodes.size()):
		var node_data = shakeable_nodes[i]
		print("  节点 ", i, ": ", node_data.type, " - ", node_data.node.name, " (", node_data.node.get_path(), ")")

## 从指定节点递归收集Line2D节点（专门用于branch和trunk）
func _collect_line2d_from_node(node: Node, node_type: String):
	print("WindManager: 检查节点: ", node.name, " (", node.get_class(), ") 路径: ", node.get_path())
	
	# 只收集Line2D节点
	if node is Line2D:
		var line = node as Line2D
		shakeable_nodes.append({
			"node": line,
			"original_pos": line.position,
			"type": node_type
		})
		print("WindManager: ✓ 添加Line2D节点: ", node.name, " 类型: ", node_type)
	
	# 递归检查子节点
	for child in node.get_children():
		_collect_line2d_from_node(child, node_type)



## 开始风效果
func _start_wind_effect():
	if is_wind_active:
		_force_stop_wind_effect()
	
	print("WindManager: 开始风抖动效果，节点数量: ", shakeable_nodes.size())
	is_wind_active = true
	is_fading_out = false
	wind_start_time = Time.get_ticks_msec() / 1000.0
	current_wind_intensity = 0.0
	
	# 创建渐入Tween
	if wind_tween:
		wind_tween.kill()
	wind_tween = create_tween()
	wind_tween.tween_property(self, "current_wind_intensity", wind_intensity, wind_fade_in_time)
	wind_tween.set_ease(Tween.EASE_OUT)
	wind_tween.set_trans(Tween.TRANS_SINE)

# 注意：已移除_stop_wind_effect方法，使用_start_fade_out方法替代

## 开始渐出效果
func _start_fade_out(fade_duration: float):
	if not is_wind_active or is_fading_out:
		return
	
	is_fading_out = true
	print("WindManager: 开始渐出，持续时间: ", fade_duration)
	
	# 创建渐出Tween
	if wind_tween:
		wind_tween.kill()
	wind_tween = create_tween()
	wind_tween.tween_property(self, "current_wind_intensity", 0.0, fade_duration)
	wind_tween.set_ease(Tween.EASE_IN)
	wind_tween.set_trans(Tween.TRANS_SINE)
	
	# 渐出完成后重置状态
	wind_tween.tween_callback(_complete_wind_stop)

## 检查是否正在渐出
func _is_fading_out() -> bool:
	return is_fading_out

## 强制停止风效果
func _force_stop_wind_effect():
	if wind_tween:
		wind_tween.kill()
		wind_tween = null
	is_wind_active = false
	is_fading_out = false
	current_wind_intensity = 0.0
	_reset_all_positions()

## 完成风效果停止
func _complete_wind_stop():
	is_wind_active = false
	is_fading_out = false
	current_wind_intensity = 0.0
	_reset_all_positions()

## 重置所有节点位置
func _reset_all_positions():
	for node_data in shakeable_nodes:
		var node = node_data.node
		var original_pos = node_data.original_pos
		if is_instance_valid(node):
			if node is Line2D:
				node.position = original_pos

func _process(delta):
	if is_wind_active:
		_update_wind_effect()

## 更新风效果
func _update_wind_effect():
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed_time = current_time - wind_start_time
	
	# 计算何时开始渐出（确保在总时长内完成渐出）
	var fade_out_start_time = max(0.0, wind_duration - wind_fade_out_time)
	
	# 检查是否应该开始渐出
	if wind_duration > 0 and elapsed_time >= fade_out_start_time and current_wind_intensity > 0:
		var remaining_time = wind_duration - elapsed_time
		if remaining_time <= wind_fade_out_time and not _is_fading_out():
			print("WindManager: 开始渐出，剩余时间: ", remaining_time)
			_start_fade_out(remaining_time)
			return
	
	# 检查是否完全结束
	if wind_duration > 0 and elapsed_time >= wind_duration:
		_force_stop_wind_effect()
		return
	
	# 应用风抖动到所有节点
	for node_data in shakeable_nodes:
		_apply_wind_to_node(node_data, elapsed_time)

## 对单个节点应用风抖动
func _apply_wind_to_node(node_data: Dictionary, elapsed_time: float):
	var node = node_data.node
	var original_pos = node_data.original_pos
	var node_type = node_data.type
	
	if not is_instance_valid(node) or current_wind_intensity <= 0:
		return
	
	# 基于统一时间基准的正弦波抖动
	var time_factor = elapsed_time / wind_frequency
	var base_shake_x = sin(time_factor * TAU) * current_wind_intensity
	var base_shake_y = sin(time_factor * TAU * 0.7) * current_wind_intensity
	
	# 应用水平偏向
	base_shake_x *= wind_horizontal_bias
	base_shake_y *= (1.0 - wind_horizontal_bias * 0.5)
	
	# 添加基于节点的随机性（确保每个节点不同但一致）
	var node_hash = hash(node.get_instance_id())
	var random_seed = int(elapsed_time * 10.0) + node_hash
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	
	var random_factor_x = rng.randf_range(-wind_randomness, wind_randomness)
	var random_factor_y = rng.randf_range(-wind_randomness, wind_randomness)
	
	# 根据节点类型调整强度（仅处理Tree类型）
	var intensity_multiplier = 0.6  # 树枝抖动较轻
	
	var final_shake_x = (base_shake_x + (random_factor_x * current_wind_intensity)) * intensity_multiplier
	var final_shake_y = (base_shake_y + (random_factor_y * current_wind_intensity)) * intensity_multiplier
	
	# 应用抖动偏移
	var shake_offset = Vector2(final_shake_x, final_shake_y)
	
	# 只处理Line2D节点
	if node is Line2D:
		node.position = original_pos + shake_offset 
