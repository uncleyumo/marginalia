# 项目现状

> 最后更新：2026-10-07
> 这份文档说的是**代码实际做到的事**。当它和 `FLUTTER_PLAN.md` 冲突时以它为准——
> 那份规划写于动工之前，第 5 行至今还写着"尚未写任何业务代码"。

## 一句话

五个界面（Queue / Article / Listen / Library / History / Words / Settings）全部实现，
离线词典、设备 TTS、MiMo 语音、写作链路、锁屏播放都已接线。**没有 stub，没有 TODO。**

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

## 代码在哪

```
lib/
  main.dart               壳：全部状态 + 每个界面的接线（约 1900 行，见 ARCHITECTURE.md 的解释）
  domain/                 纯 Dart 模型与五条不变量，不 import Flutter
  data/                   sqlite / keystore / 词典 / 音频 / HTTP / 锁屏 handler
  core/                   设计 token 与基础件
  features/               每屏一个目录
tool/check_invariants.dart  五条不变量的可执行检查（不是单元测试，原因见下）
```

## 本轮（2026-10-07）修的问题

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
| 夜间模式 | 不做。DESIGN §4/§11 明确没有日夜概念（`The small print` 里的外观切换是配色偏好，没有时间语义） |
| 评分 / 打卡 / 进度环 | 不做，DESIGN §1 明确禁止 |
| **pubspec 里 6 个依赖声明了但零引用** | `flutter_riverpod` / `go_router` / `freezed_annotation` / `json_annotation` / `intl` / `collection`，以及 dev 的 `freezed` / `json_serializable`——全仓 `grep 'package:<名字>/'` 零命中。但 pubspec 的注释在为它们辩护（"Provider composition expresses 'computed from that'"、"Nested routes and route parameters carry that context"），而 `main.dart` 里**没有任何 Provider、没有任何路由表**，状态由 `_ShellState` 单点持有。**删依赖等于改架构**，所以留着没动，等你决定：要么删掉并改写注释，要么按注释把 Provider / go_router 真的用起来 |

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
