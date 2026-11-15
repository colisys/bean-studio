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
`./BeadStudio-*.AppImage --appimage-extract-and-run` 启动。从 GitHub Release 下载后若没有
执行权限，先运行 `chmod +x BeadStudio-*.AppImage`。

## GitHub Actions 多平台构建与发布

工作流分成两个：

- `.github/workflows/build.yml`（Build Apps）：推送到 `main` / `master` 或手动触发时构建四个
  平台并上传 Actions artifact，产物保留 **90 天**。这个工作流不发布 Release。
- `.github/workflows/release.yml`（Release）：推送 `v*` 标签时自动运行（标签提交需包含
  该工作流），也可手动 `workflow_dispatch`，从对应提交最近一次成功的 Build Apps 运行中
  下载产物并创建 GitHub Release。**发布不会重新编译。**

构建产物：

| 平台 | 产物 | 说明 |
| --- | --- | --- |
| Linux | `BeadStudio-<版本>-linux-x86_64.AppImage` | 需要宿主机 GTK 3 |
| macOS | `BeadStudio-<版本>-macos-<arch>.dmg` | 未签名、未公证，首次打开需右键 → 打开 |
| Android | `BeadStudio-<版本>-android.apk` | debug keystore 签名，可直接安装 |
| iOS | `BeadStudio-<版本>-ios-unsigned.ipa` | 未签名，需自行用证书/描述文件重签 |

### 补标签 / 补发布

先等 `main` 的 Build Apps 构建成功，然后任选一种方式：

1. 在 Actions 中手动运行 **Release**，填写 `tag`（如 `v1.0.0`），`commit` 可留空
   （当前 `main` HEAD）或填入旧提交 SHA，保持 `create_tag=true`。
2. 直接打并推送标签（仅当标签指向的提交包含 `release.yml` 时会自动触发；更老的
   提交请用方式 1）：

   ```bash
   git tag v1.0.0 <commit>
   git push origin v1.0.0
   ```

Release 会按提交查找最近一次成功的 Build Apps 运行，下载四个平台的 artifact，生成
`SHA256SUMS`，并在需要时创建标签。若该提交没有成功构建，或 artifact 已超过 90 天，
发布任务会报错；此时先在该 ref 上手动运行一次 Build Apps，再重新运行 Release。

补标签发布复用原构建，因此产物版本仍是构建时的 `1.0.0+g<sha>`，标签不会改变已编译
产物。如果希望产物版本等于标签的基础版本，请在该标签 ref 上手动运行 Build Apps，再
运行 Release。

### 版本号

版本号由基础版本和短 git 提交哈希组成，例如 `1.0.0+g1a2b3c4`；基础版本默认取自
`pubspec.yaml`。若手动在 `v1.2.3` 标签 ref 上运行 Build Apps，则以标签版本为准。CI
运行号用作 Android `versionCode` / Apple `CFBundleVersion`。应用内“关于”对话框、
首页页脚、Android 的 `versionName` 和产物文件名都会带上哈希。版本解析逻辑在
`.github/actions/resolve-version/action.yml`。

iOS / macOS 的 `CFBundleShortVersionString` 按 Apple 规范保持纯数字版本，哈希通过
应用内版本、`versionName` 和产物文件名体现。DMG 的 CPU 架构跟随
`macos-latest` runner（当前通常为 arm64）。

GitHub Release 会把四个平台的构建产物和 `SHA256SUMS` 一并保存，因此发布后的文件不受
Actions artifact 90 天保留期限制。

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
.github/workflows/build.yml       # 主分支构建并缓存四平台产物
.github/workflows/release.yml     # 标签/手动发布，复用缓存产物
.github/actions/resolve-version/  # 版本号解析
```

## 许可证

Copyright (C) 2026 Bead Studio contributors

本项目以 **GNU General Public License v3.0 or later** 授权。你可以按 GPL-3.0
或更高版本重新发布和修改；完整许可证文本见 [LICENSE](LICENSE)。
