# Docker Events 实时监听实施计划

## 问题

容器/镜像/网络/卷在外部（CLI、其他工具）发生变化时，UI 列表不会主动刷新，
必须切换 Tab 触发 `.task(id:)` 重新加载才能看到最新状态。

## 根因分析

| 触发方式 | 现状 | 问题 |
|---|---|---|
| `.task(id: docker != nil)` | 仅在 docker 客户端实例变化时触发 | 切换 Tab 才会重建视图 |
| `.onReceive(.dockerDataChanged)` | 仅在 App 内部删除容器时 post | start/stop 不 post；外部变更完全无感知 |
| Docker `/events` 流 | **未使用** | — |

## 设计决策

### D1: 跨资源刷新策略

容器事件（create/destroy）会影响镜像引用计数、网络连接列表、卷挂载状态。
因此容器事件必须同时通知其他资源类型刷新。

方案：**保留 `.dockerDataChanged` 作为兜底广播**。
- 细分通知 `.dockerContainerChanged` 等用于"精确命中"的资源类型
- 容器的 create/destroy 事件额外 post `.dockerDataChanged`，驱动非容器页面刷新
- **容器页面只监听 `.dockerContainerChanged`**，避免双刷新
- 其他页面（Images/Networks/Volumes）监听自己的细分通知 + `.dockerDataChanged`

### D2: 冷启动 & daemon 恢复时序

当前 `dockerClient` 只在 nil 时创建，daemon 停止后不会置空。
所以不能用 `.onChange(of: dockerClient)` — daemon 恢复时它不变。

方案：**Monitor 的启停统一由 `daemonManager.state` 驱动**。
在 `.onChange(of: daemonManager.state)` 中：
- `isRunning == true` → `initClientsIfNeeded()` 后调用 `eventMonitor.start(docker:)`
- `isRunning == false` → `eventMonitor.stop()`

`start()` 内部幂等：若已在运行则先 cancel 旧 task 再重建。
这样冷启动（首次 running）和 daemon 恢复（再次 running）走同一条路径。

### D3: Daemon 停止时的行为

Daemon 停止后 events 流会断开，Monitor 不应无意义重连。

方案：**Monitor 感知 daemon 状态**。
- `daemonManager.state.isRunning == false` 时主动 stop，不再重连
- Daemon 恢复 running 时由 `.onChange` 重新 start
- 内部用 `isStopped: Bool` 区分"主动停止"和"意外断开"：
  - `stop()` 设 `isStopped = true`，重连循环检查此标志
  - `start()` 重置 `isStopped = false`

### D4: Action 白名单

不是所有 Docker 事件都需要触发 UI 刷新。无白名单 → 高频无效刷新。

方案：**每个资源类型维护独立的 action 白名单**：
```
container: start, stop, die, kill, pause, unpause, create, destroy, rename, update
image:     pull, push, delete, tag, untag, import, load, save
network:   create, connect, disconnect, destroy, remove
volume:    create, destroy, mount, unmount
```
白名单外的事件静默丢弃。

## 架构设计

```
DockerClient.streamEvents()          ← 已实现 ✅
        │
        ▼
DockerEventMonitor (新增)             ← App 级，生命周期跟 App 一致
        │
        │  action 白名单过滤
        │  300ms debounce (per-type)
        │
        ├─ post(.dockerContainerChanged)
        │      └─ create/destroy 额外 post(.dockerDataChanged)  ← 跨资源兜底
        ├─ post(.dockerImageChanged)
        ├─ post(.dockerNetworkChanged)
        └─ post(.dockerVolumeChanged)

各 ListView:
  ContainersListView:
    .onReceive(.dockerContainerChanged)  ← 只监听细分通知，不监听 dockerDataChanged
  ImagesListView / NetworksListView / VolumesListView:
    .onReceive(.docker<Type>Changed)     ← 精确命中
    .onReceive(.dockerDataChanged)       ← 跨资源兜底（容器 create/destroy 触发）
```

**为什么不放在 ContainersViewModel 里？**
- Events 流是全局的，一个连接能收到所有资源类型事件
- 放在某个 ViewModel 里意味着切走该 Tab 后就断开
- App 级管理 = 一条连接覆盖所有资源类型

## 实施步骤

### Phase 1: DockerEventMonitor — App 级事件中枢

**文件**: `arcbox-desktop-swift/Services/DockerEventMonitor.swift` (新增)

```swift
@MainActor
@Observable
final class DockerEventMonitor {
    private var task: Task<Void, Never>?

    func start(docker: DockerClient) { ... }
    func stop() { ... }
}
```

关键实现细节：
- 按 `event.type` + action 白名单过滤无效事件
- 按 type 独立 debounce（容器连续事件不应延迟镜像通知）
- 断线重连：仅当未被 `stop()` 且未被 cancel 时才重连
- 内部用 `isStopped: Bool` 区分"主动停止"和"意外断开"

### Phase 2: Notification 名称定义

**文件**: `Services/DockerEventMonitor.swift` (同文件)

```swift
extension Notification.Name {
    static let dockerContainerChanged = Notification.Name("dockerContainerChanged")
    static let dockerImageChanged     = Notification.Name("dockerImageChanged")
    static let dockerNetworkChanged   = Notification.Name("dockerNetworkChanged")
    static let dockerVolumeChanged    = Notification.Name("dockerVolumeChanged")
    // .dockerDataChanged 保留，定义不动
}
```

### Phase 3: App 入口集成

**文件**: `arcbox_desktop_swiftApp.swift` (修改)
**文件**: `AppDelegate` (修改)

```swift
@State private var eventMonitor = DockerEventMonitor()

// AppDelegate 需要持有 eventMonitor 引用（与 daemonManager 同模式）
class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?
    var eventMonitor: DockerEventMonitor?   // ← 新增

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        eventMonitor?.stop()                // ← 新增
        // ... 现有 daemonManager 逻辑
    }
}

// .task 中注入:
appDelegate.eventMonitor = eventMonitor

// 启停统一由 daemonManager.state 驱动:
.onChange(of: daemonManager.state) { _, newState in
    if newState.isRunning {
        initClientsIfNeeded()
        // dockerClient 此时一定非 nil（initClientsIfNeeded 刚创建/已存在）
        eventMonitor.start(docker: dockerClient!)
    } else {
        eventMonitor.stop()
    }
}
```

生命周期状态机：
```
App 启动 → .task → initClientsIfNeeded() → dockerClient 就绪
                 ↘
         .onChange(daemon: running) → initClientsIfNeeded() → Monitor.start(docker:)
                                                                    │
         .onChange(daemon: !running) ─────────────────────────→ Monitor.stop()
                                                                    │
         .onChange(daemon: running again) → initClientsIfNeeded() → Monitor.start(docker:)
                                                                    │ (幂等：cancel 旧 task + 新建)
         App 退出 → AppDelegate.applicationShouldTerminate ──→ Monitor.stop()
```

### Phase 4: 各 ListView 接入

每个 ListView 的监听策略：
- **ContainersListView**: 只监听 `.dockerContainerChanged`（不监听 `.dockerDataChanged`，避免双刷新）
- **其他 ListView**: 监听自己的细分通知 + `.dockerDataChanged` 兜底

| 文件 | 改动 |
|---|---|
| `ContainersListView.swift` | 只监听 `.dockerContainerChanged`（替换 `.dockerDataChanged`） |
| `ImagesListView.swift` | `.onReceive(.dockerImageChanged)` + 保留 `.dockerDataChanged` |
| `NetworksListView.swift` | `.onReceive(.dockerNetworkChanged)` + 保留 `.dockerDataChanged` |
| `VolumesListView.swift` | `.onReceive(.dockerVolumeChanged)` + 保留 `.dockerDataChanged` |

### Phase 5: 清理

- 删除 `ContainersViewModel` 中的 `eventsTask` / `startEventMonitoring()` / `stopEventMonitoring()`
- 删除 `ContainersListView` 中的 `.onDisappear { vm.stopEventMonitoring() }`
- 删除各 ViewModel 中手动 `post(.dockerDataChanged)` 的调用
  - **仅删除 events 会自动覆盖的场景**
  - 保留 `removeContainerDocker` 里的 post（因为删除后需要立即刷新，不能等 300ms debounce）
  - **已知 tradeoff**: destroy 事件会再触发一次其他列表刷新（即时 post + events 广播 = 双刷新），
    这是性能换时效的可接受代价

## 文件变更清单

| 文件 | 动作 |
|---|---|
| `Packages/DockerClient/.../DockerClient.swift` | 无变更（`streamEvents()` 已实现 ✅） |
| `Services/DockerEventMonitor.swift` | **新增** — App 级事件监听器 |
| `Services/DockerEventMonitorTests.swift` | **新增** — 单元测试 |
| `arcbox_desktop_swiftApp.swift` | **修改** — 初始化 & 生命周期管理 |
| `ViewModels/ContainersViewModel.swift` | **修改** — 删除 events 代码，保留 `.dockerDataChanged` 定义 |
| `Views/Containers/ContainersListView.swift` | **修改** — 接入新通知，移除旧 Monitor 调用 |
| `Views/Images/ImagesListView.swift` | **修改** — 新增 `.dockerImageChanged` |
| `Views/Networks/NetworksListView.swift` | **修改** — 新增 `.dockerNetworkChanged` |
| `Views/Volumes/VolumesListView.swift` | **修改** — 新增 `.dockerVolumeChanged` |

## 验证方式

### 自动化测试（DockerEventMonitorTests）

| 测试用例 | 验证点 |
|---|---|
| `test_containerStartEvent_postsContainerChanged` | container/start → 只 post `.dockerContainerChanged`，不 post `.dockerDataChanged` |
| `test_containerDestroyEvent_postsBothNotifications` | container/destroy → post `.dockerContainerChanged` + `.dockerDataChanged` |
| `test_imageDeleteEvent_postsImageChanged` | image/delete → 只 post `.dockerImageChanged` |
| `test_unknownAction_isFiltered` | container/exec_start → 不 post 任何通知 |
| `test_unknownType_isFiltered` | daemon/reload → 不 post 任何通知 |
| `test_debounce_coalesces_rapidEvents` | 连续 3 个 container 事件（间隔 < 300ms）→ 只触发 1 次 post |
| `test_stop_preventsReconnect` | `stop()` 后流断开 → 不再重连，task 终止 |
| `test_start_afterStop_reconnects` | `stop()` → `start()` → 新事件正常分发 |
| `test_start_isIdempotent` | 连续调用 `start()` 两次 → 只有一个活跃 task |

测试策略：注入 mock `AsyncThrowingStream<DockerEvent>` 替代真实 Docker socket，
通过 `NotificationCenter` observer 断言通知发送。

### 手工验证

1. **冷启动**: App 启动 → Xcode console 应显示 `[EventMonitor] started` → 无 crash/空指针
2. **容器事件**: 终端 `docker run -d nginx` → 容器列表 < 1s 出现新行
3. **容器停止**: 终端 `docker stop <id>` → 状态即时变为 Stopped
4. **跨资源联动**: 终端 `docker rm -f <id>` → 容器列表更新，Networks/Volumes 也刷新
5. **镜像事件**: 终端 `docker rmi <image>` → Images 列表自动移除
6. **Debounce**: 快速 `docker stop a && docker stop b` → 只触发一次刷新
7. **Daemon 停止**: 停掉 daemon → Monitor 停止，console 无重连日志
8. **Daemon 恢复**: 重启 daemon → Monitor 自动恢复，事件流重新连接
9. **Action 过滤**: `docker exec <id> ls`（exec 不在白名单）→ 不触发刷新
