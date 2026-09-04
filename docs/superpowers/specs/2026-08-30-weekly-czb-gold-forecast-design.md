# 浙商积存金一周方向预测设计

## 1. 目标

在黄金分析页增加一个独立的“一周预测”能力，预测对象为 App 当前展示的浙商积存金人民币/克。每次预测回答生成时间后第 7 个自然日附近的第一笔有效价格更可能上涨、震荡还是下跌，并展示信心等级、预期涨跌幅、价格区间、模型验证表现和主要依据。

该功能是分析工具，不是买卖信号。预测结果不得直接改变 `GoldAdvancedStrategy`、`GoldPositionAdvisor` 或持仓建议，也不得输出买入、卖出、加仓、减仓等动作。

## 2. 已确认的产品定义

- 标的：浙商积存金人民币/克。
- 预测周期：生成预测后第 7 个自然日。
- 验证价格：目标时间之后取得的第一笔有效同标的价格；最多允许延后 3 个自然日。超过宽限期仍无同标的价格时记录为 expired，不拿更晚价格冒充结果。
- 三分类标签：
  - up：实际收益率 > 0.5%。
  - flat：实际收益率位于 -0.5%...0.5%，包含边界。
  - down：实际收益率 < -0.5%。
- UI 输出：上涨、震荡或下跌；信心等级；预期收益率；预期价格；P10/P50/P90 区间；目标日期；数据状态；模型版本；主要依据；反方风险；历史验证指标。
- 数据或验证不足时显示明确原因，不强行给方向。

## 3. 当前基线与不能直接复用的部分

当前代码已经具备：

- `GoldMarketDataService.fetchHistoryPrices(range: .year)`：约一年历史日线。
- `GoldAdvancedStrategy.MonteCarloForecast`：基于最近价格序列的 7 步模拟。
- `GoldPredictionLearningStore`：记录策略预测，并约 30 分钟后验证。
- `GoldMarketIntelligenceSnapshot.eventImpact`：解释当前宏观事件影响。

一周预测不得直接把现有 `forecastSteps == 7` 解释为 7 天。现有分析使用最近 24 小时的不规则价格点，步长没有稳定的日历含义；现有 30 分钟学习记录还会参与策略自动校准，不能与一周三分类样本混合统计。

## 4. 数据来源与标的一致性

当前 `GoldPriceService` 优先返回 `JD-MS`，失败时回退 `CZB-JCJ`；历史日线来自京东 `historyPrices`。实现者必须先把数据来源写入预测快照，禁止把无法证明一致的序列隐藏成“浙商积存金历史”。

第一版采用以下规则：

1. 训练序列来自 `GoldMarketDataService.fetchHistoryPrices(range: .year)`，数据来源标记为 `JD-MS-history`。
2. 起始价必须来自当前 App 有效报价，并保存实际 `source`。
3. 如果当前价来源与历史序列属于同一已验证产品契约，`sourceCompatibility = verified`。
4. 如果只能确认二者都是国内人民币/克黄金参考价，但无法证明完全同标的，`sourceCompatibility = proxy`：可以输出参考预测，但 confidence 最高为 low，UI 必须显示“历史模型使用国内黄金参考日线”。
5. 如果价格单位、产品或时间序列无法匹配，`sourceCompatibility = incompatible`，返回 sourceMismatch，不生成预测。
6. 不允许通过名称猜测来源一致性。验证必须来自固定响应字段、明确接口文档，或至少 30 个重叠日收盘样本满足：日收益相关系数 >= 0.90 且中位绝对日收益差 <= 0.30%。

若执行阶段无法证明京东历史日线与浙商积存金一致，本功能仍可作为显式标注的 proxy 参考预测落地，但不得显示为高信心，也不得宣称使用了浙商历史数据。

## 5. 日线标准化

所有模型只消费 `GoldDailyClose`：

- 使用 `Asia/Shanghai` 日历归并同一天数据，保留当天最后一笔有效价格。
- 按日期升序排序并去重。
- 价格必须是有限数且位于 100...2,000 元/克。
- 相邻日收益绝对值超过 8% 的点标记异常并排除当前窗口；同时在数据质量原因中记录。
- 至少需要 120 个有效日收盘点。
- 120...179 点时 confidence 最高为 low；180 点及以上允许 medium；high 还需满足第 8 节的增强门槛。
- 最新日线距离 now 超过 96 小时即 staleData，不生成预测。
- 数据中存在超过 14 个自然日的缺口时仍可分析，但 confidence 至少下降一级并显示缺口风险。

## 6. 模型结构

第一版为确定性、可解释、纯 Swift 的统计组合模型，不引入 Python、Core ML、LLM 或第三方机器学习依赖。

### 6.1 基础特征

使用预测时点及以前的数据计算：

- 20 日与 60 日趋势差。
- 5 日与 20 日动量。
- 20 日收益波动率。
- 价格相对 20 日均值的 z-score，用于均值回归分量。
- 最近 120 个日收益的区块自助法模拟结果。

每个分量归一化到 -1...1：正数偏上涨，负数偏下跌。权重固定并写入模型版本：

- trend：0.35。
- momentum：0.25。
- meanReversion：0.15。
- bootstrap：0.25。

组合分数大于等于 0.18 为 up，小于等于 -0.18 为 down，其余为 flat。权重和阈值不得因为一个新闻案例临时调整；任何调整必须提升模型版本并重新走回测门槛。

### 6.2 一周价格区间

从最近 120 个日收益中抽取长度为 3 的连续区块，拼接到“过去一年中 7 个自然日通常包含的有效日线步数”，执行 2,000 次确定性模拟。随机数必须支持 seed 注入，测试使用固定 seed。

输出最终价格分布的 P10、P50、P90；`expectedPrice` 使用 P50，`expectedReturn = P50 / startPrice - 1`。方向来自组合分数，不从 P50 单独反推，避免一个分量覆盖整个组合。

### 6.3 事件影响边界

`GoldEventImpact` 不进入组合分数、预期收益率或价格区间，因为当前没有历史事件快照可用于无泄漏回测。

- 事件方向与周预测一致且事件 confidence 至少 medium：周预测 confidence 最多上调一级。
- 事件方向冲突：周预测 confidence 下调一级，并增加反方风险。
- 事件为 partial、stale、unavailable 或 neutral：不调整。
- 无论如何不能改变周预测 direction。

## 7. 信心等级

confidence 不是上涨概率，UI 不得加百分号。它综合：组合分数绝对值、四个分量的一致程度、数据质量、来源兼容性和最近走步回测表现。

- unavailable：没有可展示预测。
- low：模型通过最低发布门槛，但数据、来源或分量一致性有限。
- medium：至少 180 个有效日线点、来源 verified、四个分量至少三个同向、回测通过标准门槛。
- high：至少 240 个有效日线点，且回测样本 >= 36、balanced accuracy >= 0.45、总体准确率至少高于多数类基准 5 个百分点。事件影响不能单独把 low 提升为 high。

## 8. 无泄漏走步回测与发布门槛

`GoldWeeklyForecastBacktester` 只使用每个 anchor 当日及以前的数据生成预测。anchor 之间至少间隔 7 个自然日，避免把大量重叠目标当作独立样本。

每个 anchor 的真实标签使用 anchor + 7 天后的第一笔有效价格，宽限期同样为 3 天。输出：

- resolved sample count。
- up/flat/down 各类样本数。
- overall accuracy。
- balanced accuracy。
- majority-class baseline accuracy。
- mean absolute return error。
- confusion matrix。

最低发布门槛：

- resolved samples >= 24。
- 三个真实类别都至少出现 3 次；否则分类数据不足。
- balanced accuracy >= 0.38。
- overall accuracy >= majority baseline accuracy。
- 所有误差和分数必须有限。

任一条件失败时 snapshot.status = validationFailed，UI 显示验证指标和“不发布方向”，不得只隐藏失败结果。不得在同一批回测数据上反复试权重直到刚好过线；参数变化必须有新模型版本并保留对比结果。

## 9. 状态、缓存和记录

状态固定为：ready、insufficientHistory、staleData、sourceMismatch、validationFailed、sourceUnavailable。

- 只有 ready 可以包含 forecast。
- 预测按上海自然日和 modelVersion 去重，同一天最多保存一条正式记录；第一条 ready 预测即为当日正式预测，后续刷新继续展示该记录，不能用盘中变化回写历史判断。
- 服务缓存 6 小时；缓存键至少包含上海自然日、最新日线日期、modelVersion 和来源兼容性。
- 网络失败时可以展示不超过 24 小时的旧预测，但状态必须标 staleData，并移除方向展示；旧预测只作为“上次结果”折叠信息。
- 每条记录保存生成时特征分数、数据来源、来源兼容性、回测摘要和事件对 confidence 的调整，便于复盘。
- 一周记录使用独立 `GoldWeeklyForecastStore`，不得混入 `GoldPredictionLearningStore.summary`，避免污染 30 分钟策略自动校准。
- 周预测记录加入 `DataArchive` 可选字段，旧备份必须继续解码。

## 10. UI

黄金分析页增加 `GoldWeeklyForecastCard`，放在当前策略总览之后、事件影响卡片之前。

ready 状态展示：

- “未来一周”与目标日期。
- 上涨、震荡或下跌。
- 信心：低、中、高，不显示伪概率。
- 当前价、预期价、P10-P90 区间和预期涨跌幅。
- 数据截至时间、历史数据来源和兼容性。
- 最多 4 条模型依据、2 条反方风险。
- 回测样本数、总体准确率、balanced accuracy 和多数类基准。
- “基于历史统计和公开数据，不构成投资建议”。

非 ready 状态使用同一张卡明确显示原因、需要的样本数量或失败指标。不得用红绿颜色作为唯一方向表达；中文、英文、日文、韩文必须完整。

预测复盘页增加独立“一周预测”区块，展示 pending、validated、expired，不能和现有 30 分钟记录合并计算命中率。

## 11. 非目标

- 不自动交易，不生成仓位和买卖动作。
- 不承诺价格或收益。
- 不训练神经网络，不调用 LLM 预测价格。
- 不新增付费行情、需要 API Key 的源或受限网页抓取。
- 不使用未来新闻、未来宏观数据或完整样本统计计算历史 anchor 特征。
- 不把 XAUUSD、美元指数当前值伪装成一周历史特征。
- 不删除现有 30 分钟学习系统；第一版保持两个时间尺度隔离。

## 12. 验收标准

1. 方向和验证标签严格使用 +/-0.5% 阈值。
2. 少于 120 个日线点、数据超过 96 小时或来源不兼容时不发布方向。
3. 回测无未来数据泄漏，anchor 至少间隔 7 天。
4. 回测未过门槛时 UI 显示 validationFailed。
5. 事件影响只能调整 confidence，不能改变 direction、expectedReturn 或区间。
6. 一周记录和 30 分钟记录分库存储、分开统计。
7. 同一天同模型最多一条正式预测。
8. 第 7 天后第一笔有效价格用于验证，超过 3 天宽限期记 expired。
9. 旧数据备份可以解码，新周预测记录可以导出和恢复。
10. 完整测试和 Release 构建通过，且没有覆盖工作区其他未提交改动。
