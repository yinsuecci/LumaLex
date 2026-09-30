# LumaLex：英语听力与词汇学习

LumaLex 是一款原生 iOS 英语听力与词汇学习应用，目标是把“听英语、看懂内容、记下生词、定期复习”串成一个连续的学习过程。

## 主要功能

- **听力播放**：导入英语音频，控制播放进度和倍速，查看与音频同步的字幕。
- **字幕学习**：支持导入 SRT/VTT 字幕，提供中英双语、仅英文、难词突出和无字幕专注模式。轻点字幕中的词语或短语，可查看其在当前句子中的含义并加入生词本。
- **转写与解释**：在设备支持的情况下，可使用系统语音识别生成英文转写。配置可选的后端服务后，还可使用远程转写、翻译和结合语境的词汇解释；API 密钥不放在 iOS 应用中。
- **词汇复习**：生词保存在本机，按间隔复习计划安排回顾；完成复习阶段的词语进入“已掌握”，历史记录仍会保留。
- **直接开始学习**：首次启动直接进入主界面，不再进行词汇量测验。生词收藏、已知词管理和间隔复习仍然保留。
- **系统集成**：支持后台音频与系统播放控制，并提供锁屏实时活动和灵动岛信息展示；实际显示效果取决于设备及 iOS 系统限制。

## 离线体验与测试素材

应用内置一段带中英双语字幕的离线演示音频，无需导入文件或配置 API 密钥即可体验播放、点词和保存词汇。已导入的本地音频、字幕和词汇数据可在离线状态下使用；远程 AI 功能需要单独配置后端。

`Samples/` 中另有一份《The world this week》音频对应的双语 SRT 测试字幕；原始 MP3 不包含在仓库中。该字幕由本地语音识别生成并校正，仍可能存在个别识别或翻译误差。

## 直接导入字幕

音频和字幕是两个文件：音频从 Library 导入；打开该音频的播放器后，使用醒目的 **Import Timed Subtitles** 按钮选择 UTF-8 编码的 `.srt` 或 `.vtt` 文件。导入后按文件中的时间戳同步显示，不需要先运行语音识别、翻译服务或配置 API 密钥。字幕会关联到当前打开的音频，不会仅凭文件名自动匹配。

双语字幕建议每个时间段用独立的英文行和中文行，例如：

```srt
1
00:00:01,000 --> 00:00:03,500
The market has priced in the cut.
市场已经消化了降息预期。
```

只有英文的字幕也能导入，但双语模式下不会自动出现中文译文。

## 开发环境

- macOS、Xcode，以及 iOS 17 或更新版本的模拟器。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)，用于从 `project.yml` 生成 Xcode 工程。
- Node.js 20 或更新版本，用于可选后端及 Windows 上的部分测试。

## 构建与测试

```sh
xcodegen generate
xcodebuild build -project LumaLex.xcodeproj -scheme LumaLex -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LumaLex.xcodeproj -scheme LumaLex -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
npm test
```

测试命令中的模拟器名称可替换为当前可用设备；CI 会自动选择模拟器。生成的 `.xcodeproj` 不纳入版本控制，`project.yml` 才是工程配置来源。`npm test` 在 Windows 上可运行测验移除与启动屏配置检查、演示素材和后端测试，但不能代替 iOS 构建或实机测试。

## 可选后端

`server/` 是不依赖第三方运行时包的 Node.js API。配置 `GEMINI_API_KEY`、`LUMALEX_APP_TOKEN`，以及可选的 `GEMINI_MODEL` 后，可在该目录运行 `npm start`。服务默认只监听本机；正式部署应通过 HTTPS 暴露，并在应用的 Profile 页面配置服务地址和访问令牌。生产模式下，缺少 `LUMALEX_APP_TOKEN` 时服务不会启动。

应用只在用户主动操作后才会向后端发送音频或字幕文本。远程转写目前接收不超过 12 MB 的 MP3、M4A 或 WAV；长音频建议直接导入 SRT/VTT 字幕，当前设备端转写没有长音频分段处理。仓库不保存 API 密钥。

## 当前状态

这是 SwiftUI 项目。iOS 应用需要 macOS 和 Xcode 编译；当前仓库没有可直接安装的已签名 IPA。本地 Windows 环境也没有 Xcode 和 Apple 签名身份，无法直接生成 iOS 安装包。发布前仍需在 Mac 与真实 iPhone 上验证音频、字幕、实时活动和签名配置，并部署 HTTPS 后端。账户登录、同步、完整本地化和 App Store 提交尚未实现。完整产品设计见 [agent.md](agent.md)。
