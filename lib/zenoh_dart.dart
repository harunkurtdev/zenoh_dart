// zenoh_dart.dart

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dart:convert';

import 'src/gen/zenoh_dart_bindings_generated.dart';

typedef DartSubscriberCallback = void Function(
    String key, String value, String kind, String attachment, int subscriberId);

class ZenohDart {
  static final ZenohDartBindings _bindings = ZenohDartBindings(_dylib);

  // Store active subscribers with their callbacks
  static final Map<int, DartSubscriberCallback> _activeSubscribers = {};

  // Use a single NativeCallable that stays alive for the app lifetime
  static NativeCallable<SubscriberCallbackFunction>? _nativeCallable;
  static bool _isInitialized = false;

  /// Initialize Zenoh session and callback
  static Future<void> initialize(
      {String mode = 'client', List<String> endpoints = const []}) async {
    if (_isInitialized) return;

    print('ZenohDart: Initializing...');

    // Open session first
    final result = openSession(mode: mode, endpoints: endpoints);
    if (result < 0) {
      throw Exception('Failed to open Zenoh session: $result');
    }

    // Create a single NativeCallable that will handle ALL callbacks
    // This stays alive for the entire app lifetime
    _nativeCallable = NativeCallable<SubscriberCallbackFunction>.listener(
      _globalCallback,
    );

    _isInitialized = true;
    print('ZenohDart: Initialized successfully');
  }

  /// Global callback that dispatches to registered Dart callbacks
  static void _globalCallback(
    Pointer<Char> key,
    Pointer<Char> value,
    Pointer<Char> kind,
    Pointer<Char> attachment,
    int subscriberId,
  ) {
    // These pointers are malloc'd on C side and we OWN them
    // We MUST free them after copying to Dart strings

    String? keyStr;
    String? valueStr;
    String? kindStr;
    String? attachmentStr;

    try {
      // Check if we have a callback registered for this subscriber
      final callback = _activeSubscribers[subscriberId];
      if (callback == null) {
        // Free the strings even if no callback
        _freeCallbackStrings(key, value, kind, attachment);
        return;
      }

      // Validate pointers
      if (key.address == 0 ||
          value.address == 0 ||
          kind.address == 0 ||
          attachment.address == 0) {
        print(
            'Warning: Received null pointer in callback for subscriber $subscriberId');
        _freeCallbackStrings(key, value, kind, attachment);
        return;
      }

      // Copy strings from C memory to Dart strings
      // This must succeed before we free the C strings
      try {
        keyStr = key.cast<Utf8>().toDartString();
      } catch (e) {
        print('Error decoding key: $e');
        _freeCallbackStrings(key, value, kind, attachment);
        return;
      }

      try {
        valueStr = value.cast<Utf8>().toDartString();
      } catch (e) {
        print('Error decoding value: $e');
        valueStr = '<decode error>';
      }

      try {
        kindStr = kind.cast<Utf8>().toDartString();
      } catch (e) {
        print('Error decoding kind: $e');
        kindStr = 'UNKNOWN';
      }

      try {
        attachmentStr = attachment.cast<Utf8>().toDartString();
      } catch (e) {
        attachmentStr = '';
      }

      // Free C strings BEFORE calling Dart callback
      // Now the strings are safely copied to Dart
      _freeCallbackStrings(key, value, kind, attachment);

      // Now call the Dart callback with our Dart strings
      callback(keyStr, valueStr, kindStr, attachmentStr, subscriberId);
    } catch (e) {
      print('Error in global callback: $e');
      // Make sure we free even on error
      try {
        _freeCallbackStrings(key, value, kind, attachment);
      } catch (_) {}
    }
  }

  /// Helper to free C strings passed to callback
  static void _freeCallbackStrings(
    Pointer<Char> key,
    Pointer<Char> value,
    Pointer<Char> kind,
    Pointer<Char> attachment,
  ) {
    try {
      if (key.address != 0) calloc.free(key);
      if (value.address != 0) calloc.free(value);
      if (kind.address != 0) calloc.free(kind);
      // Attachment is usually empty string "", don't free it
      // if (attachment.address != 0) calloc.free(attachment);
    } catch (e) {
      print('Error freeing callback strings: $e');
    }
  }

  /// Subscribe to a Zenoh key expression
  static Future<int> subscribe(
      String key, DartSubscriberCallback callback) async {
    if (!_isInitialized) {
      throw Exception('ZenohDart not initialized. Call initialize() first.');
    }

    try {
      final keyPtr = key.toNativeUtf8().cast<Char>();

      // Subscribe using the global callback pointer
      final subscriberId = _bindings.zenoh_subscribe(
        keyPtr,
        _nativeCallable!.nativeFunction,
      );

      calloc.free(keyPtr);

      if (subscriberId >= 0) {
        // Store the Dart callback
        _activeSubscribers[subscriberId] = callback;
        print('ZenohDart: Subscribed to "$key" with ID: $subscriberId');
        return subscriberId;
      } else {
        throw Exception('Failed to subscribe to $key, error: $subscriberId');
      }
    } catch (e) {
      print('Error in subscribe: $e');
      rethrow;
    }
  }

  /// Unsubscribe specific subscriber
  static void unsubscribe(int subscriberId) {
    try {
      // Remove callback first
      _activeSubscribers.remove(subscriberId);

      // Then unsubscribe on native side
      _bindings.zenoh_unsubscribe(subscriberId);

      print('ZenohDart: Unsubscribed subscriber ID: $subscriberId');
    } catch (e) {
      print('Error unsubscribing $subscriberId: $e');
    }
  }

  /// Unsubscribe all subscribers
  static Future<void> unsubscribeAll() async {
    print('ZenohDart: Unsubscribing all...');

    // Clear all Dart callbacks first
    _activeSubscribers.clear();

    // Then unsubscribe on native side
    try {
      _bindings.zenoh_unsubscribe_all();
      print('ZenohDart: All subscriptions removed');
    } catch (e) {
      print('Error unsubscribing all: $e');
    }
  }

  /// Cleanup Zenoh
  static Future<void> cleanup() async {
    print('ZenohDart: Starting cleanup...');

    // Unsubscribe all first
    await unsubscribeAll();

    // Small delay to ensure callbacks finish
    await Future.delayed(const Duration(milliseconds: 100));

    // Close session
    try {
      _bindings.zenoh_close_session();
      print('ZenohDart: Session closed');
    } catch (e) {
      print('Error closing session: $e');
    }

    // Close the native callable
    _nativeCallable?.close();
    _nativeCallable = null;

    // Cleanup native resources
    try {
      _bindings.zenoh_cleanup();
      print('ZenohDart: Native cleanup complete');
    } catch (e) {
      print('Error in native cleanup: $e');
    }

    _isInitialized = false;
    print('ZenohDart: Cleanup complete');
  }

  /// Initialize Zenoh (legacy)
  static int init() => _bindings.zenoh_init();

  /// Open a new session
  // static int openSession() {
  //   final result = _bindings.zenoh_open_session();
  //   print('ZenohDart: Open session result: $result');
  //   return result;
  // }

  static int openSession(
      {String mode = 'client', List<String> endpoints = const []}) {
    final modePtr = mode.toNativeUtf8().cast<Char>();
    final endpointsJson = jsonEncode(endpoints); // ["tcp/...", "tcp/..."]
    final endpointsPtr = endpointsJson.toNativeUtf8().cast<Char>();
    final result = _bindings.zenoh_open_session(modePtr, endpointsPtr);
    calloc.free(modePtr);
    calloc.free(endpointsPtr);
    return result;
  }

  /// Close session
  static Future<void> closeSession() async {
    print('ZenohDart: Closing session...');
    await unsubscribeAll();

    try {
      _bindings.zenoh_close_session();
      print('ZenohDart: Session closed');
    } catch (e) {
      print('Error closing session: $e');
    }
  }

  /// Publish a value
  static int publish(String key, String value) {
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final valuePtr = value.toNativeUtf8().cast<Char>();
    final result = _bindings.zenoh_publish(keyPtr, valuePtr);
    calloc.free(keyPtr);
    calloc.free(valuePtr);
    return result < 0 ? -1 : 0;
  }

  /// Put a value
  static int put(String key, String value) {
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final valuePtr = value.toNativeUtf8().cast<Char>();
    final result = _bindings.zenoh_put(keyPtr, valuePtr);
    calloc.free(keyPtr);
    calloc.free(valuePtr);
    return result;
  }

  /// Get a value
  static String? get(String key) {
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final result = _bindings.zenoh_get(keyPtr);
    calloc.free(keyPtr);
    if (result.address != 0) {
      final dartString = result.cast<Utf8>().toDartString();
      _bindings.zenoh_free_string(result);
      return dartString;
    }
    return null;
  }

  static void freeString(Pointer<Char> str) => _bindings.zenoh_free_string(str);

  static Map<String, dynamic> get constants => _constants;

  static final Map<String, dynamic> _constants = {
    'CONGESTION_CONTROL_DEFAULT': Z_CONGESTION_CONTROL_DEFAULT,
    'CONSOLIDATION_MODE_DEFAULT': Z_CONSOLIDATION_MODE_DEFAULT,
    'PRIORITY_DEFAULT': Z_PRIORITY_DEFAULT,
    'QUERY_TARGET_DEFAULT': Z_QUERY_TARGET_DEFAULT,
    'SAMPLE_KIND_DEFAULT': Z_SAMPLE_KIND_DEFAULT,
    'CONFIG_MODE_KEY': Z_CONFIG_MODE_KEY,
    'CONFIG_CONNECT_KEY': Z_CONFIG_CONNECT_KEY,
    'CONFIG_LISTEN_KEY': Z_CONFIG_LISTEN_KEY,
    'CONFIG_USER_KEY': Z_CONFIG_USER_KEY,
    'CONFIG_PASSWORD_KEY': Z_CONFIG_PASSWORD_KEY,
    'CONFIG_MULTICAST_SCOUTING_KEY': Z_CONFIG_MULTICAST_SCOUTING_KEY,
    'CONFIG_MULTICAST_INTERFACE_KEY': Z_CONFIG_MULTICAST_INTERFACE_KEY,
    'CONFIG_MULTICAST_IPV4_ADDRESS_KEY': Z_CONFIG_MULTICAST_IPV4_ADDRESS_KEY,
    'CONFIG_SCOUTING_DELAY_KEY': Z_CONFIG_SCOUTING_DELAY_KEY,
    'CONFIG_SCOUTING_TIMEOUT_KEY': Z_CONFIG_SCOUTING_TIMEOUT_KEY,
    'CONFIG_ADD_TIMESTAMP_KEY': Z_CONFIG_ADD_TIMESTAMP_KEY,
    'CONFIG_SHARED_MEMORY_KEY': Z_CONFIG_SHARED_MEMORY_KEY,
  };
}

const String _libName = 'zenoh_dart';

/// The dynamic library in which the symbols for [ZenohDartBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();
