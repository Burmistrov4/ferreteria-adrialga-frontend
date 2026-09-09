import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/shortcut_service.dart';
import 'providers/theme_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restaurar la sesión persistida (token JWT) antes de mostrar la app
  await ApiService.loadToken();
  // Restaurar la preferencia de tema (claro/oscuro/sistema) antes del primer frame
  final themeNotifier = await ThemeNotifier.create();
  runApp(
    ChangeNotifierProvider.value(
      value: themeNotifier,
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
      // Navegador y observer para la ayuda contextual global (F1) y atajos.
      navigatorKey: ShortcutService.navigatorKey,
      navigatorObservers: [ShortcutService.observer],
      // Atajo global F1: ayuda contextual acorde al módulo activo.
      builder: (context, child) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.f1): AyudaContextualIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            AyudaContextualIntent: CallbackAction<AyudaContextualIntent>(
              onInvoke: (_) {
                ShortcutService.mostrarAyudaContextual();
                return null;
              },
            ),
          },
          // El `child` del builder puede ser null en transiciones de arranque.
          child: child ?? const SizedBox.shrink(),
        ),
      ),
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
