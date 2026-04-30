<p align="center">
  <img src="./typoless.svg" alt="Typoless" width="160" />
</p>

<h1 align="center">Typoless</h1>

<p align="center">Typoless 是一个面向 macOS 的菜单栏语音 + AI 输入助手。</p>

## 当前范围

- 菜单栏常驻应用，不是系统级输入法
- 单一全局快捷键，按一次开始录音，再按一次结束录音
- 本地 `FunASR` 离线识别，模型外置到 `~/.typoless/models/funasr/`
- 腾讯云一句话识别，用户手动切换
- `OpenAI Chat Completions` 兼容接口
- 默认输出 LLM 润色结果
- 文本注入优先走 `Accessibility API`，失败后回退键盘事件
- 麦克风与辅助功能权限引导
- 注入失败文本仅保留在当前运行期，可从菜单栏复制

## 技术栈

- `Swift 6`
- `SwiftUI + AppKit`
- `MVVM + Service Layer`
- `RNNoise`
- `FunASR` Python sidecar
- `OpenAI Chat Completions` 兼容接口

## 仓库结构

```text
app/      macOS 客户端与 XcodeGen 工程定义
docs/     PRD、TDD、验证与设计文档
scripts/  资源准备、构建、签名相关脚本
```

## 本地开发

依赖：

- macOS 14+
- Xcode 16+
- `xcodegen`

准备资源：

```bash
./scripts/setup-rnnoise.sh
```

如需本地 FunASR runtime 打包或签名，使用：

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

## 文档入口

- [PRD](./docs/PRD.md)
- [TDD](./docs/TDD.md)
- [EPICS_AND_STORIES](./docs/EPICS_AND_STORIES.md)
