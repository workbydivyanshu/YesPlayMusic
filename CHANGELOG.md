# 更新日志

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [3.0.1] - 2026-11-24

### 修复与优化

- **Linux 崩溃修复**：修复在部分 Linux 发行版上因 LuaJIT 与 Flutter LLVM Unwinder 符号冲突导致的 SIGSEGV 启动崩溃（链接器前置 `libgcc_s.so.1` 确保符号解析正确）。([#2532](https://github.com/qier222/YesPlayMusic/issues/2532))
- **Linux 窗口位置记忆**：自动保存并恢复窗口大小、位置与最大化状态（保存在 `~/.config/yesplaymusic/window_state.json`），并优化取消最大化时的尺寸保护与写入防抖。([#2526](https://github.com/qier222/YesPlayMusic/issues/2526))
- **唱片架渲染优化与崩溃修复**：优化大型曲库的专辑唱片架渲染性能，采用视口滑动窗口虚拟化；修复快速滚动或到达边界时除零 (NaN) 导致的红屏崩溃。([#2531](https://github.com/qier222/YesPlayMusic/issues/2531))
- **单曲循环模式**：播放循环模式支持「单曲循环」，按 列表循环 / 单曲循环 / 顺序播放 循环切换，正在播放页与迷你播放栏支持状态图标提示，多语言完整本地化。([#2534](https://github.com/qier222/YesPlayMusic/issues/2534))
- **多源歌词引擎集成**：
  - 集成多源歌词竞速引擎，支持 Apple Music、Lrc.Red、BetterLyrics、酷狗音乐（KRC）、LRCLIB 及 Musixmatch。
  - 正在播放界面支持歌词源标识、歌词控制面板（换源、±0.25s 偏移微调与记忆、手动搜索歌词、导出为本地 `.lrc` 文件）。
  - 支持纯文本无时间轴歌词的优雅降级展示与平滑滚动。
- **打包与构建**：Linux 发布流程新增开箱即用的 AppImage 独立可执行安装包。

## [3.0.0] - 2026-11-24

YesPlayMusic 用 Flutter 重写的第一个版本。

- 支持 macOS（Apple Silicon）、Windows 和 Linux。
- 本地音乐：扫描音乐文件夹，读取标签、封面和歌词。
- 插件：在线音乐源由插件提供，插件在沙箱里运行，能访问哪些网站、能不能启动本机程序都要事先声明。见 [插件开发指南](https://github.com/qier222/YesPlayMusic/blob/main/docs/plugins.md)。
- 插件安装：设置 → 插件 里一键安装官方插件（Jellyfin、Emby、Plex、Subsonic），也可以粘贴 GitHub 仓库、Release 或 .zip 链接安装，或者从本地文件夹安装。
- 插件出错停掉时自动重启一次，还不行就在设置页显示原因。
- 首页、发现页、搜索、专辑、歌手、歌单、评论，由当前音乐源提供。
- 个人主页：账号资料、听歌排行、最常听的艺人和自己创建的歌单（需要插件支持）。
- 音乐库：歌曲、专辑（唱片架）、歌单、艺人（气泡），以及 Coverflow 浏览（专辑、艺人、歌曲）。
- 正在播放：逐行歌词和翻译、播放队列、相似歌曲。
- 预载下一首的播放地址和歌词；听过的在线歌曲缓存到本地，再听不用重新下载。
- 界面语言：简体中文、繁体中文、English、日本語、한국어、Deutsch、Français、Español、Русский。
- 系统「正在播放」和媒体键（macOS），跟随系统代理。
- 键盘快捷键。
- 无障碍：屏幕阅读器能读出按钮、开关和选中状态。
- 自动更新：macOS 和 Windows 自动检查更新、一键安装，Linux 在设置里提示新版本。
- AI 助手（MCP）：让 Claude、Cursor 等 AI Agent 帮你搜歌、播放、管理队列和歌单，在 设置 → MCP 里开启。
- 日志写进本地文件，设置 → 关于 里可以打开。
- 匿名使用统计，可以在 设置 → 关于 里关闭。

[Unreleased]: https://github.com/qier222/YesPlayMusic/compare/v3.0.1...HEAD
[3.0.1]: https://github.com/qier222/YesPlayMusic/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/qier222/YesPlayMusic/releases/tag/v3.0.0
