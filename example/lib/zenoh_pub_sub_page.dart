import 'package:flutter/material.dart';
import 'package:zenoh_dart/zenoh_dart.dart' show ZenohDart;

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
      await ZenohDart.initialize(mode: 'client', endpoints: [
        'tcp/localhost:7447',
        'tcp/10.51.45.140:7447',
        'tcp/127.0.0.1:7447',
        'tcp/10.0.0.2:7447', // android emulator localhost
      ]);

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
