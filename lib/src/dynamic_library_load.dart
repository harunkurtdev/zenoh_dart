import 'dart:ffi';
import 'dart:io';

// TODO : error Unsupported operation: Unknown platform: macos
class DynamicLibraryLoader {
  static final DynamicLibraryLoader _instance =
      DynamicLibraryLoader._internal();
  static const String _libName = 'zenoh_dart';
  late final DynamicLibrary library;
  factory DynamicLibraryLoader() {
    return _instance;
  }
  DynamicLibraryLoader._internal() {
    if (Platform.isMacOS || Platform.isIOS) {
      library = DynamicLibrary.open('${_libName}.framework/${_libName}');
    }
    if (Platform.isAndroid || Platform.isLinux) {
      library = DynamicLibrary.open('lib${_libName}.so');
    }
    if (Platform.isWindows) {
      library = DynamicLibrary.open('${_libName}.dll');
    }
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }
}
