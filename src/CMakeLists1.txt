cmake_minimum_required(VERSION 3.14)
project(zenoh_dart_library VERSION 0.0.1 LANGUAGES C)
include(FetchContent)

# Zenoh-C Download & Setup
FetchContent_Declare(
    zenohc
    GIT_REPOSITORY https://github.com/eclipse-zenoh/zenoh-c.git
    GIT_TAG 1.5.1
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
    # GIT_TAG release/1.5.1
)
FetchContent_MakeAvailable(zenohc)

# --- ANDROID platform detection & configuration ---
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
    
    # Use zenohc_SOURCE_DIR for build since that's where Cargo.toml is
    set(ZENOHC_BUILD_DIR "${zenohc_SOURCE_DIR}")
    set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${ZENOHC_TARGET}/release/libzenohc.so")
    set(CARGO_CONFIG_DIR "${ZENOHC_BUILD_DIR}/.cargo")
    set(CARGO_CONFIG_FILE "${CARGO_CONFIG_DIR}/config.toml")
    
    message(STATUS "Zenoh-C source directory: ${zenohc_SOURCE_DIR}")
    message(STATUS "Zenoh-C library path: ${ZENOHC_LIB}")
    message(STATUS "Android toolchain prefix: ${ANDROID_TOOLCHAIN_PREFIX}")
    
    # Create .cargo/config.toml for cross-compilation
    file(MAKE_DIRECTORY ${CARGO_CONFIG_DIR})
    file(WRITE ${CARGO_CONFIG_FILE}
"[target.${ZENOHC_TARGET}]
linker = \"${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang\"
ar = \"${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar\"
")
    
    message(STATUS "Created Cargo config at: ${CARGO_CONFIG_FILE}")
    
    # Set up environment variables for cross-compilation
    set(CARGO_TARGET_ENV
        "CC_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang"
        "CXX_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++"
        "AR_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
        "CARGO_TARGET_${ZENOHC_TARGET}_LINKER=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang"
    )
    
    # Convert target name to uppercase and replace dashes with underscores for env var names
    string(TOUPPER ${ZENOHC_TARGET} ZENOHC_TARGET_UPPER)
    string(REPLACE "-" "_" ZENOHC_TARGET_UPPER_UNDERSCORE ${ZENOHC_TARGET_UPPER})
    
    # Also need the version with underscores replacing hyphens (for cc crate)
    string(REPLACE "-" "_" ZENOHC_TARGET_UNDERSCORE ${ZENOHC_TARGET})
    
    # --- Rust (Zenoh-C) build command for Android ---
    add_custom_command(
        OUTPUT ${ZENOHC_LIB}
        COMMAND ${CMAKE_COMMAND} -E env
            CC_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
            CXX_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++
            AR_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
            CC_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
            CXX_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++
            AR_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
            CARGO_TARGET_${ZENOHC_TARGET_UPPER_UNDERSCORE}_LINKER=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
            cargo build --release --target ${ZENOHC_TARGET}
        WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
        COMMENT "Building zenoh-c for Android target: ${ZENOHC_TARGET}"
        VERBATIM
    )
    
    add_custom_target(build_zenohc_android ALL DEPENDS ${ZENOHC_LIB})
endif()

# --- Zenoh Dart shared library ---
add_library(zenoh_dart SHARED
    "zenoh_dart.c"
    # "zenoh_dart_subscriber.c"
)

set_target_properties(zenoh_dart PROPERTIES
    PUBLIC_HEADER zenoh_dart.h
    OUTPUT_NAME "zenoh_dart"
)

# Set RPATH for Android to look in the same directory
if(ANDROID)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_RPATH "\$ORIGIN"
        INSTALL_RPATH "\$ORIGIN"
        LINK_FLAGS "-Wl,-rpath,'\$ORIGIN'"
    )
endif()

target_include_directories(zenoh_dart
    PRIVATE
    ${zenohc_SOURCE_DIR}/include
    ${zenohc_BINARY_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(zenoh_dart PUBLIC DART_SHARED_LIB)

# --- Link libraries ---
if(ANDROID)
    find_library(log-lib log)
    add_dependencies(zenoh_dart build_zenohc_android)
    
    # Import zenohc as an imported library
    add_library(zenohc SHARED IMPORTED)
    set_target_properties(zenohc PROPERTIES
        IMPORTED_LOCATION ${ZENOHC_LIB}
        IMPORTED_NO_SONAME TRUE
    )
    
    # Link zenoh_dart with zenohc and log
    target_link_libraries(zenoh_dart PRIVATE ${log-lib} zenohc)
    
    # Set linker flags to use relative RPATH
    target_link_options(zenoh_dart PRIVATE
        "-Wl,-rpath,'$ORIGIN'"
        "-Wl,--enable-new-dtags"
    )
    
    # Copy libzenohc.so to the output directory so it's included in the APK
    add_custom_command(TARGET zenoh_dart POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${ZENOHC_LIB}
            $<TARGET_FILE_DIR:zenoh_dart>/libzenohc.so
        COMMAND ${CMAKE_COMMAND} -E echo "Copied libzenohc.so to $<TARGET_FILE_DIR:zenoh_dart>/"
        COMMENT "Copying libzenohc.so to output directory"
    )
else()
    # For non-Android platforms (Linux, macOS, Windows)
    # zenohc uses Cargo to build, but we need to build it ourselves
    message(STATUS "Building for ${CMAKE_SYSTEM_NAME}")
    
    # Determine the Rust target triple for the host system
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
            set(RUST_TARGET "x86_64-unknown-linux-gnu")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
            set(RUST_TARGET "aarch64-unknown-linux-gnu")
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
            set(RUST_TARGET "x86_64-apple-darwin")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
            set(RUST_TARGET "aarch64-apple-darwin")
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set(RUST_TARGET "x86_64-pc-windows-msvc")
    endif()
    
    set(ZENOHC_BUILD_DIR "${zenohc_SOURCE_DIR}")
    
    if(WIN32)
        set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/zenohc.dll")
    elseif(APPLE)
        set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/libzenohc.dylib")
    else()
        set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/libzenohc.so")
    endif()

    message(STATUS "Rust target: ${RUST_TARGET}")
    message(STATUS "Zenoh-C library path: ${ZENOHC_LIB}")

    # Build zenohc using Cargo
    add_custom_command(
        OUTPUT ${ZENOHC_LIB}
        COMMAND cargo build --release --target ${RUST_TARGET}
        WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
        COMMENT "Building zenoh-c for ${RUST_TARGET}"
    )
    
    add_custom_target(build_zenohc ALL DEPENDS ${ZENOHC_LIB})
    
    # Import zenohc as an imported library
    add_library(zenohc SHARED IMPORTED)
    set_target_properties(zenohc PROPERTIES
        IMPORTED_LOCATION ${ZENOHC_LIB}
    )
    
    add_dependencies(zenoh_dart build_zenohc)
    target_link_libraries(zenoh_dart PRIVATE zenohc)
endif()

if(NOT ANDROID)
    # Only hide symbols on non-Android platforms if needed
    # set_target_properties(zenoh_dart PROPERTIES
    #     C_VISIBILITY_PRESET hidden
    #     VISIBILITY_INLINES_HIDDEN YES
    # )
endif()

# --- Windows export symbol handling ---
if(WIN32)
    target_compile_definitions(zenoh_dart PRIVATE ZENOH_DART_EXPORTS)
endif()