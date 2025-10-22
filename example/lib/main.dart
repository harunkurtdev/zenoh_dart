import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenoh_dart/zenoh_dart.dart';
import 'package:zenoh_dart_example/multiple_subscriber_page.dart'
    show MultipleSubscribersPage;

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
