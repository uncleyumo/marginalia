# 项目现状

> 最后更新：2026-10-13
> 这份文档说的是**代码实际做到的事**。当它和 `FLUTTER_PLAN.md` 冲突时以它为准——
> 那份规划写于动工之前，第 5 行至今还写着"尚未写任何业务代码"。

## 一句话

五个界面（Queue / Article / Listen / Library / History / Words / Settings）全部实现，
离线词典、设备 TTS、MiMo 语音、写作链路、锁屏播放都已接线。**没有 stub，没有 TODO。**

## 本轮（2026-10-13）：照片当指令

遇到好词好句会拍、好的场景会记、在别的软件背单词会截图——这些现在可以直接当指令用。

计划卡上 `↻` 旁边多了一个 **`▣`**，点它打开选图面板：先说这些图是什么
（`A good sentence` / `A scene` / `A word list`），再从相册选（最多 5 张）或现拍一张，
最后 `Attach N · then Write it` 回到卡片，**再点一次 `Write it` 才花钱**。

| 决定 | 为什么 |
|---|---|
| **附图免费，写入才花钱** | 附图是选择，选择不花钱——和 `↻`、`Change it` 同一条线 |
| **压到 2 MB 以下再发** | 12 MP 照片约 4 MB，5 张 base64 后是 27 MB 请求体，好几家 provider 会在计费前直接拒。面板显示 `3.8 MB → 480 KB` 实数 |
| **已经够小的原样发** | 把 200 KB 的截图重编码一遍，图变更差、字节没省 |
| **缩到 1568 长边** | 视觉模型的通用约定，且是本机做的——provider 自己的缩放器对文字截图不友好 |
| **`supportsVision` 是端点上的字段，不是猜的** | `deepseek-chat` 对 content 数组回 `400 unknown variant image_url`，根本没看那张图。所以**在调用前**就拒，拒绝文案点名能看的几家 |
| **只进第一条 user 消息** | agent 循环会发好几次请求，每轮都重发 5 张图等于同样的字节付四次钱 |
| **什么都不存** | 没有图片表、没有相册、写用完就消失——读者自己相册里已经有了。唯一写进队列行的是意图（`from a word list`），否则卡片会一边挂着 5 张图一边显示 `Anything` |
| **意图必填** | 同一张照片，"写这句话的意思"/"描写这个场景"/"把这些词用进句子"是三篇不同的文章，猜错就是白花一次钱。一个 chip 比一篇错的文章便宜 |
| **`system` 提示词不动，`pictureRules` 追加以图为准** | 给没收到图的模型描述照片，是让它在找一个不在那里的东西 |

**没测的部分**：本机没有连接模拟器（`adb devices` 为空），所以选图面板的 UI 交互
和实机压缩没有走完。已验的是：`flutter analyze` 0 error、149+45 条可执行规则全过、
release APK 构建通过（77.1 MB）、`data/shrink.dart` 用真图跑过（2.7 MB → 1.3 MB，
478 KB 原样透传）。

## 已在模拟器上实测通过（2026-10-07，x86_64 · Android 16）

不是"应该能跑"，是截图和 logcat 都对过：

| 项 | 证据 |
|---|---|
| 首次启动 | logcat：`boot: samples are 1` → `boot: installed 1 sample(s)` → `boot: done`，无异常 |
| 开屏通知 | 清数据后重装，弹出「Two things are not set up」，两个 key 都标 not set，带 `Set up now` / `Got it` |
| 阅读页 | 一行工具条（Translation + A−/A+），正文连续，**无逐句按钮**，界面无中文 |
| 查词 | 点 `pointers` 弹出英文释义 "a mark to indicate a direction or relation"，只有一个 Close |
| 星标 | 点一下变 `★ Starred`（朱红填充+边框+浅底），出现说明文案和 toast |
| 听力 | logcat：TTS 合成整句耗时 **5.5 秒**（旧版是 34ms 的空串），并自动推进下一句 |
| 锁屏播放 | `dumpsys activity services`：`isForeground=true`；通知含 **Previous / Pause / Next** 三键，`vis=PUBLIC` |
| 设置页刷新 | 进 `Who writes` 存一个 key，返回 hub 后该行从 `no key · the app works fully without one` 变成 `DeepSeek · a key is saved · deepseek-chat` |
| MiMo 模型 id | 设置页 `Who writes` 卡片显示 `mimo-v2.6-flash`，不再是已下线的 `mimo-v2.5` |
| **数据库迁移 v1→v2** | 用 v1 的真实数据（3 条 ledger、2 篇已写文章）升级安装：`user_version=2`，`length: 420` → `medium_words: 420`，`reader`/`topics`/`raw` 原样保留，queue 三行俱在且 `planned_band` 回填 `medium`。**触发器活过了重建**：手工插第 4 行被 `RAISE(ABORT, 'queue.size == 3')` 拒绝 |
| 难度分级 | 队列卡与阅读页头部显示 `312 words · 4 min read · Hard`，与标注密度一致 |
| 外观三档 | Light 切换后状态栏图标变浅色、Follow the phone 切回后变深色，两种都截图确认可见 |
| 字体切换 | 选 Roboto Mono 后正文变等宽；**点词仍然命中正确的词**（`pointers` 弹出 `pointers` 的释义）——命中测试的 `TextPainter` 必须用同一个字体，否则每个词都会偏 1~2 个位置 |
| AI 改配置 | 全流程实测：追加示例 prompt → `Asking…` spinner → 逐字段 jade diff → 锁定的 Close 显示 `Use this plan, or edit your request` → `Use this plan` → 数据库里 `style` 七条落库，`medium_words: 420` 与 `reader` 未被模型改动 |
| `Change it` 面板 | 主题 chip 单选（选中项 = 卡片当前主题）、长度 chip 显示 `Medium · ~420`；选 `An exact number` 出现步进器；`Use this` 后库里是 `planned_words=350, planned_band=custom` |

## 代码在哪

```
lib/
  main.dart               壳：全部状态 + 每个界面的接线（约 1900 行，见 ARCHITECTURE.md 的解释）
  domain/                 纯 Dart 模型与五条不变量，不 import Flutter
  data/                   sqlite / keystore / 词典 / 音频 / HTTP / 锁屏 handler
  core/                   设计 token 与基础件
  features/               每屏一个目录
  data/remote/            写作 agent：循环 / 工具 / 知乎 / MCP / 日志（纯 Dart，不 import Flutter）
  features/settings/      设置七行 + instructions 管理器 + debug 日志界面
tool/check_invariants.dart  五条不变量的可执行检查（不是单元测试，原因见下）
tool/check_agent.dart       agent 循环的 45 条检查（预算、重试、parse 全函数、日志打码、成本行与超时的一致性）
```

## 本轮补充（2026-10-08 第二轮）：三条交互修正

| # | 问题 | 处理 |
|---|---|---|
| 1 | **`Count this read` 点了没有任何反馈**：不显示已计了几次，离开再进来和没点过一样，用户会重复点 | 计数从数据库读出来实时显示。行文案：没读过 `finished reading?`；读过但今天没读 `finished reading? · read twice before, not today`；今天读过 `counted twice today · 2 in all`。按钮点击期间 `Counting…` 并禁用（与 `Write it` 同一套契约），写完后**从数据库重读**再刷新——不在内存里自增，因为 History 和书架都建在那一行上。进页面时先清零再异步读，防止上一篇的数字闪到这一篇上 |
| 2 | **`What you read` 没有恢复默认的选项** | 底部新增 `Restore the defaults`：改过配置时可点，点开是应用自己的确认 sheet（`Keep my plan` 是次级按钮）。恢复成 `const ReadingPlan()`；已经是默认时按钮**变灰**并显示 `Nothing to restore — this is already what a fresh install has.` |
| 3 | **快速迭代时无法确认实机装的是哪个包** | Settings hub 最底下加 mono 的 `version 0.2.0 (2)`。用 `package_info_plus` 读 Android 包管理器的 `versionName` / `versionCode`——**设备上真正装着的那一个**，不是源码里的常量。`pubspec.yaml` 升到 `0.2.0+2` |

第 1 条的根因值得记下来：`ArticleScreen.counted` 这个参数**从来没有被传进去过**，
所以它恒为 `false`，按钮无论读过几次都显示成第一次的样子。这正是「一个用户看不到的状态，
用户就会错误地相信它」——只不过这次是反过来，用户正确地不相信它，于是多点几次。

### 这一轮踩到的构建坑

加 `package_info_plus` 之后 `flutter build apk` 挂了十几分钟没有任何输出。
根因：**本机直连 `repo.maven.apache.org` 是坏的**（直连 12 秒超时，走代理 0.5 秒）。
触发条件不是「第一次构建」而是「依赖图变了」。已写进 `docs/BUILD.md`，
并给了判断方法：超过 2 分钟没有新输出就是在等网络，别等，直接加代理重来。

## 本轮（2026-10-08）：topic 被推翻 · instruction · 写作 agent · 可选信息源 · debug 日志

### 一句话

`topic` 整个设计删除，换成**用户自己写的 instruction** + **模型输出的 keywords**；写作从「一次调用」
升级成一个**有预算、有重试、有日志的小 agent**；可选接入知乎日报与阿里云 web_search MCP；
Settings 从 5 行变 7 行，新增 `Instructions` 与 `Debug log`。

### 你提的 5 条

| # | 问题 | 处理 |
|---|---|---|
| 1 | topic 影响生成随机性与丰富性，长期还要用户维护 | **已删**。`ReadingPlan.topics`、`PlanField.topics`、`QueueSlot.topic/focus`、`Article.topic/focus` 全部移除。8 个 plan 字段变 7 个。数据库 v2→v3 迁移把旧 topic **转换成 instruction**（`"NVDA"` → `"Write about NVDA"`），`Free pick` 占位符不转换 |
| 2 | topic 改为 instruction，用户自维护，可选旧的或写新的 | **已做**。`Instruction{id, text, createdDay, lastUsedDay, useCount}`，排序用 `COALESCE(last_used_day, created_day) DESC`。`Change it` 面板显示最近 10 条 chip + `✎ Write a new one` + `See all saved instructions ›`；`Settings → Instructions` 是完整管理器（搜索、增删改、二次确认） |
| 3 | 纯随机生成不受影响，模型自由发挥 | **已做**。instruction 为空即「You decide」，卡片显示 `Anything / the writer picks the subject`。prompt 里加了**当天日期与季节**，并要求「挑一个读者猜不到的题目」 |
| 4 | 模型输出 keywords 用于卡片渲染 | **已做**。`Article.keywords`（3~6 个词，每个 ≤3 个单词）。卡片与阅读页头显示为 mono 一行；解析失败只当空，不毁掉一次付费生成 |
| 5 | 接入知乎日报 + 阿里云 MCP，做成一个小 agent | **已做**。见下 |

### agent 实测（真 key，模拟器）

| 项 | 证据 |
|---|---|
| 知乎热榜 | 应用内 `Test the key` → `30 stories came back. Nothing was written.`（uapis.cn，8.4 KB） |
| 阿里云 MCP | 应用内 `Test the key` → `It offers bailian_web_search. Nothing was written.`（`tools/list`，不产生模型调用，**测试不花钱**） |
| **一次完整生成** | 日志：`hotboard fetched {items: 30}` → `run started {tools: [read_story, web_search]}` → `sending turn {reqBytes: 6171}` → `turn turn ok {status: 200, ms: 65421, completionTokens: 3092, toolCalls: []}` → `run succeeded {turns: 1, modelCalls: 1, spentCalls: 1}`。产出《Why Growing Sales Can Still Sink a Company》，167 词，Hard，keywords `quarterly report · revenue · cash flow · balance sheet` |
| 第二次生成 | 同样成功，163 词，Easy |
| **重启后正文还在** | 杀进程重开，卡片仍显示 `167 words · 1 min read · Hard` 与 keywords，点 Read **打开的是这一篇**（这条修的是一个既有缺陷 + 一个新发现的 bug，见下） |
| 数据库迁移 v2→v3 | 用真实 v2 数据（3 条 ledger、queue 三行带 topic、plan 带 `topics` 列表）升级：`user_version=3`，queue 的 `C language` → `instruction='Write about C language'` 且 `instruction_id` 指回新建的 instruction，`Free pick` → `''`，plan 的三个 topic → 三条 instruction（去重），ledger 历史 topic 原样保留。**触发器活过两次重建**：手工插第 4 行仍被 `RAISE(ABORT, 'queue.size == 3')` 拒绝 |
| 半迁移恢复 | 手工构造一个 `user_version=2` 但 schema 已是半 v3 的库（这正是第一次失败留下的状态），新代码能重新进入并走完，不再 brick |
| 卡片成本行 | 配了信息源时显示 `Write it · up to 5 calls`；关掉两个开关后变回 `Write it · ~$0.002`；`Change it` 面板显示 `free · nothing is written` |
| instruction 生效 | 在 `Change it` 里写 `Read one of today's news stories and write about one`，卡片标题立刻变成这句话、副标题 `your instruction`，生成时模型照做去读了新闻 |

### 这一轮实测抓出来的四个真 bug（都不是推断，是跑出来的）

| # | 症状 | 根因 | 修法 |
|---|---|---|---|
| 1 | 升级安装后应用启动即空队列，日志 `no such column: "topic"` | 迁移里 `INSERT ... SELECT ... FROM queue_rows WHERE "topic" <> ''` 跑在 `queue_rows` 重建**之后**，而那次重建已经把 `topic` 列删了。语句在 PREPARE 阶段就失败，整个 upgrade 中止 | 所有需要读旧列的操作**提到所有分支之前**（`_readOldTopics` / `_readOldQueueTopics`），并且每一步都用 `_hasTable` / `_hasColumn` 判断当前实际 schema——迁移变成**可重入**的 |
| 2 | 生成 60 秒超时两次，白花钱没产出 | 假设「一次调用 10~20 秒」。实测：`say hello` 1.1 s、带工具 2.5 s、完整 prompt + 30 条标题 + 两个工具 8.9 s、**真正写一篇 180 词带中文译文 72.4 s**。写文章比其它调用慢一个数量级 | `kPerCallTimeoutSeconds` 60 → **240**，`kMaxWallClockSeconds` 120 → **420**，`RemoteApi._writeTimeout` 60 → **240**。成本行从 `~25 s` 改成 `~1–3 min`。`check_agent.dart` 加了三条断言把这两个数字和文案钉在一起 |
| 3 | 重启后点 Read，打开的是**另一篇**文章 | `_articleFor(id)` 只查 `_samples` 和内存里的 `_written`。重启后正文只在 queue slot 里（从 `article_rows` 水合），查不到就回落到「第一个 ready slot」= 内置样例 | `_articleFor` 增加第三处查找：扫 `_queue.slots` |
| 4 | 设置页 `Sources` 两张卡片各有一屏空白 | `Btn` 的 build 是 `SizedBox(width: double.infinity)`，放进 `Row` 得到无界宽度 → layout error。**release 模式下错误 widget 渲染成一大块空白**，不是红色，所以看起来像「卡片就是很高」 | 按钮与成本行改成上下排列 |

另外顺手修的：

- **`ready` 卡片没有正文时不再给 `Read`**。两种来源：读者在 library 里 free 掉了字节，或文章写在「正文入库」之前。以前给一个点开是空页的 `Read`，现在卡片写 `the text is no longer on this phone · ⋯ to replace it`，⋯ 菜单里 `Read it` / `Listen to it` 两行也关掉，换成一行说明。`_openArticle` 加同一道锁。
- **确认面板的「安全选项」不再是主按钮**。`Btn` 默认 `primary: true`，所以 `Keep it` 和 `Delete` 并排两个朱红按钮——既是设计禁止的第二个强调，也让「删」和「不删」长得一样。
- **日志补了「发送前」那一行**。第一次超时排查时日志里只有 `retrying in 500ms {attempt: 1, reason: timeout}`，没有任何关于「发了什么、多大、带了哪些工具」的信息——分不清是模型在想还是请求根本没出去。现在 POST 之前先记一行。
- **debug 日志的级别标记**。info 行原本渲染成 `done · · · rmuy…`（三个点连排），现在 info 不写级别词，只有 warn / error 才写。

### 成本诚实：三处

| 位置 | 改动 |
|---|---|
| `RemoteFailure.spent` | 新增。任一 POST 拿到 2xx 就置 true。`api.dart` 那句无条件的 `Nothing was sent and nothing was spent.` 变成按 `spent` 二选一 |
| 成功 toast | 从写死的 `one call` 改成循环报回的**真实调用次数** |
| 卡片按钮 | 无信息源 = `Write it · ~$0.002`（默认读者，文案不变）；有信息源 = `Write it · up to 5 calls` |

### 补测（同日，用户要求实机跑一遍）

上一版这里写着三条「没做」，现在都做了，而且**又抓出两个 bug**：

| 项 | 结果 |
|---|---|
| **`read_story` 真的被调用** | 用 instruction「Read one of today's news stories and write about one」逼出研究行为。日志：turn 1 `finish: tool_calls`，`toolCalls: [read_story, read_story]` **并行两个**；两次抓取 `story fetched {id: 9792945, text: 1527}` 与 `{id: 9793078, text: 2437}`，各 283 ms / 166 ms；turn 2 写出《Why Nobody Farms Elephants》，385 词，Easy，keywords `feed costs · meat prices · livestock…`。**这一轮读了 2 篇、共 2 次模型调用、274 秒** |
| **快路径** | 两个信息源开关关掉后，卡片立刻变回 `Write it · ~$0.002`（截图）；点下去 65 秒产出《A Phone That Never Hears Music》171 词。**`AgentLog` 全程为空**——证明没有进循环，是真的单次调用 |
| **飞行模式** | 关掉 wifi/data 后点 Write it，得到一句人话：`Could not reach the provider — check your connection, then try again. Nothing was written and nothing was spent.` 卡片回到 `planned · not written yet · nothing has been paid for`，按钮可点，**没有卡在 Writing…** |

### 补测抓出来的两个 bug

| # | 症状 | 根因 | 修法 |
|---|---|---|---|
| 5 | 研究那一轮写了 **230 秒**，而 per-call 上限是 240 秒——**只差 10 秒就又被砍掉** | 240/420 这组数字是从一次 72 秒的文章推出来的，没算上「读完两篇再写」的那种调用（10911 个 completion token，其中 31441 字符是模型自己的推理） | `kPerCallTimeoutSeconds` 240 → **360**，`kMaxWallClockSeconds` 420 → **600**；成本行改成 `~1–10 min`；`check_agent.dart` 的断言改成对着 **230 秒这个实测值**，而不是对着感觉 |
| 6 | 飞行模式的 toast 里是一段调用栈：`Could not reach https://api.xiaomimimo.com/v1/chat/completions — ClientException with SocketException: Failed host lookup: 'api.xiaomimimo.com' (OS Error: ...` | `api.dart` 的 catch 把异常插进了给读者看的句子 | 读者拿到 `Could not reach the provider — check your connection, then try again.`，**技术细节进日志**（`[http] could not reach the provider {url, what, error}`）。同时删掉了只为这件事存在的 `_short()` |

第 6 条正是「必须实机跑一遍」的价值：这段文案在代码里读起来完全正常，
只有把它显示在一个关掉无线电的手机上，才发现是给学习者看的一段栈帧。

## 上一轮（2026-10-07 第二轮）：配置重做 · 难度分级 · 外观三档

### 你提的 5 条

| # | 问题 | 处理 |
|---|---|---|
| 1 | 「每篇标几个解释的词」不该是固定数字 | **已删**。`ReadingPlan.marked` 整个移除，prompt 里不再出现「最多标 N 个」。标几个由模型判断，App 反过来按密度算难度（`difficulty.dart`，阈值取自 Nation 2006 / Laufer 1989 的 98% / 95% 覆盖率）。`The small print` 里写清了它**不**说明什么 |
| 2 | 字数该是短/中/长三挡 | **已改**。`length` 变成 `shortWords`/`mediumWords`/`longWords`（默认 180/300/500），设置页可逐挡编辑。队列随机抽一挡；⋯ 菜单可选具体挡位、Random 或**精确数字**。数据库 v1→v2 迁移把旧的 `length` 搬进 `mediumWords` |
| 3 | 外观切换放在 `The small print` 语义不对 | **已改**。hub 新增 `Appearance` 行（五行），Light / Dark / Follow the phone 三档，默认跟随手机。**这推翻了 DESIGN §4/§11 的「no night no day」**，但只推翻了一半：仍然没有任何时钟参与，唯一能自己换面的是手机自身的设置 |
| 4 | 字体只有两档 | **已改**。6 种，每个都带实时预览（英文 + 中文）。默认 `Noto Serif`——理由见 ARCHITECTURE.md：只有系统字体族的中文才配得上（`fonts.xml` 的 `fallbackFor="serif"` 会让中文走 Noto Serif CJK），bundle 的拉丁字体没有中文，中文会掉到无衬线 |
| 5 | 没有「配置生成偏好 + AI 生成配置」的页面 | **已做**。`What you read` 现在是完整的配置页；新增 `✦ Ask the AI to change it`：示例 prompt 可叠加、`Asking…` spinner、逐字段 diff、**有未接受的付费结果时 sheet 锁定**（Close 变成 `Use this plan, or edit your request`），编辑输入即作废 diff。`PlanRewrite` 这套领域类型此前写好但从未接过 UI，现在接上了 |

### 顺手修掉的死代码 / 死菜单

| 项 | 问题 |
|---|---|
| ⋯ 菜单的 `Write it again` | 调 `_write()`，而 `_write` 开头就是 `if (!slot.isPlanned) return`——在 ready 卡上**永远静默早退**。改为 `_writeAgain()`：先 `retireReadySlot`（免费，旧文进 library 且计数保留）再走正常付费写入 |
| `Choose another topic` + `A different plan` | 合并成一个 `Change it`。原两条一个改主题不改长度、一个什么都不问就全改，都表达不了「同样的意思，短一点」 |
| `_freePlan()` 固定 300 字 | 改为随机抽短/中/长 |
| `ArticleWriter._userPrompt` 重复罗列 plan | 改为复用 `plan.toPrompt()`——两份渲染已经漂移过（一份写 `Articles may come from`，另一份写 `Topics may come from`） |
| `RemoteApi` 失败文案 | `what` 从动词短语改成动名词短语。旧写法会产出 `That address has no speak a sentence endpoint` 和 `nothing to speak a sentence`——两句从没被读出声过的话 |
| `Pill` 文字溢出 | 长 chip 会 `RIGHT OVERFLOWED BY 1.8 PIXELS`。`Text` 包进 `Flexible` |
| 状态栏图标 | `main()` 里硬编码 `statusBarIconBrightness: light`（为深色底写的），在默认的浅色面上几乎看不见。改为随主题反色 |
| 计划卡不显示长度 | `QueueSlot.lengthLabel` 定义了但从未渲染——读者选完长度，卡片看起来毫无变化。已渲染 |

## 上一轮（2026-10-07）修的问题

### 你提的 9 条

| # | 问题 | 处理 |
|---|---|---|
| 1 | 每行都有「译」「听」，影响阅读 | **已改**。逐句按钮全部删除，改为顶部一行工具条：全局译文开关 + 字号三档。正文里点词查义、长按整句发音。`article_screen.dart` |
| 2 | 超大按钮、不对称块、两个 Close、`tap for 中文`、星标无状态反馈 | **已改**。sheet 外框只画一次（不再有第二个 Close）；星标状态搬进 sheet 本体，点击立刻翻转并变色；`want this again` 是英文且带状态。`word_sheet.dart` / `primitives.dart` |
| 3 | 听力行太大、没有字号调节、播放器按钮丑 | **已改**。加了 Medium/Large/Huge 三档字号；播放器换成 Material 图标（原来是 `⏮▶⏭` 字符，在 Android 上渲染成**橙色 emoji 方块**）。`listen_screen.dart` |
| 4 | 空白；`what are they about` 与顶部齿轮重复 | **已删**。那个按钮和它下面那段解释一并移除，代码里留了注释说明为什么。`main.dart:805` |
| 5 | 样式 bug；MiMo 无法配置使用 | **已改**，见下面「MiMo 为什么配不上」 |

### MiMo 为什么配不上（三个独立原因，都不是接口写错）

调研过官方文档后确认：base URL、TTS 把正文放 `assistant`、`audio:{format,voice}`、
`choices[0].message.audio.data` 取 base64、Bearer 认证——**全部正确**。真正的问题是：

1. **设置页保存后不刷新。** `_stack` 里存的是**已构造好的 widget 实例**，`build()`
   每次返回同一个对象，Flutter 判定 widget 未变就整棵子树跳过重建。于是 key 写进了
   keystore，界面还显示「not set」。已改成存 builder。
2. **`_hasWriterKey` 从未被赋值**，恒为 false。设置页的 hub 永远说「没存 key」，
   `Test the key` 永远禁用。已在 `_loadPreferences` 和保存回调里补上。
3. **voice 列表里 4 个 id 是错的。** `Ice Sugar` / `Jasmine` / `Soda` / `Birch` 是
   冰糖/茉莉/苏打/白桦 的**英译**，不是 API 的 voice id，选中必然被拒。已删——
   这个 app 的文章是英文、DESIGN 把 voice 钉死在 en-US，中文音色在这里没有用途。
   保留 `mimo_default` / `Mia` / `Chloe` / `Milo` / `Dean`（官方 5 个英文音色）。

另外把写作模型从 `mimo-v2.5` 换成 `mimo-v2.6-flash`：前者 **2026-10-21 下线**，
之后是 404 而不是警告。

### 「所有听都没法用」

**根因是 Android 包可见性。** `AndroidManifest.xml` 的 `<queries>` 里只有
`PROCESS_TEXT`，没有 `android.intent.action.TTS_SERVICE`。Android 11+ 下
`flutter_tts` 因此找不到系统语音引擎，**设备语音这条路上每个字都是静音**——
而播放按钮看起来是活的。已补上。

同时修掉的音频层问题：

- `_toggle` 在整篇播完后调 `player.resume()`，而 `resume()` 首行是
  `if (_currentText.isEmpty) return;`，且 `_finish` 已经清空了文本 →
  按钮变成暂停图标、刻度不动、没有声音。改成重播当前句。
- MiMo 回退到设备语音时，把回退写进了**配置字段**，于是一次请求失败就让 MiMo
  在本次会话里永久关闭。拆成 `_configured` / `_lastSpoken` 两个字段。
- `_configureTts()` 在构造函数里 fire-and-forget，和第一次 `speak()` 竞态。
  改成 `late final Future` ，所有发声路径先 await 它。

### 新增

- **锁屏 / 后台播放**（DESIGN 的用例 #2，此前 pubspec 声明了 `audio_service`
  却零使用）。新增 `lib/data/handler.dart`，`main()` 里 `AudioService.init`，
  `MainActivity` 改继承 `AudioServiceActivity`，manifest 加前台服务、
  `MediaButtonReceiver` 和 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限。
- **开屏通知**（`_maybeShowSetupNotice`，原本就在）：检测 writer / voice 两个 key，
  **缺任意一个**才弹，带「Set up now」跳设置和「Got it」关闭，只弹一次。

## 已知未完成 / 明确不做

| 项 | 状态 |
|---|---|
| 单元测试 | `test/` 是空的。本机 `dart test` 起不来（native-asset 子进程 `CreateFile` 231 失败），所以不变量用 `tool/check_invariants.dart` 以**可执行程序**的形式锁住 |
| 写作端点形状 | DESIGN §9/§11 规定「唯一形状是 `POST {base}/responses`」，但实现走的是 `/chat/completions`。DeepSeek 和 MiMo **都没有** `/responses`（只有 OpenAI 有），所以按文档写会让另外两家直接不可用。实现选了能工作的那个，这是一个**文档与现实的冲突**，需要你决定改代码还是改文档 |
| 逐词卡拉OK高亮 | 不做。MiMo 不返回 word boundaries，DESIGN §9 明确只做句子级 |
| ~~夜间模式~~ → **外观三档** | 已做（2026-10-07 推翻原决定）。`Settings → Appearance` 提供 Light / Dark / **Follow the phone**，默认第三项。**仍然没有日夜概念**：没有任何时钟参与，唯一能自己换面的是手机自身的设置，而且只有读者明确要求时才生效。同时提供 6 种正文阅读字体（见 ARCHITECTURE.md「Appearance」） |
| 文章正文不落库 | 已存在的行为，但有一个可见后果：**重启后，之前写的文章卡片会显示 `0 words · 0 min read`，点 Read 打开是空的**。正文只在内存里（`_written`），数据库只存身份与计数。要修需要新增一张正文表——那和「counts are not storage」的设计直接冲突，属于要你拍板的架构决定，没动 |
| 评分 / 打卡 / 进度环 | 不做，DESIGN §1 明确禁止 |
| **pubspec 里 6 个依赖声明了但零引用** | `flutter_riverpod` / `go_router` / `freezed_annotation` / `json_annotation` / `intl` / `collection`，以及 dev 的 `freezed` / `json_serializable`——全仓 `grep 'package:<名字>/'` 零命中。但 pubspec 的注释在为它们辩护（"Provider composition expresses 'computed from that'"、"Nested routes and route parameters carry that context"），而 `main.dart` 里**没有任何 Provider、没有任何路由表**，状态由 `_ShellState` 单点持有。**删依赖等于改架构**，所以留着没动，等你决定：要么删掉并改写注释，要么按注释把 Provider / go_router 真的用起来 |
| **「总有一篇新的在等你」这条原则没有实现** | 见下面专门一节。**这是设计冲突，不是漏掉的代码** |

## 「总有一篇新的在等你」——冲突在哪儿，以及我提的方案

读者提出的原则是：**无论什么情况，至少有一篇新的在等你。** 当前代码做不到，因为
三份文档在承诺三件不同的事：

| 位置 | 承诺 |
|---|---|
| `lib/main.dart:1069`、`README.md:16`、`USER_GUIDE.md` | "Finish one and the next is written **at once**" / "读完一张，就补一张新的" |
| `lib/domain/queue.dart:255` + DESIGN.md:194 | "Done with it replaces a card with a **plan**, not an article — so the next thing also **waits**" |
| 代码实际行为 | 读完**什么都不发生**；换卡只有 `Done with it` 一条路，换成的是一张免费计划卡 |

代码是自洽的：全仓没有 Timer / WorkManager / 后台任务，`_write` 的三个调用点全是点击触发，
`mayAutoWrite` 守的是一条**不存在的代码路径**。所以"读完自动补一篇"从来就没实现过，
而三处 UI 文案一直在承诺它。

### 我提的方案（未实现，等你拍板）

读着读者的枚举，真正想说的是「**总有一篇你还没碰过的在等**」。这比"自动写一篇"便宜得多，
也不碰成本上限——它不需要花一分钱：

> **队列里永远至少有一张 `planned` 卡。**
>
> 具体规则只有一条：当三张卡全是 `ready`、且没有一张 `planned` 时，把**读得最多/
> 听得最多的那一张**收进 Library（`retireReadySlot`，计数完整保留、可重开），
> 空出的位子放一张免费计划卡。
>
> 于是所有状态都收敛到读者枚举的那三种，而且不再有第四种：
>
> | 状态 | 怎么到达 | 怎么离开 |
> |---|---|---|
> | 1 planned + 2 ready | 常态 | 点 `Write it`（花钱） |
> | 2 planned + 1 ready | 写完一篇，或 `Done with it` 掉一篇 | 点 `Write it` |
> | 3 planned | 全部 `Done with it` | 点 `Write it` |
>
> 读者枚举的"情况 3"（1 已学 + 2 待生成）由此变成**瞬态**而非稳态——它只在一个动作
> 与下一个动作之间存在，队列自己会收敛回 1 planned。
>
> 代价：**收窄了不变量 3**。"Reading counts and never removes" 变成 "reading counts and
> never removes，除非三张都读完"——那时动的是读过最多的那张，而它本来就是读者最可能
> 不想再当头一篇的。读者若不同意这个代价，替代方案见下。

两个替代方案，都不实现原则：

- **改文案**（`main.dart:1069`、`README.md:16`、`USER_GUIDE.md` 三处）改成实话，
  加一个"三篇都读完了"的提示。零花费、零架构改动，代价是原则不实现。
- **真的自动写**：三张都读过且无计划卡时自动写一篇。完全满足期待，但打破
  「未经同意不花钱」的硬顶，需要重写成本上限说明、加设置开关、限定只能前台触发。

## 环境坑（会再咬人，记下来）

**`flutter build apk` 会卡死十几分钟且没有任何输出。**

根因：`io.flutter:armeabi_v7a_debug:<hash>.jar`（114 MB）在 Gradle 缓存里**只有 .pom
没有 .jar**，Gradle 每次构建都去 `storage.googleapis.com` 下载它，而直连会在
3.5 MB 左右断掉，于是无限重试。三个 ABI 里只有这一个是坏的。

判断方法：`jstack <gradle pid>` 会看到 `ParallelResolveArtifactSet` /
`visitArtifacts`，worker 线程全在等网络，进程 CPU 几乎不涨。

绕过方法——**给 Gradle 构建 JVM 挂代理**：

```bash
cd Marginalia/android
./gradlew assembleDebug -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897 \
                        -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897
```

`--offline` **不管用**：手工把 jar 放进 `files-2.1` 也不会被认出来，Gradle 的
artifact→file 索引在 `metadata-*/` 里，不扫目录。

另外：`gradle.properties` 里设了 `kotlin.incremental=false`，那是有意的取舍，
注释里写了原因，别顺手删。

## 怎么验证

```bash
# 不变量（五条设计硬规则）
dart tool/check_invariants.dart

# 静态检查：应无 error，warning/info 可忽略
flutter analyze

# 离线词典解码器对着真包跑一遍
dart tool/check_dictionary.dart
```


---

## 模拟器测试结果（2026-10-11 · d511f85 + a8aa32f）

证据：`docs/verify/d511f85/`（41 张截图）。驱动方式：adb tap/swipe + screencap。

| 组 | 结果 | 备注 |
|---|---|---|
| 1 冷启动与基线 | **通过** | `boot: done`；卡片有间距；SAMPLE 标签；脚注非卡片 |
| 2 取词翻译 | **通过** | 折行第 2/3 行命中正确；标题可点词；二级纯中文释义可关闭无递归；Translation 可收起 |
| 3 样例覆盖 | **通过** | 自定义指示生成 `What a Hash Map Really Is`，重启后仍在；样例不再顶掉正文 |
| 4 重新生成与统计 | **通过** | Write a new one 先出选题面板；Done with it toast 明示 not counted as a read；日历今日无 read |
| 5 Listen 页 | **通过** | 默认不自动播；点词/翻译 hide/从头/Read↔Listen 保位；听完全文 listens +1 |
| 6 Listening 设置 | **通过** | 三段齐全；Play at once 会自动播；改回 Wait 后不播 |
| 7 随机音色 | **通过** | Random 在首位；选中后 hub 显示 `MiMo · Random`；Mia 恒定 |
| 8 Debug log | **通过** | 按 run 分组卡片；人话标题+时间；失败红框含 could not reach the provider；hub 写 N things asked for |
| 9 收尾 | **通过** | analyze 0 error；133+45 不变量全过；APK 73 MB；冷启动正常 |

### 测试中发现并修复的 bug

**样例槽位未 hydrate**（`a8aa32f`）：`_openArticle(q.slots[i])` 传的是数据库 stub
（有 id 无正文），`sentences.isEmpty` 直接 return——卡片渲染用的是 `_hydrated` 副本
所以画了 Read 按钮，点下去却什么都不做。菜单同样读 stub，把有正文的文章误报成
"the text is gone"。修复：`_openArticle` 内部先 `_hydrated(slot)`，`_slotMenu` 同理。

### 未逐条走完的项

- 5.6 Next article：当时队列只剩一篇 ready（A Phone 已被 Done with it 归档），
  按钮按设计隐藏。逻辑由 `_peekNextListen` 保证，check_invariants 覆盖。
- 7.3 两篇音色是否不同：需听感对比，截图无法取证；`_resolveVoice` 每次 stop 重摇。
- 8.5 Copy all 剪贴板内容：adb 读不到 Android 剪贴板；`AgentLog.dump()` 的分段
  格式由 check_agent 覆盖。
