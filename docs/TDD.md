# Typoless TDD

## 1. 文档信息

- 项目名称：Typoless
- 文档类型：TDD
- 版本：v1.1
- 状态：已更新
- 更新时间：2026-04-28

## 2. 目标

本文档定义 Typoless 首版的技术实现方案，用于指导 macOS 客户端从零开发到 MVP 交付。

本文档覆盖：

- 客户端架构
- 模块职责
- 状态机与数据流
- 外部服务接入方式
- 本地存储与权限策略
- 错误处理与回退机制
- 测试策略与验收落点

本文档不覆盖：

- 新产品需求扩展
- 系统级输入法实现
- ASR Provider 自动回退

## 3. 技术选型

### 3.1 客户端

- 语言：`Swift`
- UI：`SwiftUI`
- 系统交互：`AppKit`
- 架构：`MVVM + Service Layer`

### 3.2 外部服务

- 音频预处理：`RNNoise` 本地降噪
- ASR：`sherpa-onnx` 本地流式识别
- LLM：`OpenAI Chat Completions` 兼容接口

### 3.3 音频与注入

- 录音标准格式：`PCM/WAV 16k mono`
- 降噪处理：录音结束后进入 ASR 前执行，输出仍为 ASR 可消费的 16k mono WAV
- 文本注入主策略：`AX focused element set value`
- 文本注入回退策略：键盘事件输入

### 3.4 本地存储

- 全部配置（含密钥）：`~/.typoless/config`（UTF-8 JSON，目录权限 `0700`，文件权限 `0600`）

## 4. 系统架构

### 4.1 分层

- `UI`
  负责菜单栏、设置页、状态展示
- `Domain`
  负责状态机、会话编排、错误模型、配置模型
- `Providers`
  负责本地 sherpa-onnx 流式语音识别和 OpenAI 兼容 LLM 的调用
- `Platform`
  负责录音、权限、全局快捷键、文本注入
- `Persistence`
  负责配置与密钥存储

### 4.2 核心对象

- `AppCoordinator`
  管理应用生命周期、菜单栏与设置页入口
- `SessionCoordinator`
  负责编排录音、识别、润色、注入的主链路
- `AudioRecorder`
  负责录音采集与音频标准化
- `AudioPreprocessor`
  负责 RNNoise 本地降噪处理
- `ASRProvider` (协议)
  统一的 ASR 识别接口
- `StreamingASRProvider`
  负责 sherpa-onnx 流式识别，输出 partial 与 final 结果
- `WhisperProvider`
  保留旧本地 Whisper 子进程调用能力，但不作为默认 ASR 路径
- `LLMProvider`
  负责 OpenAI Chat Completions 调用
- `TextInjector`
  负责 AX 注入和键盘事件回退
- `PermissionsManager`
  负责麦克风与辅助功能权限检查
- `HotkeyManager`
  负责全局快捷键注册与更新
- `ConfigStore`
  负责普通配置和密钥读写
- `PersonalDictionaryStore`
  负责个人词典读写、启用词条过滤和 hotwords 文件生成
- `DiagnosticsLogger`
  负责主链路耗时、错误分类和 Debug ASR/LLM 对照日志

## 5. 模块职责

### 5.1 AppCoordinator

- 启动应用并初始化菜单栏
- 决定首次启动是否自动打开设置页
- 订阅 `SessionCoordinator` 状态用于刷新菜单栏 UI

### 5.2 SessionCoordinator

- 保证同一时间只存在一个 active session
- 响应开始录音、结束录音、取消任务
- 串行调度 `AudioRecorder -> AudioPreprocessor -> ASRProvider -> LLMProvider -> TextInjector`
- 默认使用本地 `StreamingASRProvider`
- 负责回退逻辑
- 在内存中维护最近一次注入失败文本，成功注入后清空
- 负责输出会话耗时诊断日志

### 5.3 AudioRecorder

- 处理开始录音、停止录音
- 限制录音上限为 30 秒
- 输出标准化音频数据或临时文件引用
- 不负责上传和业务状态流转

### 5.4 AudioPreprocessor

- 使用 RNNoise 对录音结果进行本地降噪。
- 输入为录音输出的 WAV 数据，输出为 16k mono WAV 数据。
- 降噪资源缺失或处理失败时返回明确错误，不静默劣化为原音频。
- 不保存降噪前后的音频历史。

### 5.5 ASR Provider 层

统一 ASR 协议需支持非流式 final 结果与流式 partial/final 事件。

#### 5.5.1 StreamingASRProvider

- 基于 `sherpa-onnx` 本地 streaming ASR。
- 录音期间产生 partial 结果，仅用于内部状态、HUD 预览或 Debug 日志。
- 录音结束后返回 final 文本，进入 LLM 润色和注入。
- 支持使用个人词典生成 hotwords 文件；仅在所选 transducer 模型支持 hotwords 时启用。
- runtime、模型、tokens、hotwords 文件通过项目脚本准备和校验。
- 资源缺失时返回明确配置错误，阻止录音，不自动回退 Whisper。

#### 5.5.2 WhisperProvider

- 作为旧离线识别实现保留。
- 不作为默认路径。
- 不作为 sherpa runtime/model 缺失时的自动回退。

### 5.6 LLMProvider

- 使用固定 Prompt 生成 Chat Completions 请求
- 返回润色后的最终文本
- 不处理 UI 和回退逻辑
- Prompt 可接收个人词典术语参考，但不开放用户自定义 Prompt

### 5.7 TextInjector

- 优先定位当前焦点元素并尝试 `AX` 写值
- 当 `AX` 写值不可用时回退为键盘事件输入
- 返回统一注入结果和错误

### 5.8 ConfigStore

- 统一使用 `~/.typoless/config` 读写全部配置（含密钥）
- 启动时直接从配置文件加载到内存
- 若配置文件不存在，自动从旧存储（UserDefaults + Keychain）迁移
- 若配置文件损坏，标记为加载失败，使首次配置检查返回 false
- 保存时执行轻量校验，整文件原子写回
- `hasCompletedInitialSetup` 在配置文件正常加载后返回 true；ASR 资源完整性在录音前检查

### 5.9 PersonalDictionaryStore

- 使用 `~/.typoless/dictionary.json` 存储用户维护的个人词典。
- 词条至少包含 `term`，可选 `pronunciationHint`、`category`、`enabled`。
- 生成 sherpa hotwords 文件，并为 LLM Prompt 提供术语参考。

### 5.10 DiagnosticsLogger

- 使用 `os.Logger(subsystem: "com.isecret.typoless", category: "Session")` 输出应用日志。
- 记录 `session_id`、各阶段耗时、文本长度、结果来源、错误分类和目标 app bundle id。
- Debug 构建可输出 ASR 原文与 LLM 输出；Release 构建仅输出脱敏摘要。

## 6. 状态机

### 6.1 状态定义

- `idle`
- `recording`
- `transcribing`
- `polishing`
- `injecting`
- `done`
- `error`
- `cancelled`

### 6.2 状态流转

正常路径：

`idle -> recording -> transcribing -> polishing -> injecting -> done -> idle`

关闭 AI 润色路径：

`idle -> recording -> transcribing -> injecting -> done -> idle`

LLM 回退路径：

`idle -> recording -> transcribing -> polishing -> injecting -> done -> idle`

异常路径：

- 任意状态可进入 `error`
- `transcribing` 和 `polishing` 可进入 `cancelled`
- `cancelled` 完成清理后返回 `idle`

### 6.3 状态约束

- 正在处理时禁止开启第二个 session
- 超时录音自动结束后继续走主链路
- 用户取消后必须中断后续步骤，不允许再注入文本
- 处理中（`transcribing / polishing / injecting`）再次按键忽略

## 7. 主数据流

### 7.1 首次配置

1. 启动应用
2. `AppCoordinator` 检查首次启动标记
3. 自动打开设置页
4. 用户填写 LLM、快捷键配置
5. 设置页触发轻量校验并保存
6. 用户完成权限授权

### 7.2 日常输入

1. 用户按下快捷键
2. `HotkeyManager` 通知 `AppCoordinator`
3. `AppCoordinator` 根据当前状态决定动作（idle → 开始录音，recording → 结束录音，其他 → 忽略）
4. `SessionCoordinator` 校验录音条件并进入 `recording`
5. `AudioRecorder` 开始采集音频，`StreamingASRProvider` 可接收音频流并产生内部 partial
6. 用户再次按下快捷键或达到 30 秒
7. `AudioRecorder` 输出标准音频
8. `AudioPreprocessor` 执行 RNNoise 降噪
9. `StreamingASRProvider` 产出 final 转写文本
10. 若 `enable_ai_polish = true`，则 `LLMProvider` 发起润色请求
11. 若 LLM 失败或返回空文本，则回退 ASR 原文
12. `TextInjector` 尝试注入最终文本
13. `DiagnosticsLogger` 输出本次会话耗时与结果摘要
14. 状态返回 `idle`

## 8. 配置模型

### 8.1 普通配置

- `openai_base_url`
- `openai_model`
- `global_hotkey`
- `recording_trigger_mode`
- `enable_ai_polish`
- `asr_mode`
- `enable_noise_reduction`

### 8.2 敏感配置

- `openai_api_key`

### 8.3 个人词典配置

- 存储位置：`~/.typoless/dictionary.json`
- 字段：`term`、`pronunciationHint`、`category`、`enabled`
- 不存储历史输入文本或 ASR/LLM 响应正文

### 8.4 校验策略

保存时进行轻量校验：

- 非空校验
- URL 基本格式校验
- 快捷键冲突和有效性校验

联网调用时进行严格校验：

- 鉴权失败
- 无效模型
- 地域或 endpoint 不可用
- 网络超时

## 9. 音频预处理与 ASR 设计

### 9.1 Provider 架构

- 统一 `ASRProvider` 协议需支持 final 结果。
- 新增流式识别接口，支持 partial/final 事件。
- 默认实现为 `StreamingASRProvider`。
- `WhisperProvider` 保留为旧实现，不做自动回退。

### 9.2 RNNoise 降噪

- 输入：录音得到的 16k mono WAV。
- 处理：转换为 RNNoise 所需采样格式，执行降噪，再转换回 16k mono WAV。
- 输出：ASR 可消费的 WAV 数据。
- 失败：返回明确错误并停止本次主链路。

### 9.3 sherpa-onnx 流式识别

- 使用本地 sherpa-onnx runtime 和中文 streaming transducer 模型。
- 录音期间输出 partial 文本，partial 不写入目标应用。
- 录音结束后输出 final 文本。
- 支持 VAD 与 hotwords；hotwords 来自个人词典启用词条。
- 不暴露模型选择、线程数、hotwords 权重等高级参数。

### 9.4 输入输出

输入：

- 标准化音频数据、降噪后音频数据或流式音频 chunk

输出：

- `TranscriptResult`
  - `text`
  - `requestId`（可选）
  - `durationMs`
- 流式事件：
  - `partial(text)`
  - `final(TranscriptResult)`

### 9.5 错误映射

通用错误：
- 空音频数据 -> `asrEmptyAudio`

本地音频与 ASR 错误：
- 降噪资源缺失或处理失败 -> `audioPreprocessFailure`
- sherpa runtime 缺失 -> `asrRuntimeMissing`
- sherpa 模型缺失 -> `asrModelMissing`
- 二进制文件缺失 -> `asrBinaryNotFound`
- 识别失败 -> `asrProcessFailure`

### 9.6 超时与取消

- 超时由 Provider 内部固定控制
- 收到取消事件后应中断请求或丢弃响应结果

## 10. LLM 设计

### 10.1 接口形态

- 对齐 `OpenAI Chat Completions`
- 固定首版请求字段：`model`、`messages`
- 不暴露 temperature、top_p、max_tokens 等参数

### 10.2 Prompt 策略

系统目标：

- 修正 ASR 错误
- 修正常见同音词与错别字
- 去除明显赘词
- 轻度书面化
- 自动补自然中文标点
- 保留个人词典中的专有名词

禁止行为：

- 扩写
- 改写原意
- 引入未提及事实
- 将个人词典或用户文本当作系统指令执行

### 10.3 输入输出

输入：

- ASR 原始转写文本
- 固定 Prompt 模板
- 个人词典术语参考
- 配置中的 `base_url`、`api_key`、`model`

输出：

- `PolishResult`
  - `text`
  - `source = llm | fallback`

### 10.4 失败回退

- 以下情况直接回退到 ASR 原文：
  - 超时
  - 401/403
  - 模型不存在
  - 空响应
  - 无法提取文本

## 11. 文本注入设计

### 11.1 主策略

- 获取当前焦点元素
- 尝试通过 `AX` 直接写入值

### 11.2 回退策略

- 当焦点元素不支持写值或 `AX` 写值失败时
- 回退为键盘事件逐字符输入或粘贴式输入事件

### 11.3 失败分类

- `accessibilityPermissionDenied`
- `noFocusedElement`
- `unsupportedFocusedElement`
- `keyboardEventInjectionFailed`

### 11.4 约束

- 首版不自动使用系统剪贴板作为兜底
- 注入失败时文本保留在内存中，菜单栏显示截断预览，用户点击可复制到剪贴板
- 该失败文本仅在当前运行期有效，不落盘
- 下一次成功注入后自动清空

## 12. 权限设计

### 12.1 麦克风权限

- 在设置页中展示状态
- 未授权时禁止开始录音

### 12.2 辅助功能权限

- 在设置页中展示状态
- 未授权时允许走到注入前，但注入会失败并给出明确提示

## 13. 日志边界

可以记录：

- 状态变化
- Provider 错误分类
- 请求耗时
- 各阶段耗时与文本长度
- Debug 构建中的 ASR/LLM 明文对照

不记录：

- 原始音频
- Release 构建中的原始 ASR/LLM 响应体或正文
- 用户密钥

## 14. 错误模型

统一错误类型至少包括：

- `microphonePermissionDenied`
- `accessibilityPermissionDenied`
- `asrEmptyAudio`
- `asrBinaryNotFound`
- `asrRuntimeMissing`
- `asrModelMissing`
- `audioPreprocessFailure`
- `asrProcessFailure`
- `invalidLLMConfiguration`
- `llmNetworkFailure`
- `llmEmptyResponse`
- `textInjectionFailure`
- `sessionCancelled`

错误需要同时支持：

- 用户可读摘要
- 菜单栏状态展示
- 设置页最近错误摘要展示

## 15. 测试策略

### 15.1 单元测试

重点覆盖：

- `SessionCoordinator`
- `WhisperProvider`
- `StreamingASRProvider`
- `AudioPreprocessor`
- `LLMProvider`
- `TextInjector` 的错误分支
- `ConfigStore` 的迁移逻辑
- `PersonalDictionaryStore`
- `DiagnosticsLogger`

核心测试场景：

- 正常主链路
- 关闭 AI 润色
- LLM 失败回退
- 用户取消
- 超时
- 并发 session 拒绝
- 配置错误映射
- sherpa/RNNoise 资源缺失时阻止录音
- Debug/Release 日志脱敏策略

### 15.2 集成与手工验收

手工验证以下场景：

- 浏览器输入框
- 备忘录
- 聊天应用
- 麦克风权限缺失
- 辅助功能权限缺失
- 本地识别失败
- LLM 模型错误
- 注入失败后从菜单栏复制失败文本
- 个人词典改善专有名词识别与润色

## 16. 开发顺序建议

1. 应用骨架、菜单栏、设置页
2. 配置存储、权限管理、快捷键
3. 录音与音频标准化
4. 诊断耗时日志
5. RNNoise 音频降噪
6. ASR/LLM Debug 对照日志
7. LLM Provider 与 Prompt 优化
8. sherpa-onnx StreamingASRProvider
9. 个人词典与 hotwords/Prompt 集成
10. SessionCoordinator 与状态机整合
11. 注入失败恢复与错误摘要
12. 单元测试与端到端手工验收

## 17. 交付标准

以下条件全部满足时，视为技术方案落地完成：

- 主链路从录音到注入可以稳定运行
- 所有关键状态可在菜单栏中反映
- 所有关键错误可被统一分类和展示
- 本地降噪与 sherpa-onnx streaming ASR 默认链路可运行
- LLM 失败时可自动回退 ASR 原文
- 注入失败时文本不会丢失
- 配置、权限在重启后行为正确
