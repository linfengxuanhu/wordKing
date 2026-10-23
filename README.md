# 文曲星式背单词（Flutter 第一版）

## 功能
- 初中、高中、四级、大学四级别内置测试词库（当前 75 个示例词）
- 每日新词目标默认 20，可在设置中调整
- 随机字母挖空，支持输入缺失字母或完整单词
- 答错自动进入错题本；复习到期词、错题再练
- 展示中文释义、IPA 音标、英文例句
- 本地保存学习进度，不需要账号和服务器

## 重要说明
这是可构建的第一版骨架，词库是用于验证流程的示例数据，并非完整、权威的初中至大学词库。第一版暂未接入语音发音引擎；点击喇叭会提示尚未启用。后续可添加经过授权的离线音频或系统 TTS。当前间隔复习是简化实现，不宣称与特定文曲星型号完全一致。

## 用 GitHub Actions 编译 APK
1. 在 GitHub 新建空仓库，例如 `wenquxing_vocab`。
2. 上传并提交本项目全部文件，确保 `.github/workflows/build-apk.yml` 路径正确。
3. 打开仓库的 **Actions**，选择 **Build Android APK**，点击 **Run workflow**；推送到 main/master 也会自动构建。
4. 构建完成后打开运行记录，在 **Artifacts** 下载 `wenquxing-vocab-release-apk`，解压后安装 `app-release.apk`。
5. 如果 Actions 的 Analyze 步骤报错，先根据日志修复后再构建。

## 目录
- `lib/main.dart`：主界面、挖空练习、错题和复习调度
- `assets/data/words.json`：词库 JSON
- `.github/workflows/build-apk.yml`：GitHub Actions 构建工作流
