extends ColorRect
var fade_tween: Tween


func _ready():
	# 确保curtain有可见的颜色（黑色）
	modulate.a = 1.0

	
	## 执行淡入淡出动画
func _process(delta: float) -> void:
	
	await get_tree().create_timer(6.0).timeout
	# 如果已有tween在运行，先停止
	if fade_tween:
		fade_tween.kill()
	
	# 创建新的tween
	fade_tween = create_tween()
	
	# 在2秒内将不透明度提升至255（即modulate.a = 1.0）
	fade_tween.tween_property(self, "modulate:a", 0.0, 2.0)
	
	# 可选：设置缓动类型让动画更平滑
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	fade_tween.set_trans(Tween.TRANS_SINE)
	
	await get_tree().create_timer(4.0).timeout
	queue_free()
