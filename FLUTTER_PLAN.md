# Marginalia — Flutter 开发规划

> 依据：`Marginalia-Prototype/`（`docs/DESIGN.md` v9 · `docs/impeccable-design-context.md` · `prototype/prototype.html` v9 · `pipeline/`）
> 目标平台：Flutter / Android（minSdk 26，compileSdk 35，targetSdk 34）· 美式英语 · 离线优先
> 状态：**待确认，尚未写任何业务代码**

---

## 0. 结论摘要

原型不是一份"参考稿"，而是一份**完整可执行的规格**：3159 行单文件原型中，界面、数据模型、状态机、成本规则、文案全部已确定。因此本项目的正确做法不是"照着设计稿实现"，而是**把原型里的 JavaScript 状态机逐条翻译成 Dart，并用单元测试锁住那五条不可违反的规则**。

三条需要你拍板的事在第 6 节，其余按本规划推进即可。

---

## 1. 原型分析结论

### 1.1 页面清单（共 18 个界面载体）

**底部导航五槽**（`prototype.html:1645`）

| # | 路由名 | 中文 | 频率 | 职责 |
|---|---|---|---|---|
| 1 | `today` | Queue | 每日 | 三张卡；读或写；齿轮入口 |
| 2 | `article` | Article | 每日 | Read / Listen 双段控件 |
| 3 | `library` | Library | 每周 | 全部文章的货架；搜索 + 5 筛选 + 释放空间 |
| 4 | `calendar` | History | 极少 | 只回望的日历 + Most revisited |
| 5 | `words` | Words | 每日 30 秒 | Crucial now（带权重条）+ All words |

**Settings：中枢 + 四个面板**（不进导航槽，由 Queue 齿轮进入）

| # | 面板 | 内容 | 频次 |
|---|---|---|---|
| 6 | `pHub` | 四行摘要，实时反映状态 | — |
| 7 | `pTopics` | 结构化 plan 七行渲染 + 预设 chips | 经常 |
| 8 | `pVoice` | MiMo 引擎 + 声音探测列表 | 偶尔 |
| 9 | `pWriter` | `/responses` 端点列表 + 切换 + 测试 | 一次 |
| 10 | `pHouse` | 成本卡 + 收纳（存储/词典/发音） | 几乎不 |

**八个底部弹层**（共用一层 scrim）

| # | id | 用途 |
|---|---|---|
| 11 | `wsheet` | 词条：英文释义 → 一次点击出中文 → 加星 |
| 12 | `ssheet` | 句子：整句 + 中文 + 本句词块 |
| 13 | `asheet` | 文章菜单：重写 / 改主题 / Done with it |
| 14 | `nsheet` | 计划单：两个字段 + 一行成本 + 三个按钮 |
| 15 | `ksheet` | 问 AI 改计划：六例句 + 规格块 + diff |
| 16 | `psheet` | 自写 `raw`，逐字保存 |
| 17 | `fshell` | 释放空间：GOES / STAYS 双栏 |
| 18 | `dsheet` | 某日记录 |

### 1.2 视觉规范（OKLCH → sRGB 已换算完毕）

原型全部色值声明为 OKLCH。**Flutter 3.44 无原生 OKLCH 支持**（`ColorSpace` 枚举仅 `sRGB / extendedSRGB / displayP3`），因此必须预先换算为 sRGB hex。换算脚本见 `.workbuddy/tmp/oklch_conv.py`，结果：

**WARM INK（夜间低眩光，原型默认）— 建议作为 App 唯一主表面**

| Token | OKLCH | sRGB |
|---|---|---|
| paper | 21% .018 66 | `#1E1710` |
| paperSunk | 24.5% .020 66 | `#271F16` |
| surface | 25.5% .019 68 | `#292119` |
| ink | 94% .012 84 | `#EFEBE2` |
| ink2 | 80% .014 80 | `#C2BDB4` |
| ink3 | 68% .014 74 | `#9E978F` |
| hair | 33% .016 66 | `#3B342D` |
| rule | 39% .016 66 | `#4B433C` |
| **verm** | 73% .16 38 | `#FA7F59` |
| vermInk | 82% .12 42 | `#FFAA86` ⚠️ 超出 sRGB，已钳制 |
| vermWash | 30% .055 36 | `#45231A` |
| **jade** | 74% .11 168 | `#5BC19D` |
| jadeWash | 29% .045 168 | `#113227` |
| **lamp** | 84% .12 78 | `#F6C16B` |
| lampWash | 31% .060 76 | `#412B06` |

**WARM PAPER（明亮版）** — 备用：`paper #FBF6EC` · `surface #FFFDF9` · `ink #261A11` · `ink2 #534840` · `ink3 #7A736C` · `hair #DED8CF` · `rule #D0C9BF` · `verm #C83122` · `vermInk #9E1614` · `vermWash #FFE6DD` · `jade #2E8D6F` · `jadeWash #D4F6E8` · `lamp #D8953D` · `lampWash #FFECC7`

> ⚠️ 原型页面最外层的 `--gal-*` 冷灰展台色**不进入 App**——它只是浏览器演示页的画廊背景。

**字体**（三族，均为开源字体，需随包分发）

| 族 | 用途 | Flutter 侧 |
|---|---|---|
| Newsreader（衬线，光学尺寸） | 一切"读"的内容：正文、lemma、标题 | `assets/fonts/` |
| Schibsted Grotesk（无衬线） | 一切"操作"的内容：按钮、标签、chips | 同上 |
| IBM Plex Mono | IPA、时间戳、API key、计数 | 同上 |

**字号阶梯**（原型 `--t-*`，1.25–1.3 模块化比例）
`2xs 10 · xs 11 · sm 13 · base 15 · md 17 · lg 18–22 · xl 24–32 · hero 32–45`
（`clamp()` 的部分按屏宽线性插值，Flutter 侧改为 `MediaQuery` 驱动的 clamp）

**间距 / 圆角 / 动效**

- 页面左右边距 `18`，卡片内距 `15–16`，卡片间距 `10–12`，区块间距 `22`
- 圆角：卡片 `16–18` · 大卡 `20–22` · 输入 `11–13` · chip `999` · 弹层顶部 `24`
- 发丝线 `--hair` 代替卡片套卡片；**弹层顶圆角 24、底部无圆角**
- 动效：`120 / 300 / 500 ms`，`cubic-bezier(.16,1,.3,1)`，**仅 transform 与 opacity**；导航指示条与分段控件指示条只滑动不重排

**质感**：全页纸纹（SVG turbulence 5%，Flutter 侧改为 `CustomPainter` 噪点 + `BlendMode.overlay`）；权重条为**斜纹填充**（`repeating-linear-gradient`），Flutter 侧用 `ShaderMask` 或 `CustomPainter` 画 135° 斜纹；生词用**朱红细下划线**（`inset 0 -.42em`）而非荧光笔色块。

### 1.3 交互流程与不变量（必须用测试锁死）

原型 `prototype.html:529-566` 给出的状态机是整个产品的核心：

```
queue.size == 3                      恒定
slot.state ∈ {planned, ready}        永远只有这两种

  autoFill()        → 若任一 planned：立即返回，什么都不写
                    → 否则用免费 plan 补齐空位
  write_it(i)       → planned → ready        一次调用 ≈$0.002
  reroll(i)         → 换一个新 plan           零调用 $0.00
  done_with(i)      → ready → planned        零调用 $0.00，且写入 LEDGER 行
  读到末尾 + 点击    → reads++               （文章留在队列，标记重新武装）
  播放             → listens++             （永不触碰 reads）
  free_space(title) → 只改 kb，绝不写 reads / listens
```

**五条不可违反的规则**

1. `queue.size == 3` 恒定
2. 只有 `planned` / `ready` 两态；**任一 planned 即停止一切自动写作**（这是成本天花板）
3. **阅读永不移除文章**，只做 `reads++`
4. **计数不是存储**：释放空间只删字节，`reads`/`listens` 永久保留
5. 全局**不存在** `finished` 布尔值，**不存在**夜/昼概念

**派生数据原则**：`shelf() = LEDGER ∪ live QUEUE`，按标题合并——**没有 library 表**，避免第二份真相失配。日汇总是查询而非独立表。

---

## 2. 项目现状

| 项目 | 结论 |
|---|---|
| Flutter 工程 | **不存在**。`E:\Dev_work\Flutter_Dev\marginalia\` 下只有 `Marginalia-Prototype/`，无 `pubspec.yaml` |
| 原型资产 | 完整。8 个文件：`prototype.html`(3159行) · `DESIGN.md`(1161行) · `impeccable-design-context.md` · `tts.py`(331行) · `dictsource.py` · `settings.example.json` · `fetch_ecdict.sh` |
| Flutter SDK | `E:\Dev_work\Android_Dev\Dev_Tools\Flutter_SDK\flutter_windows_3.44.3-stable`，Dart 3.12.2 |
| Android SDK | `E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352`，已装 platform `android-26 / 28 / 29 / 35`，build-tools `35.0.0`；**未装 android-34**，故 compileSdk 用 35 |
| JDK | GraalVM 21.0.7 ✓ |
| ⚠️ 工具链故障 | `flutter` 命令在本会话中因 Windows 管道错误（`All pipe instances are busy`，`where.exe` 调用失败）无法执行；`dart` 本身正常。**这是环境问题，非配置问题**——需你协助或改期重试 |

**因此：工程需从零初始化。** 按你的要求，确认前不写业务代码。

---

## 3. 技术选型

| 层 | 选择 | 理由 |
|---|---|---|
| 状态管理 | **Riverpod 3.x**（Notifier / AsyncNotifier） | 原型大量使用**派生**数据（`shelf()` 是 LEDGER∪QUEUE 的合并、权重按天衰减、hub 摘要实时反映面板）。Provider 组合天然表达"从一个源算出另一个"，而 Bloc 的事件流需要为每条派生规则手写事件。`Notifier` 的 `build()` 返回不可变值 + `copyWith`，与 freezed 模型契合 |
| 路由 | **go_router** | 声明式；Settings 四面板天然是嵌套路由；支持 `/article/:id?from=library` 这类带上下文参数（横幅与返回键重定向需要它） |
| 本地结构化数据 | **drift**（SQLite） | 需要 SQL 聚合（按 article 分组求和得 Most revisited、按日聚合得日历数字）与响应式查询。`files/` 存文章 JSON 与音频，`db/no-stop.db` 存计数/历史/plan——与原型 §4e 的目录约定一致 |
| 网络 | **http**（非 dio） | 只有一个形状：`POST {base}/responses`；MiMo 是 `POST {base}/chat/completions`。拦截器需求仅"注入 key"，一个薄封装足够。依赖越少越可审计 |
| 模型 | **freezed + json_serializable** | 结构化 plan 是七字段对象且要做 diff；文章模型需要 `copyWith`；`@freezed` 的 `==` 让"状态是否真变了"可测试 |
| 密钥 | **flutter_secure_storage** | Android Keystore，对应 DESIGN §11 的承诺 |
| 音频播放 | **just_audio** + **audio_service** | 文章音频是逐句 wav 文件；锁屏 MediaSession 控件是 M3 硬需求（`audio_service` 正是为此存在） |
| 单词发音 | **flutter_tts** | 系统引擎，离线免费；ECDICT 的 `audio` 列为空，这是唯一免费路线 |
| 文件路径 | **path_provider** | `<app>/files/<YYYY-MM-DD>/<article_id>.{json,wav,words.json}`，一天一目录、一文三文件 |
| 字体 | 随包分发三族 woff2/ttf | 见 1.2 |
| 测试 | `flutter_test` + 纯 Dart 单测 | 五条不变量 + 权重衰减 + 排序规则全部可纯测，无需 widget 测试 |

**明确不引入**：WorkManager（设计已定：**没有任何写文章的定时器**，"Done with it 之后立刻补写"是用户点击，不是调度）、间隔重复、任何 gamification 依赖。

---

## 4. 数据模型

```dart
// —— 内容 ——
Article        { id, title, topic, focus, sentences[], marks[], wordCount, minuteEstimate }
Sentence       { index, en, cn, audioPath? }
Mark           { surface, lemma, sentenceIndex, tier ∈ {unfamiliar, difficult}, en?, why?, cn? }

// —— 队列 ——
QueueSlot      { articleId?, state ∈ {planned, ready}, topic, focus, words, marked, isWriting }
               // planned 用 topic/focus；ready 用 articleId——两者语义不同，不可合并成一个 nullable 大对象

// —— 计划（结构化，非散文）——
ReadingPlan    { reader, topics[], style[], gloss[], avoid[], length, marked, raw }
               // raw 逐字附加在结构化字段之后，永不丢弃

// —— 账本与历史 ——
LedgerEntry    { articleId, title, topic, reads, listens, kb, isGone }
DayLogRow      { day, articleId, title, reads, listens, minutes }   // 唯一真相；日汇总与 Most revisited 都是它的查询

// —— 词池 ——
WordEntry      { lemma, weight, encounters, starredAt?, lastMetAt }
               // weight = Σ value(event) × 0.5^(ageDays/7)；半衰期 7 天；<0.5 掉出活跃列表

// —— 配置 ——
WriterEndpoint { name, baseUrl, apiKey, model, isActive }   // 只调用 active
TtsSettings    { provider=mimo|device, baseUrl, apiKey, model, style, voiceAuto, voicePick, voiceProbe{} }
Presets        { topics[], focuses[] }                     // 用户可增删的 chip 列表

// —— 派生（不落库）——
ShelfRow       { title, topic, meta, reads, listens, kb, isLive, isGone }   // = LEDGER ∪ live QUEUE
LibraryFilter  ∈ { all, reading(reads≥2), unread(reads==0), heard(reads==0&&listens>0), gone }
```

---

## 5. 分阶段开发计划

> 优先级：**P0** 阻断主链路 · **P1** 核心价值 · **P2** 完善
> ⚠️ `DESIGN.md §7` 的 M1–M6 顺序**已过时**：它成文于 Library(v8) 与存储规则(v9) 之前，未包含 Library 与 `free_space`。下表已按 v9 实际范围重排。

| 阶段 | 内容 | 依赖 | 优先级 | 验收标准 |
|---|---|---|---|---|
| **0** | 工程初始化 · 设计系统（色板/字体/间距/动效 token）· 三个可复用基件（Hairline / Sheet+Scolim / Toast） | — | P0 | `flutter analyze` 零告警；纸纹与斜纹条渲染正确；三族字体生效 |
| **1** | 领域层：全部模型 + 五条不变量的纯 Dart 实现 + 单测 | 0 | P0 | 队列恒为 3；planned 阻断自动写作；`free_space` 后计数不变；全局无 `finished` 字段（可用 grep 断言） |
| **2** | **Queue** 屏（ready/planned 两态卡、topic pill、⋯ 菜单、reroll）+ **Article·Read**（逐词可点、朱红细下划线、Count this read 重新武装）+ 本地样例文章包 | 1 | P0 | 三卡渲染；读完后计数 +1 且卡片留在队列；planned 卡不触发任何网络 |
| **3** | **Settings 四面板** + 密钥存储 + writer 客户端（`/responses` 封装 + 端点切换 + 测试按钮） | 1 | P1 | Hub 摘要实时；端点切换不改写既有文章；密钥入 Keystore |
| **4** | 真实写作链路：`POST /responses` + §10 prompt + **`kNext` diff 门控**（未接受前 scrim 拒绝关闭、再次输入即作废 diff） | 3 + **M1 golden set 验证通过** | P1 | 问 AI 产出 diff 但不落库；点"用这个"才写入；**无任何自动写作路径** |
| **5** | **Library**：`shelf()` 派生 + 搜索 + 5 筛选 + 排序（live 优先 → `reads+listens` 降序 → 标题）+ 从书架重开（横幅 + 返回键改为 `‹ Library`） | 2、1 | P1 | 归档文章可重开且两个计数仍可用；离开文章页后上下文清空不泄漏 |
| **6** | **释放空间**：存储条 + 每行 KB + GOES/STAYS 双栏确认 + **三重守卫**（队列中的活卡不渲染 ⌫、确认处理器二次校验、已删文章拒绝打开） | 5、1 | P1 | 释放后行保留、删除线、按原注意力排序、仍计入 Most revisited；`reads`/`listens` 零变化 |
| **7** | **Listen**：`⏮ ▶ ⏭` + 逐句高亮 + 锁屏 MediaSession + 变速；`listens++` | 2 | P2 | 跳句不中断播放；播放不触碰 reads；锁屏可控 |
| **8** | **History**：月历（数字=当日次数，未来日留空）+ 点开某日 + Most revisited（斜纹双条） | 1 | P2 | 全部数字来自 `DayLogRow` 查询，无独立汇总表 |
| **9** | **Words**：Crucial now（权重条 + 星标）+ All words（英文优先、点击翻中文）+ 词条弹层 | 1 | P2 | 权重按半衰期衰减；加星**立即**抬升且不触发任何重写 |

**依赖关系要点**

- 阶段 1 是全部后续阶段的地基，**必须先完成并以测试固化**
- 阶段 4 硬依赖原型 README 标注的 **M1**（§10 prompt 的 golden set 验证）。**该 prompt 是"待验证草稿"，未通过五条验收标准前不得接入**——这是原型作者明确的警告
- 阶段 6 依赖 5 的 `shelf()`；阶段 9 依赖 1 的权重计算
- 阶段 7/8/9 彼此独立，可并行或延后

**建议推进顺序**：0 → 1 → 2（此时已得到一个"能离线读三篇文章"的完整 App）→ 3 → 5 → 6 → 4 → 7 → 8 → 9

---

## 6. 需要你拍板的四件事

| # | 问题 | 我的建议 |
|---|---|---|
| 1 | **`flutter` CLI 在本会话无法执行**（Windows 管道错误，`where.exe` 调用失败；`dart` 正常）。如何推进？ | 我先手写 `pubspec.yaml` / `lib/` / `analysis_options.yaml` / `test/`，你只需执行一次 `flutter create --platforms=android .` 生成 Android 包装层；或我下一轮重试 CLI |
| 2 | **ECDICT 词典 851 MB，无法进 APK**（应用体积限制）。原型的 `fetch_ecdict.sh` 是桌面机方案，Android 端不适用。 | 内置**精简种子词典**（Top 20k 高频词，覆盖 99% 阅读场景，~4 MB），并在 Settings→小字里提供"导入完整 ECDICT"入口（用户自行放到下载目录）。你是否接受这个取舍？ |
| 3 | **主表用暖纸还是暖墨？** 设计明确"无夜昼概念"，但原型给了两套皮肤。 | 默认 **暖墨**（通勤/夜间低眩光，是产品主场景）；暖纸作为**一次性外观选择**放在 Settings→小字，不带任何时间语义。若你希望只做一套，请指定。 |
| 4 | **M1 golden set（§10 prompt 验证）是否在本项目范围内？** 它是 Python 侧工作，但阶段 4 依赖它。 | 建议**先按阶段 0→1→2 交付可用的离线阅读 App**，M1 与阶段 4 并行推进。你也可以指定先攻 M1。 |

---

## 7. 资源准备清单

| 资源 | 状态 | 动作 |
|---|---|---|
| Newsreader / Schibsted Grotesk / IBM Plex Mono | 需下载 | 三族 woff2/ttf 放入 `assets/fonts/`（均为开源字体） |
| ECDICT | **缺失** | 见问题 2；`tools/fetch_ecdict.sh` 仅供桌面 |
| 样例文章包 | 需自建 | 原型内嵌 1 篇《What a Pointer Really Is》全文 + 6 句中文；建议补 3 篇覆盖不同 topic，作为离线样例与测试夹具 |
| Golden set 夹具 | 缺失 | M1 需要：1 篇手工标注 + 3 篇他topic，附 tier 标签 |
| API key | 可选 | DeepSeek（写作，最便宜）+ MiMo（语音，免费）。**全无 key 时 App 必须仍可用**（设备 TTS + 离线词典 + 本地样例，$0.00） |

---

## 8. 编码约定（对齐 `flutter-ai-rules` 与原型风格）

- **状态管理**：`AsyncNotifier` + `ref.watch`，异步后一律 `if (!context.mounted) return;`
- **不可变模型**：freezed + `copyWith`，禁可变字段
- **const 优先**：静态子树上 `const` 构造；避免在 `build` 中 `print`（用 `debugPrint`）
- **列表**：`ListView.builder`；长列表按需构建
- **错误处理**：网络与文件操作必须 try-catch，失败要有**可见且诚实**的降级（对齐"没有 key 仍可用"）
- **token 单一来源**：色值/间距/字号只允许出现在 `design/tokens.dart`，禁止散落魔法数——这正是原型 §12 记录的三类 bug 之一（token 作用域太窄导致渲染透明）
- **文件头**：每个文件顶部注明对应的原型锚点（如 `// DESIGN §4e — counts are not storage`），便于回溯规格
- **测试**：五条不变量各有至少一条断言；派生函数（shelf 排序、筛选、权重衰减）纯函数化后全覆盖

---

## 9. 明确不做的事

- ❌ 任何"你记住了吗"式评分、确认按钮、进度环、连续打卡
- ❌ 任何夜/昼模式切换入口
- ❌ 任何 `finished` 字段
- ❌ 任何未经点击触发的写作调用（含定时器、后台任务）
- ❌ 删除记录（只释放字节）
- ❌ 槽位模式（Auto / Pinned / One-off）
- ❌ 卡片套卡片、模糊、发光、霓虹

---

*本文档为规划稿。确认第 6 节四项后进入编码阶段。*