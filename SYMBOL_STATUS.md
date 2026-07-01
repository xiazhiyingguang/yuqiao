# Mulberry Symbols 图文匹配状态文档

本文档记录语桥项目中所有 Mulberry Symbol 图文映射条目的匹配状态。

## 状态说明

- **review**：默认状态，图文匹配待审核
- **approved**：图文匹配已确认正确
- **disabled**：图文不匹配，前端已隐藏（不影响后端数据）

## 已禁用条目（图文不匹配）

以下 14 个条目因图片与中文词义不匹配，已标记为 `disabled`，前端不会显示这些符号图标，但后端数据保留以便后续替换合适的图片。

| 词汇 | SVG 资源 | 禁用原因 |
|------|----------|----------|
| 书 | `EN-symbols/read_book_,_to.svg` | 未找到合适的图片 |
| 休息 | `EN-symbols/rest_,_to.svg` | 未找到合适的图片 |
| 公园 | `EN-symbols/park_,_to.svg` | 未找到合适的图片 |
| 办公室 | `EN-symbols/desk.svg` | 未找到合适的图片 |
| 医院 | `EN-symbols/surgery_health_centre.svg` | 未找到合适的图片 |
| 卧室 | `EN-symbols/headboard.svg` | 未找到合适的图片 |
| 厨房 | `EN-symbols/cooker.svg` | 未找到合适的图片 |
| 吃饭 | `EN-symbols/eat_,_to.svg` | 未找到合适的图片 |
| 头发 | `EN-symbols/long_hair.svg` | 未找到合适的图片 |
| 手 | `EN-symbols/left_hand.svg` | 未找到合适的图片 |
| 梳头 | `EN-symbols/brush_hair_,_to.svg` | 未找到合适的图片 |
| 睡觉 | `EN-symbols/sleep_male_,_to.svg` | 未找到合适的图片 |
| 脸 | `EN-symbols/face_neutral_3.svg` | 未找到合适的图片 |
| 颜料 | `EN-symbols/paint.svg` | 未找到合适的图片 |

## 过滤逻辑

以下位置会自动跳过 `status: 'disabled'` 的条目：

- `MulberrySymbolResolver.assetForText()` — 核心关键词到 SVG 的查找
- `RehabTrainingDeck.words()` — 词语花园训练词池构建
- `MulberrySymbolResolver.hasSymbolFor()` — 间接通过 `assetForText()` 过滤

以下位置会显示所有条目（包括 disabled），用于调试和审核：

- `mulberry_symbols.dart` — 符号浏览器（开发调试用）

## 如何恢复或新增禁用

如需恢复某个条目，将其 `status` 改回 `'review'` 或 `'approved'`：

```dart
MulberrySymbolEntry('EN-symbols/example.svg', ['关键词'],
    status: 'review'),  // 改回 review 即可恢复
```

如需新增禁用，添加 `status: 'disabled'` 和 `note`：

```dart
MulberrySymbolEntry('EN-symbols/example.svg', ['关键词'],
    status: 'disabled', note: '未找到合适的图片'),
```
