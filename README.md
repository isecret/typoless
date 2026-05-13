<p align="center">
  <img src="./typoless.svg" alt="Typoless" width="160" />
</p>

<h1 align="center">Typoless</h1>

<p align="center">面向 macOS 的菜单栏语音 + AI 输入助手。</p>

## 项目优势

- 菜单栏常驻，聚焦输入框后就能直接触发，不需要切回主窗口。
- 默认围绕中文短语音输入设计，链路短，行为边界明确。
- 支持本地 ASR 服务，使用 `FunASR` ，模型下载和状态管理都在应用内完成。
- `OpenAI Chat Completions` 兼容接口即可接入 AI 润色，不锁死单一服务商。
- LLM 配置不完整或调用失败时直接报错，不会把半成品文本偷偷注入出去。
- 注入失败时会保留本次文本预览，用户可以从菜单栏手动复制，而不是丢结果。

## 怎么使用

### 首次准备

1. 启动应用后打开设置页。
2. 在 `语音识别` 中选择识别引擎。默认推荐本地 `FunASR`；如果选择本地模式，先下载模型。
3. 在 `AI 配置` 中填写 `Base URL`、`API Key`、`Model`。
4. 授予麦克风权限和辅助功能权限。
5. 设置全局快捷键。

### 日常使用

1. 在任意应用中聚焦一个可输入文本的位置。
2. 按一次全局快捷键开始录音。
3. 说完后再按一次快捷键结束录音。
4. Typoless 会依次完成降噪、识别、AI 润色，并把最终文本写回当前应用。
5. 如果本次写入失败，菜单栏会保留一段截断预览，点击即可复制完整文本。

## 相比 Typeless

- 本地优先。Typoless 把本地 `FunASR` 离线识别作为默认主链路，模型外置、状态可见、缺失可提示、下载可管理。
- 后端可替换。LLM 只要求 `OpenAI Chat Completions` 兼容，ASR 也支持在本地 `FunASR`、`腾讯云`、`阿里云`、`火山引擎`、`科大讯飞` 之间手动切换。
- 失败策略更保守。LLM 失败时不注入 ASR 原文，注入失败时也不会自动污染剪贴板，而是把恢复入口留给用户主动点击。
- 工程化程度更高。仓库内已经包含资源校验、模型下载、HUD 反馈、签名、公证、DMG 打包脚本，不是只停在“能调通一次接口”的 demo 状态。
- 更关注中文输入闭环。当前的降噪、识别、润色和注入边界都围绕中文短语音输入来收敛，而不是一个大而全的平台。

## 能力边界

- 应用形态是菜单栏助手，不是 macOS 系统级输入法。
- 当前交互是单一全局快捷键，按一次开始录音，再按一次结束录音。
- 单次录音上限为 `60 秒`，极短录音会静默取消。
- 本地识别默认使用 `FunASR`，云端识别支持 `腾讯云`、`阿里云`、`火山引擎`、`科大讯飞`。
- AI 润色仅支持 `OpenAI Chat Completions` 兼容接口。
- 不支持实时流式识别、自定义 Prompt、高级采样参数或音频历史保存。

## 仓库结构

```text
app/      macOS 客户端与 XcodeGen 工程定义
docs/     PRD、TDD、验证与设计文档
scripts/  资源准备、构建、签名相关脚本
```

## 本地开发

依赖环境：

- macOS 14+
- Xcode 16+
- `xcodegen`

准备资源：

```bash
./scripts/setup-rnnoise.sh
./scripts/setup-funasr.sh
```

如需重新打包或签名本地 `FunASR` runtime，可使用：

```bash
./scripts/bundle-funasr-runtime.sh
./scripts/sign-funasr-runtime.sh
```

生成工程并构建：

```bash
cd app
xcodegen generate
xcodebuild build -project Typoless.xcodeproj -scheme Typoless -destination 'platform=macOS'
```

如需演练正式分发链路，相关辅助脚本位于：

```bash
./scripts/ci/import-apple-signing-assets.sh
./scripts/ci/sign-macos-app.sh
./scripts/ci/create-dmg.sh
./scripts/ci/notarize-dmg.sh
./scripts/ci/verify-macos-release.sh
```

公证支持两种方式：

- `App Store Connect API Key`
- `Apple ID + app-specific password`

## 文档入口

- [PRD](./docs/PRD.md)
- [TDD](./docs/TDD.md)
- [EPICS_AND_STORIES](./docs/EPICS_AND_STORIES.md)
- [端到端验证](./docs/validation-e2e.md)
- [失败处理验证](./docs/validation-failure-handling.md)
