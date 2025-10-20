// example/lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenoh_dart/zenoh_dart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up Zenoh when app is disposed
    ZenohDart.cleanup();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Clean up when app goes to background to prevent callbacks after isolate death
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ZenohDart.closeSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenoh Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MultipleSubscribersPage(),
    );
  }
}

class ZenohHomePage extends StatefulWidget {
  const ZenohHomePage({super.key});

  @override
  State<ZenohHomePage> createState() => _ZenohHomePageState();
}

class _ZenohHomePageState extends State<ZenohHomePage> {
  String _receivedValue = 'Waiting for data...';
  int? _subscriberId;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeZenoh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload detected - clean up old subscriptions
    print('Hot reload detected - cleaning up...');
    if (_subscriberId != null) {
      try {
        ZenohDart.unsubscribe(_subscriberId!);
        _subscriberId = null;
      } catch (e) {
        print('Error during hot reload cleanup: $e');
      }
    }
    // Reinitialize
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitializing = true;
          _errorMessage = null;
        });
        _initializeZenoh();
      }
    });
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;

    try {
      // Initialize session and isolate
      await ZenohDart.initialize();

      // Subscribe
      final subscriberId = await ZenohDart.subscribe(
        'mqtt/demo/sensor/temperature',
        (key, value, kind, attachment, id) {
          if (mounted && !_isDisposed) {
            setState(() {
              _receivedValue = 'Key: $key\nValue: $value\nKind: $kind';
            });
          }
        },
      );

      if (!_isDisposed && mounted) {
        setState(() {
          _subscriberId = subscriberId;
          _isInitializing = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      print('Error initializing Zenoh: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenoh Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isInitializing)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Subscribing to demo/example...'),
                ],
              )
            else if (_errorMessage != null)
              Column(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Error: $_errorMessage'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isInitializing = true;
                        _errorMessage = null;
                      });
                      _initializeZenoh();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              )
            else
              Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 16),
                  Text('Subscribed with ID: $_subscriberId'),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _receivedValue,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _subscriberId != null && !_isInitializing
                  ? () {
                      try {
                        ZenohDart.publish(
                            'demo/example', 'Hello from Flutter!');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Message published!')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Publish Message'),
            ),
          ],
        ),
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
    super.dispose();
  }
}

// ============================================
// Alternative: StreamBuilder usage
// ============================================

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
      await ZenohDart.initialize();

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

// ============================================
// Advanced example: Multiple Subscribers
// ============================================

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
      await ZenohDart.initialize();

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
