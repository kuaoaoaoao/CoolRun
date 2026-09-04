// 手动 swiftc 构建时补齐 PostHog 静态对象的缺失符号：
// - ___llvm_profile_runtime：PostHog.o 带覆盖率插桩引用
// - _PostHog_PHPLCrashReporter_SWIFTPM_MODULE_BUNDLE：SPM 生成的 Bundle.module 访问器
// 测试运行不会调用这些符号，仅满足链接。
// 注意：Darwin 会为 C 符号自动加一个下划线前缀
int __llvm_profile_runtime;
void *PostHog_PHPLCrashReporter_SWIFTPM_MODULE_BUNDLE;
