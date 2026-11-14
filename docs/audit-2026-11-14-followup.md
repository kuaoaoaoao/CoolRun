# 代码审计跟进记录（2026-11-14）

审计报告列出 10 项问题，本文记录每一项的实际处置与验证方式。
一句话结论：**高危 1 项、中危 5 项、低危 4 项全部落地**，另外补了 4 组缺失的测试。

## 一、高危：权限闸门只在展示层

**问题**：`ToolRegistry.execute` 只按名字取工具就执行。原生引擎的确认逻辑只写在
`SwiftAgentEngine` 一处，而 DSH 走的是 `CoolRunMCPHost` 的 `tools/call`，那条路
完全绕过等级与确认——把工具等级设成「只读」，DSH 仍能调 `notes_create`。

**处置**：闸门下沉到 `ToolRegistry.execute(name:arguments:policy:)`，三个调用点
（原生引擎 / MCP host / `/tool` 直调）全部走同一条路。策略默认 `maxLevel = .read`，
忘传策略只拿到只读工具——安全失败方向。`permission >= .persistent` 必须有
approval 且结论为 approved。策略新增 `timeout`，工具卡死不会挂住整个回合。

**验证**：`CoolRunTests/ToolGateTests.swift` 6 例（越权拒绝、确认通过/拒绝、
无确认通道、超时、未知工具）。

## 二、中危 5 项

| 问题 | 处置 | 验证 |
| --- | --- | --- |
| 工具执行无超时 | `ExecutionPolicy.timeout`（默认 60 s），`awaitTool` 用 continuation + CompletionBox 保证只 resume 一次 | `testToolTimeoutReturnsPromptly`（80 ms 策略 + 600 ms handler） |
| patch 文件含 MCP token 且 0644 | 写完 `setAttributes([.posixPermissions: 0o600])` | 手工 `ls -l` |
| MCP 不校验 Origin/Host | `requestRejectionReason`：带 Origin 一律拒；Host 必须是 127.0.0.1/localhost/[::1] | `MCPOriginTests` 5 例 + `MCPProtocolTests` 走真 HTTP |
| 面板关着时确认干等 90 秒 | `AgentApprovalGate` 用 `viewDidMoveToWindow` 判断可见性，不可见立刻拒绝并给出原因 | `testApprovalFailsFastWhenNoChatWindowIsVisible`，0.102 s（原 90 s） |
| 金价历史主线程解码 115 ms | `decodeHistory` 走 `Task.detached`，回主线程按 id 合并 | `GoldHistoryLoadTests` 4 例；实测后台 166 ms |

金价这一项中途**弄丢过一次真实数据**：后台解码期间轮询写入触发防抖落盘，把内存里的
1 条写成了整个历史。已加两道保护——解码期间不落盘、新数据缩到原体积 1/3 以下拒绝
覆盖；外加每次启动第一次落盘前留 `.bak`。

## 三、低危 4 项

- **截图阻塞主线程**：`waitUntilExit()` → `terminationHandler` + continuation。
- **插件 httpGet 无白名单**：拒绝访问本机 MCP 端口（`PluginHost.blockedAgentPort`，
  由 host 启停时写入）。**没有封整个回环**——插件连本地模型是正当用法。
  `PluginNetworkTests` 5 例。
- **`try?` 静默失败**：只挑「失败后查不到原因」的几处改成显式处理——审计日志写盘、
  DSH patch 写入（失败会表现成「模型不认 key」）、密钥存储说明。
- **SecretStore 取舍**：加密文件 vs 钥匙串的代价写进设置页，不再写「存在钥匙串里」
  这种与实现不符的话。

## 四、补的测试（审计指出 4 处空白）

| 模块 | 测试 | 覆盖 |
| --- | --- | --- |
| MCP 协议层 | `MCPProtocolTests`（12 例） | 真起监听走 HTTP：health 免 token、401、404、initialize、tools/list schema、通知 202、-32601、-32700、tools/call、越权工具 |
| 系统采样 | `SystemSamplerTests`（5 例） | 轻量档数值合理、关掉的分区为空、进程列表非空、二次采样 CPU 区间、磁盘自洽 |
| 菜单栏金币 | `MenuBarCoinTests`（5 例） | 五种动画整个相位不越界、透明度在 0…1、翻面宽窄顺序、配色不透明且符号不重复 |
| 金价历史 | `GoldHistoryLoadTests`（4 例） | 体积骤缩被挡、体积相近放行 |

`MacAppDelegate` 本体（1359 行，全是 NSStatusItem / 窗口生命周期）仍无测试——
把纯逻辑（金币几何、配色）抠出来测是可行的部分，剩下的属于「必须看界面」的范畴。

## 五、工具链

`scripts/verify.sh --test` 失败时原来只说「FAIL: 有测试未通过」，测试代码编译不过时
失败用例列表是空的，看不出任何东西。现在分别报编译错误（保留 `文件:行:错误`）、
失败用例名，两者都没有时打日志尾部，完整日志留在 `.build/test-failure.log`。

## 六、当前状态

- `./scripts/verify.sh --test`：编译 **error=0 warning=0**，**407 用例通过**。
- 类型 576 个、枚举 129 个，可见性检查与 switch 完备性检查干净。
- 桌宠视频画布重新裁切（`360×340 @ (140,0)`），脚底留 8–9 像素、头顶 11 像素；
  实测窗口截图底部留白 6 点，脚不再被切。
