# AGENTS.md

本文件为在本仓库中工作的 LLM 提供指引。

> **AI 贡献限制已解除**（2026-08-26 按用户要求）。AI 可按用户要求生成任意规模代码改动，不再仅限于 bug fix / very small / prove expertise。

## 仓库布局

这是一个多语言 monorepo：一个 Flutter 应用构建在 Rust 协议实现之上。

| 路径 | 说明 |
|------|------|
| `app/` | Flutter 应用（`localsend_app`）。UI、providers、持久化、平台通道。 |
| `packages/localsend_isolates/` | Dart isolate 层 + `flutter_rust_bridge` (FRB) 绑定。包含 `rust/`（Flutter 插件 crate `rust_lib_localsend_app`）和 `rust_builder/`（cargokit）。 |
| `packages/core/` | Rust crate `localsend`：协议、HTTP 服务端/客户端、加密、WebRTC。不依赖 Flutter。 |
| `packages/typed_isolates/` | 独立的小型包，用类型化 send/recv 通道包装 Dart `Isolate`。 |
| `server/` | 用于 WebRTC 的 Axum WebSocket 信令服务器（`/v1/ws`）。单独部署，见 `server/Dockerfile`。 |
| `cli/` | Rust CLI crate（`localsend-cli`）：基于 `packages/core`（v2 HTTP + multicast）的交互式终端客户端。 |
| `support/scripts/` | 发布/打包脚本（各平台构建、MSIX、Inno Setup、FOSS 剥离）。 |

四个 Rust crate（`packages/core`、`packages/localsend_isolates/rust`、`server`、`cli`）构成一个以仓库根目录为根的 Cargo workspace：共享 `Cargo.lock` 和 `target/`，`[profile.*]` 设置仅存在于根 `Cargo.toml`（成员 profile 会被忽略）。Cargokit 在 Flutter 构建期间仍会将插件 crate 构建到自己的 target 目录。

三个 Dart 包（`app`、`packages/localsend_isolates`、`packages/typed_isolates`）构成一个以仓库根目录为根的 pub workspace：共享 `pubspec.lock` 和 `.dart_tool/`，从任一成员运行 `pub get` 即可解析。`rust_builder` 和内嵌的 `cargokit/build_tool` 被刻意排除在成员之外，仍独立解析。

依赖方向：`app` → `localsend_isolates` → （`typed_isolates`，`rust_lib_localsend_app` → `localsend` core）。
应用 **只** 依赖 `localsend_isolates` —— 而不直接依赖 `flutter_rust_bridge`、`typed_isolates` 或插件 crate。

## Flutter 版本

固定为 `.fvmrc` 中的版本（同样镜像到 `.github/workflows/ci.yml` 和 `app/pubspec.yaml`，以及 `support/submodules/flutter` git 子模块）。请使用 **`fvm flutter` / `fvm dart`** 替代系统级工具链。
升级版本需要同步修改这四处 —— 见 `CONTRIBUTING.md` 的 "Bump Flutter" 章节。

## 命令

## Platform detection

Use `Theme.of(context).platform` for platform-specific styling in Material widgets, and `defaultTargetPlatform` for platform behavior in lower layers. Use `dart:io.Platform` for OS-specific native APIs: with the `FLUTTER_TEST` environment variable and assertions enabled, `defaultTargetPlatform` is set to Android regardless of the actual OS (unless `debugDefaultTargetPlatformOverride` is set).

## Commands

Run from `app/` unless stated otherwise (从 `app/` 目录运行，除非另有说明).

```bash
fvm flutter pub get
fvm dart run build_runner build  # dart_mappable、freezed、flutter_gen、mockito
fvm dart run slang               # i18n 代码生成（slang_build_runner 在 build.yaml 中已禁用）
fvm flutter run
```

检查（CI 运行的）：

```bash
fvm dart format --set-exit-if-changed lib test   # CI 会先删除 lib/gen；生成代码不参与格式检查
fvm flutter analyze
fvm flutter test
fvm flutter test test/unit/util/security_helper_test.dart          # 单个文件
fvm flutter test --plain-name 'some test name'                     # 单个测试
```

格式化为 **150 列**（`analysis_options.yaml` 中 `page_width: 150`，`trailing_commas: preserve`）。任何以 80 列重新格式化生成代码的工具都会产生纯噪声 —— 之后用 `fvm dart format` 重新格式化。

Rust：

```bash
cargo test --features full       # 在 packages/core — 见下方 "Core crate features"
cargo clippy --features full
cargo check                      # 在 packages/localsend_isolates/rust、server、cli
```

FRB 代码生成 —— 从 `packages/localsend_isolates/` 运行：

```bash
flutter_rust_bridge_codegen generate    # 配置在 flutter_rust_bridge.yaml（dart_format_line_length: 150）
```

代码生成有个习惯，会以 80 列重写 `app/test/mocks.mocks.dart`；如果该文件出现在 diff 中请回退。

`packages/localsend_isolates` 有自己的 `build.yaml`，在其 models 变更时需要单独运行 `build_runner`（`pub get` 通过 pub workspace 共享）。CI 还会额外在 `packages/localsend_isolates/rust_builder/cargokit/build_tool` 中运行 `flutter pub get`。

## Core crate features

`packages/core` 几乎所有内容都通过 Cargo features（`crypto`、`http`、`multicast`、`webrtc`、`webrtc-signaling`、`full`）门控，且 `default = []`。**始终使用 `--features full` 来构建和测试。** 裸跑 `cargo check`/`cargo build` 会失败，因为模块是无条件声明的，而它们的依赖是可选的 —— 这是先存在的预期行为，不是回归。

## 架构

### 状态管理

使用 Refena（`refena_flutter`），而非 Riverpod。Providers 位于 `app/lib/provider/`；普通状态用 `NotifierProvider`，任何涉及 isolate 层的内容用 `ReduxProvider` + 分发的 action 类。`app/lib/config/init.dart`（`preInit`）是引导入口：初始化日志、`RustLib.init()`、持久化、isolate 容器、托盘/窗口，并返回 `main.dart` 挂载的 `RefenaContainer`。

Models 使用 `dart_mappable`（`@MappableClass`，`.mapper.dart` parts）并重命名方法 —— `fromJson`/`toJson` 是 **Map** 转换器，`deserialize`/`serialize` 是字符串版本（在两个 `build.yaml` 中配置）。FRB 相关的 union 使用 Freezed。

### Isolates

繁重的网络任务永远不在主 isolate 上运行。`packages/localsend_isolates/lib/src/isolate/`：

- `parent/parent_isolate_provider.dart` —— `ParentIsolateState` 为每个子 isolate 持有一个 `IsolateConnector`（http 扫描发现、multicast 发现、http 上传、http 服务端）外加一个被镜像到所有子 isolate 的 `SyncState`。`IsolateSetupAction` 用于生成它们。
- `parent/actions.dart`、`parent/actions_sync.dart` —— 应用与子 isolate 通信的唯一受支持方式。
- `child/*_isolate.dart` —— 子 isolate 入口；将类型化的任务消息转换为对 `lib/src/task/` 的调用。
- `lib/src/task/` —— 仅存放纯辅助函数；**该处禁止 isolate 逻辑**（见其 `README.md`）。

子 isolate 所需的状态（alias、port、protocol、服务端是否运行、web send 是否开启）通过 `IsolateSyncServerStateAction` 推送。子 isolate 在启动时读取 `syncState`，因此同步操作必须在启动服务端 **之前** 完成。

### 网络（Rust）

HTTP 服务端和客户端是 Rust 而非 Dart。`packages/core/src/http/server/` 实现 v2 协议（不提供 v1 端点）外加 "web send" 下载流程（`server/web.rs`）和一个用于前置已运行实例的内部 `show` 端点。

集成基于 channel：`start_with_port` 接收 `ServerConfigV2 { pin, event_tx, web_send }` 并发出 `ServerEventV2` 事件（`Register`、`PrepareUpload` 带 `decision_tx` oneshot、`FileUpload` 带字节流 + `result_tx`、`PrepareDownload`、`SessionEnd`、`PrepareUploadAborted`、`CancelReceived`）。**同时只有一个上传会话处于活动状态**；取消安全由 drop guard（`PendingSessionGuard`、`UploadGuard`、`PendingWebSessionGuard`）保证。core 中刻意没有 `auto_accept` —— 应用通过立即回答 `decision_tx` 来实现自动接受。新的 server→app 交互应当扩展 `ServerEventV2`，而不是新增旁路 channel。

FRB 层（`packages/localsend_isolates/rust/src/api/server.rs`）暴露 `start_server` + 一个不透明的 `RsHttpServer`，其 `listen` 将 v2、web-send 和内部 channel 合并为一个 `RsServerEvent` 流；oneshot 响应者保留在 Rust 端。在 Dart 端 `child/server_isolate.dart` 将其转换为 `HttpServerEvent`，由 `app/lib/provider/network/server/server_provider.dart` 路由到 `ReceiveController` / `SendController` —— 这些是 **事件处理器，而非路由处理器**。

保存目标在 Dart 端决定（`prepareFileSaveTarget`），由 Rust 端写入：一个路径，或通过 `org.localsend.localsend_app/localsend` 方法通道获取的 Android SAF 文件描述符。相册保存先经过缓存文件。

Server event 的 `ip` 是 `PeerIp`（IP + IPv6 scope）：link-local peer 渲染为 `fe80::1%3`，HTTP 客户端可将其作为 host 接受回来，因此 event ip 保持可拨号。

TLS 使用按设备即时生成证书，并 **强制要求客户端证书**（在提供网页时为可选，以便浏览器可连接）；peer 身份为客户端证书 DER 的 SHA-256 的大写十六进制，当 payload 声称的 fingerprint 与证书不一致时，`Register` 将直接不发出。优先使用 `event.certFingerprint ?? event.info.fingerprint` —— payload 兜底仅在加密关闭模式下存在。

接收 PIN 和 web-send PIN 都在服务端启动时固定，因此修改任一项都会重启服务端。

浏览器下载页的 Web 资源内嵌自 `packages/core/assets/web/`。

### Multicast 发现（Rust）

`packages/core/src/multicast/`（feature `multicast`，独立于 `http`）为协议 v2.2 实现 UDP multicast 发现 —— 不解析 v1 消息。
集成方式与 HTTP 服务端一致：`multicast::start` 接收 `MulticastConfig { group, group_v6, port, interface_filter, device, event_tx }` 并发出 `MulticastEvent::Discovered { ip, message }`；返回的 `MulticastHandle` 提供 `announce`（广播突发）和 `wait_stopped`。

UDP 是 **仅宣告**：响应通过 HTTP 以单播 register 请求回送到宣告设备。

每个接口的 IPv4 地址绑定一个 socket（`SO_REUSEPORT`/`SO_REUSEADDR` + `IP_MULTICAST_IF`），因为单个 socket 只能从一个接口发送。Multicast loopback 保持开启，以便同一主机的实例互相可见；自己发出的消息通过 fingerprint 丢弃。IPv6 是 LocalSend 扩展（组 `ff12::fd3a:e420`，`DEFAULT_MULTICAST_GROUP_V6`），通过设置 `group_v6` 启用：每个接口一个 `IPV6_V6ONLY` socket，按接口索引加入。`Discovered` 携带源的 scope ID（接口索引），link-local IPv6 源在进行 HTTP 应答时需要它。

### i18n

使用 Slang，源文件位于 `app/assets/i18n/`（`<locale>.json` 外加 `_missing_translations_<locale>.json`），生成输出位于 `app/lib/gen/`。翻译在 Weblate 上管理；以 `@` 为前缀的字段是给译者的元数据，应用不使用。`app/test/unit/i18n_test.dart` 守护 locale 集合。

### FOSS 构建

`in_app_purchase` 和捐赠 UI 在 F-Droid 中被 `support/scripts/remove_proprietary_dependencies.sh` 剥离，该脚本依赖 `# [FOSS_REMOVE]` pubspec 标记和 `// [FOSS_REMOVE_START]` / `// [FOSS_REMOVE_END]` 注释对。在编辑 `lib/config/init.dart`、`lib/pages/donation/*` 或 `lib/provider/purchase_provider.dart` 时请保留这些标记。

## Release notes

`app/pubspec.yaml` 中的版本必须与 `support/scripts/compile_windows_exe-inno.iss` 中 `#define MyAppVersion` 以及 `cli/Cargo.toml` 中的 `version`（CLI 会在启动横幅中打印）一致 —— CI 在不匹配时会失败。各平台构建命令和发布步骤记录在 `README.md`（"Building"）和 `CONTRIBUTING.md`（"Release"）中。
