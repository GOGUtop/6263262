# 这是整理好的 GitHub Actions 自动编译版

**请上传本 ZIP 解压后的所有文件，而不是上传 ZIP 文件本身。**

第一步：GitHub 新建仓库，默认分支使用 `main`。

第二步：解压后把全部文件放到仓库的最外层（根目录）。其中隐藏目录 `.github/` 不能漏传。

第三步：打开仓库的 **Actions → Build HarmonyOS 7 HAP (API 26)**。首次上传到 `main` 通常会自动开始构建；也可以点击 **Run workflow** 手动启动，选 `debug`。

第四步：运行成功后，在该次 Actions 运行页面最下方的 **Artifacts** 下载 `.hap` 构建产物。

**提醒：** 默认生成的是**未签名 HAP**（可以验证代码是否编译，但不一定能直接安装到手机）。要生成真机可安装包，需要你自己的 HarmonyOS 签名材料。不要上传旧 RAR 中的本地签名配置信息。

详细说明见 `docs/GITHUB_ACTIONS_BUILD.md`。
