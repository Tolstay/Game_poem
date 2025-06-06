shader_type canvas_item;

// 针对Label文本优化的bloom参数
uniform float bloomRadius : hint_range(0.1, 5.0) = 2.0;
uniform float bloomThreshold : hint_range(0.0, 1.0) = 0.1;  // 降低阈值以适配普通文本
uniform float bloomIntensity : hint_range(0.0, 5.0) = 2.0;
uniform vec4 bloomColor : source_color = vec4(1.0, 0.0, 1.0, 1.0);  // 默认紫色bloom

// 高斯模糊权重（优化的采样模式）
const float[9] BLUR_WEIGHTS = float[](
    0.227027, 0.1945946, 0.1216216, 
    0.054054, 0.016216, 0.0027027,
    0.0, 0.0, 0.0
);

vec4 GetBloomPixel(sampler2D tex, vec2 uv) {
	vec4 col = texture(tex, uv);
	// 计算像素亮度
	float brightness = max(col.r, max(col.g, col.b));
	
	// 只有超过阈值的像素才产生bloom
	if (brightness > bloomThreshold) {
		float bloom_factor = brightness - bloomThreshold;
		return col * bloom_factor;
	}
	return vec4(0.0);
}

vec4 GetBloom(sampler2D tex, vec2 uv, vec2 texelSize) {
	vec4 bloom = vec4(0.0);
	
	// 9点采样的高斯模糊
	for(int x = -2; x <= 2; x++) {
		for(int y = -2; y <= 2; y++) {
			vec2 offset = vec2(float(x), float(y)) * texelSize * bloomRadius;
			vec4 sample_color = GetBloomPixel(tex, uv + offset);
			
			// 使用距离权重
			float weight = BLUR_WEIGHTS[abs(x) + abs(y)];
			bloom += sample_color * weight;
		}
	}
	
	return bloom;
}

void fragment() {
	vec4 originalColor = texture(TEXTURE, UV);
	
	// 计算bloom效果
	vec4 bloom = GetBloom(TEXTURE, UV, TEXTURE_PIXEL_SIZE);
	
	// 混合bloom颜色
	bloom.rgb *= bloomColor.rgb;
	
	// 将bloom添加到原始颜色
	vec4 finalColor = originalColor;
	finalColor.rgb += bloom.rgb * bloomIntensity;
	
	// 保持原始alpha
	finalColor.a = originalColor.a;
	
	COLOR = finalColor;
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
