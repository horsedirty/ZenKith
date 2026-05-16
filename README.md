# ZenKith

<div align="center">

**多模态写作工作台 | 原生 macOS Markdown / LaTeX 编辑器**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://github.com/horsedirty/ZenKith/releases)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

## 概述

ZenKith 是一款为 macOS 打造的 Markdown 与 LaTeX 写作环境，集成 **AI 辅助写作**、**PDF 翻译**、**实时预览**、**多格式导出** 等能力，提供从构思到发布的完整工作流。应用采用原生 SwiftUI + AppKit 混合架构，充分利用 Apple 平台特性，在性能与体验上达到最优平衡。

## 核心功能

### 编辑与预览

- **Markdown / LaTeX 双模式编写** — 一键切换，语法高亮与补全自适应
- **LaTeX 语法高亮** — 命令、环境、数学公式、注释等 10 种 token 类型实时着色
- **实时预览** — 基于 WKWebView 渲染，支持 MathJax 数学公式与 highlight.js 代码高亮
- **三种视图布局** — 纯编辑、纯预览、分屏对照，可通过工具栏或快捷键切换

### AI 辅助

- **多模型接入** — 支持 DeepSeek、SiliconFlow 及自定义 OpenAI 兼容端点
- **对话式交互** — 流式输出、思考过程展示、历史会话管理
- **上下文注入** — 自动将当前笔记内容作为 AI 对话上下文
- **联网搜索** — 可选启用，增强回答的时效性与准确性
- **文件附件** — 支持图片、代码等文件作为附加素材
- **LaTeX 深度集成** — AI 自动感知 .tex 上下文、选中代码一键发送、编译错误 AI 诊断

### LaTeX 专业编辑

- **编译引擎** — 支持 pdflatex / xelatex / lualatex，自动检测已安装编译器
- **多轮编译 + BibTeX** — 自动处理交叉引用、目录、索引所需的多轮次编译
- **编译错误定位** — 结构化错误/警告提取，点击跳转到源码行并高亮标记
- **文档大纲** — 编辑器左侧章节结构树，解析 \section/\subsection 层级，点击跳转
- **自动补全** — \ 命令补全（170+ 命令）、\begin{ 环境补全（25+ 环境）、\cite{ 引用键智能补全
- **代码片段** — 工具栏分类模板（表格/矩阵/图形/定理/列表），一键插入
- **参考文献管理** — BibManager 自动扫描 .bib 文件，搜索/浏览/双击插入引用，重复键检测
- **SyncTeX 反向搜索** — PDF 预览点击位置跳转源码对应行
- **回退渲染** — 编译器不可用时，使用 WebView + MathJax 作为备选方案

### PDF 翻译

- **多引擎支持** — Apple 翻译（离线）与腾讯翻译 API（在线）
- **PDF 文档翻译** — 逐页提取文本、翻译、保持 Word 格式写入结果
- **翻译窗口** — 独立窗口操作，不影响主编辑流程

### 导出

| 格式 | 说明 |
|------|------|
| PDF | LaTeX 源码编译为原生 PDF 或 WebView 渲染导出 |
| Word (.docx) | 使用 NSAttributedString 富文本转换 |
| 纯文本 (.txt) | 原始 Markdown / LaTeX 文本 |
| Markdown (.md) | 源文件拷贝 |

### 项目管理

- **文件树侧边栏** — 支持文件夹导航、笔记列表、文件类型图标标识
- **文件管理** — 新建、重命名、删除笔记与文件夹，支持任意目录切换
- **面包屑导航** — 子目录浏览时可快速返回上级
- **状态栏** — 显示文件类型、字数统计、修改时间

### 其他特性

- **行号标尺** — 编辑器左侧行号显示，随字号自适应
- **字号调节** — 按住 `⌘` + 鼠标滚轮实时调节编辑器字号 (12–32pt)
- **深色模式** — 完整适配 macOS 浅色 / 深色外观
- **全局字体宋体 + Times New Roman** — 界面与预览默认使用衬线字体组合，编辑器保持等宽

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘ + N` | 新建笔记 |
| `⌘ + B` | 编译 LaTeX |
| `⌘ + ⇧ + E` | 发送选中内容给 AI |
| `⌘ + ⇧ + I` | 切换 AI 助手面板 |
| `⌘ + ⇧ + L` | 循环切换视图布局 |
| `⌘ + ⇧ + S` | 切换侧边栏 |
| `⌘ + 滚轮` | 调节编辑器字号 |
| `⌘ + ↩` | 发送 AI 消息 |

## 系统要求

- **操作系统**：macOS 14.0 (Sonoma) 或更高版本
- **架构**：Apple Silicon (arm64) 原生支持
- **LaTeX 编译**（可选）：需安装 [MacTeX](https://tug.org/mactex/) 或 BasicTeX
- **SyncTeX 反向搜索**（可选）：需安装 synctex 命令行工具（MacTeX 自带）

## 技术架构

| 层级 | 技术选型 |
|------|----------|
| UI 框架 | SwiftUI + AppKit (NSViewRepresentable) |
| Markdown 解析 | [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apple) |
| AI 消息渲染 | [Textual](https://github.com/gonzalezreal/Textual) |
| 代码高亮 | [Highlightr](https://github.com/helje5/Highlightr) |
| LaTeX 高亮 | 自研 NSTextStorage 增量高亮引擎 |
| 数学公式 | MathJax 3 (CDN) |
| 编辑器 | 自研 NSTextView 封装 + 行号标尺 |
| 密钥存储 | [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) |
| 数据持久化 | UserDefaults + 文件系统 |

## 安装

### 直接下载

从 [Releases](https://github.com/horsedirty/ZenKith/releases) 页面下载最新版本 `ZenKith_vX.X.X.dmg`，打开后将 ZenKith.app 拖入 `/Applications` 即可。

### 从源码构建

```bash
git clone https://github.com/horsedirty/ZenKith.git
cd ZenKith
open ZenKith.xcodeproj
```

在 Xcode 中选择 `ZenKith` scheme，按 `⌘ + R` 运行。

> **注意**：首次构建时 Xcode 会自动解析 SPM 依赖，请确保网络连接正常。

## 许可证

本项目采用 [MIT License](LICENSE)。

---

<div align="center">

**ZenKith** — 为严肃写作而生的 macOS 工作台

</div>
