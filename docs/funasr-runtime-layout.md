# FunASR 运行时与资源布局设计

## 1. 概述

本文档定义 FunASR Python sidecar worker、Python runtime 和模型资源在 App bundle 中的目录布局，
以支持开发期本地运行和正式签名分发。

## 2. App Bundle 内资源布局

```
Typoless.app/
└── Contents/
    └── Resources/
        └── funasr/
            ├── manifest.json          # 资源清单（版本、模型列表、校验和）
            ├── worker/
            │   ├── funasr_worker.py   # sidecar 入口脚本
            │   ├── requirements.txt   # Python 依赖声明（开发用）
            │   └── requirements-lock.txt  # 锁定版本（Release 构建用）
            ├── runtime/
            │   ├── python3            # 内嵌 Python 解释器（已签名）
            │   └── lib/               # Python stdlib + site-packages
            │       └── python3.11/
            │           └── site-packages/   # funasr, torch 等已安装包
            └── models/                # 外置到用户目录，不内嵌 bundle
```

模型资源存储在 `~/.typoless/models/funasr/`，通过设置页引导用户下载，不随 App bundle 分发。

## 3. 开发期资源布局

开发期资源放在项目目录中，通过 Xcode Build Phase 或 Copy Files 打包到 App bundle：

```
app/Typoless/Resources/funasr/
├── manifest.json
├── worker/
│   ├── funasr_worker.py
│   ├── requirements.txt           # 开发用（>=约束）
│   └── requirements-lock.txt      # Release 用（==约束）
├── runtime/                       # 开发期可使用系统 Python，不内嵌
└── models/                        # 通过脚本下载，不提交到仓库
    ├── paraformer-zh/
    └── fsmn-vad/
```

## 4. manifest.json 格式

```json
{
  "version": "1.0.0",
  "engine": "funasr",
  "models": {
    "asr": {
      "name": "paraformer-zh",
      "path": "models/paraformer-zh",
      "required": true
    },
    "vad": {
      "name": "fsmn-vad",
      "path": "models/fsmn-vad",
      "required": true
    }
  },
  "worker": {
    "entry": "worker/funasr_worker.py",
    "python": "runtime/python3"
  },
  "device": {
    "priority": ["mps", "cpu"]
  }
}
```

## 5. 资源发现机制

Swift 端通过以下路径定位资源：

```swift
let bundle = Bundle.main
let funasrRoot = bundle.resourceURL!.appendingPathComponent("funasr")
let manifestURL = funasrRoot.appendingPathComponent("manifest.json")
```

开发期可通过环境变量 `FUNASR_RESOURCE_PATH` 覆盖资源根目录，便于调试。

## 6. Python Runtime 策略

### 6.1 Runtime 来源

正式分发使用 [python-build-standalone](https://github.com/indygreg/python-build-standalone) 提供的预构建 Python：

- **版本**: Python 3.11.x（固定 minor version，与依赖包兼容）
- **架构**: `aarch64-apple-darwin`（Apple Silicon）
- **变体**: `install_only_stripped`（最小体积，无调试符号）
- **下载**: 通过 `scripts/bundle-funasr-runtime.sh` 自动完成

### 6.2 开发期

- 使用系统 Python 3（`/usr/bin/python3` 或 Homebrew Python）。
- `ASRRuntimeManager` 按以下顺序查找 Python：
  1. `funasr/runtime/python3`（内嵌 runtime）
  2. 环境变量 `FUNASR_PYTHON_PATH`
  3. `~/.pyenv/shims/python3`
  4. `/opt/homebrew/bin/python3`
  5. `/usr/local/bin/python3`
  6. `/usr/bin/python3`（系统 Python）

### 6.3 正式分发

- 内嵌 python-build-standalone 到 `funasr/runtime/`。
- Python 依赖根据 `requirements-lock.txt` 预安装到 runtime site-packages。
- 所有可执行文件和动态库已签名。

## 7. 依赖锁定策略

| 文件 | 用途 | 版本约束 |
|------|------|----------|
| `requirements.txt` | 开发环境安装 | `>=` 最低兼容 |
| `requirements-lock.txt` | Release 构建 | `==` 精确锁定 |

Release 构建要求：
- 仅使用 `--only-binary :all:` 安装（不编译 C 扩展）
- 目标平台 `macosx_14_0_arm64`
- 所有 `.so` 和 `.dylib` 必须为 arm64 Mach-O

## 8. Worker 入口约定

- 入口脚本：`funasr/worker/funasr_worker.py`
- 启动方式：`{python} -u {worker_entry}`（unbuffered）
- 通信协议：stdio JSON-RPC（stdin 读请求，stdout 写响应）
- Worker 启动后进入事件循环，逐行读取 JSON-RPC 请求并返回响应。
- Worker 不主动退出，由 `ASRRuntimeManager` 管理生命周期。

## 9. 打包与签名流程

### 9.1 脚本

| 脚本 | 职责 |
|------|------|
| `scripts/setup-funasr.sh` | 开发期下载模型 |
| `scripts/bundle-funasr-runtime.sh` | 下载 runtime、安装依赖、组装 bundle 目录 |
| `scripts/sign-funasr-runtime.sh` | 签名所有 Mach-O 文件 |

### 9.2 Release 构建步骤

```bash
# 1. 组装 runtime bundle
./scripts/bundle-funasr-runtime.sh --output build/funasr-bundle

# 2. 签名所有可执行文件
SIGNING_IDENTITY="Developer ID Application: ..." \
ENTITLEMENTS=app/Typoless/Typoless.entitlements \
./scripts/sign-funasr-runtime.sh --bundle-dir build/funasr-bundle

# 3. 复制到 App bundle
cp -R build/funasr-bundle/* "Typoless.app/Contents/Resources/funasr/"

# 4. 签名 App bundle
codesign --deep --force --options runtime \
  --sign "$SIGNING_IDENTITY" \
  --entitlements app/Typoless/Typoless.entitlements \
  Typoless.app

# 5. 验证
codesign --verify --deep --strict Typoless.app

# 6. 公证
xcrun notarytool submit Typoless.zip ...
xcrun stapler staple Typoless.app
```

## 10. 校验约定

`ASRResourceValidator` 在录音前校验：

1. `manifest.json` 存在且可解析
2. 所有 `required: true` 的模型目录存在
3. worker 入口脚本存在
4. Python runtime 可执行

校验失败返回具体错误类型（`asrRuntimeMissing` / `asrModelMissing` / `asrBinaryNotFound`）。

## 11. 签名与公证兼容性

详见 [签名设计文档](./funasr-signing-design.md)。

关键约束：
- 所有可执行文件（Python runtime、动态库）必须支持 codesign
- 模型文件作为数据资源不需要签名，但路径必须可定位
- worker 脚本作为数据文件处理，由已签名的 Python runtime 执行
- Hardened Runtime 需要 `com.apple.security.cs.allow-unsigned-executable-memory`（PyTorch JIT）
