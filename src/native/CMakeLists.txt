cmake_minimum_required(VERSION 3.20)
project(PurviewProtectionOverlay LANGUAGES CXX)

# Keep the Explorer extension self-contained and avoid requiring a separate
# Visual C++ Redistributable deployment.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_library(PurviewProtectionOverlay SHARED
    OverlayHandler.cpp
    OverlayHandler.def
)

target_compile_features(PurviewProtectionOverlay PRIVATE cxx_std_20)
target_compile_definitions(PurviewProtectionOverlay PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_compile_options(PurviewProtectionOverlay PRIVATE /W4 /permissive- /EHsc)
target_link_libraries(PurviewProtectionOverlay PRIVATE shell32 ole32 shlwapi)

set_target_properties(PurviewProtectionOverlay PROPERTIES
    OUTPUT_NAME "PurviewProtectionOverlay"
)
