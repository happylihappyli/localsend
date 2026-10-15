# LocalSend 局域网目录同步 — 设计 Spec

> 状态：草案 v0.1
> 适用：LocalSend 1.18.2+
> 范围：在现有 v2 协议之上加一层「目录同步」能力，不破坏现有 file send/receive。

---

## 1. 概览

**目标**：让 A 用户把本地某个目录标记为「共享」，B 用户能浏览这个目录、勾选子集、和 A 保持一致；冲突时让用户解决。

**非目标**（v1 不做）：

- 多向同步（>2 端） — 留给 v2
- 删除传播（v1 只下/上，不自动删 B 端文件）
- 软链接 / 硬链接处理
- 压缩传输（v1 走裸 HTTP，复用 v2 的 chunked）
- 跨设备权限管理

**复用现有**：

- v2 协议的 TLS + 客户端证书（fingerprint 即身份）
- `ServerEventV2` 作为 Rust → Dart 事件通道
- `HttpClient` Rust 客户端（B 端发起同步）
- `Register` 消息加一个字段 `sync_shares`，让 B 端无主动询问就知道 A 共享了什么

---

## 2. 用户故事

### A 端（共享方）

1. 设置页 → 「共享目录」 → 选本地目录（picker）
2. 编辑排除规则（gitignore 风格）：`bak/**`, `*.tmp`, `/build/**`
3. 确认 → 状态栏显示「正在共享 dir1 (3 个排除规则)」
4. 别的用户选我时，能看到我共享了 `dir1`（在弹窗里）

### B 端（接收方）

1. 选设备时，看到 A 标了「共享目录 dir1」→ 点「浏览」
2. 弹出树视图（懒加载）：A 端目录结构，可勾选子目录/文件
3. 确认 → 进度条：`待下 12，待上 3，跳过 200，冲突 1`
4. 完成 → 弹结果：可一键看「冲突解决」
5. 冲突项：弹窗选 [保留本地] / [保留远端] / [两个都留] / [跳过]

---

## 3. 协议

### 3.1 v2 协议扩展（不破坏）

`Register` 消息加 `sync_shares` 字段：

```json
{
  "alias": "alice-laptop",
  "version": "2.2",
  "deviceModel": "...",
  "deviceType": "desktop",
  "fingerprint": "ABC123...",
  "port": 53317,
  "syncShares": [
    {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "name": "dir1",
      "excludeCount": 3,
      "fileCount": 1247,
      "totalSize": 524288000
    }
  ]
}
```

> 字段可空；不填 = 旧客户端忽略。v1 服务器看 `syncShares` 字段缺失时返回 200 视为不支持，兼容。

### 3.2 同步协议端点

服务器在 `http/server/sync.rs` 实现：

| Method | Path | 用途 |
|--------|------|------|
| `GET` | `/sync/{share_id}/manifest` | A 端返回当前 manifest |
| `GET` | `/sync/{share_id}/tree?path=/` | A 端返回目录树（懒加载 B 端浏览用） |
| `POST` | `/sync/{share_id}/plan` | B 端提交本地 manifest → A 返回 plan |
| `GET` | `/sync/{share_id}/file?path=...&sha256=...` | B 端下文件（断点续传） |
| `PUT` | `/sync/{share_id}/file?path=...` | B 端上文件（v1 暂缓，可选） |

**所有端点**：
- 走 v2 TLS（必须客户端证书）
- 路径校验：禁止 `..`、禁止 absolute path（相对 share root）
- 命中排除规则的 path → 403

### 3.3 Manifest 格式

```json
{
  "version": 1,
  "root": "/home/alice/dir1",
  "generatedAt": "2026-08-26T10:00:00Z",
  "excludes": ["bak/**", "*.tmp", "/build/**"],
  "entries": [
    {
      "path": "subdir/file.txt",
      "size": 1234,
      "mtimeUnix": 1693000000,
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "mode": 33188
    }
  ]
}
```

**注意**：
- `path` 用 `/` 分隔，相对 root
- `sha256` 16 进制小写
- `entries` 字典序排序（diff 时方便 merge）
- 大目录分块：entries 数组按目录前缀分片，每片 ≤ 1000 项，文件名 `manifest-000.json`, `manifest-001.json` + `manifest-index.json`

### 3.4 Plan 格式

B 端 POST 本地 manifest，A 端 diff 后返回：

```json
{
  "version": 1,
  "generatedAt": "...",
  "downloads": [
    {"path": "x.txt", "size": 100, "sha256": "..."}
  ],
  "uploads": [
    {"path": "y.txt", "size": 50, "sha256": "..."}
  ],
  "conflicts": [
    {
      "path": "z.txt",
      "localMtime": 1693000000,
      "localSha256": "aaa",
      "remoteMtime": 1693000100,
      "remoteSha256": "bbb"
    }
  ],
  "skips": [
    {"path": "w.txt", "reason": "unchanged"}
  ]
}
```

---

## 4. Diff 算法

输入：manifest_remote（A 端）, manifest_local（B 端）, sync_state.last_synced（B 端持久化的上次状态）

```
for entry in manifest_remote.entries:
    local = manifest_local.find(entry.path)
    if local is None:
        if sync_state.last_synced.has(entry.path):
            # 之前同步过，但本地被删了 → 不删（v1 保守），跳过
            skip("locally-deleted", entry)
        else:
            download(entry)
    elif local.sha256 == entry.sha256:
        if local.mtimeUnix == entry.mtimeUnix:
            skip("unchanged", entry)
        else:
            # mtime 不同但 sha256 相同：内容相同，只是 touch 过
            skip("touch-only", entry)
    else:
        # sha256 不同：冲突
        if local.mtimeUnix > entry.mtimeUnix:
            # 本地更新：理论上 B 端想上
            upload(local)  # 或标 conflict 由 UI 决定
        else:
            conflict(local, entry)

for entry in manifest_local.entries:
    if not manifest_remote.has(entry.path):
        if sync_state.last_synced.has(entry.path):
            skip("remotely-deleted", entry)  # v1 不删本地
        else:
            # 本地新建，且 A 端从未有过 → 上传给 A
            upload(entry)
```

**冲突定义**：双方 sha256 不同 + 双方 mtime 都在 sync_state.last_sync_at 之后。

**v1 策略**：冲突默认标 conflict，由 UI 解决；不自动选边。

---

## 5. 排除规则

gitignore 风格（**部分子集**，足够常用即可）：

| 语法 | 含义 |
|------|------|
| `bak/**` | bak 目录下所有 |
| `*.tmp` | 所有 .tmp 文件 |
| `/build/**` | 仅 root 下的 build 目录 |
| `**/node_modules/**` | 任意层级的 node_modules |
| `!.gitkeep` | 反向（gitignore 兼容） |

**实现**：
- Rust：`globset` crate
- Dart：`glob` package
- 共享时 A 端预编译 exclude 集合，diff 时不再重算

**安全**：
- 路径规范化后匹配
- `..` 直接拒绝
- 规则里禁止反斜杠（统一 `/`）

---

## 6. 持久化

### A 端：共享元数据

位置：`$LOCAL_DATA_DIR/sync-shares.json`（Linux: `~/.local/share/localsend/sync-shares.json`）

```json
{
  "shares": [
    {
      "id": "uuid-v4",
      "name": "dir1",
      "root": "/home/alice/dir1",
      "excludes": ["bak/**"],
      "createdAt": "...",
      "enabled": true
    }
  ]
}
```

### B 端：sync 状态

位置：`<本地副本根>/.localsend-sync/<sync_id>.json`

```json
{
  "peerFingerprint": "ABC123...",
  "shareName": "dir1",
  "root": "/home/bob/mirror",
  "lastSyncAt": "...",
  "lastRemoteManifestHash": "...",
  "localOverrides": {
    "skipped": ["path/to/skip"],
    "resolved": {"conflict.txt": "local-kept"}
  }
}
```

`.localsend-sync/` 不参与同步（manifest 计算时排除 `.localsend-sync/**`）。

---

## 7. 状态机

### Sync session 生命周期

```
Idle
  │ B 端点击「同步」
  ▼
FetchingManifest (GET /manifest)
  │ 成功
  ▼
BuildingLocalManifest (B 端 walkdir)
  │ 成功
  ▼
SubmittingPlan (POST /plan)
  │ 成功 → 拿到 plan
  ▼
TransferringFiles
  │ N 个文件进度
  ▼
ResolvingConflicts (有冲突时)
  │ 用户逐个解决
  ▼
WritingSyncState (写 .localsend-sync/<id>.json)
  │ 成功
  ▼
Done
```

**取消**：任何阶段可取消；已下载的文件保留；状态写 partial。

---

## 8. 模块划分

### Rust（`packages/core/src/sync/`）

| 文件 | 职责 |
|------|------|
| `mod.rs` | 公共类型：Manifest, Entry, Plan, Conflict |
| `manifest.rs` | walkdir + sha256 + globset 排除 → Manifest |
| `diff.rs` | Manifest vs Manifest → Plan |
| `state.rs` | SyncState 持久化（serde_json） |
| `http.rs` | HTTP 端点处理（嵌入 `http/server/sync.rs`） |

**入口**：在 `ServerConfigV2` 加 `sync_shares: Vec<SyncShareConfig>`，在 `ServerEventV2` 加：

```rust
pub enum ServerEventV2 {
    // ... 现有 ...
    SyncShareAvailable { share_id: String, name: String, file_count: usize, total_size: u64 },
    SyncProgress { session_id: String, completed: usize, total: usize },
    SyncConflict { session_id: String, path: String, local: Entry, remote: Entry },
    SyncComplete { session_id: String, downloaded: usize, uploaded: usize, conflicts: usize },
}
```

### Dart（`app/lib/provider/sync/`）

| 文件 | 职责 |
|------|------|
| `sync_provider.dart` | Refena ReduxProvider，sync session 状态机 |
| `sync_shares_provider.dart` | A 端共享列表（持久化） |
| `actions.dart` | Redux actions：`StartSync`, `ResolveConflict`, ... |

### UI

| 文件 | 职责 |
|------|------|
| `app/lib/pages/settings_page.dart` | 加「共享目录」入口 |
| `app/lib/pages/dialogs/share_directory_dialog.dart` | A 端：选目录 + 编辑 exclude |
| `app/lib/pages/dialogs/sync_browse_dialog.dart` | B 端：浏览树 + 勾选 |
| `app/lib/pages/dialogs/sync_conflict_dialog.dart` | 冲突解决 UI |
| `app/lib/pages/home_page.dart` | 状态栏显示「正在共享 X」徽章 |

---

## 9. UI 流程

### A 端：「共享目录」按钮

```
[设置页]
  └─ 「共享目录」按钮
       └─ 弹窗:
           [选择目录] [text field: 显示当前路径]
           [编辑排除规则] → 弹大 text area，每行一条
           [保存] [取消]
```

### B 端：设备选择 → 看到共享

```
[主页 → 设备列表]
  └─ alice-laptop  [📁 共享: dir1]   ← 新增徽章
       └─ 点「📁」图标
            └─ 弹树视图:
                ▾ dir1/
                  ▸ src/      [✓ 同步]
                  ▸ docs/     [✓ 同步]
                  ▸ bak/      [☐ 跳过]  ← 命中 exclude
                  ▸ node_modules/ [☐ 跳过]
                [全选] [全不选] [同步所选]
```

### B 端：同步进度

```
[模态]
  正在同步 dir1 from alice-laptop
  ████████░░░░ 67% (8/12)
  下载 8 / 上传 0 / 冲突 1
  
  [取消]
```

### B 端：冲突解决

```
[弹窗]
  冲突: notes.md
  
  本地版本:  2026-08-26 10:00  sha256:aaa  [查看]
  远端版本:  2026-08-26 11:00  sha256:bbb  [查看]
  
  [保留本地] [保留远端] [两个都留] [跳过]
  
  还剩 1 个冲突
```

---

## 10. 安全

- 路径规范化（Rust 端 `path_clean` crate）— 防 `..` 穿越
- 排除规则预编译，禁止 runtime 改
- 客户端证书强制（复用 v2）
- Manifest 体积限制：单片 ≤ 1 MB，总 ≤ 100 MB
- Rate limit：每端点 100 req/s（同 v2）
- B 端写文件前预分配空间（`fallocate`），防磁盘填满攻击

---

## 11. 测试策略

### Rust unit（`packages/core/src/sync/`）

- `manifest.rs`：含/不含排除规则、软链接、大文件、空目录
- `diff.rs`：本地空 / 远端空 / 都有 / 冲突 / 仅 mtime 变 / 删后重建
- `state.rs`：序列化往返
- `http.rs`：路径穿越攻击、排除规则命中、并发请求

### Rust integration（`packages/core/tests/sync_e2e.rs`）

- A 端起 server，B 端起 client，同步一个临时目录
- 注入冲突、注入排除、注入大文件

### Dart widget

- 共享目录弹窗（picker 模拟）
- 树视图勾选交互
- 冲突解决弹窗
- 进度条更新

### 手动测试

- A 端 Linux，B 端 macOS，跨平台
- A 端 Windows，B 端 Android（file mode 处理）
- 10000 文件大目录

---

## 12. 实施阶段（拆 PR）

| PR | 内容 | 估计行数 |
|----|------|----------|
| 1 | Rust `sync/manifest.rs` + `diff.rs` + 单测 | 400 |
| 2 | Rust `http.rs` 端点 + ServerEventV2 扩展 | 300 |
| 3 | Dart `sync_provider.dart` + `sync_shares_provider.dart` | 250 |
| 4 | A 端「共享目录」UI + 持久化 | 200 |
| 5 | B 端「浏览 + 勾选」UI | 300 |
| 6 | B 端「同步进度 + 冲突解决」UI | 350 |
| 7 | 集成测试 + 文档 | 200 |

总 ~2000 行，分 7 个 PR，每个独立可合并。

---

## 13. 开放问题

1. **删除传播**：v1 不删 B 端文件。v2 要不要加「同步删除」开关？
2. **权限**：B 端只读同步，还是能 push 文件回 A 端（双向）？v1 只做下传。
3. **加密**：复用 v2 TLS 还是再加一层？
4. **进度粒度**：每文件进度，还是每 KB？v1 每文件。
5. **断点续传**：大文件下到一半断了怎么办？v1 简单重试；v2 加 Range。

---

## 14. 备选方案

| 方案 | 优劣 |
|------|------|
| **走 v2 文件传输 + manifest 走 HTTP**（推荐） | 复用 TLS + 客户端；与现有架构对齐 |
| 单独开 WebSocket sync channel | 实时性更好，但要多管理一个连接 |
| 用 Syncthing 协议 | 成熟，但依赖重 |
| 用 git 协议 | 太重 |

推荐方案一。
