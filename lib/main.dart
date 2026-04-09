import 'package:flutter/material.dart';

import 'model_manager_page.dart';

void main() {
  runApp(const LocalAiApp());
}

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005B96)),
      ),
      home: const ModelManagerPage(title: 'Local AI'),
    );
  }
}
