# Typoless TDD

## 1. 文档信息

- 项目名称：Typoless
- 文档类型：TDD
- 版本：v1.4
- 状态：已更新
- 更新时间：2026-05-21

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
- ASR 本地：`FunASR` 本地离线识别（通过 Python sidecar 运行 paraformer-zh + fsmn-vad）
- ASR 云端：`腾讯云一句话识别`、`阿里云录音文件识别极速版`、`火山引擎文件识别`、`科大讯飞语音听写`
- LLM：`OpenAI Chat Completions` 兼容接口
- 更新检查：`Sparkle 2` + GitHub Releases release assets + `updates/appcast.xml`

### 3.3 音频与注入

- 录音标准格式：`PCM/WAV 16k mono`
- 降噪处理：录音结束后进入 ASR 前执行，输出仍为 ASR 可消费的 16k mono WAV
- 文本注入主策略：`AX focused element set value`
- 文本注入回退策略：键盘事件输入

### 3.4 本地存储

- 全部配置（含密钥）：`~/.typoless/config.json`（UTF-8 JSON，目录权限 `0700`，文件权限 `0600`）

## 4. 系统架构

### 4.1 分层

- `UI`
  负责菜单栏、设置页、状态展示
- `Domain`
  负责状态机、会话编排、错误模型、配置模型
- `Providers`
  负责本地 FunASR 离线语音识别和 OpenAI 兼容 LLM 的调用
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
- `AudioSegmenter`
  负责基于 16k PCM 的静音检测和自动切段，输出 sealed segment
- `AudioPreprocessor`
  负责 RNNoise 本地降噪处理
- `ASRProvider` (协议)
  统一的 ASR 识别接口
- `FunASRProvider`
  负责 FunASR 离线识别，通过 stdio JSON-RPC 与 Python sidecar 通信，输出转写结果
- `ASRRuntimeManager`
  负责 Python sidecar 生命周期管理、warmup、健康检查与异常恢复
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
- `AppUpdateService`
  负责封装 Sparkle 更新器、迁移旧自动检查偏好，并驱动关于窗口更新入口
- `PersonalDictionaryStore`
  负责个人词典读写、启用词条过滤和 hotwords 文件生成
- `DiagnosticsLogger`
  负责主链路耗时、错误分类和 Debug ASR/LLM 对照日志

## 5. 模块职责

### 5.1 AppCoordinator

- 启动应用并初始化菜单栏
- 决定首次启动是否自动打开设置页
- 订阅 `SessionCoordinator` 状态用于刷新菜单栏 UI
- 在应用启动后启动 Sparkle 更新器，并按用户偏好执行自动检查

### 5.2 SessionCoordinator

- 保证同一时间只存在一个 active session
- 响应开始录音、结束录音、取消任务
- 串行调度 `AudioRecorder -> AudioSegmenter -> AudioPreprocessor -> ASRProvider -> LLMProvider -> TextInjector`
- 管理分段 ASR 队列：录音期间对已完成分段串行执行 ASR，用户结束录音后识别最后一段
- 所有分段 ASR 完成后按时间顺序拼接文本
- 拼接后文本超过 8000 字符时返回 `transcriptTooLong` 错误，不进入 LLM
- 任一分段 ASR 失败时整次流程失败，不注入部分文本
- 普通模式：拼接 ASR 文本 → LLM 润色 → 注入
- 翻译模式：拼接 ASR 文本 → LLM 润色 → LLM 翻译 → 注入
- 默认使用 `FunASRProvider`
- 负责回退逻辑
- 在内存中维护最近一次注入失败文本，成功注入后清空
- 取消 session 时，需要取消录音和未完成 ASR 任务
- 负责输出会话耗时诊断日志，包含分段级诊断

### 5.3 AudioRecorder

- 处理开始录音、停止录音
- 支持按 `AudioDeviceManager` 解析出的输入设备采集；未指定或已选设备不可用时使用系统默认输入
- 不设置固定录音时长上限
- 录音期间向 `AudioSegmenter` 提供 PCM chunk，或提供等价的分段回调机制
- 记录录音开始/结束时间，低于 500ms 的录音视为误触并静默取消
- 输出标准化 `PCM/WAV 16k mono` 音频数据
- 不负责上传和业务状态流转

### 5.3.1 AudioDeviceManager

- 枚举当前可用麦克风设备
- 管理 `audio.selectedDeviceID` / `audio.selectedDeviceName` 配置保存
- 菜单栏通过子菜单直接选择麦克风，当前选择用勾选展示
- 设备切换仅影响下一次录音，不中断当前 active session
- 已选设备不可用时直接切换到系统默认输入

### 5.3.2 AudioSegmenter

- 基于 16k PCM 输入，实时分析音频 chunk 并在满足条件时输出 sealed segment。
- 静音检测使用动态噪声底 + dB 阈值，并保留轻量语音保护（尖峰容忍），避免环境噪声触发无意义切段。
- 静音检测算法：
  - 每帧（20ms / 320 samples）计算 RMS 能量。
  - 维护噪声底 RMS（EMA 指数移动平均），初始值 200，仅低于动态阈值的帧参与更新（α=0.03），最小值 10。
  - 动态语音阈值 = 噪声底 × 10^(12dB/20) ≈ 噪声底 × 4。帧 RMS 低于此值判定为静音。
  - 尖峰容忍：静音期间连续 ≤3 帧（60ms）超阈值不中断静音累积；超过 3 帧连续超阈值时确认为语音并重置静音计数。
  - 仅持续语音（>3 帧连续超阈值）才标记 `voicedDetectedInSegment`，短暂尖峰不影响语音标记。
- 切段策略：
  - 静音持续 1.6 秒且当前段总时长至少 15 秒时触发自动切段。
  - 自动切段保留 300ms 段尾静音，避免句尾被切掉。
  - 单段达到 55 秒时强制切段，避免超过短音频 ASR 服务边界。
  - 用户手动结束时的最后一段不要求达到 15 秒，只要超过短录音阈值即可。
- 输出为 sealed segment（PCM 数据 + 元数据），包含：
  - `segmentIndex`
  - `pcmData`
  - `durationMs`
  - `voiceDetected`
  - `cutReason`：`silence` / `forcedMaxDuration` / `finalTail`
- 分段音频仅作为临时数据使用，不保存历史音频。
- 静音检测参数在未来可基于实测数据调整，但首版不向用户暴露配置。

### 5.4 AudioPreprocessor

- 使用 RNNoise 对每个 sealed segment 进行本地降噪。
- 输入为 segment 的 PCM 数据，输出为 16k mono WAV 数据。
- 降噪资源缺失或处理失败时返回明确错误，不静默劣化为原音频。
- 不保存降噪前后的音频历史。

### 5.5 ASR Provider 层

统一 ASR 协议需支持非流式 final 结果。

#### 5.5.1 FunASRProvider

- 基于 `FunASR` 本地离线 ASR，使用固定模型组合 `paraformer-zh + fsmn-vad`。
- 通过 `ASRRuntimeManager` 管理 Python sidecar 进程。
- 使用 stdio JSON-RPC 协议与 sidecar 通信：请求发送 WAV 文件路径，响应返回转写文本。
- 录音结束后将降噪后的 WAV 提交给 sidecar，获取转写结果进入 LLM 润色和注入。
- 支持传入个人词典 hotword 参数。
- 设备优先使用 MPS（Metal Performance Shaders）推理，不可用时回退 CPU。
- ASR 超时按分段时长动态计算：`min(90s, max(15s, segmentDurationSeconds * 1.3 + 10s))`。
- 资源缺失时返回明确配置错误，阻止录音。
- 正式分发时，内嵌 Python runtime、`.dylib`、`.so` 必须在 App 签名前完成显式签名；App 使用 Hardened Runtime，并固定启用 `com.apple.security.cs.allow-unsigned-executable-memory` 与 `com.apple.security.cs.disable-library-validation` entitlement。

#### 5.5.2 ASRRuntimeManager

- 管理 Python sidecar 进程的启动、停止、重启。
- 录音开始时触发后台预热（不阻塞录音），单飞机制避免重复预热。
- 预热与降噪并行执行，降噪完成后等待预热结果即可识别。
- 所有 RPC 请求通过串行队列发送，防止并发读写 stdio 导致响应串线。
- 提供 `ping` 健康检查接口，在录音前验证 sidecar 可用性。
- sidecar 异常退出后自动标记不可用，下次录音前尝试重启。
- sidecar 卡死（ping 超时）时执行 force kill 后重启。
- 自适应空闲保活策略：warmup-only 后保活 90 秒，识别成功后保活 180 秒。
- 诊断日志区分 cold start / reused / warmup duration / idle policy。

#### 5.5.3 Sidecar stdio JSON-RPC 协议

请求格式：

```json
{"jsonrpc": "2.0", "method": "recognize", "params": {"wav_path": "/path/to/audio.wav", "hotwords": "张三 李四"}, "id": 1}
```

响应格式：

```json
{"jsonrpc": "2.0", "result": {"text": "转写结果文本", "duration_ms": 1234}, "id": 1}
```

健康检查：

```json
{"jsonrpc": "2.0", "method": "ping", "id": 0}
```

```json
{"jsonrpc": "2.0", "result": {"status": "ok"}, "id": 0}
```

错误响应：

```json
{"jsonrpc": "2.0", "error": {"code": -1, "message": "model load failed"}, "id": 1}
```

#### 5.5.4 TencentSentenceASRProvider

- 腾讯云一句话识别（SentenceRecognition API）。
- 引擎 `16k_zh-PY`，用于中文优先的混合语音识别。
- 使用 TC3-HMAC-SHA256 签名算法，通过 CommonCrypto 实现。
- 音频 base64 编码后通过 POST 请求发送。
- 超时按分段时长动态计算。
- 直接调用 `tencentcloudapi.com` API，无 SDK 依赖。
- 配置项：`SecretId`、`SecretKey`，存储在 `~/.typoless/config.json` 的 `asr.tencentCloud` 段。
- 配置不完整时返回 `cloudASRConfigurationIncomplete` 错误。

#### 5.5.5 AliyunSentenceASRProvider / VolcengineSentenceASRProvider / XunfeiSentenceASRProvider

- `AliyunSentenceASRProvider`
  先调用阿里云 `CreateToken` 获取临时 Token，再调用录音文件识别极速版接口提交 `wav` 音频。
- `VolcengineSentenceASRProvider`
  直接调用火山引擎文件识别接口，上传 base64 编码后的 `wav` 音频。
- `XunfeiSentenceASRProvider`
  使用科大讯飞语音听写 WebSocket 协议，录音结束后将 `wav` 中的 PCM 数据按帧发送，最终对外仍返回单次 final text。
- 三家云 Provider 均按分段时长动态计算超时：`min(90s, max(15s, segmentDurationSeconds * 1.3 + 10s))`，支持取消，并统一映射到云 ASR 错误模型。

#### 5.5.6 ModelDownloadManager

- 管理本地 FunASR 模型的下载、验证和删除。
- 模型存储路径：`~/.typoless/models/funasr/`。
- 需下载模型：`paraformer-zh`（ASR）、`fsmn-vad`（VAD）。
- 下载源：优先使用 ModelScope API 获取文件列表并逐个下载；备选 git clone。
- 支持用户配置镜像源（`mirrorSource`）。
- 下载进度通过 `AsyncStream` 发布。
- 断点续传通过 HTTP Range + If-Range 支持。
- 模型验证：检查关键文件（model.onnx / model.bin）是否存在。
- 删除操作：清理整个模型目录。
- 状态跟踪：`LocalModelStatus`（notDownloaded / downloading / ready / failed）。

### 5.6 LLMProvider

- 使用固定 Prompt 生成 Chat Completions 请求
- 默认优先发送 `thinking: { "type": "disabled" }` 关闭长思考
- 若当前 LLM 配置已记录 `thinkingDisabled = true`，则直接发送普通请求
- 若上游明确返回 `thinking` 字段不支持，则回退一次普通请求，并将该结果写入 `~/.typoless/config.json`
- 返回保守型结构化处理后的最终文本
- 优先解析结构化 JSON 结果，并保留兼容的纯文本提取回退路径
- 不处理 UI 和回退逻辑
- Prompt 可接收个人词典术语参考，但不开放用户自定义 Prompt

### 5.6.1 LLMModelProvider

- 用于设置页辅助获取模型列表，不参与主链路润色请求。
- 基于当前 `Base URL` 调用 OpenAI 兼容 `/models` endpoint，使用当前 `API Key` 认证。
- 成功时解析 `data[].id` 作为候选模型，并在 UI 中供用户选择。
- 当服务不支持 `/models`、响应异常、网络失败或返回空列表时，不影响手动输入 Model，也不改变 LLM 运行时配置完整性判断。
- 最终持久化配置仍只有 `Base URL`、`API Key`、`Model` 与内部兼容性字段 `thinkingDisabled`。

### 5.7 TextInjector

- 默认通过剪贴板写入 + 粘贴快捷键将文本注入当前焦点应用
- 若粘贴路径明确失败或可判断为未生效，再回退到焦点元素 `AX` 写值
- 不再把键盘事件逐字符输入作为常规第二优先级
- 返回统一注入结果和错误

### 5.8 ConfigStore

- 统一使用 `~/.typoless/config.json` 读写全部配置（含密钥）
- 启动时直接从配置文件加载到内存
- 若配置文件不存在，自动从旧存储（UserDefaults + Keychain）迁移
- 若配置文件损坏，标记为加载失败，使首次配置检查返回 false
- 保存时执行轻量校验，整文件原子写回
- LLM 配置包含内部兼容性字段 `thinkingDisabled`
- 当 `Base URL`、`API Key`、`Model` 任一保存值发生变化时，自动重置 `thinkingDisabled = false`
- 允许保存全空或半填的 LLM 配置；运行时仅在三项都完整时视为可用
- 通用配置不再持久化更新开关；旧字段仅用于一次性迁移到 Sparkle 偏好
- `hasCompletedInitialSetup` 在配置文件正常加载后返回 true；ASR 资源完整性在录音前检查

### 5.9 AppUpdateService

- 使用 `SPUStandardUpdaterController` 托管 Sparkle 2 标准更新流程
- 更新元数据来自 `https://raw.githubusercontent.com/isecret/typoless/main/updates/appcast.xml`
- 更新包来自 GitHub Release 中的已签名 `.zip` 资产，应用内直接下载并安装
- 自动检查开关仅放在关于窗口，不在菜单栏增加入口
- 旧版 `automaticUpdateChecksEnabled` 仅迁移一次到 Sparkle 的 `automaticallyChecksForUpdates`
- 发布工作流基于 `vX.Y.Z` tag 同步 `CFBundleShortVersionString` 与 `CFBundleVersion`
- 本地构建优先使用当前分支最近可达的 `vX.Y.Z` tag；`app/project.yml` 中的版本号仅作为无 tag 环境的 fallback

### 5.10 PersonalDictionaryStore

- 使用 `~/.typoless/dictionary.json` 存储用户维护的个人词典。
- 词条至少包含 `term`，可选 `pronunciationHint`、`category`、`enabled`。
- 生成 FunASR hotwords 参数，并为 LLM Prompt 提供术语参考。

### 5.11 DiagnosticsLogger

- 使用 `os.Logger(subsystem: "com.isecret.typoless", category: "Session")` 输出应用日志。
- 记录 `session_id`、各阶段耗时、文本长度、结果来源、错误分类和目标 app bundle id。
- 记录结构化处理诊断字段：`mode`、`correction_applied`、`parse_success`、`fallback`。
- Debug 构建可输出 ASR 原文与 LLM 输出；Release 构建仅输出脱敏摘要。

Session 级分段诊断字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `segment_count` | Int | 本次 session 实际产生的分段数 |
| `queued_segment_count` | Int | 进入 ASR 队列的分段数 |
| `max_pending_segments` | Int | 队列中等待 ASR 的最大分段数 |
| `total_recording_ms` | Int | 录音总时长（毫秒） |
| `joined_transcript_chars` | Int | 拼接后转写文本总字符数 |

Segment 级诊断字段（每段独立记录）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `segment_index` | Int | 分段序号，从 0 开始 |
| `segment_duration_ms` | Int | 该分段音频时长（毫秒） |
| `voiced_detected` | Bool | 该分段是否检测到语音活动 |
| `forced_cut` | Bool | 是否因达到 55s 上限强制切段 |
| `silence_cut` | Bool | 是否因静音检测切段 |
| `asr_timeout_ms` | Int | 该分段 ASR 超时阈值（毫秒） |
| `asr_elapsed_ms` | Int | 该分段 ASR 实际耗时（毫秒） |
| `asr_result_chars` | Int | 该分段 ASR 结果字符数 |
| `failure_reason` | String? | 失败原因，成功时为 nil |

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

异常路径：

- 任意状态可进入 `error`
- `transcribing` 和 `polishing` 可进入 `cancelled`
- `cancelled` 完成清理后返回 `idle`

### 6.3 状态约束

- 正在处理时禁止开启第二个 session
- App 不设置固定录音时长上限；录音期间后台分段 ASR 不影响 recording 状态
- 低于 500ms 的短录音静默取消，不进入降噪、ASR、LLM 或文本注入
- 用户取消后必须中断后续步骤，不允许再注入文本
- 取消 session 时，需要取消录音和未完成 ASR 任务
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
5. `AudioRecorder` 开始采集音频，PCM chunk 输入 `AudioSegmenter`
6. `AudioSegmenter` 根据静音检测和 55s 强制上限输出 sealed segment
7. 已完成分段立即进入 `AudioPreprocessor` 降噪，然后串行提交 ASR
8. 用户再次按下快捷键结束录音
9. `AudioSegmenter` 输出最后一段
10. 若录音时长低于 500ms，则静默取消并通过 `DiagnosticsLogger` 记录 `short_recording_cancelled`
11. 最后一段完成降噪和 ASR 后，所有分段转写文本按时间顺序拼接
12. 若拼接文本超过 8000 字符，返回 `transcriptTooLong` 错误
13. 若 LLM 配置不完整，则主链路直接报错并结束
14. `LLMProvider` 发起润色请求（Prompt 说明输入来自连续分段转写）
15. 若 LLM 失败或返回空文本，则主链路直接报错并结束
16. `TextInjector` 尝试注入最终文本
17. `DiagnosticsLogger` 输出本次会话耗时与分段诊断摘要
18. 状态返回 `idle`

## 8. 配置模型

### 8.1 普通配置

- `openai_base_url`
- `openai_model`
- `global_hotkey`

### 8.2 敏感配置

- `openai_api_key`
- `asr.tencentCloud.secretId`
- `asr.tencentCloud.secretKey`
- `asr.aliyun.accessKeyId`
- `asr.aliyun.accessKeySecret`
- `asr.aliyun.appKey`
- `asr.volcengine.apiKey`
- `asr.xunfei.appID`
- `asr.xunfei.apiKey`
- `asr.xunfei.apiSecret`

### 8.3 ASR 配置

- `asr.selectedPlatform`：当前选中的 ASR 平台（`localFunASR` / `tencentCloudSentence` / `aliyunSentence` / `volcengineSentence` / `xunfeiSentence`）
- `asr.local.modelStatus`：本地模型状态（notDownloaded / downloading / ready / failed）
- `asr.local.lastError`：最近一次下载失败的错误信息
- `asr.local.mirrorSource`：自定义镜像源 URL
- `asr.tencentCloud.secretId`：腾讯云 SecretId
- `asr.tencentCloud.secretKey`：腾讯云 SecretKey
- `asr.aliyun.accessKeyId`：阿里云 AccessKey ID
- `asr.aliyun.accessKeySecret`：阿里云 AccessKey Secret
- `asr.aliyun.appKey`：阿里云 AppKey
- `asr.volcengine.apiKey`：火山引擎 API Key
- `asr.xunfei.appID`：科大讯飞 AppID
- `asr.xunfei.apiKey`：科大讯飞 API Key
- `asr.xunfei.apiSecret`：科大讯飞 API Secret

### 8.4 个人词典配置

- 存储位置：`~/.typoless/dictionary.json`
- 字段：`term`、`pronunciationHint`、`category`、`enabled`
- 不存储历史输入文本或 ASR/LLM 响应正文

### 8.4 校验策略

保存时进行轻量校验：

- Base URL 非空时做 URL 基本格式校验
- 快捷键冲突和有效性校验

联网调用时进行严格校验：

- 鉴权失败
- 无效模型
- 地域或 endpoint 不可用
- 网络超时

## 9. 音频预处理与 ASR 设计

### 9.1 Provider 架构

- 统一 `ASRProvider` 协议需支持 final 结果。
- 用户在设置中手动选择 ASR 平台：`本地 FunASR`、`腾讯云`、`阿里云`、`火山引擎`、`科大讯飞`。
- 默认实现为 `FunASRProvider`，通过 `ASRRuntimeManager` 管理 Python sidecar。
- 云端 Provider 固定为 `TencentSentenceASRProvider`、`AliyunSentenceASRProvider`、`VolcengineSentenceASRProvider`、`XunfeiSentenceASRProvider`。
- 不做平台间自动回退；所选平台不可用时直接报错阻止录音。

### 9.2 RNNoise 降噪

- 输入：录音得到的 16k mono WAV。
- 处理：转换为 RNNoise 所需采样格式，执行降噪，再转换回 16k mono WAV。
- 输出：ASR 可消费的 WAV 数据。
- 失败：返回明确错误并停止本次主链路。

### 9.3 FunASR 离线识别

- 使用 Python sidecar 运行 FunASR，固定模型组合：`paraformer-zh`（语音识别）+ `fsmn-vad`（语音活动检测）。
- 模型存储于用户目录 `~/.typoless/models/funasr/`，设置页引导下载。
- 通过 stdio JSON-RPC 协议通信，每次请求传入 WAV 文件路径，返回转写文本。
- 设备优先使用 MPS 推理加速，不可用时回退 CPU。
- 支持 hotword 参数，来自个人词典启用词条。
- 不暴露模型选择、线程数、hotwords 权重等高级参数。

### 9.4 模型下载管理

- `ModelDownloadManager` 管理本地模型的下载、验证和删除。
- 下载源：优先 ModelScope API，备选 git clone。支持镜像源。
- 下载进度通过 `AsyncStream` 发布至设置页。
- 模型验证：检查关键文件（model.onnx / model.bin）是否存在。
- 状态跟踪：`LocalModelStatus`（notDownloaded / downloading / ready / failed）。

### 9.5 云端 ASR Providers

- `TencentSentenceASRProvider` 直接调用腾讯云 `SentenceRecognition` API。
- 引擎 `16k_zh-PY`。
- TC3-HMAC-SHA256 签名。
- 配置：SecretId、SecretKey，存于 `~/.typoless/config.json` 的 `asr.tencentCloud`。
- `AliyunSentenceASRProvider` 通过 `CreateToken + 录音文件识别极速版` 接口提交 `wav` 音频。
- 配置：AccessKey ID、AccessKey Secret、AppKey，存于 `asr.aliyun`。
- `VolcengineSentenceASRProvider` 直接调用火山引擎文件识别接口。
- 配置：API Key，存于 `asr.volcengine`。
- `XunfeiSentenceASRProvider` 使用语音听写 WebSocket 接口，并从 `wav` 中提取 PCM 数据按帧发送。
- 配置：AppID、API Key、API Secret，存于 `asr.xunfei`。
- 所有云 Provider 超时按分段时长动态计算：`min(90s, max(15s, segmentDurationSeconds * 1.3 + 10s))`。

### 9.6 分段 ASR 编排

- 所有 ASR 平台统一走分段编排，包括本地 FunASR 和云端 ASR。
- `AudioSegmenter` 在录音期间实时分析 PCM chunk，满足切段条件时输出 sealed segment。
- 每个 sealed segment 先经 `AudioPreprocessor` 降噪，再提交给当前 ASR Provider。
- 分段 ASR 串行执行，降低 sidecar 并发、WebSocket 并发和云服务限流风险。
- 录音期间已完成的分段提前进行 ASR，用户结束录音后识别最后一段。
- 所有分段 ASR 完成后，按 `segmentIndex` 顺序拼接转写文本。
- 拼接后文本超过 8000 字符时，返回 `transcriptTooLong` 错误，不进入 LLM。
- 任一有效分段 ASR 失败时，整次流程失败，不注入部分文本。
- 分段音频仅作为临时数据使用，不保存历史音频。

### 9.7 Sidecar 生命周期

- 首次录音时触发后台预热，不阻塞录音。
- 活跃请求之间复用同一 sidecar 进程。
- 自适应空闲保活：warmup-only 后 90 秒，识别成功后 180 秒。
- sidecar 异常退出后标记不可用，下次录音前自动重启。
- 提供 ping 健康检查，录音前验证 sidecar 可用。
- sidecar ping 超时时执行 force kill 后重启。

### 9.8 输入输出

输入：

- 降噪后 16k mono WAV 文件路径（本地）或 WAV 二进制数据（云端）

输出：

- `TranscriptResult`
  - `text`
  - `requestId`（可选）
  - `durationMs`

### 9.9 错误映射

通用错误：
- 空音频数据 -> `asrEmptyAudio`
- ASR 平台未就绪 -> `asrPlatformNotReady`

本地音频与 ASR 错误：
- 降噪资源缺失或处理失败 -> `audioPreprocessFailure`
- Python runtime 缺失 -> `asrRuntimeMissing`
- FunASR 模型缺失 -> `asrModelMissing`
- sidecar worker 缺失 -> `asrBinaryNotFound`
- 识别失败 -> `asrProcessFailure`
- sidecar 健康检查失败 -> `asrRuntimeMissing`

云端 ASR 错误（腾讯云 / 阿里云 / 火山引擎 / 科大讯飞）：
- 配置不完整 -> `cloudASRConfigurationIncomplete`
- 鉴权失败 -> `cloudASRAuthenticationFailure`
- 网络错误 -> `cloudASRNetworkFailure`
- 空响应 -> `cloudASREmptyResponse`
- 响应格式无效 -> `cloudASRInvalidResponse`

分段拼接错误：
- 拼接文本超过 8000 字符 -> `transcriptTooLong`

### 9.10 超时与取消

- ASR 超时按分段时长动态计算：`min(90s, max(15s, segmentDurationSeconds * 1.3 + 10s))`
- 收到取消事件后应中断当前分段 ASR 请求并丢弃后续分段
- 取消 session 时，需同时取消录音和未完成 ASR 任务

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
- 口语赘词清理由 Prompt 明示词表与客户端兜底 sanitizer 双层控制；`然后` 仅在充当口头衔接、停顿或组合赘词时删除，表示顺序/因果/步骤推进时保留
- 轻度书面化
- 自动补自然中文标点
- 保留个人词典中的专有名词
- 中英混合术语恢复：ASR 把英文术语识别成中文音近词时，恢复为正确英文写法
- 在结构信号明确时，将内容保守整理为 `plain_text`、`list`、`message`
- 在“不是 A，是 B”“改成”“最后一句不要了”等显式自我修正场景下，优先保留最终明确表达
- 当输入来自多段分段转写时，Prompt 明确说明：输入来自同一次语音输入的连续分段转写，请按原始顺序理解为一段连续表达；可以合并因分段造成的断句，但不得扩写、改写原意或补充事实

禁止行为：

- 扩写
- 改写原意
- 引入未提及事实
- 将个人词典或用户文本当作系统指令执行
- 纯中文输入不因术语列表存在英文词而被错误替换
- 生成长邮件、摘要、会议纪要或其他超出首版边界的结构化文稿

模式约束：

- `plain_text`
  - 默认模式，继续执行纠错、标点和轻分段
- `list`
  - 仅在存在稳定枚举信号时启用
  - 仅拆分原有内容，不新增要点
- `message`
  - 仅处理短消息/短邮件级别输出
  - 允许称呼、正文和简短结尾的最小重排
  - 不补充未说出的事实、承诺、时间或地点

### 10.3 输入输出

输入：

- ASR 原始转写文本
- 固定 Prompt 模板
- 个人词典术语参考（包含 term 和 pronunciationHint）
- 配置中的 `base_url`、`api_key`、`model`

输出：

- `PolishResult`
  - `text`
  - `structured: StructuredPolishResult?`

- `StructuredPolishResult`
  - `mode: PolishMode`
  - `intro: String?`
  - `items: [String]?`
  - `outro: String?`
  - `salutation: String?`
  - `body: [String]?`
  - `closing: String?`
  - `correctionApplied: Bool`
  - `isValid: Bool`（语义校验：list 要求 items 非空，message 要求 body 非空）

- `PolishMode`
  - `plainText`
  - `list`
  - `message`

解析与渲染约束：

- 优先解析 LLM 返回的结构化 JSON（raw JSON，非 code fence）
- 解析成功后按 mode 在客户端本地渲染最终文本
  - `plain_text`：直接使用 `text` 字段
  - `list`：若有 `intro`，先输出 `intro`；按 `items` 编号换行渲染；若有 `outro`，再输出 `outro`
  - `message`：按 `salutation` + `body` + `closing` 拼接，缺失部分不强补
- 语义校验失败时（如 list 但 items 为空），退回使用 JSON 中的 `text` 字段
- 非法 JSON 时多级回退：尝试宽容提取 `text` 字段 → 使用原始内容（仅当内容不是 JSON 结构时）
- 最终注入文本始终取自安全渲染后的 `PolishResult.text`
- 绝不将 JSON 原文注入用户应用

### 10.4 失败处理

- 以下情况直接报错，不注入任何文本：
  - LLM 配置不完整（Base URL / API Key / Model 任一缺失）
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
- 正常覆盖升级时，只有在 `bundle id` 与签名身份保持一致的前提下，系统权限才应继续沿用
- 若签名身份或 `bundle id` 变化，TCC 可能将其视为新应用并要求重新授权

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
- `transcriptTooLong`

错误需要同时支持：

- 用户可读摘要
- 菜单栏状态展示
- 设置页最近错误摘要展示

## 15. 测试策略

### 15.1 单元测试

重点覆盖：

- `SessionCoordinator`
- `AudioSegmenter`
- `FunASRProvider`
- `ASRRuntimeManager`
- `AudioPreprocessor`
- `LLMProvider`
- `TextInjector` 的错误分支
- `ConfigStore` 的迁移逻辑
- `PersonalDictionaryStore`
- `DiagnosticsLogger`

核心测试场景：

- 正常主链路
- LLM 配置不完整
- LLM 失败直接报错
- `plain_text` 不被误判为 `list` 或 `message`
- `list` 可稳定识别枚举内容且顺序不乱
- `message` 可完成最小格式化且不补事实
- “不是 A，是 B”“改成”“最后一句不要了”等显式自我修正
- 非法 JSON、缺字段和纯文本兼容回退
- 用户取消
- 低于 500ms 的短录音静默取消
- ASR 超时
- sidecar 异常退出与恢复
- 并发 session 拒绝
- 配置错误映射
- FunASR/RNNoise 资源缺失时阻止录音
- Debug/Release 日志脱敏策略

分段 ASR 测试场景：

- `AudioSegmenter` 静音检测切段（1.6s 静音 + ≥15s 已录时切段）
- `AudioSegmenter` 55s 强制切段
- `AudioSegmenter` 300ms 尾部静音保留
- 分段 ASR 串行执行与结果按序拼接
- 拼接文本超过 8000 字符触发 `transcriptTooLong`
- 单段 ASR 失败导致整次流程失败
- 用户取消时同时终止录音和未完成 ASR
- 动态超时公式 `min(90s, max(15s, segmentDurationSeconds * 1.3 + 10s))`
- 录音期间分段与 ASR 并行（录音未结束时已完成分段提前 ASR）
- session 级与 segment 级诊断日志输出

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
- 列表口述和短消息口述可输出保守结构化结果
- 长录音（>55s）自动分段并拼接转写
- 分段 ASR 失败后整次流程报错
- 取消长录音时正确终止所有分段 ASR

## 16. 开发顺序建议

1. 应用骨架、菜单栏、设置页
2. 配置存储、权限管理、快捷键
3. 录音与音频标准化
4. 诊断耗时日志
5. RNNoise 音频降噪
6. AudioSegmenter 分段切割
7. ASR/LLM Debug 对照日志
8. LLM Provider 与 Prompt 优化
9. FunASR Provider 与 sidecar 集成
10. 个人词典与 hotwords/Prompt 集成
11. SessionCoordinator 与状态机整合（含分段 ASR 编排）
12. 注入失败恢复与错误摘要
13. 单元测试与端到端手工验收

## 17. 交付标准

以下条件全部满足时，视为技术方案落地完成：

- 主链路从录音到注入可以稳定运行
- 所有关键状态可在菜单栏中反映
- 所有关键错误可被统一分类和展示
- 本地降噪与 FunASR 离线 ASR 默认链路可运行
- LLM 配置不完整或请求失败时不会注入任何文本
- 注入失败时文本不会丢失
- 配置、权限在重启后行为正确
