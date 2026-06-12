# TokenBar

**English** | [中文](#中文)

TokenBar is a lightweight Touch Bar widget and macOS menu bar utility for monitoring API and quota usage across mainstream AI Agents and AI IDEs. It currently supports Codex, Claude, Gemini, Cursor, Antigravity, OpenRouter, and WorkBuddy.

The app is designed for people who use multiple AI coding assistants and want a compact, always-visible view of remaining quota without opening each provider dashboard. On Touch Bar Macs it behaves like a small usage dashboard; on other Macs it still runs from the menu bar.

## Features

- **AI Agent and AI IDE usage monitor**: shows Codex, Claude, Gemini, Cursor, Antigravity, OpenRouter, and WorkBuddy in one Touch Bar strip.
- **Touch Bar cards**: displays provider icon, plan label, remaining usage, reset time, and segmented usage bars.
- **Menu bar fallback**: runs as a background menu bar app, useful on Macs without a physical Touch Bar.
- **Manual refresh**: refresh usage from the menu bar or Touch Bar refresh control.
- **Provider visibility settings**: show or hide supported providers from the Settings menu.
- **Drag-and-drop provider ordering**: long-press a provider card on the Touch Bar, drag it left or right, and release to persist the new layout.
- **Expanded provider cards**: tap a provider card to expand/collapse richer quota details when available.
- **OpenRouter key management**: save, clear, or open the OpenRouter key page from the app menu.
- **Login startup**: the install script creates a LaunchAgent so TokenBar starts automatically after login.
- **Local-first privacy model**: reuses local provider sessions and Keychain entries instead of shipping credentials.

## Supported Providers

| Provider | What TokenBar Shows | Data Source | Notes |
|---|---|---|---|
| Codex | 5-hour and weekly rate-limit windows | Local Codex app server via `/Applications/Codex.app/Contents/Resources/codex app-server` | Requires Codex.app to be installed and logged in. |
| Claude | 5-hour and 7-day utilization | Claude Code OAuth credentials in macOS Keychain, with local-log fallback | `CLAUDE_OAUTH_CLIENT_ID` is required for OAuth refresh. |
| Gemini | Daily request estimate | Local Gemini CLI logs under `~/.gemini/tmp` | Uses a local estimate because Gemini CLI logs do not expose official server quota windows. |
| Cursor | Combined included usage plus API/auto-model breakdown | Cursor local `state.vscdb` session token and Cursor dashboard APIs | Requires Cursor to be installed and logged in. |
| Antigravity | 5-hour and weekly quota buckets | Local Antigravity language server runtime API | Requires Antigravity to be running. |
| OpenRouter | Total spend/credits usage | OpenRouter credits API | API key can be saved in Keychain from the TokenBar menu or provided via environment variable. |
| WorkBuddy | Remaining credits and reset cycle | Local WorkBuddy/CodeBuddy auth file and Tencent WorkBuddy billing APIs | Supports personal and enterprise usage responses. |

## Requirements

- macOS 13 Ventura or later
- Swift 6 toolchain
- A Mac with Touch Bar for the full Touch Bar experience
- Optional: any supported provider apps/CLIs you want to monitor

TokenBar also exposes a menu bar status item, so the app can still run on Macs without a Touch Bar.

## Build And Install

Run the install script:

```bash
./scripts/build-and-run.sh
```

The script will:

1. Build a release binary with Swift Package Manager.
2. Package `TokenBar.app`.
3. Ad-hoc sign the app bundle.
4. Install it to `~/Applications/TokenBar.app`.
5. Create `~/Library/LaunchAgents/local.tokenbar.plist`.
6. Load the LaunchAgent and start TokenBar.

## Manual Build

```bash
swift build -c release
.build/release/tokenbar
```

Manual execution is useful for development, but it does not create the app bundle or login item.

## Usage

After TokenBar is running, use the menu bar item for common actions:

- **Refresh**: fetch fresh usage data from all visible providers.
- **Show Touch Bar**: present the TokenBar Touch Bar strip.
- **Settings -> Show Provider**: toggle provider cards on or off. At least one provider must remain visible.
- **Settings -> OpenRouter API Key...**: save an OpenRouter API key into macOS Keychain.
- **Settings -> Open OpenRouter Keys Page**: open the OpenRouter key management page.
- **Settings -> Clear OpenRouter API Key**: remove the saved OpenRouter key from Keychain.
- **Settings -> Reset to Codex + Claude**: restore the default provider layout.
- **Quit**: stop TokenBar.

Touch Bar interactions:

- Tap a provider card to expand or collapse it.
- Long-press and drag a provider card to reorder visible providers.
- Use the refresh item to update usage immediately.

## Credentials And Configuration

TokenBar does not include provider secrets. It reads credentials that already exist on your Mac or values you explicitly provide.

| Name | Required For | Description |
|---|---|---|
| `CLAUDE_OAUTH_CLIENT_ID` | Claude live OAuth refresh | Claude Code OAuth client ID. Use the public Claude Code CLI client ID from Anthropic's tooling. |
| `OPENROUTER_API_KEY` | OpenRouter, if not saved in Keychain | OpenRouter API key. Prefer the in-app Keychain storage for normal use. |

OpenRouter Keychain storage:

- Service: `TokenBar.OpenRouter`
- Account: `apiKey`

Claude Keychain storage:

- TokenBar reads the existing Claude Code service: `Claude Code-credentials`
- TokenBar may write refreshed OAuth tokens back to that same Keychain item so Claude Code remains usable.

## Privacy

TokenBar is a local macOS utility. It does not run a backend service and does not upload your usage data to TokenBar-owned infrastructure.

Network requests are made only to the providers needed for enabled usage collectors, such as Anthropic, Cursor, OpenRouter, Tencent WorkBuddy, or local loopback services. Local session files and Keychain entries stay on your Mac.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Codex CLI not found` | Codex.app is not installed in `/Applications` | Install Codex.app and log in. |
| `Set CLAUDE_OAUTH_CLIENT_ID for Claude usage` | Claude OAuth refresh cannot run without the client ID | Export `CLAUDE_OAUTH_CLIENT_ID` before launching TokenBar or configure it in your launch environment. |
| `Claude credentials not found` | Claude Code is not logged in | Run `claude` and complete login. |
| `Gemini CLI not found` | No Gemini local log directory exists | Run Gemini CLI at least once. |
| `Cursor session token not found` | Cursor is not logged in or its local database is unavailable | Open Cursor and sign in. |
| `Antigravity not running` | The local language server is not active | Start Antigravity before refreshing. |
| `Set API key` for OpenRouter | No OpenRouter key is available | Use Settings -> OpenRouter API Key... or set `OPENROUTER_API_KEY`. |
| `WorkBuddy login not found` | WorkBuddy/CodeBuddy auth file is missing | Sign in to WorkBuddy or CodeBuddy. |

## Development

Project layout:

```text
.
├── Package.swift
├── Info.plist
├── Sources/TokenBar/main.swift
├── Sources/TokenBar/Resources/GeminiIcon.svg
├── scripts/build-and-run.sh
└── LICENSE
```

Useful commands:

```bash
swift build
swift build -c release
swift run tokenbar
```

Generated files such as `.build/`, `TokenBar.app/`, `.omc/`, `card-preview/`, and local Claude data are intentionally ignored by Git.

## Security Notes

TokenBar is intended to run on your own Mac and reuse sessions you already control. It does not ask you to paste provider credentials into the source code.

For normal use:

- Store OpenRouter keys with the in-app Keychain flow when possible.
- Keep provider apps and CLIs logged in through their official login flows.
- Treat local provider logs as private because they may include prompts, file paths, or project context.
- Review network access expectations in the provider table before enabling a collector.

For forks or local modifications, do not commit:

- Provider API keys.
- OAuth access or refresh tokens.
- macOS Keychain exports.
- Local AI tool logs containing private prompts or workspace context.
- Built app bundles, generated previews, or debug output.

## License

MIT. See [LICENSE](LICENSE).

---

## 中文

TokenBar 是一个轻量级 Touch Bar 小组件和 macOS 菜单栏工具，用来集中查看主流 AI Agent 与 AI IDE 的 API/额度使用情况。目前支持 Codex、Claude、Gemini、Cursor、Antigravity、OpenRouter 和 WorkBuddy。

它适合同时使用多个 AI 编程助手的用户：不用反复打开各个服务的后台，就能在 Touch Bar 或菜单栏里快速看到剩余额度、重置时间和当前计划信息。在带 Touch Bar 的 Mac 上，它就是一个常驻的小型用量仪表盘；在其他 Mac 上，也可以通过菜单栏使用。

## 功能特性

- **AI Agent / AI IDE 用量监视器**：集中展示 Codex、Claude、Gemini、Cursor、Antigravity、OpenRouter、WorkBuddy 的 API 和额度用量。
- **Touch Bar 卡片**：显示服务图标、计划标签、剩余额度、重置时间和分段进度条。
- **菜单栏兜底**：作为后台菜单栏应用运行，没有实体 Touch Bar 的 Mac 也可以使用。
- **手动刷新**：可以从菜单栏或 Touch Bar 刷新所有可见服务的数据。
- **服务显示开关**：在 Settings 菜单中选择显示或隐藏不同服务。
- **拖拽排序**：在 Touch Bar 上长按服务卡片，左右拖动并松开，即可保存新的显示顺序。
- **展开详情**：点击服务卡片可以展开或折叠更多用量细节。
- **OpenRouter 密钥管理**：可以在菜单中保存、清除 OpenRouter API Key，或打开 OpenRouter 密钥页面。
- **开机登录启动**：安装脚本会创建 LaunchAgent，登录 macOS 后自动启动 TokenBar。
- **本地优先的隐私模型**：复用本机已有登录状态和 Keychain，不在仓库中内置任何密钥。

## 支持的服务

| 服务 | 展示内容 | 数据来源 | 说明 |
|---|---|---|---|
| Codex | 5 小时和每周限额窗口 | 本地 Codex app server：`/Applications/Codex.app/Contents/Resources/codex app-server` | 需要安装并登录 Codex.app。 |
| Claude | 5 小时和 7 天用量 | macOS Keychain 中的 Claude Code OAuth 凭据，失败时使用本地日志估算 | OAuth 刷新需要 `CLAUDE_OAUTH_CLIENT_ID`。 |
| Gemini | 每日请求数估算 | `~/.gemini/tmp` 下的 Gemini CLI 本地日志 | Gemini CLI 日志不提供官方服务端限额窗口，因此这里是本地估算。 |
| Cursor | 总用量，以及 API/Auto 模型拆分 | Cursor 本地 `state.vscdb` 会话令牌和 Cursor 后台 API | 需要安装并登录 Cursor。 |
| Antigravity | 5 小时和每周限额桶 | 本地 Antigravity language server 运行时 API | 需要 Antigravity 正在运行。 |
| OpenRouter | 总消费/credits 用量 | OpenRouter credits API | API Key 可通过菜单保存到 Keychain，也可通过环境变量提供。 |
| WorkBuddy | 剩余 credits 和周期重置时间 | 本地 WorkBuddy/CodeBuddy auth 文件和腾讯 WorkBuddy 计费 API | 支持个人和企业用量返回。 |

## 系统要求

- macOS 13 Ventura 或更新版本
- Swift 6 工具链
- 如果需要完整 Touch Bar 体验，需要带 Touch Bar 的 Mac
- 可选：你希望监控的对应服务 App 或 CLI

TokenBar 同时提供菜单栏入口，因此没有实体 Touch Bar 的 Mac 也可以运行。

## 构建和安装

运行安装脚本：

```bash
./scripts/build-and-run.sh
```

脚本会执行以下操作：

1. 使用 Swift Package Manager 构建 release 二进制。
2. 打包 `TokenBar.app`。
3. 对 app bundle 做 ad-hoc 签名。
4. 安装到 `~/Applications/TokenBar.app`。
5. 创建 `~/Library/LaunchAgents/local.tokenbar.plist`。
6. 加载 LaunchAgent 并启动 TokenBar。

## 手动构建

```bash
swift build -c release
.build/release/tokenbar
```

手动运行适合开发调试，但不会创建 app bundle 或登录启动项。

## 使用说明

TokenBar 运行后，可以通过菜单栏入口操作：

- **Refresh**：刷新所有可见服务的用量。
- **Show Touch Bar**：显示 TokenBar 的 Touch Bar 控件。
- **Settings -> Show Provider**：显示或隐藏指定服务。至少必须保留一个服务。
- **Settings -> OpenRouter API Key...**：把 OpenRouter API Key 保存到 macOS Keychain。
- **Settings -> Open OpenRouter Keys Page**：打开 OpenRouter 密钥管理页面。
- **Settings -> Clear OpenRouter API Key**：从 Keychain 删除已保存的 OpenRouter API Key。
- **Settings -> Reset to Codex + Claude**：恢复默认布局。
- **Quit**：退出 TokenBar。

Touch Bar 操作：

- 点击服务卡片：展开或折叠详情。
- 长按并拖动服务卡片：调整服务顺序。
- 点击刷新项：立即刷新用量。

## 凭据和配置

TokenBar 不包含任何服务密钥。它只读取你 Mac 上已经存在的登录状态，或者你明确提供的环境变量。

| 名称 | 用于 | 说明 |
|---|---|---|
| `CLAUDE_OAUTH_CLIENT_ID` | Claude 实时 OAuth 刷新 | Claude Code OAuth client ID。请使用 Anthropic 工具链中 Claude Code CLI 的公开 client ID。 |
| `OPENROUTER_API_KEY` | OpenRouter，未保存到 Keychain 时使用 | OpenRouter API Key。日常使用建议通过 TokenBar 菜单保存到 Keychain。 |

OpenRouter Keychain 存储：

- Service：`TokenBar.OpenRouter`
- Account：`apiKey`

Claude Keychain 存储：

- TokenBar 会读取 Claude Code 现有的 `Claude Code-credentials`
- TokenBar 可能会把刷新后的 OAuth token 写回同一个 Keychain 项，以保持 Claude Code 的登录状态可用

## 隐私说明

TokenBar 是本地 macOS 工具，不运行 TokenBar 自有后端，也不会把你的用量数据上传到 TokenBar 自有服务器。

网络请求只会发往当前用量采集器需要访问的服务，例如 Anthropic、Cursor、OpenRouter、腾讯 WorkBuddy，或本机 loopback 服务。本地会话文件和 Keychain 凭据保留在你的 Mac 上。

## 常见问题

| 现象 | 可能原因 | 处理方式 |
|---|---|---|
| `Codex CLI not found` | `/Applications` 中没有 Codex.app | 安装 Codex.app 并登录。 |
| `Set CLAUDE_OAUTH_CLIENT_ID for Claude usage` | Claude OAuth 刷新缺少 client ID | 启动 TokenBar 前设置 `CLAUDE_OAUTH_CLIENT_ID`，或配置到启动环境中。 |
| `Claude credentials not found` | Claude Code 尚未登录 | 运行 `claude` 并完成登录。 |
| `Gemini CLI not found` | 没有 Gemini 本地日志目录 | 至少运行一次 Gemini CLI。 |
| `Cursor session token not found` | Cursor 未登录或本地数据库不可读 | 打开 Cursor 并登录。 |
| `Antigravity not running` | 本地 language server 未运行 | 先启动 Antigravity，再刷新。 |
| OpenRouter 显示 `Set API key` | 未提供 OpenRouter Key | 使用 Settings -> OpenRouter API Key...，或设置 `OPENROUTER_API_KEY`。 |
| `WorkBuddy login not found` | 缺少 WorkBuddy/CodeBuddy auth 文件 | 登录 WorkBuddy 或 CodeBuddy。 |

## 开发

项目结构：

```text
.
├── Package.swift
├── Info.plist
├── Sources/TokenBar/main.swift
├── Sources/TokenBar/Resources/GeminiIcon.svg
├── scripts/build-and-run.sh
└── LICENSE
```

常用命令：

```bash
swift build
swift build -c release
swift run tokenbar
```

`.build/`、`TokenBar.app/`、`.omc/`、`card-preview/` 和本地 Claude 数据等生成内容已通过 `.gitignore` 排除。

## 安全说明

TokenBar 的设计目标是在你自己的 Mac 上运行，并复用你已经掌控的本地登录状态。它不会要求你把服务商凭据写进源码。

日常使用时：

- OpenRouter API Key 建议通过应用菜单保存到 macOS Keychain。
- 各服务 App 或 CLI 建议通过官方登录流程保持登录。
- 本地 AI 工具日志可能包含 prompt、文件路径或项目上下文，请按私密数据处理。
- 启用某个采集器前，可以先查看上方服务表格中的网络访问和数据来源说明。

如果你 fork 或本地修改项目，请不要提交：

- 服务商 API Key。
- OAuth access token 或 refresh token。
- macOS Keychain 导出。
- 包含私密 prompt 或工作区上下文的本地 AI 工具日志。
- 构建产物、app bundle、生成预览或调试输出。

## 许可证

MIT。详见 [LICENSE](LICENSE)。
