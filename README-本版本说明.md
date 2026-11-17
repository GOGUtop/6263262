# SillyTavern HarmonyOS 7 — 版本 A（8001 单站）

- 站点：`http://aaa.xixisillytavern.top:8001/`
- 快捷操作通知与 AI 回复完成通知分离。
- 快捷操作通知为 ongoing/unremovable，运行期间保留“刷新 / 清理”。
- AI 回复完成通知为普通通知，可单独清除。
- 软件内部无刷新/清理工具栏。
- App 图标使用 SillyTavern 官方 PWA 512×512 图标。GitHub Actions 会在编译前自动拉取；本地 DevEco 首次构建前可运行 `tools/apply-official-sillytavern-icon.ps1`。

> 本项目包不包含你的本机签名密码/证书配置。若你在现有已签名项目上覆盖源文件，请保留自己的根目录 `build-profile.json5`。
