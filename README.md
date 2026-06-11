# GoldPrice - macOS 悬浮行情与基金持仓组件

GoldPrice 是一个常驻桌面的 macOS 小组件，实时展示上海黄金交易所
AU9999 金价、上证指数和基金持仓估算收益。应用使用无边框悬浮窗口，
不会显示 Dock 图标。

## 主要功能

### 市场行情

- 显示 AU9999 人民币/克价格及相对上一交易日结算价的涨跌幅。
- 显示上证指数及相对上一交易日收盘点位的涨跌幅。
- 启动时立即请求，之后每 5 秒刷新一次。
- 中国市场配色：红色上涨、绿色下跌、灰色平盘。
- 单击金价或指数可在默认浏览器中打开对应的东方财富行情页。
- 单个数据源请求失败时保留该来源最后一次有效数据。

### 基金持仓

- 展开列表后显示基金名称、代码、本金、累计收益和今日盈亏。
- 支持添加基金、加仓、减仓和删除。
- 基金代码必须是 6 位数字，金额必须是大于 0 的有效数字。
- 拒绝重复添加、无可用净值时调仓以及超过当前市值的减仓。
- 新增基金先显示代码，东方财富返回有效估值后自动更新基金名称。
- 基金估值在启动时立即请求，之后每小时刷新一次。
- 数据源暂时没有盘中估值时显示 `--`，不会把基金标记为不存在。

计算方式：

```text
估算市值 = 持有份额 x 估算净值
累计收益 = 估算市值 - 本金
今日盈亏 = 持有份额 x (估算净值 - 前一日净值)
```

首次获取新增或迁移基金的有效估算净值时，应用按
`初始份额 = 本金 / 估算净值` 初始化份额。加仓按当前估算净值增加份额；
减仓按当前估算净值减少份额，并按比例扣减本金。

### 窗口与交互

- 窗口默认位于主屏幕右上角，并悬浮在普通窗口之上。
- 可拖动窗口背景改变位置。
- 点击右侧箭头展开或收起基金列表。
- 展开高度会随持仓数量变化，超过屏幕可用高度时列表可以滚动。
- 基金名称可点击并打开对应的东方财富基金详情页。

## 数据与持久化

持仓保存在：

```text
~/Library/Application Support/GoldPrice/portfolio.json
```

只持久化基金代码、名称、本金和份额；估算净值、前一日净值及更新时间会在
每次启动后重新获取。写入采用原子替换。

如果持仓 JSON 损坏，应用会先在同一目录生成
`portfolio.corrupt-YYYYMMDD-HHMMSS.json` 备份，再恢复默认持仓并在列表底部
显示提示。目录不可读或不可写时也会显示明确错误，而不是静默忽略。

测试或临时运行时可通过环境变量隔离数据目录：

```bash
GOLDPRICE_DATA_DIR=/tmp/goldprice-qa swift run
```

## 数据来源

| 数据 | 来源 | 刷新频率 | 用途 |
| --- | --- | --- | --- |
| 黄金 9999 | [东方财富 AU9999](https://quote.eastmoney.com/globalfuture/AU9999.html) | 5 秒 | 当前价、昨结、涨跌额和涨跌幅 |
| 上证指数 | [东方财富](https://quote.eastmoney.com/unify/r/1.000001) | 5 秒 | 当前点位、昨收、涨跌额和涨跌幅 |
| 基金估值 | [东方财富基金](https://fund.eastmoney.com/) | 1 小时 | 基金名称、估算净值、前一日净值和估算涨跌幅 |

应用直接采用行情接口返回的涨跌额和涨跌幅。AU9999 以昨结算价为比较基准，
上证指数以昨日收盘点位为比较基准。

## 系统要求

- macOS 14.0 或更高版本
- Swift 6.0 或更高版本
- Xcode Command Line Tools
- 可访问东方财富数据接口的网络

## 构建与运行

开发模式：

```bash
swift run
```

生成 `GoldPrice.app`：

```bash
./build.sh
```

脚本会执行 Release 编译、组装 App bundle、临时签名，并通过 `plutil` 和
严格 `codesign` 验证。生成后运行：

```bash
open GoldPrice.app
```

应用没有 Dock 图标和菜单栏退出项，可通过“活动监视器”退出，或执行：

```bash
pkill -x GoldPrice
```

## 测试

运行全部自动化测试并生成覆盖率数据：

```bash
swift test --enable-code-coverage
```

运行 Release 构建和 App bundle 验证：

```bash
swift build -c release
./build.sh
plutil -lint GoldPrice.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 GoldPrice.app
```

完整功能测试结果和用例明细见 [TEST_REPORT.md](TEST_REPORT.md)。
