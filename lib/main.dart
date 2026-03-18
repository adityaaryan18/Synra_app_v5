import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const SynraApp());
}

class SynraApp extends StatelessWidget {
  const SynraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SYNRA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const HomePage(),
    );
  }
}