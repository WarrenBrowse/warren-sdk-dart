# Linux native build for the Warren in-process engine. cargokit compiles
# `native/warren_sdk_frb` into libwarren_sdk_frb.so and bundles it. See
# NATIVE_BUILD.md.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "warren_sdk_ffi")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../../native/warren_sdk_frb warren_sdk_frb "")

set(warren_sdk_ffi_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
