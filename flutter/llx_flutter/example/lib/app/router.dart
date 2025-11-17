import 'package:flutter/material.dart';
import '../features/chat/chat_page.dart';

class AppRouter {
  static const String initialRoute = '/chat';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/chat':
        return MaterialPageRoute(builder: (_) => const ChatPage());
      default:
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Unknown route'))),
        );
    }
  }
}
