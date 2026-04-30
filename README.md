# Typoless

Typoless 是一个面向 macOS 的语音 + AI 输入助手项目。

首版产品形态不是系统级输入法，而是 `菜单栏常驻应用`。用户通过全局快捷键触发录音（按一次开始，再按一次结束），录音结束后自动完成：

`录音 -> RNNoise 本地降噪 -> FunASR 离线识别 -> OpenAI 兼容 LLM 润色 -> 写回当前焦点应用`

## 项目目标

- 在 macOS 上提供全局可用的中文语音输入能力
- 使用本地 `FunASR` 离线 ASR 完成短语音识别，无需配置云端 ASR 服务
- 使用 RNNoise 本地降噪和个人词典提升中文短语音识别质量
- 支持用户接入自有 `OpenAI 兼容` 大模型服务
- 将口语输入整理为更适合直接发送或写入的文本
- 在常见桌面应用中稳定注入文本

## 首版范围

### 已实现

- 菜单栏常驻应用（MenuBarExtra）
- 设置页（LLM / 通用 / 权限 / 诊断）
- 全局快捷键（Carbon Event API）
- 按一次开始录音，再按一次结束录音
- FunASR 本地离线 ASR（默认链路，通过内置 Python sidecar 运行 paraformer-zh + fsmn-vad）
- RNNoise 本地降噪（录音后、ASR 前自动执行）
- OpenAI 兼容 LLM 润色（增强版固定 Prompt，纠错 + 同音词 + 去赘词 + 轻度书面化 + 补标点 + 专有名词保护）
- 个人词典（ASR hotwords + LLM 术语参考，`~/.typoless/dictionary.json`）
- 文本注入（AX API 主策略 + 键盘事件回退）
- 麦克风与辅助功能权限引导
- 注入失败文本临时复制入口（菜单栏内显示截断预览，点击复制到剪贴板，仅当前运行期有效）
- 状态机驱动菜单栏反馈（空闲 / 录音中 / 识别中 / 润色中 / 注入中 / 完成 / 失败 / 已取消）
- 用户可理解的错误分类与展示
- 处理中可取消（识别中 / 润色中）
- 诊断页（最近错误摘要 + 会话状态 + 版本信息）
- 诊断日志（per-session 耗时、Debug ASR/LLM 明文对照、Release 脱敏）
- 60 秒录音上限 + 500ms 短录音静默取消
- 本地 FunASR 模型外置到用户目录，设置页通过模型状态区引导下载与展示就绪状态
- 腾讯云一句话识别（用户手动选择，直接调用 Cloud API）
- 构建前与录音前资源校验

### 不包含

- macOS 系统级输入法
- 多种 LLM 协议
- 自定义 Prompt
- 风格模式切换
- temperature / max tokens 等高级参数
- ASR 高级运行参数
- 音频历史保存
- Agent 工作流

## 产品行为

- 应用形态：菜单栏常驻应用
- 交互方式：单一全局快捷键，按一次开始录音，再按一次结束录音
- 单次录音上限：`60 秒`
- 低于 `500ms` 的录音视为误触，静默取消，不进入识别和 LLM
- ASR 平台：用户手动选择 `本地 FunASR` 或 `腾讯云一句话识别`
- 本地模型：存储于 `~/.typoless/models/funasr/`，设置页仅展示模型状态，不暴露路径或版本
- 音频预处理：默认 RNNoise 本地降噪
- 默认输出：`LLM 润色版`
- LLM 启用条件：`Base URL`、`API Key`、`Model` 三项完整
- LLM 失败处理：直接报错，不注入任何文本
- 注入失败策略：不自动写剪贴板，菜单栏显示失败文本截断预览，点击可复制到剪贴板，仅当前运行期有效

## 技术架构

### 技术栈

- 客户端：`Swift 6.0 + SwiftUI + AppKit`
- 架构：`MVVM + Service Layer`
- 语音识别：`FunASR` 本地离线 ASR / `腾讯云一句话识别`（用户手动切换）
- 音频降噪：`RNNoise`
- 大模型接入：`OpenAI Chat Completions` 兼容接口
- 音频格式：`PCM/WAV 16k mono`
- 文本注入：优先 `Accessibility API`，失败后回退键盘事件输入
- 配置存储：`~/.typoless/config.json`（UTF-8 JSON）

### 分层结构

```
app/Typoless/
├── App/                    # 应用入口（TypolessApp）
├── Domain/
│   ├── Coordinators/       # AppCoordinator, SessionCoordinator
│   ├── Models/             # SessionState, TypolessError, AppConfig 等
│   └── Services/           # DiagnosticsLogger, ResourceValidator
├── Persistence/            # ConfigStore, KeychainHelper, PersonalDictionaryStore
├── Platform/               # AudioRecorder, AudioPreprocessor, HotkeyManager, PermissionsManager, TextInjector
├── Providers/              # ASRProvider, FunASRProvider, ASRRuntimeManager, StreamingASRProvider, WhisperProvider, LLMProvider
├── Resources/              # 资源文件（正式包默认包含 rnnoise, funasr）
└── UI/
    ├── MenuBar/            # MenuBarView
    └── Settings/           # 设置页各 Tab 视图
```

### 核心对象

| 对象 | 职责 |
| --- | --- |
| `AppCoordinator` | 应用生命周期、菜单栏入口、设置页导航 |
| `SessionCoordinator` | 主链路状态机编排（录音→识别→润色→注入） |
| `AudioRecorder` | 音频采集与 PCM/WAV 标准化 |
| `AudioPreprocessor` | RNNoise 本地降噪 |
| `ASRProvider` | 统一 ASR 识别协议 |
| `FunASRProvider` | FunASR 离线识别（默认链路），通过 sidecar 通信 |
| `ASRRuntimeManager` | Python sidecar 生命周期管理、warmup、健康检查 |
| `StreamingASRProvider` | sherpa-onnx 流式识别（旧链路） |
| `WhisperProvider` | 本地 Whisper 子进程调用（旧链路） |
| `LLMProvider` | OpenAI Chat Completions 调用 |
| `TextInjector` | AX API 文本注入 + 键盘事件回退 |
| `PermissionsManager` | 麦克风与辅助功能权限管理 |
| `HotkeyManager` | Carbon Event 全局快捷键 |
| `ConfigStore` | `~/.typoless/config.json` 配置读写 |
| `PersonalDictionaryStore` | 个人词典管理（`~/.typoless/dictionary.json`） |
| `DiagnosticsLogger` | 会话耗时与 ASR/LLM 对照日志 |
| `ResourceValidator` | 运行时资源完整性校验 |

## 核心流程

### 首次配置

1. 启动应用
2. 应用内置降噪、FunASR runtime 与 worker；若使用本地 FunASR，先在设置页下载模型
3. 配置 LLM `Base URL / API Key / Model`
4. 设置全局快捷键
5. 授予麦克风权限
6. 授予辅助功能权限

### 日常使用

1. 在任意应用中聚焦输入区域
2. 按下快捷键开始录音
3. 再次按下快捷键结束录音（或达到 60 秒自动结束）
4. 对音频进行本地降噪
5. 使用 FunASR 进行本地离线识别，获取转写文本
6. 调用 LLM 做纠错与轻度书面化
7. 将最终文本一次性注入当前焦点应用

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
| LLM 空结果 | LLM 返回空结果，请检查模型或网关配置 |
| 文本注入失败 | 文本注入失败：具体原因 |

## LLM 处理边界

首版 LLM 只做以下事情：

- 修正 ASR 识别错误
- 修正常见同音词和错别字
- 去掉明显口语赘词
- 轻度书面化表达
- 自动补自然中文标点
- 保留个人词典中的专有名词

首版 LLM 不做以下事情：

- 大幅改写句子结构
- 扩写用户没说出的内容
- 擅自改变语义、语气、事实

## 配置项

| 配置字段 | 存储位置 |
| --- | --- |
| `openai_base_url` | `~/.typoless/config.json` |
| `openai_model` | `~/.typoless/config.json` |
| `global_hotkey` | `~/.typoless/config.json` |
| `pasteboard_injection_bundle_ids` | `~/.typoless/config.json` |
| `openai_api_key` | `~/.typoless/config.json` |
| 个人词典 | `~/.typoless/dictionary.json` |

## 测试策略

- 单元测试重点覆盖 `Provider`（FunASR/sherpa/Whisper）、`ASRRuntimeManager`、`AudioPreprocessor`、`PersonalDictionaryStore` 和 `Session Coordinator`
- 端到端以手工验收主链路为主
- 重点验证权限缺失、配置错误、LLM 回退、注入失败

### 手工验收清单

- [ ] 首次启动自动打开设置页
- [ ] 配置 LLM 并保存成功
- [ ] 设置全局快捷键并生效
- [ ] 麦克风权限授权后可录音
- [ ] 低于 500ms 的短录音静默取消，不触发 ASR / LLM / 注入
- [ ] 辅助功能权限授权后可注入文本
- [ ] 完整链路：录音 → 降噪 → FunASR → LLM → 注入（浏览器输入框、备忘录、聊天应用）
- [ ] RNNoise 降噪链路正常
- [ ] FunASR 离线识别链路正常
- [ ] FunASR sidecar 首次惰性启动成功
- [ ] Debug 日志可查看耗时和 ASR/LLM 明文对照
- [ ] Release 日志不泄露 ASR/LLM 明文
- [ ] 个人词典可改善专有名词识别与润色
- [ ] LLM 配置不完整时，录音流程直接报错且不注入文本
- [ ] LLM 失败或空结果时直接报错且不注入文本
- [ ] 注入失败后菜单栏显示失败文本预览，点击可复制
- [ ] 成功注入后失败文本预览消失
- [ ] 菜单栏状态随主链路正确刷新
- [ ] 识别中 / 润色中可从菜单取消
- [ ] 诊断页展示最近错误摘要
- [ ] 权限缺失场景提示清晰
- [ ] 本地识别失败场景提示清晰
- [ ] 应用重启后配置正常恢复，无历史文本残留

## 目录说明

- [PRD.md](./docs/PRD.md): 已更新的产品需求文档
- [TDD.md](./docs/TDD.md): 已更新的技术设计文档
- [EPICS_AND_STORIES.md](./docs/EPICS_AND_STORIES.md): Epic 和 Story 拆分
- `app/`: macOS 客户端代码（Swift + SwiftUI + AppKit）
- `app/project.yml`: XcodeGen 项目配置

## 开发环境

### 依赖

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 准备本地语音资源

正式包默认仅内置 `FunASR + RNNoise` 资源。开发环境至少需要准备 RNNoise；旧链路脚本只保留给历史调试用途：

```bash
# 准备 RNNoise 降噪库
./scripts/setup-rnnoise.sh

# 可选：准备 sherpa-onnx runtime 与中文 streaming 模型（旧链路调试）
# ./scripts/setup-sherpa.sh

# 可选：准备 Whisper 资源（旧链路调试）
# ./scripts/setup-whisper.sh
```

脚本支持通过环境变量指定资源路径，详见各脚本顶部注释。

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

- `PRD`: 已更新至 v1.2（FunASR 收敛）
- `TDD`: 已更新至 v1.2（FunASR sidecar 架构）
- `代码实现`: FunASR 默认链路实现中（DiagnosticsLogger、RNNoise、个人词典、Prompt 优化、资源校验已完成；FunASR Provider 与 sidecar 集成进行中）

## 参考

- 产品需求文档：[PRD.md](./docs/PRD.md)
- Epic 和 Story 拆分：[EPICS_AND_STORIES.md](./docs/EPICS_AND_STORIES.md)
- 技术设计文档：[TDD.md](./docs/TDD.md)
