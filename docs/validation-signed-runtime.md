# E16-I3 签名分发可运行性验证清单

> 对应 Issue: #88
> 前置依赖: #84 (签名与公证兼容设计)

## 目的

验证 App 签名构建后内嵌的 Python runtime 和 FunASR 资源可正常运行。

## 前置条件

1. 使用 `codesign` 签名后的 .app 包（Release 或 Archive 构建）
2. 参考 `docs/funasr-signing-design.md` 中的签名流程

## 验证步骤

### 1. Worker 启动

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 1.1 | 签名构建后启动 App，触发首次录音 | sidecar worker 可正常启动（无 "killed" 或权限拒绝错误） | ☐ |
| 1.2 | 检查 Console.app 系统日志 | 无 code signing 或 Gatekeeper 拒绝信息 | ☐ |

### 2. 路径定位

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 2.1 | 将 .app 移动到 /Applications | runtime 和模型路径仍可正确定位（基于 Bundle.main） | ☐ |
| 2.2 | 将 .app 移动到 ~/Desktop | 同上 | ☐ |
| 2.3 | 检查 manifest.json 解析 | 所有模型路径可相对于资源根正确解析 | ☐ |

### 3. 执行权限

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 3.1 | 检查内嵌 Python 可执行文件权限 | 文件具有 execute 权限（755） | ☐ |
| 3.2 | 检查 funasr_worker.py 权限 | 文件可读（644 即可，由 Python 解释器执行） | ☐ |
| 3.3 | Hardened Runtime 下执行识别 | 无 JIT/mmap 权限异常；MPS（Metal）可正常使用或 graceful 降级到 CPU | ☐ |

### 4. 公证验证（发布前）

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 4.1 | 提交 notarization 并等待完成 | Apple notarytool 返回 Accepted | ☐ |
| 4.2 | staple 公证票据后 spctl 检查 | `spctl --assess --type execute` 返回 accepted | ☐ |
| 4.3 | 从 DMG/ZIP 解压后首次运行 | 无 Gatekeeper 弹窗阻止；worker 正常启动 | ☐ |

## 发布检查清单

以下检查项应纳入每次发布流程：

1. **签名完整性**: `codesign --verify --deep --strict Typoless.app`
2. **Hardened Runtime**: `codesign -d --entitlements :- Typoless.app` 确认必要 entitlement
3. **Python runtime 签名**: 内嵌 Python 二进制已 ad-hoc 或 Developer ID 签名
4. **动态库签名**: `.so`/`.dylib` 文件已签名且 rpath 正确
5. **Notarization**: `xcrun notarytool submit` 完成且 Accepted
6. **Staple**: `xcrun stapler staple Typoless.app`
7. **首次运行测试**: 全新用户环境下从 DMG 安装运行一次完整识别
