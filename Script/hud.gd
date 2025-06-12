extends Label

func _ready():
	# 初始化显示文本
	
	
	# 设置字体样式
	add_theme_font_size_override("font_size", 8)

	
	# 设置对齐方式
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	
	# 连接signalbus的更新信号
	_connect_to_signalbus()

func _connect_to_signalbus():
	# 等待signalbus准备好
	await get_tree().process_frame
	
	# 查找并连接signalbus
	var signalbus = get_tree().get_first_node_in_group("signalbus")
	if signalbus:
		if signalbus.has_signal("hud_update_requested"):
			signalbus.hud_update_requested.connect(_on_hud_update_requested)
		if signalbus.has_signal("hud_destroy_requested"):
			signalbus.hud_destroy_requested.connect(_on_hud_destroy_requested)
		print("📱 [HUD] 已连接到SignalBus")
	else:
		print("⚠️ [HUD] 未找到SignalBus或信号")

func _on_hud_update_requested(pick_count: int, wind_count: int):
	text = "%d plucked,%d winds" % [pick_count, wind_count]
	print("📱 [HUD] 更新显示: picks %d, winds %d" % [pick_count, wind_count])

func _on_hud_destroy_requested():
	print("💀 [HUD] 接收到销毁信号，正在销毁HUD")
	queue_free()
