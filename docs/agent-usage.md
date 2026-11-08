# CoolRun Agent 使用说明

> 面向使用者，不是设计文档。设计见 `agent-engine-design.md`。

## 1. 怎么叫出它

| 方式 | 操作 |
| --- | --- |
| 全局快捷键 | `⌥⌘A`，任何 app 里都能用 |
| 菜单栏 | 点鲸鱼图标 → 切到「AI 助手」 |
| 桌宠 | 双击桌面上的鲸鱼娘 |
| 快捷指令 | 在输入框里敲 `/` |

面板是同一个 popover，切到别的模块再回来，对话还在。

## 2. 第一次用

打开面板 → 右上角齿轮 → 选协议、填 Base URL、模型名、API Key。

四种协议都支持：

- **Chat** — OpenAI `/v1/chat/completions`，兼容面最广（DeepSeek、Kimi、Qwen、各类中转网关都走这个）
- **Responses** — OpenAI 新的 `/v1/responses`
- **Claude** — Anthropic `/v1/messages`
- **Ollama** — 本地模型，默认 `http://127.0.0.1:11434`

本地模型不用联网也不用 key，只要 Ollama 跑起来、模型拉下来就行。注意小模型（0.5B 那种）经常不会正确地调工具，7B 以上才稳。

「从 AI 助手同步配置」可以把之前助手模块里填过的配置直接搬过来。

## 3. 能做什么

### 场景卡

空对话时有 12 张卡，点一下就开始：

电脑体检 / 金价快报 / 今天有什么 / 谁在吃内存 / 电池还行吗 / 能清理什么 / 记一笔 / 剪贴板找东西 / 提醒我 / 额度还剩多少 / 截个图 / 切到金价

需要补充信息的卡（比如「记一笔」）点了之后会把提示语填进输入框，不会直接发出去。

### 斜杠指令

```
/体检  /金价  /今天  /内存  /电池  /清理  /记 <内容>  /剪贴板 <词>
/提醒 30m 喝水   /额度  /截图  /切金价
/tool system_snapshot       直接跑一个工具
/help                       看全部
/clear                      清空对话
```

### 工具浏览器

状态栏的九宫格按钮 → 看到当前允许的所有工具，按权限分组。选一个，表单会自动根据 JSON Schema 生成，填完点运行就能直接调 —— 不用经过模型，适合「我就想看一眼某个数据」的场景。

L2 及以上的工具点一次变「确认执行」，再点一次才真的写。

### 对话里能干什么

工具调用会显示成卡片（图标 + 工具名 + 参数），点开看返回的原始结果。

L2 工具（写笔记、建提醒、截图）执行前会弹一条橙色的确认条，90 秒不点自动拒绝。

每条消息右键可以复制或删除。历史会存下来，重开 app 还在，最多 200 条。

## 4. 权限

设置里可以选工具等级，模型能看到的工具集永远不超过这个等级：

| 等级 | 含义 | 例子 |
| --- | --- | --- |
| L0 只读 | 看，不改任何东西 | 系统快照、金价、搜笔记 |
| L1 可逆 | 改了能马上改回来 | 切面板、发通知、写剪贴板 |
| L2 持久 | 会留下痕迹 | 建笔记、建提醒、截图 |
| L3 危险 | 执行命令、写文件 | 默认不注册 |

默认是 L0。想让 agent 帮你记东西，调到 L2。

## 5. 插件

插件是本地目录，后缀 `.coolplugin`：

```
我的插件.coolplugin/
├── manifest.json
└── main.js
```

`manifest.json`：

```json
{
  "id": "com.example.hello",
  "name": "Hello",
  "version": "1.0.0",
  "summary": "一个示例插件",
  "author": "你",
  "main": "main.js",
  "permissions": ["storage", "notify"],
  "tools": [
    {
      "name": "now",
      "summary": "返回当前时间",
      "handler": "now",
      "parameters": { "type": "object", "properties": {} }
    }
  ]
}
```

`main.js`：

```js
function now() {
  var n = (coolrun.storage.get("count") || 0) + 1;
  coolrun.storage.set("count", n);
  return "现在是 " + new Date().toLocaleString() + "（第 " + n + " 次）";
}
```

能用的 API：`coolrun.log` / `coolrun.storage.get|set` / `coolrun.httpGet` / `coolrun.notify` / `coolrun.copy`，每个都要在 `permissions` 里声明。

装：设置 → 插件 → 安装，选那个目录。装完工具会自动出现在工具浏览器里，也能被模型调用。

## 6. 桌宠

桌面右下角那只鲸鱼。

- 拖动：按住拖到任意位置，位置会记住
- 双击：打开 Agent
- 右键：打开 Agent / 隐藏
- 气泡：Agent 在想事情的时候她会冒「本鱼在想…」

不想要了：设置 → 通用 → 桌宠 → 关掉。

### 她是怎么画出来的

用的是角色立绘（`CoolRun/Assets.xcassets/PetWhale.imageset/pet-whale.png`），
动效全部由 SwiftUI 合成：呼吸（纵向 0.994↔1.012 拉伸，锚点在脚底）、摇摆
（±1.5°）、地面影子（跟着呼吸缩放）、悬停放大 4%、思考时冒气泡。

没有用 Live2D，原因很实际：Live2D 要 `.moc3` 模型 + 贴图 + 物理参数，从一张
PNG 手工绑骨骼是几天的工作量，而 Q 版立绘的呼吸摇摆已经有「活着」的感觉。
BongoCat 那种 Rust + Live2D 的方案可以借鉴渲染层，但要先有模型文件。

换角色很简单：把新的 PNG 抠图（透明背景）覆盖 `pet-whale.png`，尺寸比例保持
约 355×393 即可，代码不用动。抠图用 macOS 自带的 Vision：

```swift
let request = VNGenerateForegroundInstanceMaskRequest()
```

### 想要更进一步的动画

如果以后有了 Live2D 模型，或者拿到了同一角色的多张表情/动作图，可以：

1. 多张表情图 → 按状态切换（思考/说话/睡觉），`WhalePetView` 里换 `Image` 即可
2. 序列帧 → 把 PNG 序列放进 imageset，用 `TimelineView` 逐帧播放
3. Live2D → 引入 Cubism SDK，工作量约一周

现在的方案是「一张图 + 合成动效」，性价比最高的一档。

## 7. 两个版本

| | Lite | Full |
| --- | --- | --- |
| 体积 | 8.6 MB | 107 MB |
| 原生引擎 | ✅ | ✅ |
| 云端 / 本地 LLM | ✅ | ✅ |
| 工具 / 插件 / 桌宠 | ✅ | ✅ |
| DSH 引擎 | 首次使用时下载（约 90 MB） | 内置，离线可用 |

功能完全一样，区别只在 DSH 引擎是内置还是按需下载。

## 8. 引擎怎么选

设置 → 引擎：

- **原生引擎**（默认）：Swift 实现，四种协议 + 工具循环，体积为零，够用
- **DeepSeek Harness**：能力更全（多步任务、子代理、skill），代价是 300 MB 和一个外部进程

两个引擎用的是同一套工具、同一套权限闸门，切换对使用者是透明的。

## 9. 出问题了

- **一直弹钥匙串授权**：已经在 v4.3 改成 AES-GCM 本地加密文件，不再用钥匙串。如果你还看到弹窗，说明跑的是旧包。
- **模型不调工具，只输出 JSON 文本**：模型太弱，换 7B 以上的。
- **DSH 引擎起不来**：设置里看运行时状态；缺的话点下载。日志在 `~/Library/Application Support/CoolRun/agent-home/`。
- **快捷键没反应**：可能被别的 app 占了，换一个或者用菜单栏图标。
