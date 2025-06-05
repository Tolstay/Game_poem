# 树干弯曲系统使用指南

## 功能概述
新的弯曲系统将原本的直线trunk段改为自然的弯曲线段，并提供独立的功能在弯曲点生成branch_point。

## 按键功能分离

### 空格键 - 生成弯曲trunk段
- **功能**: 生成带有随机折线和圆角连接的trunk线段
- **特点**: 只生成线段，不自动生成branch_point
- **视觉**: 自然弯曲的树干，使用随机纹理

### G键 - 传统branch生成
- **功能**: 在现有trunk线段上生成branch_point + 立即生成branch线段
- **适用**: 传统的branch生成流程

### B键 - 独立branch_point生成  
- **功能**: 仅在trunk线段上生成branch_point，不生成branch线段
- **适用**: 精细控制branch_point位置

### F键 - 折线点branch生成（新功能）
- **功能**: 在之前生成的折线点位置生成branch_point
- **特点**: 基于概率，每次最多生成5个
- **优势**: 利用自然的弯曲点位置

## 推荐工作流程

### 基础树形生成
1. **空格键**: 生成弯曲的trunk段
2. **空格键**: 继续生成更多分支trunk段
3. **F键**: 在弯曲点生成branch_point
4. **G键**: 从branch_point生成branch线段

### 精细控制流程
1. **空格键**: 生成弯曲trunk段
2. **B键**: 在特定位置手动生成branch_point
3. **F键**: 补充在弯曲点生成branch_point
4. **G键**: 批量生成branch线段

## 参数配置

### BranchGenerator节点参数

#### Bend System（弯曲系统）
- **Bend Max Points** (0-4): 每条线段最多生成的弯曲点数量
- **Bend Probability** (0.0-1.0): 生成弯曲点的概率，1.0表示总是生成
- **Bend Max Offset** (像素): 弯曲点的最大垂直偏移距离
- **Bend Min Segment Length** (像素): 只有达到此长度的线段才会生成弯曲点
- **Bend Enable Coordinated** (true/false): 启用协调弯曲，避免曲折摆动
- **Bend Arc Intensity** (0.0-1.0): 弧形强度，0.0为直线分布，1.0为完整弧形
- **Bend Direction Consistency** (0.0-1.0): 方向一致性，1.0为完全同向，0.0为完全随机
- **Bend Offset Smoothness** (0.0-1.0): 偏移量平滑度，1.0为完全平滑，0.0为完全随机

#### Texture System（纹理系统）
- **Texture Trunk Textures**: 纹理变体数组，将准备的PNG文件拖拽到这里
- **Texture Use Random**: 是否为每条线段随机选择纹理

### Fruits节点参数

#### Bend Point Branch Generation（弯曲点分支生成）
- **Bend Branch Enabled**: 是否启用F键功能
- **Bend Branch Probability** (0.0-1.0): 每个弯曲点生成branch_point的概率
- **Bend Branch Collision Radius** (像素): 弯曲点branch_point的碰撞检测半径

## 推荐参数设置

### 自然协调弯曲（推荐）
```
BranchGenerator:
  Bend Max Points: 3
  Bend Probability: 0.7
  Bend Max Offset: 15.0
  Bend Min Segment Length: 40.0
  Bend Enable Coordinated: true
  Bend Arc Intensity: 0.8
  Bend Direction Consistency: 1.0
  Bend Offset Smoothness: 0.8

Fruits:
  Bend Branch Enabled: true
  Bend Branch Probability: 0.5
  Bend Branch Collision Radius: 20.0
```

### 完全平滑弯曲（解决抖动）
```
BranchGenerator:
  Bend Max Points: 5-10
  Bend Probability: 1.0
  Bend Max Offset: 10.0
  Bend Min Segment Length: 50.0
  Bend Enable Coordinated: true
  Bend Arc Intensity: 1.0
  Bend Direction Consistency: 1.0
  Bend Offset Smoothness: 1.0

Fruits:
  Bend Branch Enabled: true
  Bend Branch Probability: 0.6
  Bend Branch Collision Radius: 25.0
```

### 强烈协调弯曲
```
BranchGenerator:
  Bend Max Points: 4
  Bend Probability: 0.9
  Bend Max Offset: 25.0
  Bend Min Segment Length: 30.0
  Bend Enable Coordinated: true
  Bend Arc Intensity: 1.0
  Bend Direction Consistency: 0.9

Fruits:
  Bend Branch Enabled: true
  Bend Branch Probability: 0.7
  Bend Branch Collision Radius: 25.0
```

### 传统随机弯曲（向后兼容）
```
BranchGenerator:
  Bend Max Points: 3
  Bend Probability: 0.7
  Bend Max Offset: 15.0
  Bend Min Segment Length: 40.0
  Bend Enable Coordinated: false

Fruits:
  Bend Branch Enabled: true
  Bend Branch Probability: 0.5
  Bend Branch Collision Radius: 20.0
```

## 功能优势

- **视觉自然**: 圆角连接的弯曲线段，摆脱机械感
- **协调弯曲**: 新的协调弯曲系统避免曲折摆动，创造优美的同向弯曲
- **弧形美感**: 支持弧形强度调节，创造自然的弯曲弧度
- **精确控制**: 通过方向一致性参数精确控制弯曲行为
- **功能分离**: 各按键职责明确，不会混淆
- **灵活控制**: 可以选择性地在弯曲点生成branch
- **向后兼容**: 支持传统随机弯曲模式
- **防脱落**: 改进的曲线采样确保branch point准确附着在弯曲trunk上

## 测试建议

### 基础测试流程
1. **测试协调弯曲**: 确保 `Bend Enable Coordinated` 设为 true，按空格键观察trunk的协调弯曲效果
2. **对比传统模式**: 设置 `Bend Enable Coordinated` 为 false，观察随机弯曲的区别
3. **调整弧形强度**: 修改 `Bend Arc Intensity` 参数（0.0-1.0），观察弧形效果变化
4. **测试方向一致性**: 调整 `Bend Direction Consistency` 参数，观察弯曲方向的一致性

### 高级测试
5. **测试F键**: 按F键在弯曲点生成branch_point，确认点准确附着在弯曲trunk上
6. **完整流程**: 空格→F→G的完整生成流程，验证branch_point不会脱落
7. **参数组合**: 尝试不同的参数组合，找到最理想的视觉效果

### 推荐测试参数序列
- **温和弯曲**: Arc Intensity = 0.5, Direction Consistency = 1.0
- **自然弯曲**: Arc Intensity = 0.8, Direction Consistency = 0.9  
- **强烈弯曲**: Arc Intensity = 1.0, Direction Consistency = 0.8 