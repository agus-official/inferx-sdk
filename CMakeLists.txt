cmake_minimum_required(VERSION 3.20)
project(mac_llama_sdk C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 99)

# 平台后端选项：macOS 启用 Metal/Accelerate，其它平台关闭
if(APPLE)
  option(LLAMA_METAL "Enable Metal backend" ON)
  option(LLAMA_ACCELERATE "Enable Accelerate" ON)
else()
  set(LLAMA_METAL OFF CACHE BOOL "Enable Metal backend" FORCE)
  set(LLAMA_ACCELERATE OFF CACHE BOOL "Enable Accelerate" FORCE)
endif()

# 上游开关：非 Apple 平台默认不构建 examples，避免额外依赖；测试统一关闭
if(APPLE)
  set(LLAMA_BUILD_EXAMPLES ON CACHE BOOL "Build examples to get common lib" FORCE)
else()
  set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "No examples on non-Apple" FORCE)
endif()
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "No tests" FORCE)

set(LLAMA_CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp)
add_subdirectory(${LLAMA_CPP_DIR})

# -------- nlohmann/json：优先用系统/包管理器，找不到就 FetchContent 拉取 --------
# 方案 A：find_package（如果你用 brew 装过：brew install nlohmann-json）
find_package(nlohmann_json QUIET)

# 方案 B：没找到就 FetchContent（纯头文件库）
if (NOT nlohmann_json_FOUND)
  include(FetchContent)
  # 固定一个稳定版本（如 3.11.3）
  FetchContent_Declare(
    nlohmann_json
    URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
  )
  FetchContent_MakeAvailable(nlohmann_json)
endif()

# 统一变量，待会儿给目标链接
set(LLX_JSON_TARGET nlohmann_json::nlohmann_json)

set(MINJA_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/minja/include")

# -------- 选择 llama.cpp 的 common --------
set(LLAMA_COMMON_DIR "${LLAMA_CPP_DIR}/common")

# -------- SDK 动态库 --------
add_library(llx SHARED src/llx.cpp)
target_include_directories(llx
  PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${LLAMA_CPP_DIR}            # for llama.h
          ${LLAMA_COMMON_DIR}         # for common.h / chat.h / json helpers
          ${LLAMA_CPP_DIR}/vendor     # for cpp-httplib (common/http.h)
          ${MINJA_INCLUDE_DIR}
)
target_link_libraries(llx PRIVATE llama ${LLX_JSON_TARGET})
target_compile_definitions(llx PRIVATE GGML_USE_K_QUANTS)
set_target_properties(llx PROPERTIES OUTPUT_NAME "inferx_llm")

# Windows 下导出符号并链接必要系统库
if(WIN32)
  target_compile_definitions(llx PRIVATE LLX_BUILD_DLL _CRT_SECURE_NO_WARNINGS NOMINMAX)
  target_link_libraries(llx PRIVATE ws2_32 bcrypt)
endif()

file(GLOB _LLX_COMMON_SRC "${LLAMA_COMMON_DIR}/*.cpp")
add_library(llx_common STATIC ${_LLX_COMMON_SRC})
target_sources(llx_common PRIVATE src/llx_build_info.cpp)
target_include_directories(llx_common
PUBLIC
  "${LLAMA_COMMON_DIR}"
  "${LLAMA_CPP_DIR}/vendor"  # for cpp-httplib (common/http.h)
  "${MINJA_INCLUDE_DIR}"      # ✅ 加上这行
)
target_link_libraries(llx_common PUBLIC llama ${LLX_JSON_TARGET})
target_link_libraries(llx PRIVATE llx_common)

# -------- CLI 示例 --------
add_executable(llx-cli example/cli.cpp)
target_include_directories(llx-cli PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(llx-cli PRIVATE llx)
add_executable(llx-agent example/agent.cpp)
target_include_directories(llx-agent PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(llx-agent PRIVATE llx ${LLX_JSON_TARGET})

if(APPLE)
  target_compile_options(llx PRIVATE -fvisibility=hidden)
  target_compile_options(llx-cli PRIVATE -fvisibility=hidden)
endif()
