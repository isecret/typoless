# E16-I2 FunASR 失败处理与 LLM 失败验证清单

> 对应 Issue: #87, #97
> 前置依赖: #80 (FunASRProvider), #81 (FunASR 设为默认)

## 目的

验证 FunASR sidecar 架构下各类失败场景的处理行为，确保不会进入不可解释状态。

## 前置条件

1. App 已正确打包 FunASR 运行资源（manifest.json、worker、Python runtime），且用户目录模型默认可用
2. 麦克风和辅助功能权限已授予

## 验证步骤

### 1. 资源缺失

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 1.1 | 删除 manifest.json 后启动 App | ResourceValidator 报告资源异常；录音按钮不可用或提示用户 | ☐ |
| 1.2 | 删除某个 required 模型目录 | 同上，明确提示缺失项 | ☐ |
| 1.3 | 删除 worker/funasr_worker.py | 同上 | ☐ |
| 1.4 | 恢复所有资源后重新启动 | App 恢复正常 | ☐ |

### 2. ASR 超时与取消

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 2.1 | 模拟 worker 响应超过 15 秒 | ASR 报超时；worker 被 terminate 并清理；状态回到 idle/error | ☐ |
| 2.2 | 超时后立即再次录音 | 启动新 worker（新 generation）；不读取旧响应；识别正常完成 | ☐ |
| 2.3 | 录音过程中用户手动取消（transcribing 阶段） | 处理链路终止；worker 被 invalidate；不进入 LLM 或注入 | ☐ |
| 2.4 | 快速连续触发两次录音 | 前一 session 被正确取消；后一 session 正常执行 | ☐ |

### 3. Worker 异常恢复

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 3.1 | 手动 kill sidecar 进程 | terminationHandler 检测退出；本次请求报失败 | ☐ |
| 3.2 | kill 后下一次录音 | 自动启动新 worker；识别正常完成 | ☐ |
| 3.3 | 连续 kill 两次后录音 | 仍能自动恢复 | ☐ |
| 3.4 | idle 超时释放 worker 后再次录音 | 自动启动新 worker；识别正常完成 | ☐ |

### 4. 协议异常

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 4.1 | worker 返回 response id 不匹配 | 本次请求失败；worker 被标记 contaminated 并清理 | ☐ |
| 4.2 | worker 返回非法 JSON | 本次请求失败；worker 被标记 contaminated 并清理 | ☐ |
| 4.3 | worker 返回 JSON-RPC error | 映射为 ASR 失败；不造成协议失步；worker 不被清理 | ☐ |

### 5. LLM 失败处理

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 5.1 | 配置无效 LLM endpoint | ASR 结果正常获取；LLM 失败后直接报错，不注入任何文本 | ☐ |
| 5.2 | 配置 LLM 超时（极低 timeout） | 超时后直接报错，不注入任何文本 | ☐ |
| 5.3 | 注入失败（目标无文本焦点） | 菜单栏显示截断预览；点击可复制到剪贴板 | ☐ |

### 6. 进程清理验证

| # | 操作 | 预期结果 | 通过 |
|---|------|---------|------|
| 6.1 | 超时后 `ps aux | grep funasr` | 无残留 Python 进程 | ☐ |
| 6.2 | 取消后 `ps aux | grep funasr` | 无残留 Python 进程 | ☐ |
| 6.3 | Grace period 内 worker 正常退出 | 使用 SIGTERM（日志无 force-killed） | ☐ |
| 6.4 | Grace period 超时 | 使用 SIGKILL（日志有 force-killed 警告） | ☐ |

## 通过标准

- 所有失败场景不产生 UI 卡死或不可解释状态
- 超时和取消后无孤儿 worker 进程
- Worker 恢复后下一次请求可正常完成
- 旧 worker 响应不会污染新 session
- LLM 失败不会注入 ASR 原文
- processGeneration 机制防止旧回调干扰新 worker
