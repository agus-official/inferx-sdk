# Changelog

## 0.0.1 (2025-10-11)

### 功能

- ✅ 初始版本发布
- ✅ Android 平台支持（通过 llx-android）
- ✅ 完整的 Dart API
  - 后端管理（init/free）
  - 模型加载和释放
  - 会话创建和管理
  - 流式文本生成
  - OpenAI 兼容的 chat completion API
  - LoRA 适配器管理（加载、添加、更新、移除、清空）
  - 基准测试工具
- ✅ 样例应用
  - 聊天界面
  - 文件选择器
  - LoRA 管理界面
  - Markdown 渲染
  - 聊天历史管理
- ✅ 完整文档
  - API 文档
  - 使用指南
  - 样例说明

### 架构

- Flutter MethodChannel 桥接
- Kotlin 平台实现
- 依赖 llx-android (v1.0)

### 已知限制

- iOS 平台暂未实现
- Android 仅支持 arm64-v8a 架构
- 需要 Android 7.0+ (API 24+)

### 技术栈

- Flutter SDK: ^3.9.2
- Kotlin: 2.1.0
- Android Gradle Plugin: 8.9.1
- 依赖：
  - markdown_widget: ^2.3.2
  - path_provider: ^2.1.5
  - file_picker: ^8.1.6

### 待办事项

- [ ] iOS 平台支持
- [ ] 更多示例（如 RAG、Function Calling）
- [ ] 性能优化
- [ ] 单元测试覆盖
- [ ] CI/CD 集成
