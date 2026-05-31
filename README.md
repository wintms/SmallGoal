# SmallGoal

SmallGoal 是一个面向 TestFlight MVP 的 iOS 个人投资账本 App。当前版本实现了股票、基金、理财、现金的本地持仓管理，资产总览，当天盈亏统计，以及可替换的行情服务抽象。

## 打开项目

使用完整 Xcode 打开：

```sh
open SmallGoal.xcodeproj
```

当前项目已使用 Xcode 26.5 和 iOS 26.5 SDK 验证通过。命令行构建使用 `/private/tmp/SmallGoalDerivedData` 作为 DerivedData，避免污染项目目录。

## 已实现

- SwiftUI 三栏导航：首页、持仓、设置
- SwiftData 本地资产模型
- 股票、基金、理财、现金新增、编辑、删除
- 资产详情页
- 总资产、今日盈亏、累计盈亏、资产分布
- 中国投资习惯的盈亏颜色：盈利红色、亏损绿色
- `QuoteProvider` 抽象
- `MockQuoteProvider` 默认演示行情
- `ChinaMarketQuoteProvider` 通用真实行情代理接入
- `MXDataQuoteProvider` 东方财富妙想 API 客户端直连接入
- 设置页行情配置入口：模拟行情 / 真实行情代理 / 妙想直连、endpoint、API Key
- API Key 使用 Keychain 保存，endpoint 和模式使用 UserDefaults 保存
- 首页和设置页展示行情刷新成功、警告、失败状态
- 组合计算和行情配置单元测试

## 行情接入

默认使用模拟行情。接入真实行情不需要改代码，在 App 内打开：

`设置 > 行情`

可选两种真实行情模式：

- `真实行情`：填写通用行情代理 endpoint，并按需填写 API Key。
- `妙想直连`：不需要后端代理，直接填写东方财富妙想 API Key。

API Key 仅保存在本机 Keychain 中，不写入仓库。妙想直连会从 iOS App 直接请求妙想 API，适合当前 MVP 验证；正式发布前仍建议重新评估 API Key 暴露、抓包滥用、接口授权和稳定性。

真实请求格式：

```text
GET {endpoint}?codes=600519,510300&apikey=your-api-key
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

妙想直连内部请求：

```text
POST https://mkapi2.dfcfs.com/finskillshub/api/claw/query
Header: apikey: your-api-key
Body: {"toolQuery":"600519 最新价、昨收、涨跌额、涨跌幅、证券名称"}
```

刷新失败时会保留上次价格和上次成功更新时间，不会把资产价格清空。部分代码无返回时，已返回的资产会正常更新，界面显示警告状态。

## 验证

已完成：

- `plutil -lint SmallGoal.xcodeproj/project.pbxproj SmallGoal/Info.plist`
- `swiftc -parse ...`
- `xcodebuild -project SmallGoal.xcodeproj -scheme SmallGoal -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/SmallGoalDerivedData CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project SmallGoal.xcodeproj -scheme SmallGoal -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/SmallGoalDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing`
- `xcodebuild -project SmallGoal.xcodeproj -scheme SmallGoal -configuration Debug -destination 'id=29AC139D-643A-42A2-B01D-461DD60213CB' -derivedDataPath /private/tmp/SmallGoalDerivedData test`

测试结果：

- `PortfolioCalculatorTests.testCashDoesNotCreateProfitLoss` 通过
- `PortfolioCalculatorTests.testStockProfitLossUsesLatestAndPreviousClose` 通过
- `PortfolioCalculatorTests.testWealthProductAccruesDailyYield` 通过
- `QuoteConfigurationTests.testDefaultConfigurationUsesMockProvider` 通过
- `QuoteConfigurationTests.testChinaMarketModeWithoutEndpointFailsBeforeRequest` 通过
- `QuoteConfigurationTests.testMXDataModeWithoutAPIKeyFailsBeforeRequest` 通过
- `QuoteConfigurationTests.testMXDataModeCreatesProviderWhenAPIKeyExists` 通过
- `QuoteConfigurationTests.testMXDataPayloadParsesQuoteSchema` 通过
- `QuoteConfigurationTests.testPartialQuoteResponseUpdatesReturnedAssetsAndWarns` 通过
- `QuoteConfigurationTests.testFailureDoesNotOverwriteExistingPrice` 通过
- `QuoteConfigurationTests.testKeychainCredentialStoreSavesReadsAndDeletesAPIKey` 通过
- `ChinaMarketQuoteProviderTests.testHTTPErrorMapsToQuoteProviderError` 通过
- `ChinaMarketQuoteProviderTests.testMalformedJSONMapsToDecodingError` 通过
