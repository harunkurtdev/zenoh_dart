// ============================================
// Alternative: StreamBuilder usage
// ============================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenoh_dart/zenoh_dart.dart' show ZenohDart;

class ZenohStreamPage extends StatefulWidget {
  const ZenohStreamPage({super.key});

  @override
  State<ZenohStreamPage> createState() => _ZenohStreamPageState();
}

class _ZenohStreamPageState extends State<ZenohStreamPage> {
  final StreamController<String> _messageController =
      StreamController<String>();
  int? _subscriberId;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to avoid issues during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSubscriber();
    });
  }

  Future<void> _setupSubscriber() async {
    if (_isDisposed) return;

    try {
      await ZenohDart.initialize(mode: 'client', endpoints: [
        'tcp/localhost:7447',
        'tcp/10.51.45.140:7447',
        'tcp/127.0.0.1:7447',
        'tcp/10.0.0.2:7447', // android emulator localhost
      ]);

      if (_isDisposed || !mounted) return;

      _subscriberId = await ZenohDart.subscribe(
        'demo/stream',
        (key, value, kind, attachment, id) {
          if (!_isDisposed && !_messageController.isClosed) {
            _messageController.add('$key: $value');
          }
        },
      );
    } catch (e) {
      print('Error setting up subscriber: $e');
      if (!_messageController.isClosed) {
        _messageController.addError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenoh StreamBuilder Demo'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<String>(
              stream: _messageController.stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Waiting for messages...'),
                      ],
                    ),
                  );
                }
                return Center(
                  child: Text(
                    snapshot.data!,
                    style: const TextStyle(fontSize: 18),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _subscriberId != null
                  ? () {
                      try {
                        ZenohDart.publish(
                          'demo/stream',
                          'Message at ${DateTime.now().toIso8601String()}',
                        );
                      } catch (e) {
                        print('Error publishing: $e');
                      }
                    }
                  : null,
              child: const Text('Send Message'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_subscriberId != null) {
      try {
        ZenohDart.unsubscribe(_subscriberId!);
      } catch (e) {
        print('Error unsubscribing: $e');
      }
    }
    _messageController.close();
    super.dispose();
  }
}
