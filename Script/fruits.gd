extends Node2D

## Fruits控制器
## 负责管理所有生成点的坐标与状态，控制生成器的交互

# 点状态枚举
enum PointStatus {
	AVAILABLE,    # 可生成状态（紫色）
	EXHAUSTED,    # 已耗尽状态（红色）
	PATH_TRUNK,   # 路过节点：剩余次数1但无合法路径（黄色）
	END_TRUNK     # 终点节点：剩余次数2但无合法路径（绿色）
}

# 状态颜色定义
const STATUS_COLORS = {
	PointStatus.AVAILABLE: Color(0.6, 0.2, 0.8, 1.0),  # 紫色
	PointStatus.EXHAUSTED: Color(0.8, 0.2, 0.2, 1.0),  # 红色
	PointStatus.PATH_TRUNK: Color(1.0, 1.0, 0.0, 1.0), # 黄色
	PointStatus.END_TRUNK: Color(0.2, 0.8, 0.2, 1.0)   # 绿色
}

# 生成点坐标记录
var point_positions: Array[Vector2] = []
var point_states: Array[int] = []  # 记录剩余生成次数，0=已耗尽，>0=可用次数
var point_directions: Array[Vector2] = []  # 记录每个点的生长方向
var point_generated_branches: Array[Array] = []  # 记录每个点已生成的分支方向
var point_status: Array[PointStatus] = []  # 记录每个点的当前状态
var point_nodes: Array[Node2D] = []  # 直接引用每个trunk点节点

# 生成器引用
var generator: Node2D

# 生成参数
@export var max_generations_per_point: int = 2  # 每个生成点的最大生成次数

# 记录本轮参与生成的点
var points_used_this_round: Array[int] = []

func _ready():
	# 获取生成器引用
	generator = $BranchGenerator
	# 记录初始生成点
	_record_initial_points()
	# 设置初始颜色
	update_all_point_colors()

func _input(_event):
	# 响应generate输入映射
	if Input.is_action_just_pressed("generate"):
		_execute_generation()

## 记录所有生成点的坐标和状态
func _record_initial_points():
	# 遍历子节点，找到所有生成点
	for child in get_children():
		if "Point" in child.name:
			point_positions.append(child.global_position)
			point_states.append(max_generations_per_point)  # 初始生成次数
			point_directions.append(Vector2.ZERO)  # 初始点没有方向
			point_generated_branches.append([])  # 初始化空的分支记录
			point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
			point_nodes.append(child)  # 记录节点引用
			print("记录生成点: ", child.name, " 位置: ", child.global_position, " 剩余次数: ", max_generations_per_point)

## 执行生成操作
func _execute_generation():
	print("执行生成操作")
	# 检查是否有可用的生成点
	if get_available_points_count() == 0:
		print("没有可用的生成点")
		return
	
	# 清空本轮使用记录
	points_used_this_round.clear()
	
	# 调用生成器的生成方法
	_call_generator_generate()
	
	# 生成完成后，减少参与生成的点的剩余次数
	_decrease_generation_counts()

## 减少参与生成的点的剩余次数
func _decrease_generation_counts():
	for point_index in points_used_this_round:
		if point_index < point_states.size() and point_states[point_index] > 0:
			point_states[point_index] -= 1
			print("生成点 ", point_index, " 剩余生成次数: ", point_states[point_index])
			if point_states[point_index] == 0:
				print("生成点 ", point_index, " 已耗尽所有生成次数")
				point_status[point_index] = PointStatus.EXHAUSTED

## 调用生成器的生成方法
func _call_generator_generate():
	if generator and generator.has_method("generate"):
		generator.generate()
	else:
		print("生成器未找到或没有generate方法")

## 标记生成点已使用（减少剩余次数）
func _mark_point_used(point_index: int):
	if point_index < point_states.size():
		point_states[point_index] -= 1
		print("生成点 ", point_index, " 剩余生成次数: ", point_states[point_index])
		
		if point_states[point_index] == 0:
			print("生成点 ", point_index, " 已耗尽所有生成次数")
			point_status[point_index] = PointStatus.EXHAUSTED
		
		# 立即更新该点的颜色
		_update_point_color(point_index)

## 记录某个点生成了新分支（由生成器调用）
func _record_generated_branch(point_index: int, branch_direction: Vector2):
	if point_index < point_generated_branches.size():
		point_generated_branches[point_index].append(branch_direction.normalized())
		print("记录生成点 ", point_index, " 的新分支方向: ", branch_direction.normalized())

## 获取某个点已生成的分支方向
func get_point_generated_branches(point_index: int) -> Array:
	if point_index < point_generated_branches.size():
		return point_generated_branches[point_index]
	return []

## 添加新的生成点（由生成器调用）
func _add_new_point(pos: Vector2, direction: Vector2 = Vector2.ZERO, node: Node2D = null):
	point_positions.append(pos)
	point_states.append(max_generations_per_point)  # 新生成的点有完整的生成次数
	point_directions.append(direction.normalized())  # 记录生长方向
	point_generated_branches.append([])  # 初始化空的分支记录
	point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
	point_nodes.append(node)  # 记录节点引用
	print("添加新生成点: ", pos, " 方向: ", direction, " 剩余次数: ", max_generations_per_point)

## 获取当前可用的生成点数量
func get_available_points_count() -> int:
	var count = 0
	for state in point_states:
		if state > 0:
			count += 1
	return count

## 获取生成点的详细状态信息
func get_points_status():
	print("=== 生成点状态 ===")
	for i in range(point_positions.size()):
		var status = "可用" if point_states[i] > 0 else "已耗尽"
		var branch_count = point_generated_branches[i].size() if i < point_generated_branches.size() else 0
		print("点 ", i, ": 位置 ", point_positions[i], " 剩余次数 ", point_states[i], " 状态 ", status, " 已生成分支数: ", branch_count)

## 设置点为无空间状态
func set_point_no_space(point_index: int):
	if point_index < point_status.size():
		# 根据剩余次数决定无空间状态的类型
		if point_states[point_index] == 1:
			# 剩余次数为1且无合法路径 -> 黄色（路过节点）
			point_status[point_index] = PointStatus.PATH_TRUNK
			print("生成点 ", point_index, " 设置为路过节点状态（黄色），剩余次数: ", point_states[point_index])
		elif point_states[point_index] == 2:
			# 剩余次数为2且无合法路径 -> 绿色（终点节点）
			point_status[point_index] = PointStatus.END_TRUNK
			print("生成点 ", point_index, " 设置为终点节点状态（绿色），剩余次数: ", point_states[point_index])
		else:
			# 其他情况（剩余次数0或其他值）保持原有逻辑
			if point_states[point_index] <= 0:
				point_status[point_index] = PointStatus.EXHAUSTED
				print("生成点 ", point_index, " 设置为已耗尽状态（红色），剩余次数: ", point_states[point_index])
		_update_point_color(point_index)

## 更新所有点的颜色显示
func update_all_point_colors():
	for i in range(point_positions.size()):
		_update_point_color(i)

## 更新单个点的颜色
func _update_point_color(point_index: int):
	if point_index >= point_status.size() or point_index >= point_nodes.size():
		return
	
	# 根据剩余次数更新状态（除非已经是无空间状态）
	if point_status[point_index] != PointStatus.END_TRUNK and point_status[point_index] != PointStatus.PATH_TRUNK:
		if point_states[point_index] <= 0:
			point_status[point_index] = PointStatus.EXHAUSTED
		else:
			point_status[point_index] = PointStatus.AVAILABLE
	
	# 直接使用节点引用更新颜色
	var trunk_node = point_nodes[point_index]
	if trunk_node and is_instance_valid(trunk_node):
		var trunk_status_polygon = trunk_node.get_node_or_null("Trunk_Status")
		if trunk_status_polygon and trunk_status_polygon is Polygon2D:
			var status = point_status[point_index]
			trunk_status_polygon.color = STATUS_COLORS[status]
			print("更新点 ", point_index, " 颜色为: ", STATUS_COLORS[status])
		else:
			print("警告：点 ", point_index, " 的Trunk_Status节点未找到或类型不正确")

## 获取所有trunk点节点（按添加顺序）
func _get_trunk_point_nodes() -> Array:
	var trunk_nodes = []
	for child in get_children():
		if "Point" in child.name or child.name.begins_with("Trunk_Point"):
			trunk_nodes.append(child)
	return trunk_nodes

## 执行生成后的清理工作
func _post_generation_cleanup():
	# 清空本轮使用记录
	points_used_this_round.clear()
	
	# 输出当前所有点的状态
	print("=== 当前所有生成点状态 ===")
	for i in range(point_positions.size()):
		var status_name = ""
		match point_status[i]:
			PointStatus.AVAILABLE: status_name = "可用"
			PointStatus.EXHAUSTED: status_name = "已耗尽"
			PointStatus.PATH_TRUNK: status_name = "路过节点"
			PointStatus.END_TRUNK: status_name = "终点节点"
		var branch_count = point_generated_branches[i].size() if i < point_generated_branches.size() else 0
		print("点 ", i, ": 位置 ", point_positions[i], " 剩余次数 ", point_states[i], " 状态 ", status_name, " 已生成分支数: ", branch_count)
