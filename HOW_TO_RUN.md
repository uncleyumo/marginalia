# 启动与构建

**用模拟器：双击 `run-emulator.bat`**（就这一步，它会自己搞定所有事）

卡住了先跑 `doctor.bat`，它会直接告诉你哪一步坏了。

---

## 关于终端

用 **Windows Terminal** 或普通 CMD 都行。之前那些乱码是终端代码页的问题：

- 老 conhost 按 GBK 读 `.bat`，把字符读乱
- Windows Terminal 默认 UTF-8，没这个问题

**三个脚本现在都是纯 ASCII**，所以两个终端里都不会乱码。中文说明在这份文档里，不在脚本里。

---

## run-emulator.bat 会做什么

1. 检查引擎和 AVD，没有就**自动创建**（这一步自动用 JDK 8，因为 `avdmanager` 在 JDK 11+ 上会崩）
2. 启动模拟器（最小化在后台）
3. 等它引导完成（首次 1–3 分钟）
4. 清掉旧构建产物，停掉用错 JDK 的 daemon
5. `flutter run`

**首次构建 3–10 分钟**（下载 Gradle 222 MB + 依赖），之后每次一两分钟。

---

## 跑起来会看到什么

**启动时解压词典**（10.4 MB → 38.9 MB），1–3 秒。这期间点单词显示「The dictionary is still loading」。

**Queue 首屏**：第一张卡是 **ready**（实心玉色圆点 + `Read`）——样例文章《What a Pointer Really Is》已自动装进去。后两张是 planned（虚线朱红边框 + `planned · not written yet · nothing has been paid for`）。

- 点 `Read` → **Article 屏**：11 段正文，**点任意单词弹词条**（英文优先，中文再点一次）
- 16 处标记：**9 处朱红**（没见过）**7 处玉色**（见过但难）
- 滑到底 → `Count this read`，计数后**文章留在队列**
- 顶部切 **Listen** → 一屏一句 26px，可跳句

**底部五槽**：Queue / Article / Library / History / **Words**。Words 那栏显示的是**数字**（有多少词等着再见面）。

**右上角齿轮** → Settings：切色板（暖纸 ↔ 暖墨），看词典真实词数。

跑起来后按 **r** 热重载、**R** 热重启。

---

## 真机（如果以后要用）

```
E:\Dev_work\Flutter_Dev\marginalia\run-app.bat
```

小米/红米需要手动授权：**设置 → 更多设置 → 开发者选项 → 打开「USB 安装」**，安装时手机弹窗点「允许」。不点会报 `INSTALL_FAILED_USER_RESTRICTED`。

---

## 先做这一步：下载 64 位镜像

**你现在看到的 `emulator-5554 unsupported` 是真问题，不是标签。**

之前建的 AVD 用的是 **32 位 x86 镜像**，而 **Flutter 不支持在 32 位模拟器上运行或调试**。
这不是能靠参数绕过的，必须换镜像。

双击：

```
E:\Dev_work\Flutter_Dev\marginalia\fix-emulator-64.bat
```

它会下载 `android-29 google_apis_playstore x86_64`（约 2-3 GB，sdkmanager 已确认本机可下载），
然后建一个名为 `marginalia64` 的新 AVD。

**原来的 32 位 AVD 不会被删**，我不动不是你装的东西。留着不占额外空间。

下载完之后再跑 `run-emulator.bat`，它已经改成用 `marginalia64` 了。

> 跑之前先关掉现在开着的模拟器窗口，否则两个模拟器会抢同一个 `emulator-5554` 端口。

---

## 排查

| 症状 | 处理 |
|---|---|
| `run-emulator.bat` 说引擎缺失 | 引擎文件确实在，那说明脚本被改坏了，重新下载我给的版本 |
| 构建卡住 | 第一次 3–10 分钟正常，不是卡死 |
| 装到模拟器上报 ABI 不匹配 | 说明混用了，`run-emulator.bat` 只管模拟器，`run-app.bat` 只管真机 |
| 装上后闪退 | 跑 `run-app.bat`，把 Dart 报错贴给我 |

超过 15 分钟构建还没动静，把输出贴给我。