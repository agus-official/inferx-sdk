#include "llx_tool_families.h"

#include <cctype>

static std::string llx_to_lower_copy(std::string s) {
    for (auto &c : s) c = (char) std::tolower((unsigned char) c);
    return s;
}

static bool llx_contains_ci(const std::string &hay, const std::string &needle) {
    if (needle.empty()) return true;
    return llx_to_lower_copy(hay).find(llx_to_lower_copy(needle)) != std::string::npos;
}

bool llx_is_qwen_family(const std::string &model_name) {
    // 覆盖 qwen / qwen2 / qwen2.5 / qwen3 等命名
    return llx_contains_ci(model_name, "qwen");
}


