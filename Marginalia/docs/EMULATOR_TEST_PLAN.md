# 模拟器测试任务明细

> 目标：把 `d511f85` 之后这轮改动**在模拟器上跑一遍**，逐条截图确认，最后打 APK。
> 不做「应该能跑」——每条都要有截图或 logcat 证据。

---

## 0. 环境与约定

| 项 | 值 |
|---|---|
| 设备 | Android 模拟器，1080×1920，**PNG 像素坐标 == 设备坐标** |
| 包名 | `com.marginalia.reader` |
| SDK | `export ANDROID_HOME="/path/to/Android/sdk"` |
| ADB | `"$ANDROID_HOME/platform-tools/adb.exe"`，路径带 `/` 时加 `MSYS_NO_PATHCONV=1` |

**驱动 UI 的三条铁律**（以前踩过）：
1. 点击前先截图确认目标在屏上。
2. 坐标从 PNG 上量，不凭感觉估。
3. 滑动前先看列表当前滚到哪——同一坐标在不同滚动位置命中不同行。

**截图动作**：
```bash
MSYS_NO_PATHCONV=1 "$ADB" shell screencap -p /data/local/tmp/s.png
MSYS_NO_PATHCONV=1 "$ADB" pull /data/local/tmp/s.png ./shot/NN-<名称>.png
```

---

## 1. 冷启动与基线

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1.1 | 装 release 包，冷启动 | logcat 出现 `boot: done`，无 `exception` / `no such column` | logcat |
| 1.2 | 首屏 Queue | 三张卡有间距；第一张若为样例，标题旁有红色 `SAMPLE` 标签 | 截图 |
| 1.3 | 队列下方脚注 | 不是圆角卡片，是两行小字，含 `Every word…` 与 `Nothing to confirm` | 截图 |

---

## 2. 取词翻译（本轮最重要）

**背景 bug**：句子折成 2–3 行时，点第 2/3 行的词永远弹出第 1 行的词。

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 2.1 | 打开样例 Read 页 | 标题 `What a Pointer Really Is` 下有中文 `指针到底是什么` | 截图 |
| 2.2 | 点标题上的一个词 | 弹出该词释义（不是别的词） | 截图 |
| 2.3 | 找一句**折成 ≥2 行**的句子，点**第 2 行**的词 | 弹出的是第 2 行那个词的释义 | 截图 |
| 2.4 | 同一句点**第 3 行**（如有）的词 | 同上，命中正确 | 截图 |
| 2.5 | 词卡英文释义里点一个**你看不懂的词** | 下方出现**纯中文**释义，可关闭；中文释义里的词**不可再点** | 截图 |
| 2.6 | 点 `Chinese translation` → 再点 `hide` | 翻译收起（Read 页） | 截图 |

---

## 3. 样例覆盖 bug（回归必测）

**背景 bug**：Done with it 后新文章被样例顶掉，永远显示 `What a Pointer Really Is`。

> 需要 writer key。先在 Settings → Who writes 存好 key。

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 3.1 | 样例卡 ⋯ → `Write a new one` | 弹出选题面板（不是直接开写） | 截图 |
| 3.2 | 输入自定义指示，如 `explain how a hash map works`，点 Use this | 开始写 | 截图 |
| 3.3 | 写完后看队列 | **新标题 ≠ What a Pointer Really Is** | 截图 |
| 3.4 | 点 Read 打开 | 正文是 hash map，不是指针 | 截图 |
| 3.5 | 退出重进 app，再打开该文 | 仍是 hash map（没有被样例换掉） | 截图 + logcat |
| 3.6 | 样例卡仍在队列某处时 | 标题旁有 `SAMPLE` | 截图 |

---

## 4. 重新生成与统计

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 4.1 | 任意 ready 卡 ⋯ | 有 `Write a new one`（副标题 `choose the subject · the old one is kept`） | 截图 |
| 4.2 | ⋯ → `Done with it` | toast 写明 **not counted as a read**；旧文进 Library | 截图 |
| 4.3 | History / 日历 | 该文**不增加 read 次数** | 截图 |

---

## 5. Listen 页

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 5.1 | 进 Listen（默认设置） | **不自动播放**，停在第 1 句，Play 可点 | 截图 |
| 5.2 | 点 Play | 开始朗读 | logcat / 声音 |
| 5.3 | 点句子里的词 | 弹出词卡，和 Read 一致 | 截图 |
| 5.4 | 点 `Chinese translation` → `hide` | **能收起**（旧 bug 是点了没反应） | 截图 |
| 5.5 | 点 `⟳`（From the beginning） | 回到第 1 句并朗读 | 截图 |
| 5.6 | 点 `⏭` 形式的 Next article（如有） | 切到下一篇并可继续听 | 截图 |
| 5.7 | 切到 Read 再切回 Listen | **句子位置保留**，不从第 0 句重来 | 截图 |
| 5.8 | 完整听完一篇 | History 里 listens +1，reads **不变** | 截图 |

---

## 6. 设置 → Listening

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 6.1 | Settings hub | 有 `Listening` 一行，副标题概括当前状态 | 截图 |
| 6.2 | 打开 Listening | 三段：开播方式 / 一篇听完后 / 下一篇按什么挑 | 截图 |
| 6.3 | 选 `Play at once`，回 Listen | 一进去就开始播 | 截图/logcat |
| 6.4 | 选回 `Wait for me to tap Play` | 又不自动播 | 截图 |
| 6.5 | 选 `Keep going a few more` = 2 | 听完一篇自动进下一篇，最多再 2 次 | 截图 |
| 6.6 | 顺序选 `Random, not today's` | 连听几篇不会反复撞同一首（避开今天听过的） | 观察 |

---

## 7. 设置 → Voice 随机音色

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 7.1 | Settings → Voice → Voice | 选项首位是 **`Random`**，其后是 `mimo_default / Mia / Chloe / Milo / Dean` | 截图 |
| 7.2 | 选 `Random` | hub 副标题显示 `MiMo · Random` | 截图 |
| 7.3 | 回 Listen 连听两篇（中间停止/重开） | 两次朗读音色**可能不同**（一篇内保持一致） | 听感 / logcat |
| 7.4 | 选固定 `Mia` | 恒定为 Mia | 听感 |

---

## 8. Debug log（本轮重做）

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 8.1 | 完成一次写文章后进 Settings → Debug log | **不是平铺行**，是按 run 分组的卡片 | 截图 |
| 8.2 | 看那张卡的标题行 | 写着 `Writing an article: <你的指示>` | 截图 |
| 8.3 | 看卡片副标题 | 有日期时间 `MM-DD HH:mm`、结果 `finished`/`failed`、调用次数、步数 | 截图 |
| 8.4 | 点开卡片 | 时间线，每步 `HH:MM:SS.mmm` + 人话标题（`asking the model` / `the model answered` / `finished OK`） | 截图 |
| 8.5 | 点 `Copy all` | 粘贴出来按 run 分段，带 `── Writing an article: … · finished · <时间>` | 剪贴板 |
| 8.6 | 断网后写一次 | 卡片边框变红，结果 `failed`，步骤里有 `could not reach the provider` | 截图 |
| 8.7 | Settings hub 的 Debug log 行 | 写着 `N things asked for`，不是 `N lines` | 截图 |

---

## 9. 收尾

| # | 步骤 | 期望 |
|---|---|---|
| 9.1 | `flutter analyze --no-pub` | 0 error |
| 9.2 | `dart tool/check_invariants.dart` | ALL PASSED |
| 9.3 | `dart tool/check_agent.dart` | ALL PASSED |
| 9.4 | `flutter build apk --release` | 产物 `build/app/outputs/flutter-apk/app-release.apk` |
| 9.5 | 装回模拟器再冷启动 | `boot: done`，核心页面可进 |

---

## 10. 证据目录

截图统一放 `Marginalia/docs/verify/d511f85/`，命名 `NN-<步骤号>-<名称>.png`，例如：

```
verify/d511f85/
  01-1.2-queue-gap-sample-badge.png
  02-2.3-word-tap-line2.png
  03-3.3-new-article-not-sample.png
  05-5.4-listen-hide-works.png
  08-8.2-debug-log-run-card.png
  …
```

测试完成后，把「通过 / 未通过 / 阻塞」汇总回 STATUS.md，并打出 APK。
