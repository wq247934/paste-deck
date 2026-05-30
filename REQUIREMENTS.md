# PasteDeck 功能性建议

> 基于代码审查发现的待完善功能项。

---

## 1. 黑名单未生效

- `ClipboardMonitor.isBlacklisted()` 始终返回 `false`，未从 `AppSettings` 读取黑名单数据
- 设置页 `FilterSettingsView` 使用 `@State` 管理黑名单，修改不持久化到 SwiftData
- **需要**：Monitor 从 AppSettings 读取 `blacklistedApps`；设置页改为直接修改 AppSettings model

## 2. 历史记录条数/天数限制未执行

- `AppSettings` 有 `historyCountLimit` 和 `historyDaysLimit`，但 `saveItem()` 只留了注释"清理逻辑移到启动时执行"
- 实际启动时也没有清理逻辑
- **需要**：实现启动时 + 定期的过期清理

## 3. 设置页状态未持久化

- `GeneralSettingsView`、`HistorySettingsView` 等都用 `@State`，修改后不会写入 SwiftData 的 `AppSettings`
- **需要**：改为 `@Query` 查询 `AppSettings` 并直接修改 model 属性

## 4. 开机启动未实现

- `launchAtLogin` 开关存在但无实际逻辑
- **需要**：集成 `SMAppService`（macOS 13+）实现开机启动

## 5. 快捷键不可自定义

- 设置页只显示当前快捷键文本，无法录制/修改
- `HotKeyManager` 已支持参数化注册，缺的是 UI 录制入口
- **需要**：设置页增加快捷键录制功能

## 6. 图片搜索缺失

- 搜索过滤中 `image` 类型直接返回 `false`
- **可选方案**：OCR 文字识别（Vision 框架）或至少支持按尺寸/来源搜索

## 7. 多文件复制只记录第一个

- `parseFile()` 只取 `fileURLs.first`，Finder 多选复制时会丢失其余文件
- **需要**：改为记录文件列表或创建多条记录

## 8. 置顶排序未生效

- `isPinned` 属性存在，但 `@Query` 排序只按 `createdAt`，置顶项不会排在前面
- **需要**：调整排序逻辑（先 pinned 再 createdAt）

## 9. 软删除逻辑缺失

- `isDeleted` 字段存在但从未被设置（删除用的是 `modelContext.delete` 直接删除）
- 也没有定期清理已标记项的逻辑
- **需要**：二选一——用软删除 + 定期清理，或去掉 `isDeleted` 字段
