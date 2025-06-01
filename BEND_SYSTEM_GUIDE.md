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

#### Texture System（纹理系统）
- **Texture Trunk Textures**: 纹理变体数组，将准备的PNG文件拖拽到这里
- **Texture Use Random**: 是否为每条线段随机选择纹理

### Fruits节点参数

#### Bend Point Branch Generation（弯曲点分支生成）
- **Bend Branch Enabled**: 是否启用F键功能
- **Bend Branch Probability** (0.0-1.0): 每个弯曲点生成branch_point的概率
- **Bend Branch Collision Radius** (像素): 弯曲点branch_point的碰撞检测半径

## 推荐参数设置

### 自然效果设置
```
BranchGenerator:
  Bend Max Points: 3
  Bend Probability: 0.7
  Bend Max Offset: 15.0
  Bend Min Segment Length: 40.0

Fruits:
  Bend Branch Enabled: true
  Bend Branch Probability: 0.5
  Bend Branch Collision Radius: 20.0
```

### 强烈弯曲效果
```
BranchGenerator:
  Bend Max Points: 4
  Bend Probability: 0.9
  Bend Max Offset: 25.0
  Bend Min Segment Length: 30.0

Fruits:
  Bend Branch Enabled: true
  Bend Branch Probability: 0.7
  Bend Branch Collision Radius: 25.0
```

## 功能优势

- **视觉自然**: 圆角连接的弯曲线段，摆脱机械感
- **功能分离**: 各按键职责明确，不会混淆
- **灵活控制**: 可以选择性地在弯曲点生成branch
- **纹理多样**: 每条线段随机选择纹理，避免重复

## 测试建议

1. **先测试弯曲**: 按空格键观察trunk的弯曲效果
2. **调整参数**: 根据视觉效果调整弯曲参数
3. **测试F键**: 按F键在弯曲点生成branch_point
4. **完整流程**: 空格→F→G的完整生成流程 