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

# 使用现有的计时器节点
@onready var windrises_timer: Timer = %Windrises
@onready var still_threshold: Timer = %StillThreshold
@onready var curtain: ColorRect = %Curtain

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
	fade_in_now.emit()

## 当接收到fruit_picked信号时的处理方法
func _on_fruit_picked():
	fruit_picked_now.emit()


func _on_still_threshold_timeout() -> void:
	disable_pickoff_interaction.emit()  # 发出禁用pickoff交互信号,需要手动连接
	print("禁用交互，起风")
	fading = true
	windrises_timer.start()

func _on_curtain_fade_in_completed_forbus() -> void:
	await get_tree().create_timer(1.5).timeout
	fading = false
	able_pickoff_interaction.emit() # 发出接触禁用，需要手动连接

## 花瓣被摘除时调用（增加计数）
func on_petal_picked():
	petal_pick_count += 1

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
