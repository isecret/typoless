# Typoless

Typoless 是一个面向 macOS 的语音 + AI 输入助手项目。

首版产品形态不是系统级输入法，而是 `菜单栏常驻应用`。用户通过全局快捷键按住录音，松开后自动完成：

`录音 -> 腾讯云 ASR -> OpenAI 兼容 LLM 润色 -> 写回当前焦点应用`

项目当前处于产品定义已冻结、待进入实现阶段的状态。

## 项目目标

- 在 macOS 上提供全局可用的中文语音输入能力
- 用腾讯云 ASR 完成短语音识别
- 支持用户接入自有 `OpenAI 兼容` 大模型服务
- 将口语输入整理为更适合直接发送或写入的文本
- 在常见桌面应用中稳定注入文本

## 首版范围

### 包含

- 菜单栏常驻应用
- 设置页
- 全局快捷键
- 按住说话，松开处理
- 腾讯云一句话/短音频识别
- OpenAI 兼容 LLM 润色
- 文本注入
- 麦克风与辅助功能权限引导
- 最近 10 条文本记录
- LLM 失败时自动回退 ASR 原文

### 不包含

- macOS 系统级输入法
- 实时流式识别
- 多 ASR Provider
- 多种 LLM 协议
- 自定义 Prompt
- 风格模式切换
- temperature / max tokens 等高级参数
- 音频历史保存
- Agent 工作流

## 产品行为

- 应用形态：菜单栏常驻应用
- 交互方式：单一全局快捷键，`按住说话，松开处理`
- 单次录音上限：`30 秒`
- 默认输出：`LLM 润色版`
- LLM 失败回退：自动输出 `ASR 原文`
- 注入失败策略：不自动写剪贴板，结果保留在最近记录中供用户复制
- 最近记录：仅保存 `最终文本 + 时间 + 状态`

## 技术方向

- 客户端：`Swift + SwiftUI + AppKit`
- 架构：`MVVM + Service Layer`
- 语音识别：`腾讯云 ASR`，首版采用自实现 `HTTP Provider + 签名`
- 大模型接入：`OpenAI Chat Completions` 兼容接口
- 音频格式：`PCM/WAV 16k mono`
- 文本注入：优先 `Accessibility API`，失败后回退输入事件
- 普通设置存储：`UserDefaults`
- 密钥存储：`Keychain`

## 核心流程

### 首次配置

1. 启动应用
2. 自动打开设置页
3. 配置腾讯云 `SecretId / SecretKey / Region`
4. 配置 LLM `Base URL / API Key / Model`
5. 设置全局快捷键
6. 授予麦克风权限
7. 授予辅助功能权限

### 日常使用

1. 在任意应用中聚焦输入区域
2. 按住快捷键开始录音
3. 松开快捷键结束录音
4. 提交音频到腾讯云 ASR
5. 获取原始转写文本
6. 调用 LLM 做纠错与轻度书面化
7. 将最终文本注入当前焦点应用

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

## 状态机

主状态流转：

`idle -> recording -> transcribing -> polishing -> injecting -> done`

异常状态：

- `error`
- `cancelled`

约束：

- 同一时间只允许一个 session
- 菜单栏允许取消处理中任务
- 取消后不得继续注入文本

## 测试策略

- 单元测试重点覆盖 `Provider` 和 `Session Coordinator`
- 端到端以手工验收主链路为主
- 重点验证权限缺失、配置错误、LLM 回退、注入失败

## 配置项

首版公开配置字段：

- `tencent_secret_id`
- `tencent_secret_key`
- `tencent_region`
- `openai_base_url`
- `openai_api_key`
- `openai_model`
- `global_hotkey`
- `enable_ai_polish`
- `source_language`

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

## 开发优先级建议

1. 搭建菜单栏应用骨架与设置页
2. 打通全局快捷键和录音链路
3. 接入腾讯云 ASR
4. 接入 OpenAI 兼容 LLM
5. 实现文本注入
6. 完成权限、错误处理和最近记录

## 当前状态

- `PRD`: 已冻结
- `TDD`: 已冻结
- `README`: 已建立
- `代码实现`: E1 应用骨架与菜单栏已完成

## 参考

- 产品需求文档：[PRD.md](./docs/PRD.md)
- Epic 和 Story 拆分：[EPICS_AND_STORIES.md](./docs/EPICS_AND_STORIES.md)
- 技术设计文档：[TDD.md](./docs/TDD.md)
