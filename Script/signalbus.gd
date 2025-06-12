extends Node

## SignalBus脚本
## 用于处理全局信号通信

signal fruit_picked_now
signal fade_in_now
signal disable_pickoff_interaction
signal able_pickoff_interaction
# 新增：HUD更新信号
signal hud_update_requested(pick_count: int, wind_count: int)
# 新增：HUD销毁信号
signal hud_destroy_requested

# 风抖动信号（由wind_manager连接和使用，在静止超时时触发）
signal wind_shake_start(duration: float, intensity: float, frequency: float, horizontal_bias: float, randomness: float)
signal wind_shake_stop  # 风抖动停止信号

# Fruit坐标管理
signal fruit_generated(position: Vector2)
signal fruit_removed(position: Vector2)
signal movement_bounds_updated(bounds: Rect2)

var fading:bool = false

# Fruit坐标记录
var fruit_coordinates: Array[Vector2] = []
var heart_coordinate: Vector2 = Vector2.ZERO  # Heart坐标（永不移除）

# 花瓣摘除计数系统
var petal_pick_count: int = 0
var pick_number: int = 0
var fruit_pick_count: int = 0
var wind_count: int = 0
var first_wind = true
var first_pick = true
var show_text = false
var gameover = false

# 使用现有的计时器节点
@onready var windrises_timer: Timer = %Windrises
@onready var still_threshold: Timer = %StillThreshold
@onready var curtain: ColorRect = %Curtain
@onready var info: Label = %Info
@onready var ending: AudioStreamPlayer = %ending

# 打字机效果相关变量（与textdisplay.gd保持一致的速率）
var typing_speed: float = 0.05  # 每个字符的显示间隔（秒）
var backspace_speed: float = 0.03  # 每个字符的消失间隔（秒）
var full_text: String = ""
var current_char_index: int = 0
var typing_timer: Timer
var is_typing: bool = false
var is_backspacing: bool = false

func _ready():
	# 添加到signalbus组
	
	
	add_to_group("signalbus")
	
	# 连接fruit管理信号
	fruit_generated.connect(_on_fruit_generated)
	fruit_removed.connect(_on_fruit_removed)
	
	# 延迟添加heart坐标（等待场景完全加载）
	call_deferred("_add_heart_coordinate")
	await get_tree().process_frame
	call_deferred("emit_disable_signal")
	
	# 创建打字机计时器
	_setup_typing_timer()
	await get_tree().create_timer(0.5).timeout
	
	# 新增：初始化HUD显示
	_update_hud_display()
	
	info.add_theme_font_size_override("font_size", 10)
	_start_typing_effect("Recall a decision that\nyou've been putting off")
	if gameover:
		return
	if first_pick == false:
		return
	await get_tree().create_timer(8.0).timeout
	_start_backspace_effect()
	able_pickoff_interaction.emit() #开场结束启用交互
	
	if gameover:
		return
	if first_pick == false:
		return
	await get_tree().create_timer(1.5).timeout
	_start_typing_effect("long press to pick things")
	
func emit_disable_signal():
	disable_pickoff_interaction.emit()
	

func _setup_typing_timer():
	typing_timer = Timer.new()
	typing_timer.wait_time = typing_speed
	typing_timer.timeout.connect(_on_typing_timer_timeout)
	add_child(typing_timer)

@warning_ignore("unused_parameter")

func _physics_process(delta: float) -> void:
	_connect_pickoff_signals_recursive(get_tree().current_scene)
	
## 递归查找并连接pickoff信号
func _connect_pickoff_signals_recursive(node: Node):
	# 检查当前节点是否是pickoff节点
	if node.name == "pickoff" and node.has_signal("fruit_picked"):
		# 连接fruit_picked信号
		if not node.fruit_picked.is_connected(_on_fruit_picked):
			node.fruit_picked.connect(_on_fruit_picked)
	
	# 递归处理子节点
	for child in node.get_children():
		_connect_pickoff_signals_recursive(child)


## 当鼠标停止移动时的处理
func _on_mouse_stopped_moving():
	if first_pick:
		return
		
	if show_text == false:
		return
	
	if fading == true: #还在fading阶段
		return

	still_threshold.start()

## 当鼠标开始移动时的处理
func _on_mouse_started_moving():
	if fading == false:
		_stop_all_timers()
	else:
		return

## 停止所有计时器
func _stop_all_timers():
	if windrises_timer.time_left > 0:
		windrises_timer.stop()
	if still_threshold.time_left > 0:
		still_threshold.stop()


## windrises计时器超时处理
func _on_windrises_timeout():
	# 新增：增加wind计数
	wind_count += 1
	print("💨 [SignalBus] Wind次数: ", wind_count)
	
	# 更新HUD显示
	_update_hud_display()
	
	if first_wind == true:
		first_wind = false
		print("第一阵风过了")
		_start_backspace_effect()
	
	fade_in_now.emit()

## 新增：更新HUD显示的方法
func _update_hud_display():
	var total_picks = petal_pick_count + fruit_pick_count
	hud_update_requested.emit(total_picks, wind_count)
	print("📊 [SignalBus] HUD更新 - pick: %d, wind: %d" % [total_picks, wind_count])

## 当接收到fruit_picked信号时的处理方法
func _on_fruit_picked():
	fruit_picked_now.emit()
	
	# 新增：增加fruit摘除计数
	fruit_pick_count += 1
	pick_number += 1
	print("🍎 [SignalBus] Fruit摘除 - fruit总数: ", fruit_pick_count, " 总摘除数: ", pick_number)
	
	# 更新HUD显示
	_update_hud_display()

func _on_still_threshold_timeout() -> void:
	disable_pickoff_interaction.emit()  # 发出禁用pickoff交互信号,需要手动连接
	fading = true
	windrises_timer.start()

func _on_curtain_fade_in_completed_forbus() -> void:
	await get_tree().create_timer(1.5).timeout
	fading = false
	able_pickoff_interaction.emit() # 发出接触禁用，需要手动连接

## 花瓣被摘除时调用（增加计数）
func on_petal_picked():
	petal_pick_count += 1
	pick_number += 1
	
	# 检测剩余petal数量
	var remaining_petals = _check_remaining_petals()
	print("🌸 [SignalBus] 花瓣摘除 - 已摘: ", pick_number, " 剩余: ", remaining_petals)
	
	# 更新HUD显示
	_update_hud_display()
	
	# 根据摘除数量更新info文本
	_update_info_text(pick_number)
	
	if remaining_petals == 0:
		gameover = true
		print("gameover为true")
		set_global_gameover(true)
		
		# 发送HUD销毁信号
		hud_destroy_requested.emit()
		
		_start_backspace_effect()
		await get_tree().create_timer(3.0).timeout
		_start_typing_effect("You've stepped out")
		ending.play()
		await get_tree().create_timer(7.0).timeout
		_start_backspace_effect()
		await get_tree().create_timer(2.5).timeout
		info.add_theme_font_size_override("font_size", 20)
		_start_typing_effect("Game Over")


## 获取当前应显示的文本
func get_current_petal_text() -> String:
	# 根据摘除计数简单交替显示yes或no
	# count=0: yes, count=1: no, count=2: yes, count=3: no, ...
	if petal_pick_count % 2 == 0:
		return "yes"
	else:
		return "no"

## 根据摘除数量更新info文本
func _update_info_text(pick_num: int):
	if not info:
		return
		
	match pick_num:
		1:
			# 清空文本
			if info.text != "":
				_start_backspace_effect()
			first_pick = false
			await get_tree().create_timer(3.0).timeout
			_start_typing_effect("Hold still for the wind")
			show_text = true

## 开始打字机效果
func _start_typing_effect(text: String):
	if is_typing or is_backspacing:
		# 如果正在执行其他效果，先停止
		_stop_all_effects()
	
	full_text = text
	is_typing = true
	current_char_index = 0
	
	if info:
		info.text = ""
		info.visible = true
	
	typing_timer.wait_time = typing_speed
	typing_timer.start()

## 开始backspace效果
func _start_backspace_effect():
	if is_backspacing or not info or not info.visible:
		return
	
	# 停止打字效果
	if is_typing:
		_stop_typing_effect()
	
	is_backspacing = true
	current_char_index = info.text.length()
	
	typing_timer.wait_time = backspace_speed
	typing_timer.start()

## 停止打字机效果
func _stop_typing_effect():
	if is_typing:
		is_typing = false
		typing_timer.stop()

## 停止backspace效果
func _stop_backspace_effect():
	if is_backspacing:
		is_backspacing = false
		typing_timer.stop()
		if info:
			info.text = ""
			info.visible = false

## 停止所有效果
func _stop_all_effects():
	_stop_typing_effect()
	_stop_backspace_effect()

## 打字机计时器回调
func _on_typing_timer_timeout():
	if is_typing:
		_handle_typing_step()
	elif is_backspacing:
		_handle_backspace_step()

## 处理打字步骤
func _handle_typing_step():
	if current_char_index >= full_text.length():
		_complete_typing_effect()
		return
	
	# 显示下一个字符
	current_char_index += 1
	if info:
		info.text = full_text.substr(0, current_char_index)

## 处理backspace步骤
func _handle_backspace_step():
	if current_char_index <= 0:
		_complete_backspace_effect()
		return
	
	# 删除最后一个字符
	current_char_index -= 1
	if info:
		if current_char_index > 0:
			info.text = info.text.substr(0, current_char_index)
		else:
			info.text = ""

## 完成打字机效果
func _complete_typing_effect():
	is_typing = false
	typing_timer.stop()
	if info:
		info.text = full_text

## 完成backspace效果
func _complete_backspace_effect():
	is_backspacing = false
	typing_timer.stop()
	current_char_index = 0
	if info:
		info.text = ""
		info.visible = false

## 测试打字机效果（调试用）
func test_typewriter_effect():
	print("🧪 [SignalBus] 测试打字机效果")
	_start_typing_effect("测试打字机效果")

## 测试游戏结束状态切换（供调试使用）
func test_gameover_toggle():
	var main_scene = get_tree().current_scene
	var current_state = false
	
	if main_scene and main_scene.has_method("is_gameover"):
		current_state = main_scene.is_gameover()
	
	# 切换状态
	set_global_gameover(not current_state)
	print("🧪 [SignalBus] 游戏结束状态已切换为: ", not current_state)

## 开始相机下落效果（与petal相同速度）
func _start_camera_fall():
	var camera_node = _find_camera_node()
	if not camera_node:
		print("⚠️ [SignalBus] 未找到Camera2D节点")
		return
	
	print("📹 [SignalBus] 开始相机下落效果")
	
	# 创建Tween控制相机下落
	var camera_tween = create_tween()
	camera_tween.set_loops()  # 无限循环下落
	
	# 以petal相同的速度向下移动（15.0像素/秒）
	var fall_speed = 15.0  # 与pickoff脚本中petal的掉落速度一致
	var fall_distance = 1000.0  # 每次下落的距离
	var fall_duration = fall_distance / fall_speed  # 计算下落时间
	
	# 开始无限下落动画 - 修复tween_method调用
	var start_y = camera_node.global_position.y
	camera_tween.tween_method(func(offset: float): _move_camera_down(camera_node, offset), 0.0, fall_distance, fall_duration)

## 查找Camera2D节点
func _find_camera_node() -> Camera2D:
	var main_scene = get_tree().current_scene
	var camera_node = null
	
	# 查找路径：SubViewportContainer/SubViewport/Movement/Camera2D
	var subviewport_container = main_scene.get_node_or_null("SubViewportContainer")
	if subviewport_container:
		var subviewport = subviewport_container.get_node_or_null("SubViewport")
		if subviewport:
			var movement = subviewport.get_node_or_null("Movement")
			if movement:
				camera_node = movement.get_node_or_null("Camera2D")
	
	# 如果找不到，尝试直接查找
	if not camera_node:
		camera_node = main_scene.find_child("Camera2D", true, false)
	
	return camera_node

## 移动相机向下（供Tween调用）
func _move_camera_down(camera: Camera2D, offset: float):
	if camera and is_instance_valid(camera):
		camera.global_position.y = camera.global_position.y + offset

## 检测剩余petal数量
func _check_remaining_petals() -> int:
	var remaining_count = 0
	
	# 通过group系统统计剩余的petal
	var petal_group_prefix = "petal_position_"
	
	# 遍历所有可能的位置组
	for i in range(20):  # 假设最多20个位置
		var group_name = petal_group_prefix + str(i)
		var petals_at_position = get_tree().get_nodes_in_group(group_name)
		
		# 统计有效且未被摘除的petal节点
		for petal in petals_at_position:
			if is_instance_valid(petal) and petal.is_inside_tree():
				# 检查petal是否还未被摘除（通过检查pickoff状态）
				var pickoff_node = petal.find_child("pickoff", true, false)
				if pickoff_node and pickoff_node.has_method("is_object_picked"):
					if not pickoff_node.is_object_picked():
						remaining_count += 1
				else:
					# 如果没有pickoff节点或方法，默认计入剩余
					remaining_count += 1
	
	return remaining_count

## 获取剩余petal总数（供外部调用）
func get_remaining_petals_count() -> int:
	return _check_remaining_petals()

## 检查是否所有petal都已被摘除
func are_all_petals_picked() -> bool:
	
	return _check_remaining_petals() == 0

## 设置全局游戏结束状态
func set_global_gameover(state: bool):
	print("🎮 [SignalBus] 设置全局游戏结束状态: ", state)
	
	# 设置主脚本的gameover状态
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("set_gameover"):
		main_scene.set_gameover(state)
	
	# 设置所有pickoff脚本的gameover状态
	_set_all_pickoff_gameover(state)
	
	# 设置movement脚本的gameover状态
	_set_movement_gameover(state)

## 设置所有pickoff脚本的gameover状态
func _set_all_pickoff_gameover(state: bool):
	# 获取所有fruit和petal的pickoff节点
	var all_pickoff_nodes = []
	
	# 查找所有petal的pickoff节点
	for i in range(20):  # 假设最多20个位置
		var group_name = "petal_position_" + str(i)
		var petals_at_position = get_tree().get_nodes_in_group(group_name)
		
		for petal in petals_at_position:
			if is_instance_valid(petal) and petal.is_inside_tree():
				var pickoff_node = petal.find_child("pickoff", true, false)
				if pickoff_node and pickoff_node.has_method("set_gameover"):
					all_pickoff_nodes.append(pickoff_node)
	
	# 查找所有fruit的pickoff节点
	var fruits_group = get_tree().get_nodes_in_group("fruits")
	for fruit in fruits_group:
		if is_instance_valid(fruit) and fruit.is_inside_tree():
			var pickoff_node = fruit.find_child("pickoff", true, false)
			if pickoff_node and pickoff_node.has_method("set_gameover"):
				all_pickoff_nodes.append(pickoff_node)
	
	# 设置所有找到的pickoff节点的gameover状态
	for pickoff_node in all_pickoff_nodes:
		pickoff_node.set_gameover(state)
	
	print("🎮 [SignalBus] 已设置 ", all_pickoff_nodes.size(), " 个pickoff节点的gameover状态")

## 设置movement脚本的gameover状态
func _set_movement_gameover(state: bool):
	# 在SubViewport结构中查找Movement节点
	var main_scene = get_tree().current_scene
	var movement_node = null
	
	# 查找路径：SubViewportContainer/SubViewport/Movement
	var subviewport_container = main_scene.get_node_or_null("SubViewportContainer")
	if subviewport_container:
		var subviewport = subviewport_container.get_node_or_null("SubViewport")
		if subviewport:
			movement_node = subviewport.get_node_or_null("Movement")
	
	# 如果找不到，尝试直接查找
	if not movement_node:
		movement_node = main_scene.find_child("Movement", true, false)
	
	# 设置movement的gameover状态
	if movement_node and movement_node.has_method("set_gameover"):
		movement_node.set_gameover(state)
		print("🎮 [SignalBus] 已设置Movement节点的gameover状态")
	else:
		print("⚠️ [SignalBus] 未找到Movement节点")

# ==================== Fruit坐标管理 ====================

## 当fruit生成时调用
func _on_fruit_generated(fruit_position: Vector2):
	fruit_coordinates.append(fruit_position)
	print("🍎 [SignalBus] Fruit生成于: ", fruit_position, " 总数: ", fruit_coordinates.size())
	_update_movement_bounds()

## 当fruit被摘除时调用
func _on_fruit_removed(fruit_position: Vector2):
	# 查找并移除最接近的坐标（允许小误差）
	for i in range(fruit_coordinates.size()):
		if fruit_coordinates[i].distance_to(fruit_position) < 10.0:  # 10像素误差范围
			fruit_coordinates.remove_at(i)
			print("🍎 [SignalBus] Fruit移除于: ", fruit_position, " 剩余fruit: ", fruit_coordinates.size())
			_update_movement_bounds()
			break

## 计算并更新movement边界
func _update_movement_bounds():
	# 准备所有坐标（包含heart和fruit）
	var all_coordinates: Array[Vector2] = []
	
	# 添加heart坐标（如果存在）
	if heart_coordinate != Vector2.ZERO:
		all_coordinates.append(heart_coordinate)
	
	# 添加所有fruit坐标
	all_coordinates.append_array(fruit_coordinates)
	
	if all_coordinates.size() == 0:
		# 没有任何坐标时，设置一个极小的边界（实际上禁用移动）
		var zero_bounds = Rect2(Vector2.ZERO, Vector2(1, 1))
		movement_bounds_updated.emit(zero_bounds)
		print("🚫 [SignalBus] 无任何坐标，movement被限制")
		return
	
	# 找到四个方向的极值
	var min_x = all_coordinates[0].x
	var max_x = all_coordinates[0].x
	var min_y = all_coordinates[0].y
	var max_y = all_coordinates[0].y
	
	for coord in all_coordinates:
		min_x = min(min_x, coord.x)
		max_x = max(max_x, coord.x)
		min_y = min(min_y, coord.y)
		max_y = max(max_y, coord.y)
	
	# 创建边界矩形
	var padding = 50.0
	var bounds: Rect2
	
	# 如果只有heart（没有fruit），创建一个以heart为中心的合理区域
	if all_coordinates.size() == 1 and heart_coordinate != Vector2.ZERO:
		var heart_area_size = 200.0  # heart周围的活动区域大小
		bounds = Rect2(
			Vector2(heart_coordinate.x - heart_area_size/2, heart_coordinate.y - heart_area_size/2),
			Vector2(heart_area_size, heart_area_size)
		)
	else:
		# 多个坐标时，创建包围所有点的矩形（稍微扩大一点防止过于严格）
		bounds = Rect2(
			Vector2(min_x - padding, min_y - padding),
			Vector2(max_x - min_x + padding * 2, max_y - min_y + padding * 2)
		)
	
	movement_bounds_updated.emit(bounds)
	print("📏 [SignalBus] Movement边界更新: ", bounds, " (包含", all_coordinates.size(), "个坐标点)")

## 手动添加fruit坐标（供调试使用）
func add_fruit_coordinate(fruit_position: Vector2):
	fruit_generated.emit(fruit_position)

## 手动移除fruit坐标（供调试使用）
func remove_fruit_coordinate(fruit_position: Vector2):
	fruit_removed.emit(fruit_position)

## 获取当前所有fruit坐标（供外部调用）
func get_fruit_coordinates() -> Array[Vector2]:
	return fruit_coordinates.duplicate()

## 获取fruit数量（供外部调用）
func get_fruit_count() -> int:
	return fruit_coordinates.size()

## 添加heart坐标到管理系统
func _add_heart_coordinate():
	var heart_position = _find_heart_position()
	if heart_position != Vector2.ZERO:
		heart_coordinate = heart_position
		print("❤️ [SignalBus] Heart坐标已添加: ", heart_coordinate)
		_update_movement_bounds()
	else:
		print("⚠️ [SignalBus] 未找到Heart位置")

## 查找heart的位置
func _find_heart_position() -> Vector2:
	# 方法1: 通过First_Point查找
	var main_scene = get_tree().current_scene
	var first_point_node = main_scene.find_child("First_Point", true, false)
	if first_point_node:
		print("❤️ [SignalBus] 通过First_Point找到Heart位置: ", first_point_node.global_position)
		return first_point_node.global_position
	
	# 方法2: 通过Heart节点直接查找
	var heart_node = main_scene.find_child("Heart", true, false)
	if heart_node:
		print("❤️ [SignalBus] 通过Heart节点找到位置: ", heart_node.global_position)
		return heart_node.global_position
	
	# 方法3: 在Fruits节点下查找First_Point
	var fruits_node = main_scene.find_child("Fruits", true, false)
	if fruits_node:
		first_point_node = fruits_node.get_node_or_null("First_Point")
		if first_point_node:
			print("❤️ [SignalBus] 在Fruits下找到First_Point: ", first_point_node.global_position)
			return first_point_node.global_position
	
	print("⚠️ [SignalBus] 所有方法都未找到Heart位置")
	return Vector2.ZERO

## 获取包含Heart的所有坐标（供调试使用）
func get_all_coordinates() -> Array[Vector2]:
	var all_coords: Array[Vector2] = []
	if heart_coordinate != Vector2.ZERO:
		all_coords.append(heart_coordinate)
	all_coords.append_array(fruit_coordinates)
	return all_coords

## 获取Heart坐标（供外部调用）
func get_heart_coordinate() -> Vector2:
	return heart_coordinate

## 获取当前pick和wind计数（供调试使用）
func get_total_pick_count() -> int:
	return petal_pick_count + fruit_pick_count

func get_current_wind_count() -> int:
	return wind_count

func get_current_petal_count() -> int:
	return petal_pick_count

func get_current_fruit_pick_count() -> int:
	return fruit_pick_count

## 测试HUD更新（供调试使用）
func test_hud_update():
	print("🧪 [SignalBus] 测试HUD更新")
	_update_hud_display()
