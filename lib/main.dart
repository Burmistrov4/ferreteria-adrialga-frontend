import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'providers/theme_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restaurar la sesión persistida (token JWT) antes de mostrar la app
  await ApiService.loadToken();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    return MaterialApp(
      title: 'Sistema Adrialga',
      debugShowCheckedModeBanner: false,
      // Delegados de localización en español: requeridos por showDateRangePicker,
      // DatePicker, Tooltips y diálogos de Material/Cupertino. Sin ellos la app
      // falla con "No MaterialLocalizations found".
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES'), Locale('es'), Locale('en')],
      locale: const Locale('es', 'ES'),
      theme: themeNotifier.theme,
      home: const LoginScreen(),
    );
  }
}
