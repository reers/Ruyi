cmake_minimum_required(VERSION 3.16.5)
project(ruyi_harmony LANGUAGES CXX)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

# Headers: vendored under this module (OHPM @vnixx/thorvg ships .so only for now).
set(THORVG_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")

# libthorvg.so from ohpm-installed @vnixx/thorvg (module / project / hashed cache).
set(THORVG_SO "")
foreach(candidate
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/@vnixx/thorvg/libs/${OHOS_ARCH}/libthorvg.so"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/@vnixx/thorvg/libs/arm64-v8a/libthorvg.so"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../oh_modules/@vnixx/thorvg/libs/${OHOS_ARCH}/libthorvg.so"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../oh_modules/@vnixx/thorvg/libs/arm64-v8a/libthorvg.so"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../libs/native/${OHOS_ARCH}/libthorvg.so"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../libs/native/arm64-v8a/libthorvg.so"
)
    if(EXISTS "${candidate}")
        set(THORVG_SO "${candidate}")
        break()
    endif()
endforeach()

# ohpm may store packages under oh_modules/.ohpm/<hash>/oh_modules/@vnixx/thorvg/
if(THORVG_SO STREQUAL "")
    file(GLOB_RECURSE THORVG_SO_CANDIDATES
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/.ohpm/*/oh_modules/@vnixx/thorvg/libs/*/libthorvg.so"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../../oh_modules/.ohpm/*/oh_modules/@vnixx/thorvg/libs/*/libthorvg.so"
    )
    if(THORVG_SO_CANDIDATES)
        list(GET THORVG_SO_CANDIDATES 0 THORVG_SO)
    endif()
endif()

if(THORVG_SO STREQUAL "")
    message(FATAL_ERROR
        "libthorvg.so not found. Run: (cd ruyi && ohpm install) "
        "to pull @vnixx/thorvg from OHPM.")
endif()

if(NOT EXISTS "${THORVG_INCLUDE_DIR}/thorvg_capi.h")
    message(FATAL_ERROR "thorvg_capi.h missing under ruyi/src/main/cpp/include")
endif()

message(STATUS "Ruyi linking ThorVG: ${THORVG_SO}")

add_library(thorvg SHARED IMPORTED)
set_target_properties(thorvg PROPERTIES
    IMPORTED_LOCATION "${THORVG_SO}"
)

# NAPI + render bridge (Android equivalent: libruyi.so / jni_bridge.cpp).
add_library(ruyi SHARED
    napi_bridge.cpp
    render_core.cpp
)

target_include_directories(ruyi
    PRIVATE
        ${NATIVERENDER_ROOT_PATH}
        ${THORVG_INCLUDE_DIR}
)

target_compile_features(ruyi PRIVATE cxx_std_17)

target_link_libraries(ruyi
    PRIVATE
        thorvg
        ace_napi.z
        hilog_ndk.z
)
