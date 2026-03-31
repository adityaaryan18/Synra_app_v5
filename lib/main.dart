import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/camera/setup_page.dart'; // Ensure this path is correct

void main() {
  // Ensure Flutter bindings are initialized before calling native channels
  WidgetsFlutterBinding.ensureInitialized();
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
        // Optional: Ensure text scales don't break your UI
        useMaterial3: true,
      ),
      // Use 'initialRoute' OR 'home'. Since we want a reset path, 
      // named routes are better.
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/setup': (context) => const SetupPage(),
      },
    );
  }
}