# Typoless TDD

## 1. 文档信息

- 项目名称：Typoless
- 文档类型：TDD
- 版本：v1.0
- 状态：已冻结
- 更新时间：2026-04-24

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
- 实时流式 ASR
- 多 Provider 设计

## 3. 技术选型

### 3.1 客户端

- 语言：`Swift`
- UI：`SwiftUI`
- 系统交互：`AppKit`
- 架构：`MVVM + Service Layer`

### 3.2 外部服务

- ASR：`腾讯云 ASR`
- ASR 接入方式：自实现 `HTTP Provider + 签名`
- LLM：`OpenAI Chat Completions` 兼容接口

### 3.3 音频与注入

- 录音标准格式：`PCM/WAV 16k mono`
- 文本注入主策略：`AX focused element set value`
- 文本注入回退策略：键盘事件输入

### 3.4 本地存储

- 全部配置（含密钥）：`~/.typoless/config`（UTF-8 JSON，目录权限 `0700`，文件权限 `0600`）
- 最近记录：本地持久化存储，首版可使用 `UserDefaults` 或轻量文件存储封装在 `HistoryStore` 内部

## 4. 系统架构

### 4.1 分层

- `UI`
  负责菜单栏、设置页、状态展示、最近记录展示
- `Domain`
  负责状态机、会话编排、错误模型、配置模型
- `Providers`
  负责腾讯云 ASR 和 OpenAI 兼容 LLM 的网络访问
- `Platform`
  负责录音、权限、全局快捷键、文本注入
- `Persistence`
  负责配置、密钥和最近记录存储

### 4.2 核心对象

- `AppCoordinator`
  管理应用生命周期、菜单栏与设置页入口
- `SessionCoordinator`
  负责编排录音、识别、润色、注入的主链路
- `AudioRecorder`
  负责录音采集与音频标准化
- `TencentASRProvider`
  负责腾讯云 ASR 调用
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
- `HistoryStore`
  负责最近记录持久化

## 5. 模块职责

### 5.1 AppCoordinator

- 启动应用并初始化菜单栏
- 决定首次启动是否自动打开设置页
- 订阅 `SessionCoordinator` 状态用于刷新菜单栏 UI

### 5.2 SessionCoordinator

- 保证同一时间只存在一个 active session
- 响应开始录音、结束录音、取消任务
- 串行调度 `AudioRecorder -> TencentASRProvider -> LLMProvider -> TextInjector`
- 负责回退逻辑与记录落盘

### 5.3 AudioRecorder

- 处理开始录音、停止录音
- 限制录音上限为 30 秒
- 输出标准化音频数据或临时文件引用
- 不负责上传和业务状态流转

### 5.4 TencentASRProvider

- 接收标准音频输入
- 生成请求签名和 HTTP 请求
- 发起一次性短语音识别请求
- 把原始响应映射为统一 `TranscriptResult`

### 5.5 LLMProvider

- 使用固定 Prompt 生成 Chat Completions 请求
- 返回润色后的最终文本
- 不处理 UI 和回退逻辑

### 5.6 TextInjector

- 优先定位当前焦点元素并尝试 `AX` 写值
- 当 `AX` 写值不可用时回退为键盘事件输入
- 返回统一注入结果和错误

### 5.7 ConfigStore

- 统一使用 `~/.typoless/config` 读写全部配置（含密钥）
- 启动时直接从配置文件加载到内存
- 若配置文件不存在，自动从旧存储（UserDefaults + Keychain）迁移
- 若配置文件损坏，回退为空配置（首次配置状态）
- 保存时执行轻量校验，整文件原子写回

### 5.8 HistoryStore

- 最多保留 10 条记录
- 记录项只保存 `最终文本 + 时间 + 状态`
- 支持查询、复制和清空

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

## 7. 主数据流

### 7.1 首次配置

1. 启动应用
2. `AppCoordinator` 检查首次启动标记
3. 自动打开设置页
4. 用户填写腾讯云、LLM、快捷键配置
5. 设置页触发轻量校验并保存
6. 用户完成权限授权

### 7.2 日常输入

1. 用户按下快捷键
2. `HotkeyManager` 通知 `SessionCoordinator`
3. `SessionCoordinator` 校验录音条件并进入 `recording`
4. `AudioRecorder` 开始采集音频
5. 用户松开快捷键或达到 30 秒
6. `AudioRecorder` 输出标准音频
7. `TencentASRProvider` 发起一次性识别并返回转写文本
8. 若 `enable_ai_polish = true`，则 `LLMProvider` 发起润色请求
9. 若 LLM 失败或返回空文本，则回退 ASR 原文
10. `TextInjector` 尝试注入最终文本
11. `HistoryStore` 写入记录
12. 状态返回 `idle`

## 8. 配置模型

### 8.1 普通配置

- `tencent_region`
- `openai_base_url`
- `openai_model`
- `global_hotkey`
- `enable_ai_polish`
- `source_language`

### 8.2 敏感配置

- `tencent_secret_id`
- `tencent_secret_key`
- `openai_api_key`

### 8.3 校验策略

保存时进行轻量校验：

- 非空校验
- URL 基本格式校验
- 快捷键冲突和有效性校验

联网调用时进行严格校验：

- 鉴权失败
- 无效模型
- 地域或 endpoint 不可用
- 网络超时

## 9. 腾讯云 ASR 设计

### 9.1 接入策略

- 不依赖腾讯云重型 SDK
- 直接实现 HTTP 请求和签名
- Provider 对外只暴露业务无关的统一接口

### 9.2 输入输出

输入：

- 标准化音频数据或标准化音频临时文件
- 用户配置中的密钥与地域

输出：

- `TranscriptResult`
  - `text`
  - `requestId`
  - `durationMs`

### 9.3 错误映射

- 鉴权错误 -> `invalidCredentials`
- 网络错误 -> `networkFailure`
- 服务错误 -> `asrFailure`
- 空文本结果 -> `emptyTranscript`

### 9.4 超时与取消

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
- 去除明显赘词
- 轻度书面化
- 自动补自然中文标点

禁止行为：

- 扩写
- 改写原意
- 引入未提及事实

### 10.3 输入输出

输入：

- ASR 原始转写文本
- 固定 Prompt 模板
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
- 注入失败时必须保留文本到最近记录

## 12. 权限设计

### 12.1 麦克风权限

- 在设置页中展示状态
- 未授权时禁止开始录音

### 12.2 辅助功能权限

- 在设置页中展示状态
- 未授权时允许走到注入前，但注入会失败并给出明确提示

## 13. 记录与日志

### 13.1 最近记录

存储字段：

- `id`
- `text`
- `timestamp`
- `status`

状态值：

- `success`
- `fallback_success`
- `failed`
- `cancelled`

### 13.2 日志边界

可以记录：

- 状态变化
- Provider 错误分类
- 请求耗时

不记录：

- 原始音频
- 原始 ASR/LLM 响应体
- 用户密钥

## 14. 错误模型

统一错误类型至少包括：

- `microphonePermissionDenied`
- `accessibilityPermissionDenied`
- `invalidTencentCredentials`
- `tencentNetworkFailure`
- `tencentASRFailure`
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
- `TencentASRProvider`
- `LLMProvider`
- `TextInjector` 的错误分支

核心测试场景：

- 正常主链路
- 关闭 AI 润色
- LLM 失败回退
- 用户取消
- 超时
- 并发 session 拒绝
- 配置错误映射

### 15.2 集成与手工验收

手工验证以下场景：

- 浏览器输入框
- 备忘录
- 聊天应用
- 麦克风权限缺失
- 辅助功能权限缺失
- 腾讯云密钥错误
- LLM 模型错误
- 注入失败后从最近记录复制

## 16. 开发顺序建议

1. 应用骨架、菜单栏、设置页
2. 配置存储、权限管理、快捷键
3. 录音与音频标准化
4. 腾讯云 ASR Provider
5. LLM Provider 与 Prompt
6. 文本注入
7. SessionCoordinator 与状态机整合
8. 最近记录与错误摘要
9. 单元测试与端到端手工验收

## 17. 交付标准

以下条件全部满足时，视为技术方案落地完成：

- 主链路从录音到注入可以稳定运行
- 所有关键状态可在菜单栏中反映
- 所有关键错误可被统一分类和展示
- LLM 失败时可自动回退 ASR 原文
- 注入失败时文本不会丢失
- 配置、权限、最近记录在重启后行为正确
