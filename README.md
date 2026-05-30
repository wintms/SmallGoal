# SmallGoal

SmallGoal 是一个面向 TestFlight MVP 的 iOS 个人投资账本 App。当前版本实现了股票、基金、理财、现金的本地持仓管理，资产总览，当天盈亏统计，以及可替换的行情服务抽象。

## 打开项目

使用完整 Xcode 打开：

```sh
open SmallGoal.xcodeproj
```

当前工作区所在环境只有 Command Line Tools，不能直接运行 `xcodebuild` 或模拟器。请在安装完整 Xcode 并选中对应 Developer Directory 后构建运行。

## 已实现

- SwiftUI 三栏导航：首页、持仓、设置
- SwiftData 本地资产模型
- 股票、基金、理财、现金新增、编辑、删除
- 资产详情页
- 总资产、今日盈亏、累计盈亏、资产分布
- 中国投资习惯的盈亏颜色：盈利红色、亏损绿色
- `QuoteProvider` 抽象
- `MockQuoteProvider` 默认演示行情
- `ChinaMarketQuoteProvider` 真实行情接入骨架
- 组合计算单元测试

## 行情接入

默认使用 `MockQuoteProvider`，入口在 `SmallGoalApp.swift`：

```swift
@StateObject private var quoteRefreshService = QuoteRefreshService(provider: MockQuoteProvider())
```

接入真实行情时替换为：

```swift
QuoteRefreshService(
    provider: ChinaMarketQuoteProvider(
        endpoint: URL(string: "https://your-quote-service.example.com/quotes"),
        apiKey: "your-api-key"
    )
)
```

真实接口预期返回：

```json
{
  "quotes": [
    {
      "code": "600519",
      "name": "贵州茅台",
      "latestPrice": 1688.0,
      "previousClose": 1670.0,
      "changeAmount": 18.0,
      "changePercent": 0.0108,
      "quoteTime": "2026-05-30T09:45:00Z"
    }
  ]
}
```

## 验证

已在当前环境完成：

- `plutil -lint SmallGoal.xcodeproj/project.pbxproj SmallGoal/Info.plist`
- `swiftc -parse ...`

未完成：

- 完整 `xcodebuild`
- 模拟器运行
- SwiftData 宏类型检查

原因是当前机器 active developer directory 是 `/Library/Developer/CommandLineTools`，缺少完整 Xcode、模拟器工具和 SwiftData macro plugin。
