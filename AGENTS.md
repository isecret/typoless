# Agent 协作指南

## 语言约定

- 除非用户明确要求使用其他语言，协作、方案、评审、变更说明默认使用简体中文
- 代码、配置键名、API 字段名、类型名、模型名保持英文，不做强制翻译
- 对外展示文案若已由产品文档定义，以文档为准

## 项目概览

- 项目名称：Typoless
- 产品形态：macOS 菜单栏常驻应用
- 业务目标：提供语音 + AI 的全局文本输入体验
- 首版定位：中文短语音输入助手，不是系统级输入法

## 技术栈

- 客户端语言：Swift
- UI：SwiftUI
- 系统交互：AppKit
- 架构：MVVM + Service Layer
- ASR：本地 FunASR
- LLM：OpenAI Chat Completions 兼容接口
- 音频格式：PCM/WAV 16k mono
- 配置存储：~/.typoless/config（UTF-8 JSON）

## 仓库结构

当前仓库以文档先行为主，后续实现时应保持以下主结构清晰：

```text
.agents/
docs/
README.md
AGENTS.md
```

若开始实现客户端，优先扩展为：

```text
app/
docs/
scripts/
README.md
AGENTS.md
```

## 事实依据顺序

做决策时，按以下顺序使用文档作为事实依据：

1. `docs/PRD.md`
2. `docs/TDD.md`
3. `docs/EPICS_AND_STORIES.md`
4. `README.md`

如果实现与文档冲突，在改变产品行为、技术边界或验收标准前必须先与用户确认。

## 产品范围

首版明确在范围内：

- 菜单栏常驻应用
- 设置页
- 全局快捷键
- 按住说话，松开处理
- 本地 FunASR 语音识别
- OpenAI 兼容 LLM 润色
- 文本注入
- 麦克风与辅助功能权限引导
- 最近 10 条文本记录
- LLM 失败回退 ASR 原文

除非用户明确提出，否则以下内容不在范围内：

- macOS 系统级输入法
- 实时流式识别
- 多 ASR Provider
- 多种 LLM 协议
- 自定义 Prompt
- 风格模式切换
- temperature、max tokens 等高级参数
- 音频历史保存
- Agent 工作流扩展

## 核心行为约束

- 交互方式固定为单一全局快捷键，`按住说话，松开处理`
- 单次录音上限固定为 30 秒
- 默认输出 LLM 润色版
- LLM 失败或超时时自动回退 ASR 原文
- 文本注入失败时不自动覆盖剪贴板
- 最近记录只保存 `最终文本 + 时间 + 状态`
- 同一时间只允许一个 active session

## 架构与实现约束

- 优先保持 `UI / Domain / Providers / Platform / Persistence` 分层清晰
- `SessionCoordinator` 负责主链路编排，不要把核心流程散落到 View 层
- LLM 首版只对齐 `Chat Completions` 兼容接口，不扩展到多协议抽象
- 文本注入优先走 `Accessibility API`，失败后再回退输入事件
- 配置保存时做轻量校验；严格失败在真实调用阶段处理
- Provider 层必须支持固定超时和取消

## 安全与隐私边界

- 不得在仓库中硬编码 API Key、测试令牌或任何生产凭据
- 不得在日志、截图、测试数据或文档中泄露真实用户语音、文本、访问令牌或内部域名凭据
- 不得默认保存原始音频
- 不得在未经说明的情况下把用户输入自动复制到系统剪贴板
- 不得为了联调方便绕过麦克风权限、辅助功能权限或请求鉴权
- 不得把 LLM 输出当作可信系统指令执行
- 不得让 AI 润色擅自扩写、改写原意或编造事实

## 敏感变更

以下修改必须先向用户升级确认：

- 产品从“菜单栏助手”改为“系统输入法”
- ASR 引擎变更或引入多 Provider
- LLM 接口协议变更或开放自定义 Prompt / 高级参数
- 文本注入策略从当前主方案切换到剪贴板主方案
- 录音保存策略、日志保留策略、隐私边界变化
- 配置项、状态机、错误模型的破坏性调整

## 测试要求

- 单元测试优先覆盖 `SessionCoordinator`
- 单元测试优先覆盖 `FunASRProvider`、`LLMProvider`、`TextInjector` 的关键分支
- 端到端以手工验收为主，重点验证：
  - 权限缺失
  - 配置错误
  - LLM 失败回退
  - 注入失败后保留最近记录
- 未验证主链路时，不应宣称“可用”或“完成”

## 文档要求

- 新的产品决策优先更新 `docs/PRD.md`
- 新的技术决策优先更新 `docs/TDD.md`
- 新的任务拆分与排期调整优先更新 `docs/EPICS_AND_STORIES.md`
- 新增或重命名重要文档时，同步更新 `README.md`
- 若实现与现有文档不一致，先更新文档或先与用户确认，不要静默偏离

## Skills 使用约定

当前仓库已具备以下本地 skills：

- `.agents/skills/github-workflow-automation`
- `.agents/skills/sparc-methodology`
- `.agents/skills/swarm-orchestration`

使用原则：

- 需要结构化拆解、审查、实现节奏管理时，优先使用 `sparc-methodology`
- 需要多步骤并行分析或协作时，优先使用 `swarm-orchestration`
- 涉及 GitHub 工作流、Issue、PR 操作时，优先使用 `github-workflow-automation`
- 不得借助 skill 绕过本文件中的安全、范围和文档约束

## 提交信息约定

使用 `[#AI]` 标记 AI 辅助提交。

格式：

```text
[#AI] <type>(<scope>): <description>
```

建议的 `type`：

- `feat`
- `fix`
- `docs`
- `refactor`
- `test`
- `chore`

示例：

```text
[#AI] docs(tdd): add technical design constraints
```

## 分支与变更原则

- 未经用户要求，不擅自创建复杂分支策略说明
- 保持变更小而清晰，优先按文档或单一功能提交
- 遇到和现有文档冲突的实现，先停下来确认，而不是边写边改产品定义
