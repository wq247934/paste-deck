# PasteDeck 功能需求文档

> 基于 `$grill-me` 讨论整理的 v2.0 新增需求，逐条细化。

---

## 1. Cmd+F 聚焦搜索框

- 面板打开后，按 `Cmd+F` 将键盘焦点移入搜索框
- **硬编码**，不需要在设置页配置
- 实现方式：监听 `keyCode=3 + modifiers=.command`

## 2. 多选 + 批量粘贴

### 交互方式

| 操作 | 行为 |
|------|------|
| 左右方向键 | 单选移动（蓝色高亮边框） |
| **Shift + 左右方向键** | 扩展/收缩选择区间（类 Finder），以当前锚点为起点 |
| **Shift + 点击卡片** | 区间选中：从锚点扩展到点击位置 |
| **Cmd + 点击卡片** | Toggle 单张卡片选中状态，不影响其他卡片 |
| 普通点击卡片 | 清除多选，变为单选 |

### 视觉反馈

- 选中卡片：蓝色边框 + 背景加深（方案A，无 checkmark badge）

### 批量粘贴

- 按 **Enter**：面板关闭 → 按显示顺序（newest first）依次粘贴所有选中内容
- 每次粘贴间隔 ~150ms（`DispatchQueue.main.asyncAfter`），确保目标应用能依次处理

## 3. 预览窗口上下键滚动

- 当前代码预览（CodeHighlightView / NSScrollView）已支持上下键，但打开时焦点不在内容区
- **修复方式**：预览窗口打开后，让内容区的 `NSScrollView` 自动成为 `firstResponder`
- 文本预览也改用 `NSScrollView`，不使用 SwiftUI 的 `@FocusState`（在 NSWindow 环境下不可靠）

## 4. 关闭面板时清空搜索框

- 每次关闭面板 → 清空 `searchText`
- 实现：`MainPanelController.hidePanel()` 发 `Notification.Name.clearSearchText`，`MainPanelView` 接收并重置
- 同时重置多选和筛选状态

## 5. 鼠标滚轮横向滚动卡片

- 鼠标移到卡片区域（下方 ~75%）时，滚轮事件转发到 `ScrollView(.horizontal)`
- 触控板双指左右滑原生支持；普通鼠标滚轮需拦截 `scrollWheel` 并转发
- **注意**：不可通过让某个 NSView 成为 `firstResponder` 来实现，否则会拦截其他事件

## 6. Tab 切换收藏夹

- 按 **Tab** 在筛选标签间循环切换：全部 → 收藏夹1 → 收藏夹2 → ... → 全部
- **放弃**原有的 Tab 切换「焦点区域」（cards ↔ search）功能

## 7. 自定义收藏夹系统

### 数据模型

- 新建 `FavoriteCollection` SwiftData 模型：
  - `id: UUID`
  - `name: String`
  - `sortOrder: Int`
  - `isDefault: Bool`
  - `createdAt: Date`
  - `items: [ClipboardItem]?`（多对多）
- `ClipboardItem` 移除 `isFavorite: Bool`，新增 `collections: [FavoriteCollection]?`
- 预置一个**默认收藏夹**，名称"收藏"，`isDefault = true`，**不允许改名、不允许删除**
- 一张卡片可以属于多个收藏夹（多对多）

### UI

#### 筛选标签栏
- 横向滚动，标签过多时支持滑动（不折叠为下拉菜单）
- 标签顺序：**全部**（始终最左）→ 收藏夹（按 `sortOrder` 排序）→ **+ 按钮**（紧跟最后一个标签后）
- "+" 按钮点击 → 弹出 sheet "新建收藏夹"，输入名称（默认"新建收藏夹"），点击创建

#### 卡片上的收藏操作
- 右上角**星标**（star icon）：点击 toggle 加入/移出默认"收藏"收藏夹
  - 已收藏 → 黄色实心 `star.fill`
  - 未收藏 → 灰色空心 `star`
- 右键菜单 → "添加到收藏夹" → 子菜单列出所有收藏夹，已加入的打勾
- 卡片底部显示非默认收藏夹的 **badge**（最多显示 2 个，超出显示 "+N"）

#### 设置页 - 收藏夹 Tab
- 新增"收藏夹" Tab（位于"过滤"和"外观"之间）
- 列表展示所有收藏夹，默认收藏夹显示"默认"标签且无删除按钮
- 非默认收藏夹可删除（仅解除卡片关联，不删卡片）
- 拖拽排序（`List` + `.onMove`）

---



## 构建 & 打包

```bash
./scripts/build-dmg.sh
```

输出 `PasteDeck-1.0.dmg`。
