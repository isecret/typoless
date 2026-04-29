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
            │   └── requirements.txt   # Python 依赖声明
            ├── runtime/
            │   └── python3            # 内嵌 Python 解释器（或符号链接到系统 Python）
            └── models/
                ├── paraformer-zh/     # 语音识别模型
                └── fsmn-vad/          # 语音活动检测模型
```

## 3. 开发期资源布局

开发期资源放在项目目录中，通过 Xcode Build Phase 或 Copy Files 打包到 App bundle：

```
app/Typoless/Resources/funasr/
├── manifest.json
├── worker/
│   ├── funasr_worker.py
│   └── requirements.txt
├── runtime/                  # 开发期可使用系统 Python，不内嵌
└── models/                   # 通过脚本下载，不提交到仓库
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

### 6.1 开发期

- 使用系统 Python 3（`/usr/bin/python3` 或 Homebrew Python）。
- `manifest.json` 中 `worker.python` 路径不做硬编码，由 `ASRRuntimeManager` 按以下顺序查找：
  1. `funasr/runtime/python3`（内嵌 runtime）
  2. 环境变量 `FUNASR_PYTHON_PATH`
  3. `/usr/bin/python3`（系统 Python）

### 6.2 正式分发

- 内嵌精简 Python runtime（如 python-build-standalone 或 conda-forge 构建）。
- 放置在 `funasr/runtime/` 下，与 App bundle 一起签名。
- Python 依赖（funasr、torch 等）预安装到 runtime site-packages 中。

## 7. Worker 入口约定

- 入口脚本：`funasr/worker/funasr_worker.py`
- 启动方式：`{python} {worker_entry}`
- 通信协议：stdio JSON-RPC（stdin 读请求，stdout 写响应）
- Worker 启动后进入事件循环，逐行读取 JSON-RPC 请求并返回响应。
- Worker 不主动退出，由 `ASRRuntimeManager` 管理生命周期。

## 8. 模型下载脚本

提供 `scripts/setup-funasr.sh` 用于开发期下载模型：

```bash
# 下载 FunASR 模型到项目资源目录
./scripts/setup-funasr.sh
```

脚本职责：
- 从 ModelScope 下载 paraformer-zh、fsmn-vad 模型
- 放置到 `app/Typoless/Resources/funasr/models/` 下
- 生成或更新 `manifest.json`
- 不提交模型文件到仓库（`.gitignore` 排除）

## 9. 校验约定

`ASRResourceValidator` 在录音前校验：

1. `manifest.json` 存在且可解析
2. 所有 `required: true` 的模型目录存在
3. worker 入口脚本存在
4. Python runtime 可执行

校验失败返回具体错误类型（`asrRuntimeMissing` / `asrModelMissing` / `asrBinaryNotFound`）。

## 10. 签名与公证兼容性

详见 [签名设计文档](./funasr-signing-design.md)。

关键约束：
- 所有可执行文件（Python runtime、动态库）必须支持 codesign
- 模型文件作为数据资源不需要签名，但路径必须在 App bundle 内
- worker 脚本作为数据文件处理，由已签名的 Python runtime 执行
