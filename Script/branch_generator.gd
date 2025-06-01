extends Node2D

## 树枝生成器
## 简单的生成逻辑，由Fruits控制器调用

# 生成参数
@export var branch_length: float = 100.0
@export var min_branch_length: float = 60.0  # 分支长度下限
@export var max_branch_length: float = 120.0  # 分支长度上限
@export var length_randomness: float = 0.8  # 长度随机化频率 (0.0=固定长度, 1.0=完全随机)
@export var line_width: float = 3.0
@export var line_color: Color = Color(0.6, 0.4, 0.2, 1.0)
@export var min_angle_degrees: float = 30.0  # 最小分支角度（度）
@export var max_angle_degrees: float = 85.0  # 最大分支角度（度）
@export var min_branch_separation_degrees: float = 60.0  # 同一生成点的分支之间最小角度（度）
@export var trunk_point_radius: float = 60.0  # trunk点的碰撞半径

# 生成点场景
const TRUNK_POINT_SCENE = preload("res://Scence/trunk_point.tscn")

# 存储已生成的线段，用于避免交叉
var existing_lines: Array[Dictionary] = []

func generate():
	print("生成器执行生成操作")
	# 获取父节点（Fruits）的可用生成点
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	_generate_branches_from_available_points(fruits_controller)

## 从所有可用生成点生成分支
func _generate_branches_from_available_points(fruits_controller):
	var point_positions = fruits_controller.point_positions
	var point_states = fruits_controller.point_states
	var point_directions = fruits_controller.point_directions  # 获取每个点的原始方向
	var point_types = fruits_controller.point_types  # 获取每个点的类型
	
	for i in range(point_positions.size()):
		# 只处理TRUNK_POINT类型且还有生成次数的点
		if point_states[i] > 0 and point_types[i] == fruits_controller.PointType.TRUNK_POINT:
			var original_direction = Vector2.ZERO
			if i < point_directions.size():
				original_direction = point_directions[i]
			
			# 获取该点已生成的分支方向
			var existing_branches = fruits_controller.get_point_generated_branches(i)
			
			# 尝试生成分支，如果成功则标记该点并记录分支方向
			var generation_result = _generate_single_branch(point_positions[i], fruits_controller, original_direction, existing_branches, i)
			if generation_result.success:
				fruits_controller._mark_point_used(i)
				fruits_controller._record_generated_branch(i, generation_result.direction)
			else:
				# 无法生成有效路径，设置为无空间状态
				fruits_controller.set_point_no_space(i)
	
	# 更新所有点的颜色显示
	fruits_controller.update_all_point_colors()

## 生成单条分支，返回生成结果
func _generate_single_branch(start_pos: Vector2, fruits_controller, original_direction: Vector2, existing_branches: Array, start_point_index: int) -> Dictionary:
	var max_attempts = 30  # 增加尝试次数，因为现在有更多角度限制
	var attempt = 0
	
	while attempt < max_attempts:
		# 生成随机方向
		var new_direction = _generate_valid_direction(original_direction, existing_branches)
		# 使用随机化的分支长度
		var current_branch_length = _get_random_branch_length()
		var end_pos = start_pos + new_direction * current_branch_length
		
		# 检查是否与现有线段交叉
		if not _check_line_intersection(start_pos, end_pos):
			# 检查新生成点是否与已有点距离过近
			if not _check_point_collision(end_pos, fruits_controller):
				# 没有交叉且不与其他点碰撞，可以生成
				_create_branch_line(start_pos, end_pos)
				var end_point_index = _create_end_point(end_pos, fruits_controller, new_direction)
				
				# 记录这条线段
				existing_lines.append({
					"start": start_pos,
					"end": end_pos
				})
				
				# 记录trunk线段信息
				fruits_controller._record_trunk_segment(start_point_index, end_point_index)
				
				return {"success": true, "direction": new_direction}
		
		attempt += 1
	
	print("无法找到不交叉且角度合适的路径，跳过此生成点")
	return {"success": false, "direction": Vector2.ZERO}

## 生成符合角度要求的方向
func _generate_valid_direction(original_direction: Vector2, existing_branches: Array) -> Vector2:
	if original_direction == Vector2.ZERO:
		# 如果没有原始方向，随机生成，但要避免与已有分支冲突
		return _generate_direction_avoiding_existing(existing_branches)
	
	# 计算原始方向的角度
	var original_angle = original_direction.angle()
	
	# 生成符合角度限制的新方向
	var min_angle_rad = deg_to_rad(min_angle_degrees)
	var max_angle_rad = deg_to_rad(max_angle_degrees)
	
	var max_direction_attempts = 20
	for attempt in range(max_direction_attempts):
		# 随机选择左转或右转
		var turn_left = randf() > 0.5
		var angle_range = max_angle_rad - min_angle_rad
		var random_offset = min_angle_rad + randf() * angle_range
		
		var new_angle = original_angle + (random_offset if turn_left else -random_offset)
		var candidate_direction = Vector2(cos(new_angle), sin(new_angle))
		
		# 检查与已有分支的角度
		if _check_branch_separation(candidate_direction, existing_branches):
			return candidate_direction
	
	# 如果无法找到合适的方向，尝试完全随机的方向
	return _generate_direction_avoiding_existing(existing_branches)

## 生成避免与已有分支冲突的随机方向
func _generate_direction_avoiding_existing(existing_branches: Array) -> Vector2:
	var max_attempts = 50
	for attempt in range(max_attempts):
		var random_angle = randf() * 2 * PI
		var candidate_direction = Vector2(cos(random_angle), sin(random_angle))
		
		if _check_branch_separation(candidate_direction, existing_branches):
			return candidate_direction
	
	# 如果实在找不到，返回随机方向（可能会有角度冲突）
	var fallback_angle = randf() * 2 * PI
	return Vector2(cos(fallback_angle), sin(fallback_angle))

## 检查新方向与已有分支的角度分离是否足够
func _check_branch_separation(new_direction: Vector2, existing_branches: Array) -> bool:
	var min_separation_rad = deg_to_rad(min_branch_separation_degrees)
	
	for existing_branch in existing_branches:
		var angle_diff = abs(new_direction.angle() - existing_branch.angle())
		# 处理角度环绕（0度和360度相邻）
		if angle_diff > PI:
			angle_diff = 2 * PI - angle_diff
		
		if angle_diff < min_separation_rad:
			return false  # 角度太小，不符合要求
	
	return true  # 角度分离足够

## 检查线段是否与现有线段交叉
func _check_line_intersection(new_start: Vector2, new_end: Vector2) -> bool:
	for line in existing_lines:
		if _lines_intersect(new_start, new_end, line.start, line.end):
			return true
	return false

## 判断两条线段是否相交
func _lines_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 = _direction(p3, p4, p1)
	var d2 = _direction(p3, p4, p2)
	var d3 = _direction(p1, p2, p3)
	var d4 = _direction(p1, p2, p4)
	
	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
	   ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
		return true
	
	return false

## 计算方向（用于线段相交判断）
func _direction(pi: Vector2, pj: Vector2, pk: Vector2) -> float:
	return (pk.x - pi.x) * (pj.y - pi.y) - (pj.x - pi.x) * (pk.y - pi.y)

## 创建分支线条
func _create_branch_line(start_pos: Vector2, end_pos: Vector2):
	var line = Line2D.new()
	line.add_point(to_local(start_pos))
	line.add_point(to_local(end_pos))
	line.width = line_width
	line.default_color = line_color
	add_child(line)

## 在末端创建新的生成点
func _create_end_point(end_pos: Vector2, fruits_controller, direction: Vector2) -> int:
	var new_point = TRUNK_POINT_SCENE.instantiate()
	new_point.global_position = end_pos
	
	# 添加到Fruits节点下
	fruits_controller.add_child(new_point)
	
	# 更新Fruits控制器的记录，传入方向信息和节点引用，并获取新点的索引
	var new_point_index = fruits_controller._add_new_point(end_pos, direction, new_point)
	return new_point_index

## 检查新生成点是否与已有点距离过近
func _check_point_collision(new_pos: Vector2, fruits_controller) -> bool:
	var point_positions = fruits_controller.point_positions
	for pos in point_positions:
		if (pos - new_pos).length() < trunk_point_radius:
			return true
	return false

## 计算随机化的分支长度
func _get_random_branch_length() -> float:
	if randf() < length_randomness:
		# 使用随机长度
		return randf_range(min_branch_length, max_branch_length)
	else:
		# 使用固定长度
		return branch_length

## 记录branch线段到existing_lines（供fruits.gd调用）
func _record_branch_line(start_pos: Vector2, end_pos: Vector2):
	existing_lines.append({
		"start": start_pos,
		"end": end_pos
	})
	print("记录branch线段: ", start_pos, " -> ", end_pos)

## 生成branch线段（由fruits.gd调用）
func generate_branch():
	print("生成器执行branch生成操作")
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	# 获取可用的branch_point
	var available_branch_points = _get_available_branch_points(fruits_controller)
	if available_branch_points.size() == 0:
		print("没有可用的branch_point用于生成branch")
		return
	
	# 随机选择一个可用的branch_point
	var random_branch_index = available_branch_points[randi() % available_branch_points.size()]
	_generate_branch_from_point(random_branch_index, fruits_controller)

## 从指定的branch_point生成branch线段（新增方法，用于完整branch生成）
func generate_branch_from_specific_point(branch_point_index: int):
	print("从指定点位生成branch：", branch_point_index)
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	_generate_branch_from_point(branch_point_index, fruits_controller)

## 获取所有可用的branch_point索引
func _get_available_branch_points(fruits_controller) -> Array[int]:
	var available_points: Array[int] = []
	for i in range(fruits_controller.point_positions.size()):
		if fruits_controller.point_types[i] == fruits_controller.PointType.BRANCH_POINT and fruits_controller.point_states[i] > 0:
			available_points.append(i)
	return available_points

## 从指定的branch_point生成branch线段
func _generate_branch_from_point(branch_point_index: int, fruits_controller):
	if branch_point_index >= fruits_controller.point_positions.size():
		print("错误：branch_point索引超出范围")
		return
	
	var branch_start_pos = fruits_controller.point_positions[branch_point_index]
	var parent_segment_index = fruits_controller.point_parent_segments[branch_point_index]
	
	# 计算trunk的方向
	var trunk_direction = _calculate_trunk_direction(parent_segment_index, fruits_controller)
	if trunk_direction == Vector2.ZERO:
		print("无法计算trunk方向")
		return
	
	# 尝试生成branch线段
	var max_attempts = 20
	for attempt in range(max_attempts):
		# 生成随机的branch方向和长度
		var branch_direction = _generate_branch_direction(trunk_direction, fruits_controller)
		var current_branch_length = randf_range(fruits_controller.branch_min_length, fruits_controller.branch_max_length)
		var branch_end_pos = branch_start_pos + branch_direction * current_branch_length
		
		# 检查碰撞
		if not _check_branch_line_collision(branch_start_pos, branch_end_pos, fruits_controller):
			# 没有碰撞，创建完整的branch
			_create_complete_branch(branch_point_index, branch_start_pos, branch_end_pos, branch_direction, fruits_controller)
			return
		else:
			print("Branch生成尝试 ", attempt + 1, " 发生碰撞，重新尝试")
	
	print("无法为branch_point ", branch_point_index, " 找到有效的branch生成位置")

## 计算trunk的生长方向
func _calculate_trunk_direction(segment_index: int, fruits_controller) -> Vector2:
	if segment_index < 0 or segment_index >= fruits_controller.trunk_segments.size():
		print("错误：无效的trunk线段索引")
		return Vector2.ZERO
	
	var segment = fruits_controller.trunk_segments[segment_index]
	var start_pos = fruits_controller.point_positions[segment.start_point_index]
	var end_pos = fruits_controller.point_positions[segment.end_point_index]
	
	return (end_pos - start_pos).normalized()

## 基于trunk方向生成branch方向
func _generate_branch_direction(trunk_direction: Vector2, fruits_controller) -> Vector2:
	var trunk_angle = trunk_direction.angle()
	
	# 随机选择左转或右转
	var turn_left = randf() > 0.5
	
	# 生成随机角度偏移
	var min_angle_rad = deg_to_rad(fruits_controller.branch_min_angle_degrees)
	var max_angle_rad = deg_to_rad(fruits_controller.branch_max_angle_degrees)
	var angle_offset = randf_range(min_angle_rad, max_angle_rad)
	
	# 计算新角度
	var new_angle = trunk_angle + (angle_offset if turn_left else -angle_offset)
	
	return Vector2(cos(new_angle), sin(new_angle))

## 检查branch线段是否与现有对象碰撞
func _check_branch_line_collision(start_pos: Vector2, end_pos: Vector2, fruits_controller) -> bool:
	# 检查与已有点的碰撞
	for pos in fruits_controller.point_positions:
		if (pos - end_pos).length() < fruits_controller.branch_collision_radius:
			return true
	
	# 检查与已有线段的交叉
	if _check_line_intersection(start_pos, end_pos):
		return true
	
	return false

## 创建完整的branch（线段 + 终点）
func _create_complete_branch(start_point_index: int, start_pos: Vector2, end_pos: Vector2, direction: Vector2, fruits_controller):
	# 标记起点branch_point为已使用
	fruits_controller.point_states[start_point_index] = 0
	fruits_controller.point_status[start_point_index] = fruits_controller.PointStatus.EXHAUSTED
	fruits_controller._update_point_color(start_point_index)
	
	# 创建branch线段
	_create_branch_line(start_pos, end_pos)
	
	# 记录线段到existing_lines中
	_record_branch_line(start_pos, end_pos)
	
	# 创建终点branch_point
	var end_branch_point = fruits_controller.BRANCH_POINT_SCENE.instantiate()
	end_branch_point.global_position = end_pos
	fruits_controller.add_child(end_branch_point)
	
	# 添加终点到管理系统
	var end_point_index = fruits_controller.point_positions.size()
	fruits_controller.point_positions.append(end_pos)
	fruits_controller.point_states.append(0)  # 终点没有生成次数
	fruits_controller.point_directions.append(direction)
	fruits_controller.point_generated_branches.append([])
	fruits_controller.point_status.append(fruits_controller.PointStatus.END_BRANCH)  # 设置为END_BRANCH状态
	fruits_controller.point_nodes.append(end_branch_point)
	fruits_controller.point_types.append(fruits_controller.PointType.BRANCH_POINT)
	fruits_controller.point_parent_segments.append(-1)  # 终点不属于任何trunk线段
	
	# 立即更新终点颜色
	fruits_controller._update_point_color(end_point_index)
	
	print("成功生成branch：从点 ", start_point_index, " 到点 ", end_point_index)
	print("Branch方向: ", direction, " 长度: ", start_pos.distance_to(end_pos))
