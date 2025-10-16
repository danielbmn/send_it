import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/messages_home_screen.dart';
import 'utils/logger.dart';

void main() {
  // Minimal initialization - no async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Comprehensive error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    Logger.error('Flutter Error: ${details.exception}');
    Logger.error('Stack trace: ${details.stack}');
    // Don't rethrow - just log and continue
  };

  // Handle platform errors
  ServicesBinding.instance.platformDispatcher.onError = (error, stack) {
    Logger.error('Platform Error: $error');
    Logger.error('Stack trace: $stack');
    return true; // Mark as handled
  };

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sendit',
      theme: ThemeData(
        primaryColor: Color(0xFF007AFF),
        scaffoldBackgroundColor: Color(0xFFF2F2F7),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFF9F9F9),
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: MessagesHomeScreen(),
    );
  }
}
