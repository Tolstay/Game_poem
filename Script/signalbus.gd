extends Node

## SignalBus脚本
## 用于处理全局信号通信

signal fruit_picked_now
signal fade_in_now
signal disable_pickoff_interaction
signal able_pickoff_interaction

# 风抖动信号
signal wind_shake_start(duration: float, intensity: float, frequency: float, horizontal_bias: float, randomness: float)
signal wind_shake_stop

var fading:bool = false

# 花瓣摘除计数系统
var petal_pick_count: int = 0
var pick_number: int = 0
var first_wind = true

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
	# 创建打字机计时器
	_setup_typing_timer()
	await get_tree().create_timer(0.5).timeout
	info.add_theme_font_size_override("font_size", 20)
	_start_typing_effect("First Moves")
	await get_tree().create_timer(2.0).timeout
	_start_backspace_effect()
	await get_tree().create_timer(1.0).timeout
	info.add_theme_font_size_override("font_size", 10)
	_start_typing_effect("long press to remove")
	
	
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
	if first_wind == true:
		first_wind = false
		print("第一阵风过了")
		_start_backspace_effect()
	
	fade_in_now.emit()

## 当接收到fruit_picked信号时的处理方法
func _on_fruit_picked():
	fruit_picked_now.emit()


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
	
	
	
	# 根据摘除数量更新info文本
	_update_info_text(pick_number)
	
	if remaining_petals == 0:
		_start_backspace_effect()
		await get_tree().create_timer(3.0).timeout
		_start_typing_effect("You've made your choice")
		ending.play()
		await get_tree().create_timer(3.0).timeout
		_start_backspace_effect()
		await get_tree().create_timer(1.5).timeout
		info.add_theme_font_size_override("font_size", 20)
		_start_typing_effect("Game Over")

## 获取当前应显示的文本
func get_current_petal_text() -> String:
	# 根据摘除计数生成文本
	# count=0: yes, count=1: no, count=2: yesyes, count=3: nono, ...
	var base_text: String
	var repeat_count: int
	
	if petal_pick_count % 2 == 0:
		base_text = "yes "
	else:
		base_text = "no "
	
	repeat_count = (petal_pick_count / 2) + 1
	
	var result = ""
	for i in range(repeat_count):
		result += base_text
	
	return result

## 根据摘除数量更新info文本
func _update_info_text(pick_num: int):
	if not info:
		return
		
	match pick_num:
		1:
			# 清空文本
			if info.text != "":
				_start_backspace_effect()
		3:
			# 显示提示文本
			if first_wind == true:
				_start_typing_effect("Hold still for the wind")

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

## 检测剩余petal数量
func _check_remaining_petals() -> int:
	var remaining_count = 0
	var main_scene = get_tree().current_scene
	
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
