# 拼豆工坊 · Bead Studio

一款用 Flutter 编写的拼豆（Perler / Hama / MARD）图案编辑器，支持桌面、移动端和 Web。

把照片或像素稿变成可照着拼的图纸，也可以从一块空白拼豆板开始自由创作。

![GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-E85D75)

## 功能

- **拼豆画布**：画笔、橡皮、油漆桶、直线、方框、吸管、移动工具，支持撤销 / 重做、网格、拼豆 / 像素两种显示样式。
- **真彩色调色板**：HSV 取色器、HEX 输入、最近使用颜色；可把任意颜色加入画布。
- **常用色号**：内置 MARD（291 色）、Hama Midi（92 色）、Perler Midi（103 色）色卡，支持按色号或名称搜索。
- **图片导入**：自动缩小、保持宽高比、可选裁切 / 留白 / 拉伸、Floyd–Steinberg 抖动，并按 CIE Lab 颜色距离匹配到最接近的实体豆色。
- **摄像头拾色**：手机实时预览取景框，拍摄后取样颜色，显示最接近的常用色号；桌面端自动回退到“从照片拾色”和手动调色。
- **导出与分享**：
  - 带标题、材料图例和网格的分享卡片 PNG；
  - 纯图案 / 拼豆样式 / 像素样式可选；
  - 工程文件（`.bead.json`，RLE 压缩）导入导出；
  - 材料清单 CSV（含品牌、色号、名称、色值和数量）。
- **本地作品库**：自动保存，最近作品缩略图，支持重命名、删除和继续编辑。

## 平台

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Android | ✅ | 摄像头、相册、分享、文件导入导出 |
| iOS | ✅ | 摄像头、相册、分享、文件导入导出 |
| Linux | ✅ | 桌面运行；摄像头不可用，回退到照片拾色 |
| Windows | ✅ | 桌面运行；摄像头不可用，回退到照片拾色 |
| macOS | ✅ | 桌面运行；摄像头插件不可用，回退到照片拾色 |
| Web | ✅ | 需要 HTTPS 或 localhost 才能使用实时摄像头 |

> 桌面端使用 `file_selector` 的系统保存对话框；Linux 上 `share_plus` 不支持文件分享，会自动回退为保存文件。

## 开发与运行

要求 Flutter 3.50+（Dart 3.14+）。项目同时使用 Flutter 3.50 新的
`material_ui` / `cupertino_ui` 包。

```bash
flutter pub get
flutter run -d linux        # Linux 桌面
flutter run -d android      # 需要已配置 Android SDK
flutter run -d chrome       # 需要 Chrome
flutter test
flutter analyze
flutter build linux --release
flutter build apk --release
flutter build web --release
```

生成应用图标（修改 `assets/icon/app_icon.png` 后执行）：

```bash
dart run flutter_launcher_icons
```

### Android

相机权限已写入 `android/app/src/main/AndroidManifest.xml`。构建 release APK 需要
Android SDK / cmdline-tools；本项目在缺少 Android SDK 的环境中只验证了 Dart 层与
Linux/Web 构建。CI 里的 APK 使用 Flutter 模板的 debug keystore 签名，可以直接安装，
正式发布时请替换为自己的 keystore。

### Linux AppImage 本地打包

```bash
flutter build linux --release
# 需要先准备 appimagetool：
# https://github.com/AppImage/appimagetool/releases
APPIMAGETOOL=/path/to/appimagetool \
  APP_VERSION=1.0.0+g$(git rev-parse --short=7 HEAD) \
  ./packaging/linux/build_appimage.sh
```

AppImage 内置 Flutter 运行时与插件，但仍使用宿主机的 GTK 3 / GLib；主流桌面环境
默认已安装。产物写入 `dist/`。若系统缺少 FUSE 2，可用
`./BeadStudio-*.AppImage --appimage-extract-and-run` 启动。

## GitHub Actions 多平台构建

工作流位于 `.github/workflows/build.yml`，在以下情况运行：

- 推送到 `main` / `master`
- 推送 `v*` 标签
- 手动触发 `workflow_dispatch`

构建产物：

| 平台 | 产物 | 说明 |
| --- | --- | --- |
| Linux | `BeadStudio-<版本>-linux-x86_64.AppImage` | 需要宿主机 GTK 3 |
| macOS | `BeadStudio-<版本>-macos-<arch>.dmg` | 未签名、未公证，首次打开需右键 → 打开 |
| Android | `BeadStudio-<版本>-android.apk` | debug keystore 签名，可直接安装 |
| iOS | `BeadStudio-<版本>-ios-unsigned.ipa` | 未签名，需自行用证书/描述文件重签 |

版本号由基础版本和短 git 提交哈希组成，例如 `1.0.0+g1a2b3c4`；基础版本默认取自
`pubspec.yaml`，打 `v1.2.3` 形式的标签时以标签为准。CI 运行号用作 Android
`versionCode` / Apple `CFBundleVersion`。应用内“关于”对话框、首页页脚、Android 的 `versionName`
和产物文件名都会带上哈希。版本解析逻辑在
`.github/actions/resolve-version/action.yml`。

iOS / macOS 的 `CFBundleShortVersionString` 按 Apple 规范保持纯数字版本，哈希通过
应用内版本、`versionName` 和产物文件名体现。DMG 的 CPU 架构跟随
`macos-latest` runner（当前通常为 arm64）。

每次构建都会上传 Actions artifact。推送 `v*` 标签时，`release` job 会自动创建
GitHub Release，附带四个平台的安装包和 `SHA256SUMS`。

> iOS 的未签名 IPA 和 macOS 的未公证 DMG 不能直接通过系统默认安全策略；iOS 需要
> 使用 AltStore / Sideloadly / 自己的签名证书处理，macOS 用户可以右键打开或在
> “系统设置 → 隐私与安全性”中放行。正式分发请配置 Apple Developer 证书与公证。

### Web 摄像头

浏览器只在安全上下文（HTTPS 或 `http://localhost`）开放摄像头。部署到静态站点时
请配置 HTTPS。

## 工程文件格式

```json
{
  "format": "bead-studio-pattern",
  "version": 1,
  "id": "…",
  "title": "小蘑菇",
  "width": 29,
  "height": 29,
  "createdAt": "2026-11-14T04:00:00.000Z",
  "updatedAt": "2026-11-14T04:10:00.000Z",
  "encoding": "rle",
  "cells": "841:00000000;3:ffe85d75;…"
}
```

`cells` 为行优先的 `次数:ARGB十六进制` 游程编码，空豆子为 `00000000`。单个画布
最多 400 × 400 格。

## 色卡数据

MARD、Hama、Perler 的色号与屏幕色值整理自公开色卡
[EasyBeadPattern colour charts](https://easybeadpattern.com/colors)。

屏幕色值只是近似参考，实体豆子会因品牌、批次、光线产生差异；大批量购买或重要作品
请以实物色卡为准。应用允许用真彩色取色器覆盖任何色卡颜色。

## 隐私

- 图片、摄像头画面和拾取的颜色全部在本机处理，不会上传服务器。
- 作品仅保存在本机（`shared_preferences`）；导出的文件由用户自行选择保存位置。

## 目录结构

```
lib/
  data/palettes.dart              # 内置色卡数据
  models/                         # 豆色、图案、RLE
  state/editor_controller.dart    # 编辑器状态、工具、撤销栈
  services/                       # 作品存储、图片转换、PNG 渲染、文件导出
  screens/                        # 主页、编辑器、图片导入、摄像头拾色
  widgets/                        # 画布、色板、真彩色取色器、导出对话框
packaging/linux/                  # AppImage 的 AppRun、desktop 和打包脚本
.github/                          # 多平台构建、版本解析、自动 Release
```

## 许可证

Copyright (C) 2026 Bead Studio contributors

本项目以 **GNU General Public License v3.0 or later** 授权。你可以按 GPL-3.0
或更高版本重新发布和修改；完整许可证文本见 [LICENSE](LICENSE)。
