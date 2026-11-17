# GitHub Actions 自动编译教程（HarmonyOS 7 / API 26）

本工程已整理成 **GitHub Actions 可用的完整仓库结构**，无需把整套 DevEco Studio 缓存上传到 GitHub。源码是 ArkTS / ArkWeb，编译产物是 `.hap`，**不是 Android `.apk`**。

## 一、上传代码（重要）

1. **先解压**本次提供的 `Homa-GitHub-Actions-Ready.zip`。不要把 ZIP 文件本身直接上传仓库指望它自动编译。
2. 打开 GitHub → **New repository**，新建仓库，默认分支建议 `main`。
3. 将**解压后的内容**放在仓库根目录：必须直接看得到 `build-profile.json5`、`AppScope/`、`entry/`、`hvigor/`、`oh-package.json5` 和隐藏目录 `.github/`。
4. 重点确认存在：`.github/workflows/build-hap.yml`。
5. 提交后，如果仓库允许 GitHub Actions，向 `main` 或 `master` 推送代码会自动触发构建。

> 建议使用电脑解压后用 Git 或 GitHub Desktop 上传，这样隐藏的 `.github/` 目录最不容易漏掉。不要只上传 `entry/` 子文件夹。

## 二、GitHub Actions 编译和下载

1. 打开你刚创建的 GitHub 仓库，进入 **Actions**。
2. 选择 **Build HarmonyOS 7 HAP (API 26)**。
3. 如果上传时已经自动触发，可直接打开最新运行记录。也可以点击 **Run workflow**，选择 `debug`，再点击运行。
4. 等工作流所有编译步骤显示绿色成功。
5. 进入对应运行记录，底部 **Artifacts** 中下载 `SillyTavern-HarmonyOS7-API26-debug-运行编号`。
6. 解压 GitHub 提供的 Artifact ZIP，取出里面的 `*.hap` 文件。

`debug` 和 `release` 两种选项在这个版本**都会输出未签名 HAP**；`release` 不意味着可以直接安装或上架。

## 三、这份 GitHub 版做了什么

- 固定 HarmonyOS Command Line Tools **26.0.0.821**，对应本项目 SDK API 26。
- 选用 **Ubuntu 22.04 + Java 21**；工具链由 `ErBWs/setup-ohos@v2` 下载。
- 使用 HarmonyOS 工具链内置 Node.js / Hvigor / OHPM。
- 分别在项目根目录和 `entry/` 安装 OHPM 依赖。
- 自动执行 `hvigorw clean` 和 `hvigorw assembleHap`。
- 自动上传 `.hap`，Artifacts 保留 30 天。
- 内置 `tools/ci/validate_project.py`，提前排查 SDK 配置或本机签名凭据误提交。
- 移除了原项目中指向 Windows 本机的签名证书路径和密码；删除构建缓存、IDE 缓存和旧编译输出。
- 不再在 CI 构建时强制联网覆盖内置图标，减少不必要的外部请求和构建失败点。

## 四、编译成功后为什么可能不能安装？

**因为默认产物是未签名 HAP。** 在华为 HarmonyOS 真机上安装，通常需要与你的 App ID / 包名 / 设备或发布配置对应的有效签名证书及 Profile。未签名构建只用于确认源码在 CI 中能完成编译。

签名材料包含 `.p12`、`.cer`、`.p7b`、alias 和密码。不要直接提交进 GitHub 仓库；要做自动签名需另行将必要信息作为 GitHub Actions **Secrets** 安全配置，并根据自己的开发者证书正确签名。

**原始 RAR 包包含本地签名配置信息**，不要上传原始 RAR 或旧版 `build-profile.json5`。本次整理的 ZIP 已移除这部分配置；如果原证书或密码曾在公共位置公开过，应在开发者后台更新/重新签发相关签名材料。

## 五、失败排查

| GitHub Actions 报错 | 检查内容 |
| --- | --- |
| Actions 看不到构建流程 | 检查是否上传了隐藏的 `.github/workflows/build-hap.yml`，且仓库未禁用 Actions |
| `Set up HarmonyOS CLI` 失败 | 检查 GitHub 是否能访问第三方工具链镜像，稍后重试；该镜像不是华为官方托管服务 |
| `ohpm install` 失败 | 依赖仓库访问、证书或网络问题，查看对应步骤日志 |
| `hvigorw assembleHap` 失败 | 具体 ArkTS 编译报错应以 GitHub Actions 日志中的文件和行号为准 |
| `Upload HAP` 报未找到文件 | 说明前面的构建未产出 `.hap`；检查上游编译日志 |
| 编译成功但手机无法安装 | 通常需要匹配的有效签名与 Profile，不等于源码编译失败 |
| 看到的是 APK，而不是 HAP | 本项目是原生 HarmonyOS ArkTS 工程，输出 HAP，不会生成 Android APK |

## 六、当前配置

- `modelVersion`: `26.0.0`
- `compileSdkVersion`: `26.0.0`
- `targetSdkVersion`: `26.0.0`
- `compatibleSdkVersion`: `5.0.0(12)`
- `Command Line Tools`: `26.0.0.821`
- `JDK`: `21`
- 流水线：`.github/workflows/build-hap.yml`

> 注：已完成本地**配置及静态检查**。由于这里没有安装完整的 HarmonyOS API 26 命令行编译 SDK，不能声称已在本地实际编译成功；首次真正的 HAP 编译结果需以你在 GitHub Actions 的运行日志为准。
