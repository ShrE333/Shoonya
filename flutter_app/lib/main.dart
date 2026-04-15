import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/kyc_verification_screen.dart';
import 'screens/apply_loan_screen.dart';
import 'screens/chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://taouioyptfryozornfgh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRhb3Vpb3lwdGZyeW96b3JuZmdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxNjY2OTEsImV4cCI6MjA5MTc0MjY5MX0.2mDcchzVjhiQF0x7XZCQgBX9wItLK8dM0FDNi8rH4gs',
  );

  runApp(const MyApp());
}

// Shell Screen to provide persistent navigation
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Determine current index based on location
    final location = GoRouterState.of(context).uri.path;
    int index = 0;
    if (location.startsWith('/dashboard')) index = 0;
    else if (location.startsWith('/kyc')) index = 1;
    else if (location.startsWith('/documents')) index = 2; // Dummy
    else if (location.startsWith('/profile')) index = 3;   // Dummy

    final isKyc = location.contains('/kyc/');

    return Scaffold(
      body: child,
      bottomNavigationBar: isKyc ? null : BottomNavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: Colors.white30,
        currentIndex: index,
        onTap: (i) {
          if (i == 0) context.go('/dashboard');
          if (i == 1) context.go('/kyc/demo'); // Demo link if not coming from deep link
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.verified_user), label: 'Verification'),
          BottomNavigationBarItem(icon: Icon(Icons.description_outlined), label: 'Documents'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupScreen(),
    ),
    // Auth-protected shell
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/apply',
          builder: (context, state) => const ApplyLoanScreen(),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) => const ChatScreen(),
        ),
        GoRoute(
          path: '/kyc/:token',
          builder: (context, state) {
            final token = state.pathParameters['token']!;
            return KYCVerificationScreen(token: token);
          },
        ),
      ],
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shoonya App',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
