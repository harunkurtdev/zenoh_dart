// ============================================
// Advanced example: Multiple Subscribers
// ============================================

import 'package:flutter/material.dart';
import 'package:zenoh_dart/zenoh_dart.dart' show ZenohDart;

class MultipleSubscribersPage extends StatefulWidget {
  const MultipleSubscribersPage({super.key});

  @override
  State<MultipleSubscribersPage> createState() =>
      _MultipleSubscribersPageState();
}

class _MultipleSubscribersPageState extends State<MultipleSubscribersPage> {
  final Map<String, int?> _subscriberIds = {};
  final Map<String, String> _latestValues = {};
  final Map<String, bool> _isLoading = {};
  final Map<String, String?> _errors = {};
  bool _isDisposed = false;

  final List<String> _topics = [
    'mqtt/demo/sensor/temperature',
    'sensor/humidity',
    'sensor/pressure',
    'mqtt/demo/sensor/temperature',
    'mqtt/demo/sensor/**',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize loading states
    for (var topic in _topics) {
      _isLoading[topic] = true;
    }
    // Use addPostFrameCallback to avoid issues during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSubscriptions();
    });
  }

  Future<void> _initSubscriptions() async {
    if (_isDisposed) return;

    try {
      // Initialize Zenoh session, isolate, etc.
      // ip address for zenoh routers
      await ZenohDart.initialize(mode: 'client', endpoints: [
        'tcp/localhost:7447',
        'tcp/10.51.45.140:7447',
        'tcp/127.0.0.1:7447',
        'tcp/10.0.0.2:7447', // android emulator localhost
      ]);

      for (var topic in _topics) {
        if (_isDisposed) break;

        try {
          final subscriberId = await ZenohDart.subscribe(
            topic,
            (key, value, kind, attachment, id) {
              if (!_isDisposed && mounted) {
                setState(() {
                  _latestValues[key] = value;
                });
              }
            },
          );

          if (!_isDisposed && mounted) {
            setState(() {
              _subscriberIds[topic] = subscriberId;
              _isLoading[topic] = false;
              _errors[topic] = null;
            });
          }
        } catch (e) {
          print('Error subscribing to $topic: $e');
          if (!_isDisposed && mounted) {
            setState(() {
              _isLoading[topic] = false;
              _errors[topic] = e.toString();
            });
          }
        }
      }
    } catch (e) {
      print('Error initializing subscriptions: $e');
      if (!_isDisposed && mounted) {
        for (var topic in _topics) {
          setState(() {
            _isLoading[topic] = false;
            _errors[topic] = e.toString();
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multiple Zenoh Subscribers'),
      ),
      body: ListView.builder(
        itemCount: _topics.length,
        itemBuilder: (context, index) {
          final topic = _topics[index];
          final isLoading = _isLoading[topic] ?? true;
          final error = _errors[topic];
          final subscriberId = _subscriberIds[topic];

          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : error != null
                      ? const Icon(Icons.error, color: Colors.red)
                      : const Icon(Icons.check_circle, color: Colors.green),
              title: Text(topic),
              subtitle: Text(
                isLoading
                    ? 'Subscribing...'
                    : error != null
                        ? 'Error: $error'
                        : 'Value: ${_latestValues[topic] ?? "No data yet"}',
              ),
              trailing: subscriberId != null && !isLoading
                  ? IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        try {
                          ZenohDart.publish(
                            topic,
                            '${DateTime.now().millisecondsSinceEpoch}',
                          );
                        } catch (e) {
                          print('Error publishing: $e');
                        }
                      },
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Unsubscribe all individually
    for (var id in _subscriberIds.values) {
      if (id != null) {
        try {
          ZenohDart.unsubscribe(id);
        } catch (e) {
          print('Error unsubscribing $id: $e');
        }
      }
    }
    super.dispose();
  }
}
