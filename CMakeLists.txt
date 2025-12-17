# Semi-hacky way to get Emacs eglot with clangd to work OK on macOS. The use of Cmake here is solely for the purposes of
# generating a cmake/compile_commands.json file with the list of sources. There is an existing Makefile which is used
# for the Github CI pipeline, and it can also be used via the command-line.

cmake_minimum_required(VERSION 4.2)

project(DSPHeaders)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(SDK "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")

# Change path from /src if needed, or add more directories
file(GLOB_RECURSE Sources "${CMAKE_SOURCE_DIR}/Sources/DSPHeaders/*.mm")

# No idea what is really necessary here, but this seems to give clangd enough info to parse the Objective C++ files..
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-g;-DDEBUG;-D__OBJC2__;-D__USE_PUBLIC_HEADERS__;-ObjC++;-std=c++23;>")
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-framework;Foundation;-framework;AudioToolbox;-isysroot;${SDK};>")

add_executable(DSPHeaders ${Sources})

target_include_directories(
  DSPHeaders PUBLIC
  "${CMAKE_SOURCE_DIR}/Sources/DSPHeaders/include"
)
