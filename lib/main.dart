import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_page.dart';
import 'dashboard_page.dart';
import 'map_page.dart';
import 'rides_page.dart';
import 'safety_page.dart';
import 'tips_page.dart';
import 'profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BikeApp',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      routes: {
        '/': (context) => const AuthGate(),
        '/dashboard': (context) => const DashboardPage(),
        '/map': (context) => const MapPage(),
        '/rides': (context) => const RidesPage(),
        '/safety': (context) => const SafetyWellnessPage(),
        '/tips': (context) => const TipsPage(),
        '/profile': (context) => const ProfilePage(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const DashboardPage();
        }
        return const AuthPage();
      },
    );
  }
}
