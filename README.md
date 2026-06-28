# Masker — macOS 文本脱敏应用

macOS 原生脱敏工具。粘贴或拖入文本/文件，自动检测敏感信息替换为 UUID 占位符，交给 AI 处理后一键还原。

## 快速开始

```bash
git clone https://github.com/lezi-fun/masker
cd masker
open Masker.app
```

## 功能

- **脱敏**：检测姓名、手机号、身份证、银行卡、邮箱、URL、IP、护照号等 → 替换为 `🔒UUID.类型🔒`
- **还原**：导入映射 JSON → 粘贴 AI 结果 → 一键还原
- **文件支持**：TXT / DOCX / PDF / XLSX（拖拽或打开）
- **AI 增强**：可选开启 OpenAI Privacy Filter，额外识别地址、密码、密钥等
- **类型标签**：占位符带 `.姓名` `.手机` 等标签，AI 能理解上下文

## 构建

```bash
./build.sh both       # 两个版本
./build.sh            # 完整版（含 AI 模型 ~3.3G）
./build.sh light      # 轻量版（仅 regex，零依赖）
```

## 技术栈

- **语言**：Swift + SwiftUI
- **AI 模型**：OpenAI Privacy Filter (1.5B, Apache 2.0)
- **文件解析**：Python (python-docx, PyMuPDF, openpyxl)
- **架构**：SPM 多目标（MaskerCore 库 + Masker GUI + Test）

## License

MIT
