import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'screens/monitor_db_screen.dart';
import 'services/api_service.dart';
import 'services/session_guard.dart';
import 'services/shortcut_service.dart';
import 'services/socket_service.dart';
import 'providers/theme_notifier.dart';

/// ¿La URL pidió el Monitor de Base de Datos como vista suelta?
///
/// Se acepta el fragmento `#monitor` (estrategia de rutas por hash, la que usa
/// Flutter Web por defecto) y también `?vista=monitor` por comodidad. Con esto
/// el Monitor puede abrirse en su propia pestaña del navegador —y arrastrarse
/// fuera como ventana— para dejarlo al lado de la aplicación en la exposición.
bool _vistaMonitorSolicitada() {
  try {
    final fragmento = Uri.base.fragment.toLowerCase();
    if (fragmento == 'monitor' || fragmento.startsWith('monitor')) return true;
    final vista = Uri.base.queryParameters['vista']?.toLowerCase();
    return vista == 'monitor';
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restaurar la sesión persistida (token JWT) antes de mostrar la app
  await ApiService.loadToken();
  // Selección de entorno persistida (selector del login: Local Wi-Fi / manual).
  await ApiService.loadBaseUrlRuntime();
  // Guardia global JWT: ante 401 (TOKEN_EXPIRADO) respalda el carrito del
  // POS y redirige al login con mensaje claro.
  ApiService.onSesionExpirada = SessionGuard.manejarSesionExpirada;
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
      scaffoldMessengerKey: SocketService.messengerKey, // global notifications (WebSocket LAN)
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
      // Vista suelta del Monitor (#monitor): solo si ya hay sesión, porque el
      // esquema se lee con JWT. Sin sesión se muestra el login y, una vez
      // autenticado, el Monitor se abre con el botón «Abrir en otra pestaña».
      home: (_vistaMonitorSolicitada() && ApiService.isLoggedIn)
          ? const MonitorDbScreen(independiente: true)
          : const LoginScreen(),
    );
  }
}
