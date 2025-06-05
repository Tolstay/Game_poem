extends Node2D

## Fruits控制器
## 负责管理所有生成点的坐标与状态，控制生成器的交互

# 点状态枚举
enum PointStatus {
	AVAILABLE,    # 可生成状态
	EXHAUSTED,    # 已耗尽状态
	PATH_TRUNK,   # 路过节点：剩余次数1但无合法路径
	END_TRUNK,    # 终点节点：剩余次数2但无合法路径
	END_BRANCH    # branch终点节点：不可生成
}

# 点类型枚举
enum PointType {
	TRUNK_POINT,      # trunk点
	BRANCH_POINT      # branch点
}

# 生成点坐标记录
var point_positions: Array[Vector2] = []
var point_states: Array[int] = []  # 记录剩余生成次数，0=已耗尽，>0=可用次数
var point_directions: Array[Vector2] = []  # 记录每个点的生长方向
var point_generated_branches: Array[Array] = []  # 记录每个点已生成的分支方向
var point_status: Array[PointStatus] = []  # 记录每个点的当前状态
var point_nodes: Array[Node2D] = []  # 直接引用每个trunk点节点
var point_types: Array[PointType] = []  # 记录每个点的类型
var point_parent_segments: Array[int] = []  # branch_point所属的线段索引（trunk_point为-1）

# 线段信息记录
var trunk_segments: Array[Dictionary] = []
# 每个Dictionary包含：
# {
#   "start_point_index": int,     # 起点在point_positions中的索引
#   "end_point_index": int,       # 终点在point_positions中的索引
#   "length": float,              # 线段长度
#   "max_branch_points": int,     # 最大branch_point数量
#   "current_branch_count": int,  # 当前已生成的branch_point数量
#   "branch_point_indices": Array[int],  # 该线段上的branch_point索引
#   "curve_points": Array[Vector2]  # 完整的弯曲路径点（包括起点、折线点、终点）
# }



# 生成器引用
var generator: Node2D

# Fruitlayer节点引用（用于管理所有生成的内容）
var fruit_layer: Node2D

# 生成参数
@export var max_generations_per_point: int = 2  # 每个生成点的最大生成次数
@export var min_branch_points_per_segment: int = 1       # 每线段最少branch_point数（物理约束的最小值）
@export var max_branch_points_per_segment: int = 3       # 每线段最多branch_point数（物理约束的最大值）



# Branch生成参数（仅保留位置相关参数）
var branch_position_min: float = 0.15  # branch_point在线段上的最小位置（0.0-1.0）
var branch_position_max: float = 0.85  # branch_point在线段上的最大位置（0.0-1.0）
var branch_collision_radius: float = 40.0  # branch_point的碰撞半径（决定实际可容纳数量）

# 折线点branch生成参数
@export_group("Bend Point Branch Generation", "bend_branch_")
@export var bend_branch_enabled: bool = true  # 是否启用基于折线点的branch生成
@export var bend_branch_probability: float = 0.6  # 每个折线点生成branch_point的概率
@export var bend_branch_collision_radius: float = 25.0  # 折线点branch_point的碰撞半径



# 记录本轮参与生成的点
var points_used_this_round: Array[int] = []

# 记录已实例化果实的节点
var points_with_fruit: Array[bool] = []

# 折线点管理（为"G"键功能预留）
var stored_bend_points: Array[Vector2] = []  # 存储的折线点，等待"G"键处理
var bend_point_segments: Array[int] = []  # 记录每个折线点所属的线段索引

# 生成点场景
const BRANCH_POINT_SCENE = preload("res://Scence/branch_point.tscn")
const FRUIT_SCENE = preload("res://Scence/fruit.tscn")
const BLOODCUT_SCENE = preload("res://Scence/bloodcut.tscn")

func _ready():
	# 获取生成器引用
	generator = $BranchGenerator
	
	# 查找或创建Fruitlayer节点
	_find_or_create_fruit_layer()
	
	# 记录初始生成点
	_record_initial_points()

## 查找或创建Fruitlayer节点
func _find_or_create_fruit_layer():
	# 优先查找用户创建的 "Fruitlayer" 节点
	var existing_fruitlayer = get_parent().get_node_or_null("Fruitlayer")
	
	if existing_fruitlayer and existing_fruitlayer is Node2D:
		# 找到了用户创建的正确类型的Fruitlayer节点
		fruit_layer = existing_fruitlayer as Node2D
		return
	
	# 如果没找到正确的Fruitlayer，创建备用节点
	fruit_layer = Node2D.new()
	fruit_layer.name = "FruitlayerBackup"
	get_parent().call_deferred("add_child", fruit_layer)

# ==================== 输入处理 ====================

# 删除原有的 _input() 方法和相关的执行方法

# ==================== 初始化和数据管理 ====================

## 记录所有生成点的坐标和状态
func _record_initial_points():
	# 遍历子节点，找到所有生成点
	for child in get_children():
		if "Point" in child.name:
			point_positions.append(child.global_position)
			
			# 检查是否为特殊的起始点，给予额外生成机会
			var initial_generations = max_generations_per_point
			if child.name == "First_Point":
				initial_generations = 3  # 起始点拥有3次生成机会
			
			point_states.append(initial_generations)  # 设置生成次数
			point_directions.append(Vector2.ZERO)  # 初始点没有方向
			point_generated_branches.append([])  # 初始化空的分支记录
			point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
			point_nodes.append(child)  # 记录节点引用
			point_types.append(PointType.TRUNK_POINT)  # 初始点都是trunk点
			point_parent_segments.append(-1)  # trunk点不属于任何线段
			points_with_fruit.append(false)  # 初始化果实标记

## 添加新生成点（trunk点）
func _add_new_point(pos: Vector2, direction: Vector2 = Vector2.ZERO, node: Node2D = null):
	var new_point_index = point_positions.size()
	point_positions.append(pos)
	point_states.append(max_generations_per_point)  # 新生成的点有完整的生成次数
	point_directions.append(direction.normalized())  # 记录生长方向
	point_generated_branches.append([])  # 初始化空的分支记录
	point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
	point_nodes.append(node)  # 记录节点引用
	point_types.append(PointType.TRUNK_POINT)  # 新生成的点都是trunk点
	point_parent_segments.append(-1)  # trunk点不属于任何线段
	points_with_fruit.append(false)  # 初始化果实标记
	return new_point_index

## 添加新的branch_point到管理系统
func _add_branch_point(pos: Vector2, parent_segment_index: int, node: Node2D) -> int:
	var branch_point_index = point_positions.size()
	point_positions.append(pos)
	point_states.append(1)  # branch_point只有1次生成机会
	point_directions.append(Vector2.ZERO)  # branch_point初始没有方向
	point_generated_branches.append([])  # 初始化空的分支记录
	point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
	point_nodes.append(node)  # 记录节点引用
	point_types.append(PointType.BRANCH_POINT)  # 标记为branch点
	point_parent_segments.append(parent_segment_index)  # 记录所属线段
	points_with_fruit.append(false)  # 初始化果实标记
	
	return branch_point_index

# ==================== Trunk生成 ====================

## 调用生成器执行生成
func _call_generator_generate():
	if generator and generator.has_method("generate"):
		generator.generate()

## 减少参与生成的点的剩余次数
func _decrease_generation_counts():
	for point_index in points_used_this_round:
		if point_index < point_states.size():
			point_states[point_index] -= 1
			
			# 更新状态
			if point_states[point_index] <= 0:
				point_status[point_index] = PointStatus.EXHAUSTED
	
	# 生成完成后的清理
	_post_generation_cleanup()

## 记录点被使用
func _mark_point_used(point_index: int):
	if point_index not in points_used_this_round:
		points_used_this_round.append(point_index)

## 记录生成的分支方向
func _record_generated_branch(point_index: int, direction: Vector2):
	if point_index < point_generated_branches.size():
		point_generated_branches[point_index].append(direction)

## 获取点已生成的分支方向
func get_point_generated_branches(point_index: int) -> Array:
	if point_index < point_generated_branches.size():
		return point_generated_branches[point_index]
	return []

## 记录新的trunk线段（由生成器调用）
func _record_trunk_segment(start_point_index: int, end_point_index: int):
	if start_point_index >= point_positions.size() or end_point_index >= point_positions.size():
		return
	
	var start_pos = point_positions[start_point_index]
	var end_pos = point_positions[end_point_index]
	var segment_length = start_pos.distance_to(end_pos)
	
	# 根据长度计算最大branch_point数量
	var max_branch_points = _calculate_max_branch_points(segment_length)
	
	var segment_data = {
		"start_point_index": start_point_index,
		"end_point_index": end_point_index,
		"length": segment_length,
		"max_branch_points": max_branch_points,
		"current_branch_count": 0,
		"branch_point_indices": [],
		"curve_points": []
	}
	
	trunk_segments.append(segment_data)

# ==================== Branch点生成 ====================

## 在任意可用线段上尝试生成branch_point（统一接口）
func _try_generate_branch_point_anywhere(available_segments: Array[int]) -> int:
	# 调用generator尝试生成branch点
	if generator and generator.has_method("try_generate_branch_point_anywhere"):
		return generator.try_generate_branch_point_anywhere(available_segments)
	else:
		return -1

## 尝试在指定线段上生成branch_point（统一接口，返回新点索引或-1）
func _try_generate_branch_point_on_segment(segment_index: int) -> int:
	# 调用generator尝试在指定线段生成branch点
	if generator and generator.has_method("try_generate_branch_point_on_segment"):
		return generator.try_generate_branch_point_on_segment(segment_index)
	else:
		return -1

## 获取线段数据（提取公共逻辑）
func _get_segment_data(segment_index: int) -> Dictionary:
	if segment_index >= trunk_segments.size():
		return {}
	
	var segment = trunk_segments[segment_index]
	var start_pos = point_positions[segment.start_point_index]
	var end_pos = point_positions[segment.end_point_index]
	
	return {
		"start_pos": start_pos,
		"end_pos": end_pos,
		"segment": segment
	}



## 在指定位置创建branch_point（统一接口）
func _create_branch_point_at_position(branch_pos: Vector2, segment_index: int) -> int:
	# 创建branch_point实例
	var branch_point = BRANCH_POINT_SCENE.instantiate()
	branch_point.global_position = branch_pos
	
	# 添加到Fruitlayer而不是当前节点
	if fruit_layer:
		fruit_layer.add_child(branch_point)
	else:
		add_child(branch_point)
	
	# 添加到点位管理系统
	var branch_point_index = _add_branch_point(branch_pos, segment_index, branch_point)
	
	# 更新线段数据
	_update_segment_branch_count(segment_index, branch_point_index)
	
	return branch_point_index

## 更新线段的branch计数（提取公共逻辑）
func _update_segment_branch_count(segment_index: int, branch_point_index: int):
	if segment_index < trunk_segments.size():
		trunk_segments[segment_index].current_branch_count += 1
		trunk_segments[segment_index].branch_point_indices.append(branch_point_index)

# ==================== 折线点Branch生成 ====================

## 存储折线点用于后续处理
func _store_bend_points_for_future_processing(all_points: Array[Vector2], segment_index: int = -1):
	if not bend_branch_enabled or all_points.size() <= 2:
		return
	
	# 如果传入了有效的线段索引，使用它；否则使用默认逻辑
	var target_segment_index = segment_index
	if target_segment_index < 0:
		target_segment_index = trunk_segments.size() - 1
	
	if target_segment_index < 0 or target_segment_index >= trunk_segments.size():
		return
	
	# 存储完整的弯曲路径到线段数据中
	trunk_segments[target_segment_index].curve_points = all_points.duplicate()
	
	# 同时保持原有的折线点存储逻辑（用于F键功能）
	for i in range(1, all_points.size() - 1):
		var bend_point = all_points[i]
		stored_bend_points.append(bend_point)
		bend_point_segments.append(target_segment_index)

## 获取存储的折线点数据（供generator调用）
func get_stored_bend_points() -> Dictionary:
	return {
		"points": stored_bend_points,
		"segments": bend_point_segments
	}

## 获取线段的弯曲路径点（供generator调用）
func get_segment_curve_points(segment_index: int) -> Array[Vector2]:
	if segment_index < 0 or segment_index >= trunk_segments.size():
		return []
	
	var curve_points = trunk_segments[segment_index].curve_points
	if curve_points.size() > 0:
		return curve_points
	else:
		# 如果没有弯曲数据，返回直线端点
		var segment = trunk_segments[segment_index]
		var start_pos = point_positions[segment.start_point_index]
		var end_pos = point_positions[segment.end_point_index]
		return [start_pos, end_pos]

## 在折线点位置创建branch_point
func _create_branch_point_at_bend_position(bend_pos: Vector2, segment_index: int):
	# 检查线段是否还有容量
	if segment_index >= 0 and segment_index < trunk_segments.size():
		var segment = trunk_segments[segment_index]
		if segment.current_branch_count >= segment.max_branch_points:
			return
	
	var branch_point = BRANCH_POINT_SCENE.instantiate()
	branch_point.global_position = bend_pos
	
	# 添加到Fruitlayer而不是当前节点
	if fruit_layer:
		fruit_layer.add_child(branch_point)
	else:
		add_child(branch_point)
	
	var branch_point_index = _add_branch_point(bend_pos, segment_index, branch_point)
	
	# 更新线段的branch计数（如果线段还存在）
	if segment_index >= 0 and segment_index < trunk_segments.size():
		_update_segment_branch_count(segment_index, branch_point_index)

# ==================== 碰撞检测 ====================

## 检查branch_point位置是否与已有点碰撞
func _check_branch_point_collision(new_pos: Vector2) -> bool:
	for pos in point_positions:
		if (pos - new_pos).length() < branch_collision_radius:
			return true
	return false

## 检查折线点位置是否与现有点碰撞
func _check_bend_point_collision(bend_pos: Vector2) -> bool:
	for pos in point_positions:
		if (pos - bend_pos).length() < bend_branch_collision_radius:
			return true
	return false

# ==================== Branch线段生成相关 ====================

## 获取所有可用的branch_point索引
func _get_available_branch_points() -> Array[int]:
	var available_points: Array[int] = []
	for i in range(point_positions.size()):
		if point_types[i] == PointType.BRANCH_POINT and point_states[i] > 0:
			available_points.append(i)
	return available_points

## 创建完整的branch（线段 + 终点）- 通过调用generator实现
func _create_complete_branch(start_point_index: int, start_pos: Vector2, end_pos: Vector2, direction: Vector2):
	# 调用generator创建完整branch
	if generator and generator.has_method("create_complete_branch"):
		generator.create_complete_branch(start_point_index, start_pos, end_pos, direction)

# ==================== 查询和状态管理 ====================

## 检查是否有可用的trunk线段
func _has_available_trunk_segments() -> bool:
	for segment in trunk_segments:
		if segment.current_branch_count < segment.max_branch_points:
			return true
	return false

## 获取所有可用的trunk线段索引
func _get_available_trunk_segments() -> Array[int]:
	var available_segments: Array[int] = []
	for i in range(trunk_segments.size()):
		var segment = trunk_segments[i]
		if segment.current_branch_count < segment.max_branch_points:
			available_segments.append(i)
	return available_segments

## 根据线段长度计算最大branch_point数量
func _calculate_max_branch_points(segment_length: float) -> int:
	# 基于物理约束的计算逻辑
	var ideal_count = int(segment_length / 40.0)  # 每40像素一个branch_point
	return clamp(ideal_count, min_branch_points_per_segment, max_branch_points_per_segment)

## 获取当前可用的生成点数量
func get_available_points_count() -> int:
	var count = 0
	for state in point_states:
		if state > 0:
			count += 1
	return count



## 设置点为无空间状态
func set_point_no_space(point_index: int):
	if point_index >= point_status.size():
		return
	
	# 检查剩余生成次数，设置相应的无空间状态
	var remaining_count = point_states[point_index] if point_index < point_states.size() else 0
	
	if remaining_count <= 0:
		point_status[point_index] = PointStatus.END_TRUNK  # 无剩余次数且无路径
	else:
		point_status[point_index] = PointStatus.PATH_TRUNK  # 有剩余次数但无路径



# ==================== 清理和维护 ====================

## 生成后清理
func _post_generation_cleanup():
	# 清空本轮使用记录
	points_used_this_round.clear()



## 供generator调用的接口方法 ====================

## 获取线段数据（供generator调用）
func get_segment_data(segment_index: int) -> Dictionary:
	return _get_segment_data(segment_index)

## 检查branch点是否可以在指定位置创建（供generator调用）
func can_create_branch_point_at(pos: Vector2) -> bool:
	return not _check_branch_point_collision(pos)

## 检查线段是否还能创建branch点（供generator调用）
func can_segment_create_branch_point(segment_index: int) -> bool:
	if segment_index >= trunk_segments.size():
		return false
	var segment = trunk_segments[segment_index]
	return segment.current_branch_count < segment.max_branch_points

## 在指定位置创建branch点（供generator调用）
func create_branch_point_at_position(branch_pos: Vector2, segment_index: int) -> int:
	return _create_branch_point_at_position(branch_pos, segment_index)

## 标记branch点为已使用（供generator调用）
func mark_branch_point_exhausted(point_index: int):
	if point_index < point_states.size():
		point_states[point_index] = 0
		point_status[point_index] = PointStatus.EXHAUSTED

## 检查是否有终点状态的节点，实例化果实
func _instantiate_fruits_at_endpoint_nodes():
	# 确保points_with_fruit数组大小与点位数组同步
	while points_with_fruit.size() < point_positions.size():
		points_with_fruit.append(false)
	
	for i in range(point_positions.size()):
		# 检查是否为END_TRUNK或END_BRANCH状态，并且还没有果实
		if (point_status[i] == PointStatus.END_TRUNK or point_status[i] == PointStatus.END_BRANCH) and not points_with_fruit[i]:
			# 先实例化bloodcut
			var bloodcut = BLOODCUT_SCENE.instantiate()
			bloodcut.global_position = point_positions[i]
			
			# 添加到Fruitlayer而不是当前节点
			if fruit_layer:
				fruit_layer.add_child(bloodcut)
			else:
				add_child(bloodcut)
			
			# 再实例化fruit（fruit会在视觉上遮蔽bloodcut）
			var fruit = FRUIT_SCENE.instantiate()
			fruit.global_position = point_positions[i]
			
			# 计算fruit的正确旋转方向
			var fruit_rotation = _calculate_fruit_rotation(i)
			
			# 获取fruit的Sprite2D节点并设置旋转
			var sprite = fruit.get_node("Sprite2D")
			if sprite:
				sprite.rotation = fruit_rotation
			
			# 添加到Fruitlayer而不是当前节点
			if fruit_layer:
				fruit_layer.add_child(fruit)
			else:
				add_child(fruit)
			
			points_with_fruit[i] = true  # 标记为已实例化果实

## 计算fruit的旋转角度，使其尾部（负y轴）连接到branch
func _calculate_fruit_rotation(point_index: int) -> float:
	# 获取该点的生长方向
	var growth_direction = Vector2.ZERO
	if point_index < point_directions.size():
		growth_direction = point_directions[point_index]
	
	# 如果没有方向信息，尝试从父线段计算
	if growth_direction == Vector2.ZERO:
		growth_direction = _calculate_growth_direction_from_parent(point_index)
	
	# 如果仍然没有方向信息，使用默认方向（向上）
	if growth_direction == Vector2.ZERO:
		growth_direction = Vector2.UP
	
	# 计算旋转角度
	# fruit的正y轴是头，负y轴是尾
	# 我们希望尾部连接到branch，即正y轴指向branch生长方向
	# 这样负y轴自然指向branch的来源，实现尾部连接
	
	# 计算从默认方向（向上，即Vector2.UP）到growth_direction的旋转角度
	var rotation_angle = growth_direction.angle() - Vector2.UP.angle()
	
	return rotation_angle

## 从父线段计算生长方向
func _calculate_growth_direction_from_parent(point_index: int) -> Vector2:
	# 如果是END_BRANCH状态的点，尝试从所属的branch线段计算方向
	if point_index < point_parent_segments.size():
		var parent_segment_index = point_parent_segments[point_index]
		
		# 对于branch终点，parent_segment为-1，需要特殊处理
		if parent_segment_index == -1:
			# 查找以该点为终点的线段
			for segment_index in range(trunk_segments.size()):
				var segment = trunk_segments[segment_index]
				if segment.end_point_index == point_index:
					# 计算从起点到终点的方向
					var start_pos = point_positions[segment.start_point_index]
					var end_pos = point_positions[point_index]
					return (end_pos - start_pos).normalized()
		else:
			# 从父线段计算方向
			if parent_segment_index < trunk_segments.size():
				var segment = trunk_segments[parent_segment_index]
				var start_pos = point_positions[segment.start_point_index]
				var end_pos = point_positions[segment.end_point_index]
				return (end_pos - start_pos).normalized()
	
	# 如果是END_TRUNK状态，查找最近生成的分支方向
	if point_index < point_generated_branches.size():
		var branches = point_generated_branches[point_index]
		if branches.size() > 0:
			# 使用最后生成的分支方向
			return branches[branches.size() - 1]
	
	return Vector2.ZERO

## 创建branch终点（供generator调用）
func create_branch_endpoint(end_pos: Vector2, direction: Vector2) -> int:
	# 创建终点branch_point
	var end_branch_point = BRANCH_POINT_SCENE.instantiate()
	end_branch_point.global_position = end_pos
	
	# 添加到Fruitlayer而不是当前节点
	if fruit_layer:
		fruit_layer.add_child(end_branch_point)
	else:
		add_child(end_branch_point)
	
	# 添加终点到管理系统
	var end_point_index = point_positions.size()
	point_positions.append(end_pos)
	point_states.append(0)  # 终点没有生成次数
	point_directions.append(direction)
	point_generated_branches.append([])
	point_status.append(PointStatus.END_BRANCH)  # 设置为END_BRANCH状态
	point_nodes.append(end_branch_point)
	point_types.append(PointType.BRANCH_POINT)
	point_parent_segments.append(-1)  # 终点不属于任何trunk线段
	points_with_fruit.append(false)  # 初始化果实标记
	
	return end_point_index

## 获取Fruitlayer节点引用（供generator调用）
func get_fruit_layer() -> Node2D:
	return fruit_layer

# ==================== 供Main脚本调用的接口方法 ====================

## 执行单次trunk生成（供main调用）
func execute_trunk_generation() -> bool:
	# 检查是否有可用的生成点
	if get_available_points_count() == 0:
		return false
	
	# 清空本轮使用记录
	points_used_this_round.clear()
	
	# 选择一个可用点进行单次生成
	var selected_point = _select_single_available_point()
	if selected_point == -1:
		return false
	
	# 调用生成器对单个点进行生成
	_call_generator_generate_from_single_point(selected_point)
	
	# 生成完成后，减少参与生成的点的剩余次数
	_decrease_generation_counts()
	
	# 检查是否有终点状态的节点，实例化果实
	_instantiate_fruits_at_endpoint_nodes()
	
	return points_used_this_round.size() > 0  # 如果有点参与生成则返回成功

## 选择一个可用的生成点
func _select_single_available_point() -> int:
	var available_points: Array[int] = []
	
	for i in range(point_positions.size()):
		if point_states[i] > 0 and point_status[i] == PointStatus.AVAILABLE:
			available_points.append(i)
	
	if available_points.size() == 0:
		return -1
	
	# 随机选择一个可用点，或者可以实现其他选择策略
	return available_points[randi() % available_points.size()]

## 调用生成器对单个点进行生成
func _call_generator_generate_from_single_point(point_index: int):
	if generator and generator.has_method("generate_from_single_point"):
		generator.generate_from_single_point(point_index)
	else:
		# 降级到原有方法，但标记只有这一个点可用
		_mark_point_used(point_index)
		if generator and generator.has_method("generate"):
			generator.generate()

## 执行单次branch生成（供main调用）
func execute_branch_generation() -> bool:
	# 检查是否有可用的trunk线段
	var available_segments = _get_available_trunk_segments()
	if available_segments.size() == 0:
		return false
	
	# 尝试生成branch_point
	var new_branch_point_index = _try_generate_branch_point_anywhere(available_segments)
	if new_branch_point_index == -1:
		return false
	
	# 立即从新生成的branch_point生成branch线段
	if generator and generator.has_method("generate_branch_from_specific_point"):
		generator.generate_branch_from_specific_point(new_branch_point_index)
		return true
	else:
		return false

## 获取所有END_BRANCH状态的点索引（供main调用）
func get_end_branch_points() -> Array[int]:
	var end_branch_points: Array[int] = []
	for i in range(point_status.size()):
		if point_status[i] == PointStatus.END_BRANCH:
			end_branch_points.append(i)
	return end_branch_points

## 在指定点位生成bloodcut（供main调用）
func generate_bloodcut_at_point(point_index: int):
	if point_index >= point_positions.size():
		return
	
	var point_position = point_positions[point_index]
	var bloodcut = BLOODCUT_SCENE.instantiate()
	bloodcut.global_position = point_position
	
	# 添加到Fruitlayer
	if fruit_layer:
		fruit_layer.add_child(bloodcut)
	else:
		add_child(bloodcut)

## 在指定点位生成fruit（供main调用）
func generate_fruit_at_point(point_index: int):
	if point_index >= point_positions.size():
		return
	
	if point_index < points_with_fruit.size() and points_with_fruit[point_index]:
		return
	
	var point_position = point_positions[point_index]
	var fruit = FRUIT_SCENE.instantiate()
	
	# 计算fruit的正确旋转方向
	var fruit_rotation = _calculate_fruit_rotation(point_index)
	
	# 查找fruit场景中的Marker2D节点
	var marker = _find_marker2d_in_fruit(fruit)
	if marker:
		# 计算marker相对fruit根节点的偏移
		var marker_offset = marker.position
		# 根据旋转调整偏移方向
		var rotated_offset = marker_offset.rotated(fruit_rotation)
		# 设置fruit位置，使marker对齐目标点
		fruit.global_position = point_position - rotated_offset
	else:
		# 如果没找到marker，使用原来的中心对齐方式
		fruit.global_position = point_position
	
	# 获取fruit的Sprite2D节点并设置旋转
	var sprite = fruit.get_node("Sprite2D")
	if sprite:
		sprite.rotation = fruit_rotation
	
	# 添加到Fruitlayer
	if fruit_layer:
		fruit_layer.add_child(fruit)
	else:
		add_child(fruit)
	
	# 标记为已生成fruit
	while points_with_fruit.size() <= point_index:
		points_with_fruit.append(false)
	points_with_fruit[point_index] = true

## 在fruit实例中查找Marker2D节点
func _find_marker2d_in_fruit(fruit_node: Node) -> Marker2D:
	# 直接检查是否有Marker2D子节点
	for child in fruit_node.get_children():
		if child is Marker2D:
			return child
	
	# 如果没找到，递归查找
	for child in fruit_node.get_children():
		var found_marker = _find_marker2d_in_fruit(child)
		if found_marker:
			return found_marker
	
	return null

## 获取当前trunk数量（供main调用）
func get_trunk_count() -> int:
	# 统计trunk线段数量
	return trunk_segments.size()

## 获取当前branch数量（供main调用）
func get_branch_count() -> int:
	# 统计END_BRANCH状态的点数量（每个branch会产生一个END_BRANCH点）
	var branch_count = 0
	for i in range(point_status.size()):
		if point_status[i] == PointStatus.END_BRANCH:
			branch_count += 1
	return branch_count
