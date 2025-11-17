// src/llx_build_info.cpp
#include <string>

extern "C"
{
    // 这些变量在 llama.cpp/common/common.cpp 里被引用
    // 类型需与 third_party/llama.cpp/common/build-info.cpp.in 保持一致
    int LLAMA_BUILD_NUMBER = 0;
    const char *LLAMA_COMMIT = "custom";
    const char *LLAMA_COMPILER = "Clang";
    const char *LLAMA_BUILD_TARGET = "generic";
}
