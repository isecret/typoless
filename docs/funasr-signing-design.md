# FunASR 签名与公证兼容设计

## 1. 概述

本文档明确 Typoless 在正式分发（签名 + 公证）场景下，FunASR Python sidecar、runtime 和模型资源的兼容性约束与打包要求。

## 2. 资源分类与签名要求

| 资源类型 | 示例 | 签名要求 | 说明 |
| --- | --- | --- | --- |
| 可执行文件 | `runtime/python3` | 必须 codesign | Apple 要求所有 Mach-O 可执行文件签名 |
| 动态库 | `*.dylib`, `*.so` | 必须 codesign | Python 扩展模块和依赖库 |
| 脚本文件 | `funasr_worker.py` | 无需签名 | 作为数据文件，由已签名的 Python 解释器执行 |
| 模型文件 | `paraformer-zh/` | 无需签名 | 纯数据资源，放在 Resources/ 目录下 |
| 配置文件 | `manifest.json` | 无需签名 | 纯数据资源 |

## 3. Python Runtime 签名

### 3.1 内嵌 Python Runtime

正式分发时内嵌 Python runtime（如 python-build-standalone），需要：

1. **主可执行文件签名**：`funasr/runtime/python3` 必须使用与 App 相同的 signing identity。
2. **动态库签名**：`runtime/lib/` 下所有 `.dylib` 和 `.so` 文件必须签名。
3. **Python 扩展模块签名**：`site-packages/` 中的 `.so` 文件（如 torch、funasr C 扩展）必须签名。

### 3.2 签名命令示例

```bash
# 签名 Python runtime
codesign --force --options runtime --sign "${SIGNING_IDENTITY}" \
  "${APP_BUNDLE}/Contents/Resources/funasr/runtime/python3"

# 批量签名动态库和扩展模块
find "${APP_BUNDLE}/Contents/Resources/funasr/runtime" \
  -name '*.dylib' -o -name '*.so' | while read f; do
  codesign --force --options runtime --sign "${SIGNING_IDENTITY}" "$f"
done
```

### 3.3 Hardened Runtime 约束

- 启用 Hardened Runtime（`--options runtime`）时，Python 需要 `com.apple.security.cs.allow-unsigned-executable-memory` entitlement（PyTorch 等库需要 JIT）。
- 如使用 MPS，可能需要 `com.apple.security.cs.disable-library-validation`。
- 这些 entitlement 应定义在 App 的 `.entitlements` 文件中。

## 4. App Sandbox 约束

### 4.1 当前策略

首版 Typoless 不启用 App Sandbox（非 App Store 分发）：

- sidecar 进程通过 `Process()` 启动，无需额外权限。
- 资源文件通过 `Bundle.main.resourceURL` 定位，无需文件系统访问权限。
- 配置文件位于 `~/.typoless/`，需要文件系统写入权限。

### 4.2 未来 App Store 分发

如需 App Store 分发，需要：

- sidecar 放入 `Contents/XPCServices/` 或使用 XPC 通信。
- 模型和配置文件使用 App Group container。
- 评估 MPS 在 sandbox 中的可用性。

本轮不实现 App Store 适配，但资源布局设计不阻碍未来迁移。

## 5. 公证（Notarization）要求

Apple 公证要求：

1. 所有可执行代码必须签名（包括嵌套的 Python runtime 和 `.so` 扩展）。
2. 使用 Hardened Runtime。
3. 不包含被 Gatekeeper 拒绝的文件。

### 5.1 公证前检查

```bash
# 检查所有可执行文件是否已签名
codesign --verify --deep --strict "${APP_BUNDLE}"

# 检查是否满足公证要求
xcrun stapler validate "${APP_BUNDLE}"
```

### 5.2 已知风险

- PyTorch 等 C 扩展可能包含未签名的第三方 `.so`，需要在打包时统一签名。
- 某些 Python 包可能使用 `ctypes.CDLL` 动态加载库，Hardened Runtime 下可能被拦截。
- 建议在构建流水线中加入签名验证步骤。

## 6. 构建与打包流程

### 6.1 开发期

1. 使用系统 Python，无需签名。
2. 模型通过 `scripts/setup-funasr.sh` 下载到项目目录。
3. Xcode 通过 Copy Files Build Phase 将 `funasr/` 打包到 App bundle。

### 6.2 正式构建

1. 准备 Python runtime（python-build-standalone 或 conda-forge）。
2. 安装 Python 依赖到 runtime site-packages。
3. 精简 runtime（移除 `__pycache__`、`*.pyc`、测试目录、文档）。
4. 签名所有可执行文件和动态库。
5. 打包到 App bundle。
6. 签名 App bundle。
7. 提交公证。
8. Staple 公证票据。

### 6.3 Release 检查清单

- [ ] Python runtime 已签名
- [ ] 所有 `.dylib` 和 `.so` 已签名
- [ ] App bundle deep sign 验证通过
- [ ] 公证提交成功
- [ ] Staple 完成
- [ ] 首次启动 sidecar 可正常运行
- [ ] 模型加载和识别请求正常返回
