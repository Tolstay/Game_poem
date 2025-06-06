extends ColorRect

## Curtain脚本
## 负责幕布的淡入淡出效果

# Tween动画管理器
var fade_tween: Tween
@onready var windrises: AudioStreamPlayer = %windrises

signal fade_in_completed
signal fade_in_completed_forbus

func _ready():
	# 确保curtain有可见的颜色（黑色）
	color = Color.BLACK
	# 初始状态设为完全透明
	modulate.a = 0.0

func _on_signalbus_fade_in_now() -> void:
	_fade_curtain(1.0)
	windrises.volume_db = 0.0
	windrises.play()
	await get_tree().create_timer(2.0).timeout
	fade_in_completed.emit()
	fade_in_completed_forbus.emit()



## 动画完成回调
func _on_fade_complete():
	pass

func _on_main_instantiation_compeleted() -> void:
	await get_tree().create_timer(1.0).timeout
	_fade_curtain(0.0)
	
	## 执行淡入淡出动画
func _fade_curtain(target_color):
	# 如果已有tween在运行，先停止
	if fade_tween:
		fade_tween.kill()
	
	# 创建新的tween
	fade_tween = create_tween()
	
	if modulate.a == target_color:
		return
	
	# 在2秒内将不透明度提升至255（即modulate.a = 1.0）
	fade_tween.tween_property(self, "modulate:a", target_color, 2.0)
	
	# 可选：设置缓动类型让动画更平滑
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	fade_tween.set_trans(Tween.TRANS_SINE)
