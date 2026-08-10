cmake_minimum_required(VERSION 3.22.1)
project(ruyi_android LANGUAGES CXX)

# Prefab package from io.github.vnixx:thorvg (C API libthorvg.so).
find_package(thorvg REQUIRED CONFIG)

add_library(ruyi SHARED jni_bridge.cpp)

target_compile_features(ruyi PRIVATE cxx_std_17)

find_library(log-lib log)
find_library(android-lib android)

target_link_options(ruyi PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/export.map"
)

target_link_libraries(ruyi
    PRIVATE
        thorvg::thorvg
        ${log-lib}
        ${android-lib}
)
