# 打包与验证操作手册

这份文档只讲**怎么在这台机器上把 Marginalia 打包出来、装进模拟器、并确认它真的能用**。
架构与设计见 `ARCHITECTURE.md`，当前状态见 `STATUS.md`。

---

## 0. 三条命令（急着要 APK 的话）

```bash
cd Marginalia

# 1. 设 SDK 路径。每个新开的 shell 都要设一次，不设 build 会报 No Android SDK found
export ANDROID_HOME="/path/to/Android/sdk"

# 2. 静态检查 + 两条可执行规则（约 15 秒，不碰网络）
flutter analyze --no-pub
dart tool/check_invariants.dart     # 五条不变量，126 项
dart tool/check_agent.dart          # agent 循环，45 项

# 3. 打包
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`（约 72.8 MB）

装进模拟器：

```bash
ADB="$ANDROID_HOME/platform-tools/adb.exe"
MSYS_NO_PATHCONV=1 "$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 1. 环境：三个不在 PATH 上的东西

| 东西 | 在哪 | 为什么要单独说 |
|---|---|---|
| Android SDK | 你的 Android SDK 路径（见上） | 路径写在 `android/local.properties` 的 `sdk.dir`。**`flutter build` 只认 `ANDROID_HOME` 环境变量**，不会去读那个文件，所以每个 shell 都要 export |
| JDK 21 | 一个 JDK 21 的路径 | 已经钉在 `android/gradle.properties` 的 `org.gradle.java.home`，**不需要设 `JAVA_HOME`**。见下面「为什么钉 JDK」 |
| `adb` | `$ANDROID_HOME/platform-tools/adb.exe` | 不在 PATH 上。**Git Bash 里任何以 `/` 开头的设备路径都要加 `MSYS_NO_PATHCONV=1`**，否则 Git Bash 会把它改写成 Windows 路径，adb 报 `remote secure_mkdirs failed` |

`flutter analyze` 和 `dart` **不需要** `ANDROID_HOME`，只有 Gradle 需要。

### 为什么 JDK 要钉在项目里

`avdmanager` 需要 JDK 8（在 11+ 上会因为 JAXB 被移除而 `NoClassDefFoundError`），
Gradle 9 需要 JDK 17+。一个全局 `JAVA_HOME` 只能满足其中一个，所以钉在项目里，
`avdmanager` 单独在命令行上给 `JAVA_HOME=8`。

### 代理：只要「依赖有变化」就必须加

**本机直连 `repo.maven.apache.org` 是坏的。** 实测：直连 12 秒超时，走代理 0.5 秒。
所以任何**需要下载新 artifact** 的构建都会挂在 Gradle 里十几分钟，**没有任何输出**。

触发条件不是「第一次构建」，而是「依赖图变了」——加一个插件、升一个版本、
甚至 `pub get` 动了传递依赖，都会重新去 Maven 取东西。2026-10-08 加
`package_info_plus` 时就是这么挂的（顺带还装了 Android SDK Platform 34）。

```properties
# TEMPORARY-PROXY-MARKER
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7897
```

加到 `android/gradle.properties` 末尾。**打完包删掉再提交。**

**判断方法**：`flutter build` 超过 2 分钟没有新输出，就是它在等网络。
不要等，直接 Ctrl-C、加代理、重来。依赖缓存住之后，普通重建不需要这两行。

---

## 2. 打包

### 只有一种签名

`android/app/build.gradle.kts:50` 写着 `signingConfig = signingConfigs.getByName("debug")`——
**release 包也是用 debug key 签的**。所以 `flutter build apk --debug` 和 `--release`
可以互相覆盖安装（`install -r`），数据不丢。这对升级安装测试是必要的。

代价：这个 APK 不能上架任何应用商店。要上架得先生成正式 keystore。

### release 与 debug 的区别，实测过的两条

| | debug | release |
|---|---|---|
| 速度 | JIT，明显卡 | AOT，跟手 |
| **布局错误怎么显示** | 红色错误块 + 文字 | **一大块空白** |

第二条值得记住：`Btn` 是 `SizedBox(width: double.infinity)`，放进 `Row` 会得到无界宽度。
debug 下是红框报错，release 下渲染成一大片白，看起来像「卡片本来就很高」。
**UI 布局问题一定要用 release 包再看一眼**，否则会被 debug 的报错块误导成「这个 bug 只在 debug 有」。

### 改版本号

`pubspec.yaml` 第 11 行：

```yaml
version: 0.4.0+11      # versionName+versionCode
```

**每次交付前跑一次这个**，别手改：

```bash
dart tool/bump_version.dart
# → 0.4.0+12  (was 0.4.0+11)
```

它只动 build number（`+11` → `+12`），不动语义版本号，同时把
`android/local.properties` 里 Flutter 自己缓存的那两行一起刷掉。
`--quiet` 可以关掉输出。

Settings 页最底下会显示 `version 0.4.0 (12)`，这是从 Android 包管理器读的
`versionName` / `versionCode`，也就是**设备上真正装着的那一个**——快速迭代时用来确认
「手机跑的是不是我刚打的那个包」。版本号不变的话，这一行就分不出两个不同的构建，
而手改这件事漏一次就成了一个上午的困惑。

### 打包命令与产物

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk（192 MB，只用来跑 run-as 取数据库）
```

`--split-per-abi` 没开：这个包只装在自己手机上，一个 fat APK 省事。

---

## 3. 装进模拟器并驱动

### 起模拟器

屏幕是 **1080×1920**，所以下面的 PNG 像素坐标 == 设备坐标。

```bash
"$ANDROID_HOME/emulator/emulator.exe" -avd marginalia64 -no-skin -no-boot-anim
"$ANDROID_HOME/platform-tools/adb.exe" wait-for-device
```

### 用 adb 驱动 UI

```bash
ADB="$ANDROID_HOME/platform-tools/adb.exe"

# 截图。注意 PNG 就是 1080×1920，也就是 PNG 上的像素坐标 == 设备坐标
MSYS_NO_PATHCONV=1 "$ADB" shell screencap -p /data/local/tmp/s.png
MSYS_NO_PATHCONV=1 "$ADB" pull /data/local/tmp/s.png ./s.png

# 点击
MSYS_NO_PATHCONV=1 "$ADB" shell input tap <x> <y>

# 滑动
MSYS_NO_PATHCONV=1 "$ADB" shell input swipe <x1> <y1> <x2> <y2> <毫秒>

# 输入文字。空格必须写成 %s，撇号会让 shell 报 no closing quote
MSYS_NO_PATHCONV=1 "$ADB" shell input text "Read%sone%sof%stodays%sstories"
```

**盲点击踩过的三个坑**（都真的浪费过时间）：

1. **坐标要按 PNG 上的像素读**，不要凭观感估。PNG 是 1080×1920，跟设备 1:1。
2. **滑动前先确认列表的滚动位置**。同一套坐标在列表滚到不同位置时命中完全不同的行——
   「点歪了」和「按钮坏了」在截图上一模一样。
3. **点击前先截图确认目标在屏上**。一次成功 = 一次截图 + 一次点击，
   比连点五次再猜哪里出错便宜。

文字输入要**先点中输入框**再 `input text`，否则文字会掉在地上（界面看起来完全正常，
只是输入框是空的）。

### 取数据库

应用把 sqlite 放在 `files/no-stop.db`（`getApplicationSupportDirectory()`，**不是** `app_flutter/`）。

```bash
# release 包取不了：run-as 要求 debuggable。要先装一次 debug 包
MSYS_NO_PATHCONV=1 "$ADB" shell am force-stop com.marginalia.reader
MSYS_NO_PATHCONV=1 "$ADB" shell "run-as com.marginalia.reader cat files/no-stop.db > /data/local/tmp/x.db"
MSYS_NO_PATHCONV=1 "$ADB" shell "run-as com.marginalia.reader cat files/no-stop.db-wal > /data/local/tmp/x.db-wal"
MSYS_NO_PATHCONV=1 "$ADB" pull /data/local/tmp/x.db ./x.db
MSYS_NO_PATHCONV=1 "$ADB" pull /data/local/tmp/x.db-wal ./x.db-wal
```

四个必须做对的地方：

- **必须 `am force-stop`**，否则应用持有连接，拷出来的 `.db` 和 `-wal` 不是一对，
  WAL 不会重放，你看到的是一个空库（`user_version 0`、没有表）。
- **`-wal` 一定要一起拷**。这个库是 WAL 模式，主文件可能一个页都没有。
- **重定向必须在 `run-as` 外面**：`run-as` 掉权限，写不了 `/data/local/tmp`；
  外层 shell（uid 2000）可以。
- **不要用 `adb shell ... cat > 本地文件`**：Windows 的管道会把 `\n` 转成 `\r\n`，
  49152 字节的库拷出来是 49164 字节，文件头就坏了。**用 `adb pull`**。

本机和设备上都**没有 `sqlite3` 命令行**，用 Python 的 `sqlite3` 模块，路径用相对路径
（Windows 的 Python 解析不了 Git Bash 的 `/tmp/...`）。

### 看日志

```bash
# 应用内：Settings → Debug log（倒序、可展开、Copy all）
# 命令行：
MSYS_NO_PATHCONV=1 "$ADB" logcat -d -s flutter:* | grep -E "flutter : \["
```

`AgentLog` 每条同时 `print`，所以 logcat 拿得到同样的内容。
**agent 的每一行都在这里**：`[plan] run started`、`[http] sending turn`、
`[tool] tool ok`、`[done] run succeeded`。一次失败生成能靠 `runId` 串起来。

`[http] sending turn` 是**发送前**写的。第一次排查超时的时候没有这一行，
日志里只有 `retrying in 500ms {reason: timeout}`，分不清「模型在想」和「请求根本没出去」。

---

## 4. 改完之后跑什么

### 每次改动

```bash
export ANDROID_HOME="/path/to/Android/sdk"
flutter analyze --no-pub          # lib/ 必须 0 error 0 warning
dart tool/check_invariants.dart   # 126 项
dart tool/check_agent.dart        # 45 项
```

`tool/` 下的两个可执行程序不是单元测试。**本机跑不起 `dart test`**
（native-asset 子进程 `CreateFile` error 231），所以规则用可执行程序锁，
`test/` 是空的。改动了不变量、预算常量、或成本文案，这两个程序必须跟着改——
它们存在的意义就是让「代码」和「屏幕上写的字」不能各自漂移。

### 动了数据库 schema

`TableMigration` 重建一张表会**连带 DROP 掉它上面的触发器**。
`queue_at_most_three` 是不变量 1 的数据库实现，所以 `_installQueueTrigger` 必须在
`onCreate` 和 `onUpgrade` **两处**都调。迁移链里 `queue_rows` 被重建两次，
所以 `onUpgrade` 末尾那次调用不是可选的。

迁移还必须是**可重入**的：每一步先用 `_hasTable` / `_hasColumn` 问当前 schema 实际长什么样。
第一版没做这件事，一个 `INSERT ... SELECT` 选到了前面刚删掉的列，在 PREPARE 阶段失败，
upgrade 中止——而 SQLite 已经把 DDL 提交了。用户被留在一个 `user_version=2`
但 schema 已是半 v3 的库上，下次启动死在 `table instruction_rows already exists`。

跑完 `build_runner` 之后，升级安装测试：

```bash
flutter build apk --release
MSYS_NO_PATHCONV=1 "$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
MSYS_NO_PATHCONV=1 "$ADB" logcat -c
MSYS_NO_PATHCONV=1 "$ADB" shell am start -n com.marginalia.reader/.MainActivity
MSYS_NO_PATHCONV=1 "$ADB" logcat -d -s flutter:* | grep -iE "boot:|no such|exception"
```

期望看到 `boot: done`，不该有 `no such column`。

---

## 5. 发布前清单

按顺序过一遍，每一条都是**实测过的**，不是「应该没问题」：

- [ ] `flutter analyze --no-pub` → lib/ 0 error 0 warning
- [ ] `dart tool/check_invariants.dart` → 126 全绿
- [ ] `dart tool/check_agent.dart` → 45 全绿
- [ ] `flutter build apk --release` 成功
- [ ] 装进模拟器，冷启动 → logcat 出现 `boot: done`，无异常
- [ ] 队列三张卡都在，`ready` 的显示真实 `N words · M min read · 难度` 与 keywords
- [ ] `ready` 且正文不在手机上时，卡片**不给 Read**，写 `the text is no longer on this phone`
- [ ] Settings 七行，`Instructions` 显示条数，`Debug log` 显示行数
- [ ] Settings hub 最底下显示 `version X.Y.Z (N)`，且与 `pubspec.yaml` 一致
- [ ] `What you read` → `Restore the defaults`：改过配置时可点、确认后七个字段归零、
      按钮随即变灰并显示「Nothing to restore」
- [ ] 阅读页 `Count this read`：点之前显示已有次数（没读过则 `finished reading?`），
      点之后数字**当场变大**，离开再进来数字还在
- [ ] 卡片成本行：没配信息源 = `Write it · ~$0.002`；配了 = `Write it · up to 5 calls`
- [ ] 点 Write it → 卡片变 `Writing…`（转圈、按钮禁用、↻ 关闭）
- [ ] 生成成功 → toast 说**真实调用次数**
- [ ] **杀进程重开 → 卡片仍显示真实词数与 keywords，点 Read 打开的是这一篇**
- [ ] 飞行模式下点 Write it → 一句人话（`Could not reach the provider — check your
      connection, then try again.`），卡片回到可点状态，**不是卡在 Writing…**
- [ ] 升级安装：`user_version` 是 3，旧 topic 变成了 instruction，触发器仍在

### 花了钱才会发现的那些

- **超时数字必须大于最慢的一次真实调用。** 实测：`say hello` 1.1 s、带工具 2.5 s、
  完整 prompt + 30 条标题 + 两个工具 8.9 s、写一篇 180 词带中文 **72.4 s**、
  读完两篇再写一篇 **230 s**。写文章比别的慢一个数量级。
  当前 `kPerCallTimeoutSeconds = 360`、`kMaxWallClockSeconds = 600`。
  **这两个数字和卡片上的时间文案是绑在一起的**，`check_agent.dart` 里有断言。
- **`Future.timeout` 不是取消。** 它让 future 以 `TimeoutException` 完成，socket 还开着。
  所以 agent 循环独占一个 `http.Client`，超时后 `close()` 再惰性重建。
  **绝不能 close `main._api`**——audio 和 plan rewrite 也在用它。
- **`reasoning_content` 必须在回传前剥掉。** MiMo 和 DeepSeek 看到自己上一轮的推理会报错。
  剥除只在 `ChatTurn.assistantMessage()` 一处发生。

---

## 6. 常见故障

| 症状 | 原因 | 修法 |
|---|---|---|
| `No Android SDK found` | 没 export `ANDROID_HOME` | 见 §1 |
| `assembleDebug` 卡 15 分钟无输出 | Gradle 在下引擎 jar，需要代理 | 见 §1「代理」 |
| `remote secure_mkdirs failed` | Git Bash 改写了设备路径 | 加 `MSYS_NO_PATHCONV=1` |
| 拷出来的库是空的 | 没 force-stop，或没拷 `-wal` | 见 §3「取数据库」 |
| 库文件大 12 字节 | 用了 shell 重定向而不是 `adb pull` | 见 §3「取数据库」 |
| `input text` 没输进去 | 输入框没获得焦点 | 先 tap 输入框 |
| `input text` 报 `no closing quote` | 文本里有撇号 | 去掉撇号，空格写 `%s` |
| 点不动某个按钮 | 十有八九是点歪了 | 先截图确认坐标 |
| release 包某处一大块空白 | 布局错误，release 不画红框 | 换 debug 包看红框报错 |
| 生成失败且卡片一直 `Writing…` | `_failWrite` 没被调用（不该发生） | 查 logcat 里 `[done] run crashed` |

---

## 7. 这一版的 APK

```
Marginalia/build/app/outputs/flutter-apk/app-release.apk
```

72.8 MB，debug key 签名，`applicationId = com.marginalia.reader`。
装之前不用卸载旧版——同签名，`install -r` 直接覆盖，数据保留。
