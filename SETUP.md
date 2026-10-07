# Marginalia — 你要做的事，一次说全

> **状态：全部完成。你现在没有待办。**
>
> - ✅ 环境变量、`flutter create`、`flutter pub get`（21 个依赖）
> - ✅ 词典 392,695 词 / 10.42 MB
> - ✅ 四个决策已定（词典内置不接API · UI 归我 · M1 不做 · key 存本地不做服务端）
> - ✅ `dart run build_runner build` 已执行，28 个 codegen 产物落盘
> - ✅ 阶段 0 设计系统、阶段 1 领域层 + 82 项不变量检查
>
> **唯一的注意事项**：如果我改动了 `@DriftDatabase` 里的表定义，
> 需要你再跑一次 `dart run build_runner build`。这是设计表的改动才需要。

> **当前状态：工程已创建，依赖已解析完成。你可以只回答第 3 节四个决策，然后我立刻开始编码。**
>
> - ✅ 第 1–2 步（环境变量 + `flutter create`）已完成
> - ✅ 第 3 步（`flutter pub get`）已完成，18 个依赖全部锁定
> - ⬜ 只剩：回答四个决策
>
> 本文保留已完成步骤的记录，供你复现或日后重装时参考。

---

## 0. 网络：已改用国内镜像（重要）

实测数据（本机）：

| 目标 | 直连 | 经 Clash 代理 |
|---|---|---|
| `pub.dev` | **20s 超时** | 0.47s |
| `github.com` | **20s 超时** | 0.43s |
| `pub.flutter-io.cn` | **0.21s** | 0.12s |
| `storage.flutter-io.cn` | **0.14s** | 0.14s |

你截图里 `Downloading packages... (7:13.9)` 卡了 7 分钟，根因就是 **pub.dev 直连超时**，不是 Clash 的问题。

**已经用镜像跑通了，所以现在不用管代理。** 但建议你**永久写入环境变量**，否则以后每次 `flutter pub get` 都会再卡十几分钟：

```powershell
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

> 如果你更想用 Clash 走代理（`setx HTTPS_PROXY "http://127.0.0.1:7897"`），也能work，但多一层依赖。**镜像是官方中国区镜像，更稳。**

> 截图里那条 `fatal: unable to access 'https://github.com/flutter/flutter.git/'` 是**非致命的**——`flutter create` 读版本号失败后回退到本地 revision 继续执行，项目已完整生成（`android/` 全部就位、`.metadata` 已写入）。**可以忽略。**

---

## 1. 已完成：设置环境变量

```powershell
$env:ANDROID_HOME     = "E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:JAVA_HOME        = "E:\Dev_work\Java_Dev\JDK_SRC\JDK_21_GRAALVM"
```

要永久生效，把这三行写进「系统属性 → 环境变量」。

> **注意目录名**：本机 Android SDK 真实路径是 `...\Android_SDK\SDK_For_AS352`，**不是** `...\Android_SDK`。多一层子目录，我已确认。
> `android/local.properties` 已由 `flutter create` 自动写入 `flutter.sdk`，这一项你不用再操心。

## 2. 已完成：生成 Android 包装层

```powershell
cd E:\Dev_work\Flutter_Dev\marginalia\Marginalia
flutter create . --platforms=android --org com.marginalia --project-name marginalia
```

已生成 `android/`（app · gradle · gradlew · local.properties …）。传 `--platforms=android` 是刻意的：设计明确 **Android only**。

## 3. 已完成：依赖解析

```powershell
flutter pub get
```

**实际锁定版本**（`dart pub deps` 权威输出）：

```
flutter_riverpod 3.4.3 · riverpod 3.4.3 · go_router 16.3.0 · drift 2.34.4
freezed 3.2.5 · freezed_annotation 3.1.0 · http 1.6.0 · flutter_secure_storage 10.3.4
just_audio 0.10.6 · audio_service 0.18.19 · audio_session 0.2.4 · flutter_tts 4.2.5
sqlite3_flutter_libs 0.5.42 · path_provider 2.1.6 · intl 0.19.0 · collection 1.19.1
flutter_lints 6.0.0 · build_runner 2.15.1 · drift_dev 2.34.0 · json_serializable 6.14.1
```

共 75.9 秒，零错误。

---

## 4. 决策已定

四个问题都已答复，工程可以全面开工。

| # | 决策 | 结论 |
|---|---|---|
| 1 | 词典 | **内置 39.3 万词离线词典（10.4 MB），不接任何 API**。详见 `DICTIONARY.md` |
| 2 | 主表 / UI | **UI 由我负责**，按原型规范落地；主色板两套都实现，暖纸为默认 |
| 3 | M1 golden set | **本版本不做**，先交付完整可用的离线 App |
| 4 | API key | **key 存本地 Keystore，不做服务端**（本版本不卖服务，无服务端） |

### 关于第 3 点：M1 golden set 是什么

一句话：**它是"验证 AI 写文章的那条提示词靠不靠谱"的一道工序，不是功能。**

展开说——这个 App 有两种内容来源：

- **离线样例文章**：我打包好的那几篇，零成本、零风险
- **AI 现场写的文章**：调用 LLM，按你设置的主题现场生成一篇新的

第二种要花钱（每次约 $0.002），所以必须**由你点一下才写**（这是成本天花板，见不变量第 2 条）。但问题来了：**我写的那条提示词（`DESIGN.md §10`）从来没被验证过**。原作者在 README 里明确警告：

> **Do not wire the prompt in and move on.** It has not passed its acceptance criteria yet.
> （别接上去就跑。它还没通过验收标准。）

"golden set"就是验收手段：手工准备几篇**已知的好文章**当标准答案，把提示词生成的稿子跟它们对比，检查是否达标（比如：标出的生词数量对不对、句子长度是否失控、是否真的避开了你标记为"已掌握"的内容）。**5 篇标注 + 人工对比，是一个独立的小项目，通常 1-2 天。**

**为什么现在不做**：它只影响"AI 现场写文章"这一个功能（阶段 4）。前 3 个阶段——Queue、Article、Library、History、Words、Settings、离线词典、听读——**完全不依赖它**。先把这些做完，你就已经有一个每天能用的 App 了；M1 和 AI 写作功能可以之后并行补上。

**所以本版本的范围**：AI 写作入口保留但不接真实调用（点了会明确告诉你"还没接"，而不是假装失败）。其余全部可用。

### 决策 1 · 词典 → 内置 39.3 万词，不接 API

原型要求的 ECDICT 是 851 MB / 3.4M 词条，APK 装不下。已找到可用方案并实施完毕：

| 项 | 值 |
|---|---|
| 词条数 | **392,695** |
| 打包体积 | **10.42 MB** |
| 覆盖验证 | 样例文章 100% · Top-200 高频词 100% |

数据源 [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT)（MIT）。做了四件必要修正：英式音标转美式、词形回落（`crashes`→`crash`）、义项重排（`water` 不再给化学定义）、文本清洗。**全部细节与验收见 `DICTIONARY.md`。**

**不接有道云的理由**：设计承诺「查词永远 $0.00、离线、飞行模式可用」，接 API 就作废了。真正的缺口是词形和义项质量，都能在数据处理阶段解决。

### 决策 2 · UI 交给我

按原型规范落地：OKLCH 已换算为 sRGB 常量、三族字体已打包、纸纹与斜纹条用 `CustomPainter` 实现、两套色板都实现（暖纸为默认，暖墨作为一次性外观选择放在「设置 → 小字」，不带时间语义）。

### 决策 3 · M1 本版本不做

见上文「M1 golden set 是什么」。AI 写作入口保留但不接真实调用，其余功能全部可用。

### 决策 4 · key 存本地，不做服务端

本版本不卖服务，因此**没有服务端**。Settings 的「谁写文章」面板只写本地：base URL + key 存 Android Keystore，只发给你自己填的那个地址。

---

## 5. 我已经替你做完的事

| 文件 | 内容 |
|---|---|
| `Marginalia/pubspec.yaml` | 全部依赖 + **每条都写了「为什么选它」** + 三族字体声明 |
| `Marginalia/analysis_options.yaml` | lint 规则，每条都注明对应的设计约束 |
| `Marginalia/assets/fonts/*.ttf` | 三族字体**已下载并逐字节校验完整**（5 个文件全部 OK） |
| `Marginalia/assets/dict/dictionary.zip` | **39.3 万词离线词典，10.42 MB**（见 `DICTIONARY.md`） |
| `Marginalia/assets/sample/pointers.json` | 样例文章，11 句全中英，16 处生词标记 |
| `Marginalia/android/` | 由 `flutter create` 生成 |
| `Marginalia/tools/*.py` | 词典构建与验收脚本，可复现 |
| 目录结构 | 11 个功能目录 + assets + test 分层 |

**已做的校验**（都实际跑过）：
- 5 个字体文件按 TrueType 表目录逐个核对长度 → 全部完整。**过程中发现 `Newsreader-Italic.ttf` 被截断成 262144 字节，已重下为 495684 字节并复验通过**
- 样例文章 16 处标记 → 全部能在种子词典里查到、全部指向真实句子、全部的表面形式确实出现在该句中
- 两份 JSON 均语法有效
- 18 个依赖全部解析成功（75.9s，rc=0）

---

## 6. 一点说明

**为什么建议用 PowerShell 而不是 Git Bash**：Git Bash 会经由 MSYS 转换路径与环境变量，Flutter 的 `where.exe` 调用在那个链路下不稳定。PowerShell 走原生路径，最稳。

**关于依赖版本**：`pubspec.yaml` 里用 `^` 范围（如 `flutter_riverpod: ^3.0.0`）而非精确锁定。原因是 `flutter_riverpod` 近期已到 3.4.3、3.x 改过 Notifier API——钉死版本反而可能在将来安全更新时卡住你。`pub get` 已解析出实际版本（见第 3 节），`pubspec.lock` 已落盘，随时可复现。

---

## 7. 一句话总结

> 环境变量已设、`flutter create` 已跑、`pub get` 已成功、词典已就位、四个决策已定。
> **无待办事项。** 我从**设计系统 + 五条不变量测试**开始编码。

---

## 附：路径速查

| 用途 | 路径 |
|---|---|
| 项目根（你要 cd 进去） | `E:\Dev_work\Flutter_Dev\marginalia\Marginalia` |
| 原型（只读，不改） | `E:\Dev_work\Flutter_Dev\marginalia\Marginalia-Prototype` |
| 规划文档 | `E:\Dev_work\Flutter_Dev\marginalia\FLUTTER_PLAN.md` |
| Flutter SDK | `E:\Dev_work\Android_Dev\Dev_Tools\Flutter_SDK\flutter_windows_3.44.3-stable` |
| Android SDK | `E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352` |
| JDK | `E:\Dev_work\Java_Dev\JDK_SRC\JDK_21_GRAALVM` |
