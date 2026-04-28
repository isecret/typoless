# Typoless

Typoless 是一个面向 macOS 的语音 + AI 输入助手项目。

首版产品形态不是系统级输入法，而是 `菜单栏常驻应用`。用户通过全局快捷键触发录音（按一次开始，再按一次结束），录音结束后自动完成：

`录音 -> 本地 FunASR 识别 -> OpenAI 兼容 LLM 润色 -> 写回当前焦点应用`

## 项目目标

- 在 macOS 上提供全局可用的中文语音输入能力
- 使用本地 FunASR 完成短语音识别，无需配置云端 ASR 服务
- 支持用户接入自有 `OpenAI 兼容` 大模型服务
- 将口语输入整理为更适合直接发送或写入的文本
- 在常见桌面应用中稳定注入文本

## 首版范围

### 已实现

- 菜单栏常驻应用（MenuBarExtra）
- 设置页（LLM / 通用 / 权限 / 诊断 / 最近记录）
- 全局快捷键（Carbon Event API）
- 按一次开始录音，再按一次结束录音
- 本地 FunASR 语音识别（内置子进程方式）
- OpenAI 兼容 LLM 润色（固定 Prompt，纠错 + 去赘词 + 轻度书面化 + 补标点）
- 文本注入（AX API 主策略 + 键盘事件回退）
- 麦克风与辅助功能权限引导
- 最近 10 条文本记录（查看 / 复制 / 清空）
- LLM 失败时自动回退 ASR 原文
- 状态机驱动菜单栏反馈（空闲 / 录音中 / 识别中 / 润色中 / 注入中 / 完成 / 失败 / 已取消）
- 用户可理解的错误分类与展示
- 处理中可取消（识别中 / 润色中）
- 诊断页（最近错误摘要 + 会话状态 + 版本信息）

### 不包含

- macOS 系统级输入法
- 实时流式识别
- 多 ASR Provider
- 多种 LLM 协议
- 自定义 Prompt
- 风格模式切换
- temperature / max tokens 等高级参数
- FunASR 高级运行参数
- 音频历史保存
- Agent 工作流

## 产品行为

- 应用形态：菜单栏常驻应用
- 交互方式：单一全局快捷键，按一次开始录音，再按一次结束录音
- 单次录音上限：`30 秒`
- ASR Provider：`本地 FunASR`
- 默认输出：`LLM 润色版`
- LLM 失败回退：自动输出 `ASR 原文`
- 注入失败策略：不自动写剪贴板，结果保留在最近记录中供用户复制
- 最近记录：仅保存 `最终文本 + 时间 + 状态`

## 技术架构

### 技术栈

- 客户端：`Swift 6.0 + SwiftUI + AppKit`
- 架构：`MVVM + Service Layer`
- 语音识别：`本地 FunASR`（内置子进程方式）
- 大模型接入：`OpenAI Chat Completions` 兼容接口
- 音频格式：`PCM/WAV 16k mono`
- 文本注入：优先 `Accessibility API`，失败后回退键盘事件输入
- 普通设置存储：`~/.typoless/config`（UTF-8 JSON）
- 密钥存储：`~/.typoless/config`（与普通设置统一存储）
- 最近记录存储：`UserDefaults`（JSON 编码）

### 分层结构

```
app/Typoless/
├── App/                    # 应用入口（TypolessApp）
├── Domain/
│   ├── Coordinators/       # AppCoordinator, SessionCoordinator
│   └── Models/             # SessionState, TypolessError, RecentRecord, AppConfig 等
├── Persistence/            # ConfigStore, KeychainHelper, RecentRecordStore
├── Platform/               # AudioRecorder, HotkeyManager, PermissionsManager, TextInjector
├── Providers/              # ASRProvider, FunASRProvider, LLMProvider
├── Resources/              # 资源文件
└── UI/
    ├── MenuBar/            # MenuBarView
    └── Settings/           # 设置页各 Tab 视图
```

### 核心对象

| 对象 | 职责 |
| --- | --- |
| `AppCoordinator` | 应用生命周期、菜单栏入口、设置页导航 |
| `SessionCoordinator` | 主链路状态机编排（录音→识别→润色→注入→记录） |
| `AudioRecorder` | 音频采集与 PCM/WAV 标准化 |
| `ASRProvider` | 统一 ASR 识别协议 |
| `FunASRProvider` | 本地 FunASR 子进程调用 |
| `LLMProvider` | OpenAI Chat Completions 调用 |
| `TextInjector` | AX API 文本注入 + 键盘事件回退 |
| `PermissionsManager` | 麦克风与辅助功能权限管理 |
| `HotkeyManager` | Carbon Event 全局快捷键 |
| `ConfigStore` | `~/.typoless/config` 配置读写 |
| `RecentRecordStore` | 最近记录持久化（最多 10 条） |

## 核心流程

### 首次配置

1. 启动应用
2. 本地 FunASR 无需额外 ASR 配置
3. 配置 LLM `Base URL / API Key / Model`
4. 设置全局快捷键
5. 授予麦克风权限
6. 授予辅助功能权限

### 日常使用

1. 在任意应用中聚焦输入区域
2. 按下快捷键开始录音
3. 再次按下快捷键结束录音（或达到 30 秒自动结束）
4. 提交音频到本地 FunASR
5. 获取原始转写文本
6. 调用 LLM 做纠错与轻度书面化
7. 将最终文本注入当前焦点应用
8. 记录保存到最近记录

## 状态机

主状态流转：

`idle -> recording -> transcribing -> polishing -> injecting -> done`

异常状态：

- `error`
- `cancelled`

约束：

- 同一时间只允许一个 session
- 菜单栏允许取消处理中任务（识别中 / 润色中）
- 取消后不得继续注入文本
- 状态变化实时反映到菜单栏图标

## 错误处理

| 错误类型 | 用户提示 |
| --- | --- |
| 麦克风权限缺失 | 麦克风权限未开启，无法录音 |
| 辅助功能权限缺失 | 辅助功能权限未开启，无法注入文本 |
| 录音数据为空 | 录音数据为空，请重试 |
| 本地识别引擎未就绪 | 本地识别引擎未就绪，请重新安装应用 |
| LLM 配置无效 | LLM 配置无效：具体原因 |
| LLM 网络失败 | LLM 网络连接失败，请检查网络 |
| LLM 空结果 | LLM 返回空结果，已使用原始识别文本 |
| 文本注入失败 | 文本注入失败：具体原因 |

## LLM 处理边界

首版 LLM 只做以下事情：

- 修正 ASR 识别错误
- 去掉明显口语赘词
- 轻度书面化表达
- 自动补自然中文标点

首版 LLM 不做以下事情：

- 大幅改写句子结构
- 扩写用户没说出的内容
- 擅自改变语义、语气、事实

## 配置项

| 配置字段 | 存储位置 |
| --- | --- |
| `openai_base_url` | `~/.typoless/config` |
| `openai_model` | `~/.typoless/config` |
| `global_hotkey` | `~/.typoless/config` |
| `recording_trigger_mode` | `~/.typoless/config` |
| `enable_ai_polish` | `~/.typoless/config` |
| `openai_api_key` | `~/.typoless/config` |

## 测试策略

- 单元测试重点覆盖 `Provider`（FunASR）和 `Session Coordinator`
- 端到端以手工验收主链路为主
- 重点验证权限缺失、配置错误、LLM 回退、注入失败

### 手工验收清单

- [ ] 首次启动自动打开设置页
- [ ] 配置 LLM 并保存成功
- [ ] 设置全局快捷键并生效
- [ ] 麦克风权限授权后可录音
- [ ] 辅助功能权限授权后可注入文本
- [ ] 完整链路：录音 → ASR → LLM → 注入（浏览器输入框、备忘录、聊天应用）
- [ ] FunASR 本地识别链路正常
- [ ] 关闭 AI 润色：录音 → ASR → 直接注入
- [ ] LLM 失败自动回退 ASR 原文
- [ ] 注入失败后文本保留在最近记录
- [ ] 最近记录可查看、复制、清空
- [ ] 菜单栏状态随主链路正确刷新
- [ ] 识别中 / 润色中可从菜单取消
- [ ] 诊断页展示最近错误摘要
- [ ] 权限缺失场景提示清晰
- [ ] 本地识别失败场景提示清晰
- [ ] 应用重启后配置和记录正常恢复

## 目录说明

- [PRD.md](./docs/PRD.md): 已冻结的产品需求文档
- [TDD.md](./docs/TDD.md): 已冻结的技术设计文档
- [EPICS_AND_STORIES.md](./docs/EPICS_AND_STORIES.md): Epic 和 Story 拆分
- `app/`: macOS 客户端代码（Swift + SwiftUI + AppKit）
- `app/project.yml`: XcodeGen 项目配置

## 开发环境

### 依赖

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 生成 Xcode 工程

```bash
cd app
xcodegen generate
open Typoless.xcodeproj
```

### 构建与运行

```bash
cd app
xcodegen generate
xcodebuild build -project Typoless.xcodeproj -scheme Typoless -destination 'platform=macOS'
```

或在 Xcode 中打开 `Typoless.xcodeproj` 后按 `⌘R` 运行。

## 当前状态

- `PRD`: 已冻结
- `TDD`: 已冻结
- `代码实现`: MVP 全部 Epic（E1-E10）已完成

## 参考

- 产品需求文档：[PRD.md](./docs/PRD.md)
- Epic 和 Story 拆分：[EPICS_AND_STORIES.md](./docs/EPICS_AND_STORIES.md)
- 技术设计文档：[TDD.md](./docs/TDD.md)
