#pragma once

#include <string>

// 内部：模型族识别（用于 tool calling 策略选择）
bool llx_is_functiongemma_family(const std::string &model_name);
bool llx_is_qwen_family(const std::string &model_name);


