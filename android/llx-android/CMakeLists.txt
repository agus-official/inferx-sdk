cmake_minimum_required(VERSION 3.22)
project(llx-android LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 默认 Release，提升 O2/O3 等优化并启用 NEON
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_C_FLAGS_RELEASE   "${CMAKE_C_FLAGS_RELEASE} -O3")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")
add_compile_options(-fvisibility=hidden)

if(ANDROID)
    # arm64 常见优化（保留异常以兼容 nlohmann::json 等）
    # ggml 要求允许非有限数学（与 -ffast-math 并存）：-fno-finite-math-only
    add_compile_options(-DNDEBUG -ffast-math -fno-finite-math-only)
endif()

# 控制 llama.cpp 构建选项（Android 先用 CPU）
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)

# 引入 llama.cpp 子工程
add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/../../third_party/llama.cpp
                 ${CMAKE_CURRENT_BINARY_DIR}/llama.cpp)

# 源码路径
set(INFERX_ROOT ${CMAKE_CURRENT_LIST_DIR}/../..)

add_library(llx-android SHARED
    ${INFERX_ROOT}/src/llx.cpp
    ${INFERX_ROOT}/src/llx_build_info.cpp
    src/main/cpp/jni/llx_jni.cpp
)

target_include_directories(llx-android PRIVATE
    ${INFERX_ROOT}/include
    ${INFERX_ROOT}/third_party/llama.cpp
    ${INFERX_ROOT}/third_party/llama.cpp/include
    ${INFERX_ROOT}/third_party/llama.cpp/vendor
)

find_library(log-lib log)

########################################
# nlohmann_json（头文件库）：优先 find，找不到则 FetchContent
find_package(nlohmann_json QUIET)
if (NOT nlohmann_json_FOUND)
  include(FetchContent)
  FetchContent_Declare(
    nlohmann_json
    URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
  )
  FetchContent_MakeAvailable(nlohmann_json)
endif()

target_link_libraries(llx-android PRIVATE
    llama
    common
    nlohmann_json::nlohmann_json
    ${log-lib}
)

target_compile_definitions(llx-android PRIVATE)

