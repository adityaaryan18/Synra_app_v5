import 'package:flutter/material.dart';

class AnalysisPage extends StatelessWidget {
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Previous Analysis')),
      body: const Center(
        child: Text(
          'List of previous analyses will appear here (UNDER DEVELOPMENT)',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}