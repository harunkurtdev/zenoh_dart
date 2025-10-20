#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zenoh_dart.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zenoh_dart'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  
  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  
  s.platform = :osx, '10.11'
  s.swift_version = '5.0'
  
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build/_deps/zenohc-src/include"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build"',
    'OTHER_LDFLAGS' => '$(inherited) -lzenohc -lzenoh_dart'
  }
  
  # CMake build için prepare_command
  # CMake build için prepare_command
  s.prepare_command = <<-CMD
    set -e
    echo "================================================"
    echo "Building zenoh-c via CMake..."
    echo "Current directory: $(pwd)"
    echo "================================================"
    
    # Cargo path'ini ayarla
    export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
    
    # Rust ve Cargo kontrolü
    if ! command -v cargo &> /dev/null; then
      echo "❌ Error: cargo not found!"
      echo "Please install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      exit 1
    fi
    
    echo "✓ Found cargo: $(which cargo)"
    echo "✓ Rust version: $(rustc --version)"
    
    # Plugin kök dizinine git (macos klasörünün bir üstü)
    PLUGIN_ROOT="$(cd .. && pwd)"
    SRC_DIR="${PLUGIN_ROOT}/src"
    
    echo "Plugin root: ${PLUGIN_ROOT}"
    echo "Source dir: ${SRC_DIR}"
    
    # src dizininin varlığını kontrol et
    if [ ! -d "${SRC_DIR}" ]; then
      echo "❌ Error: ${SRC_DIR} not found!"
      echo "Available directories in ${PLUGIN_ROOT}:"
      ls -la "${PLUGIN_ROOT}"
      exit 1
    fi
    
    # src dizinine git
    cd "${SRC_DIR}"
    echo "Working in: $(pwd)"
    
    # Build dizini oluştur
    mkdir -p build
    cd build
    
    # CMake configure
    echo "Running CMake configure..."

    export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$(uname -m)"
    
    # CMake build
    echo "Running CMake build..."
    cmake --build . --config Release
    
    echo "================================================"
    echo "✓ zenoh-c built successfully!"
    echo "Build artifacts:"
    ls -lh *.dylib 2>/dev/null || echo "No .dylib files found"
    echo "================================================"
  CMD



  # Preserve paths - CMake build ürünlerini koru
  s.preserve_paths = [
    '../src/build/**/*',
    '../src/build/_deps/zenohc-src/include/**/*',
    '../src/_deps/**/*'
  ]
  
  # Vendored libraries
  s.vendored_libraries = [
    '../src/build/libzenoh_dart.dylib',
    '../src/build/libzenohc.dylib'
  ]

  s.vendored_frameworks = '../src/build/zenoh_dart.framework'
  
  # Public header files - zenoh.h'yi Xcode'a tanıt
  s.public_header_files = [
    'Classes/**/*.h'
  ]
end