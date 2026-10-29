# Task

一个用来**看清 Swift Concurrency 中 `Task` 取消机制**的 SwiftUI 演示项目。

📖 在线文档：<https://jeffery812.github.io/Task/>

## 为什么做这个项目

“用户连续触发同一个请求，只保留最新的结果”是 App 里非常常见的需求：搜索框输入、下拉刷新、切换筛选条件、反复点击加载按钮……

用 Swift Concurrency 实现它看起来只需要一行 `previousTask?.cancel()`，但真正写对并不简单：

- **取消是协作式的：** `cancel()` 只是设置一个标记，被取消的任务可能还会继续跑一会儿，甚至照常返回结果。
- **过期结果可能覆盖新状态：** 旧请求晚到的值或错误，不能把新请求的状态冲掉。
- **`await` 之后世界可能已经变了：** MainActor 上的 `async` 函数可以重入，挂起期间别的调用会修改状态。
- **非结构化 `Task` 不会自动跟着调用方取消：** 需要 `withTaskCancellationHandler` 手动转发。
- **`Task { }` 不等于“放到后台”：** 在 MainActor 上下文中，它仍然在主线程执行，需要 `@concurrent` 才会离开主线程。

这些问题在文章里读起来容易，在真实代码里却很难“看见”。本项目的目的，就是**把这些行为放到一个可以亲手操作、可以观察、可以测试的环境里**。

## 怎么做到“看得见”

- **真实请求，人为放慢：** 每次请求先等待 2 秒，再拉取一份约 500 KB 的真实 JSON，留出足够的时间连续点击、取消。
- **实时任务日志：** 每个请求的提交、开始、是否在主线程、取消、完成、失败都带毫秒时间戳记录下来。
- **同一个界面，三种策略：** 只替换 ViewModel，方便对比行为差异。

| Tab | `load()` 签名 | 新请求到来时 |
|---|---|---|
| **Cancel Previous** | `load()` | 取消旧任务，立即开始；调用方不等结果，靠 `state` 驱动 UI |
| **Serial Latest** | `load() async throws -> FetchResult` | 取消旧任务，**等它真正停下**再开始；排队期间被替换的请求从不执行 |
| **Async Latest** | `load() async throws -> FetchResult` | 取消旧任务，立即开始；只有最新的调用方拿到值，其余收到 `CancellationError` |

- **单元测试固化结论：** ViewModel 通过 `init(fetch:)` 注入假请求，用 Swift Testing 验证“只有最新请求生效”“过期结果不覆盖”“调用方取消会传进去”“工作不在主线程”等行为，测试不访问网络。

## 文档

文档通过 GitHub Pages 发布，可以直接在线阅读：

- [项目详解](https://jeffery812.github.io/Task/)（[`index.html`](index.html)）：三种策略的时间线动画、核心代码、项目结构、测试清单。
- [Task 用法手册](https://jeffery812.github.io/Task/TaskGuide.html)（[`TaskGuide.html`](TaskGuide.html)）：结构化 vs 非结构化、`Task { @concurrent }`、取消、启动时机、常见坑、本项目调用链，以及 10 道面试自测题。

两个页面都是单文件 HTML，也可以克隆后直接用浏览器打开（字体来自 Google Fonts，需要联网）。

## 运行

- Xcode 26（iOS 26 SDK），部署目标 iOS 26.0
- 构建设置：`SWIFT_APPROACHABLE_CONCURRENCY = YES`，默认隔离为 `MainActor`

```bash
open Task.xcodeproj          # ⌘R 运行，⌘U 测试

# 或命令行运行测试（模拟器名称按本机实际替换）
xcodebuild test -project Task.xcodeproj -scheme Task \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

运行 App 需要联网访问 `sportsbff-ams.kindredext.net`；单元测试不需要网络。
