cmake_minimum_required(VERSION 3.14)
project(zenoh_dart_library VERSION 0.0.1 LANGUAGES C)

# FetchContent ile zenoh-c'yi indir (ama henüz build etme)
include(FetchContent)
FetchContent_Declare(
    zenohc
    GIT_REPOSITORY https://github.com/eclipse-zenoh/zenoh-c.git
    GIT_TAG 1.5.1
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)

# Sadece kaynak kodunu indir, build etme
FetchContent_GetProperties(zenohc)
if(NOT zenohc_POPULATED)
    message(STATUS "Downloading zenoh-c...")
    FetchContent_Populate(zenohc)
    message(STATUS "zenoh-c downloaded to: ${zenohc_SOURCE_DIR}")
endif()

# Platform tespiti
if(ANDROID)
    message(STATUS "Building for Android ABI: ${ANDROID_ABI}")
    
    if(${ANDROID_ABI} STREQUAL "arm64-v8a")
        set(ZENOHC_TARGET "aarch64-linux-android")
        set(ANDROID_TOOLCHAIN_PREFIX "aarch64-linux-android")
    elseif(${ANDROID_ABI} STREQUAL "armeabi-v7a")
        set(ZENOHC_TARGET "armv7-linux-androideabi")
        set(ANDROID_TOOLCHAIN_PREFIX "armv7a-linux-androideabi")
    elseif(${ANDROID_ABI} STREQUAL "x86_64")
        set(ZENOHC_TARGET "x86_64-linux-android")
        set(ANDROID_TOOLCHAIN_PREFIX "x86_64-linux-android")
    elseif(${ANDROID_ABI} STREQUAL "x86")
        set(ZENOHC_TARGET "i686-linux-android")
        set(ANDROID_TOOLCHAIN_PREFIX "i686-linux-android")
    else()
        message(FATAL_ERROR "❌ Unsupported ANDROID_ABI: ${ANDROID_ABI}")
    endif()
    
    set(ZENOHC_LIB "${zenohc_SOURCE_DIR}/target/${ZENOHC_TARGET}/release/libzenohc.so")
else()
    message(STATUS "Building for ${CMAKE_SYSTEM_NAME}")
    
    # Host sistem için Rust target belirleme
    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|ARM64")
            set(RUST_TARGET "aarch64-apple-darwin")
        else()
            set(RUST_TARGET "x86_64-apple-darwin")
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
            set(RUST_TARGET "aarch64-unknown-linux-gnu")
        else()
            set(RUST_TARGET "x86_64-unknown-linux-gnu")
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set(RUST_TARGET "x86_64-pc-windows-msvc")
    endif()
    
    if(WIN32)
        set(ZENOHC_LIB "${zenohc_SOURCE_DIR}/target/${RUST_TARGET}/release/zenohc.dll")
        set(ZENOHC_IMPLIB "${zenohc_SOURCE_DIR}/target/${RUST_TARGET}/release/zenohc.dll.lib")
    elseif(APPLE)
        set(ZENOHC_LIB "${zenohc_SOURCE_DIR}/target/${RUST_TARGET}/release/libzenohc.dylib")
    else()
        set(ZENOHC_LIB "${zenohc_SOURCE_DIR}/target/${RUST_TARGET}/release/libzenohc.so")
    endif()
endif()

message(STATUS "Rust target: ${RUST_TARGET}")
message(STATUS "zenoh-c source: ${zenohc_SOURCE_DIR}")
message(STATUS "zenoh-c library: ${ZENOHC_LIB}")
message(STATUS "zenoh-c headers: ${zenohc_SOURCE_DIR}/include")

# ÖNEMLİ: zenoh-c'yi HEMEN build et (configure zamanında)
if(NOT EXISTS ${ZENOHC_LIB})
    message(STATUS "====================================")
    message(STATUS "Building zenoh-c library NOW...")
    message(STATUS "====================================")
    
    # Cargo'yu bul
    find_program(CARGO_EXECUTABLE cargo)
    if(NOT CARGO_EXECUTABLE)
        message(FATAL_ERROR "cargo not found! Please install Rust: https://rustup.rs/")
    endif()
    message(STATUS "Found cargo at: ${CARGO_EXECUTABLE}")
    
    if(ANDROID)
        # Android için cargo config oluştur
        set(CARGO_CONFIG_DIR "${zenohc_SOURCE_DIR}/.cargo")
        file(MAKE_DIRECTORY ${CARGO_CONFIG_DIR})
        file(WRITE "${CARGO_CONFIG_DIR}/config.toml"
"[target.${ZENOHC_TARGET}]
linker = \"${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang\"
ar = \"${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar\"
")
        
        string(TOUPPER ${ZENOHC_TARGET} ZENOHC_TARGET_UPPER)
        string(REPLACE "-" "_" ZENOHC_TARGET_UPPER_UNDERSCORE ${ZENOHC_TARGET_UPPER})
        string(REPLACE "-" "_" ZENOHC_TARGET_UNDERSCORE ${ZENOHC_TARGET})
        
        execute_process(
            COMMAND ${CMAKE_COMMAND} -E env
                CC_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
                CXX_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++
                AR_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
                CC_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
                CXX_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++
                AR_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
                CARGO_TARGET_${ZENOHC_TARGET_UPPER_UNDERSCORE}_LINKER=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
                ${CARGO_EXECUTABLE} build --release --target ${ZENOHC_TARGET}
            WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
            RESULT_VARIABLE CARGO_BUILD_RESULT
            OUTPUT_VARIABLE CARGO_OUTPUT
            ERROR_VARIABLE CARGO_ERROR
            COMMAND_ECHO STDOUT
        )
    
    else()
        # macOS, Linux, Windows için
        message(STATUS "Running: ${CARGO_EXECUTABLE} build --release --target ${RUST_TARGET}")
        message(STATUS "Working directory: ${zenohc_SOURCE_DIR}")
        
        execute_process(
            COMMAND ${CARGO_EXECUTABLE} build --release --target ${RUST_TARGET}
            WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
            RESULT_VARIABLE CARGO_BUILD_RESULT
            OUTPUT_VARIABLE CARGO_OUTPUT
            ERROR_VARIABLE CARGO_ERROR
            COMMAND_ECHO STDOUT
        )
    endif()
    
    # Detaylı hata mesajı
    if(NOT CARGO_BUILD_RESULT EQUAL 0)
        message(STATUS "====================================")
        message(STATUS "❌ Cargo build failed!")
        message(STATUS "====================================")
        message(STATUS "Working directory: ${zenohc_SOURCE_DIR}")
        message(STATUS "Command: ${CARGO_EXECUTABLE} build --release --target ${RUST_TARGET}")
        message(STATUS "Result code: ${CARGO_BUILD_RESULT}")
        message(STATUS "------------------------------------")
        if(CARGO_OUTPUT)
            message(STATUS "Standard Output:")
            message(STATUS "${CARGO_OUTPUT}")
        else()
            message(STATUS "No standard output")
        endif()
        message(STATUS "------------------------------------")
        if(CARGO_ERROR)
            message(STATUS "Standard Error:")
            message(STATUS "${CARGO_ERROR}")
        else()
            message(STATUS "No error output")
        endif()
        message(STATUS "====================================")
        message(FATAL_ERROR "Failed to build zenoh-c!")
    endif()
    
    message(STATUS "====================================")
    message(STATUS "✓ zenoh-c built successfully!")
    message(STATUS "====================================")
else()
    message(STATUS "✓ zenoh-c already built")
endif()

# Kütüphanenin var olduğunu doğrula
if(NOT EXISTS ${ZENOHC_LIB})
    message(FATAL_ERROR "zenoh-c library not found at: ${ZENOHC_LIB}")
endif()

# Header dosyasının var olduğunu doğrula
if(NOT EXISTS "${zenohc_SOURCE_DIR}/include/zenoh.h")
    message(FATAL_ERROR "zenoh.h not found at: ${zenohc_SOURCE_DIR}/include/zenoh.h")
endif()

message(STATUS "✓ All zenoh-c files verified")

# zenoh_dart kütüphanesini oluştur
add_library(zenoh_dart SHARED
    "zenoh_dart.c"
)

set_target_properties(zenoh_dart PROPERTIES
    PUBLIC_HEADER zenoh_dart.h
    OUTPUT_NAME "zenoh_dart"
)

# RPATH ayarları
if(ANDROID)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_RPATH "\$ORIGIN"
        INSTALL_RPATH "\$ORIGIN"
    )
elseif(APPLE)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_RPATH "@loader_path"
        INSTALL_RPATH "@loader_path"
    )
elseif(UNIX)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_RPATH "\$ORIGIN"
        INSTALL_RPATH "\$ORIGIN"
    )
endif()

# Include dizinleri - PUBLIC olarak ayarla ki Xcode görebilsin
target_include_directories(zenoh_dart
    PUBLIC
        ${zenohc_SOURCE_DIR}/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(zenoh_dart PUBLIC DART_SHARED_LIB)

# zenohc'yi imported library olarak tanımla
add_library(zenohc SHARED IMPORTED GLOBAL)
set_target_properties(zenohc PROPERTIES
    IMPORTED_LOCATION ${ZENOHC_LIB}
    INTERFACE_INCLUDE_DIRECTORIES ${zenohc_SOURCE_DIR}/include
)

if(WIN32 AND EXISTS ${ZENOHC_IMPLIB})
    set_target_properties(zenohc PROPERTIES
        IMPORTED_IMPLIB ${ZENOHC_IMPLIB}
    )
endif()

# Link kütüphaneleri
if(ANDROID)
    find_library(log-lib log)
    target_link_libraries(zenoh_dart PRIVATE ${log-lib} zenohc)
    
    target_link_options(zenoh_dart PRIVATE
        "-Wl,-rpath,'$ORIGIN'"
        "-Wl,--enable-new-dtags"
    )
else()
    target_link_libraries(zenoh_dart PRIVATE zenohc)
endif()

# zenohc kütüphanesini output dizinine kopyala
add_custom_command(TARGET zenoh_dart POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${ZENOHC_LIB}
        $<TARGET_FILE_DIR:zenoh_dart>/
    COMMENT "Copying zenoh-c library to output directory"
)

# Windows export tanımlamaları
if(WIN32)
    target_compile_definitions(zenoh_dart PRIVATE ZENOH_DART_EXPORTS)
endif()