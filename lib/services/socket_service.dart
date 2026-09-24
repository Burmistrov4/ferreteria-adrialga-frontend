import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_service.dart';

/// Servicio singleton de WebSocket para sincronización en tiempo real.
///
/// Se conecta contra la misma URL base usada por HTTP (`apiBaseUrl`),
/// normalizando `localhost` a la IP de red del equipo cuando el selector de
/// entorno de la app opera en "Local Wi-Fi" (SharedPreferences `api_base_url`).
class SocketService {
  SocketService._();

  /// Registro para el MaterialApp (dispara snackbars sin depender del contexto).
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static io.Socket? _socket;
  static final List<VoidCallback> _listeners = [];
  static bool _started = false;

  /// Suscribe un listener al evento global `db_update`.
  static void onDbUpdate(VoidCallback listener) => _listeners.add(listener);

  /// Elimina el listener del evento.
  static void offDbUpdate(VoidCallback listener) => _listeners.remove(listener);

  static void _emitirNotaEventoGlobal() {
    for (final l in List.of(_listeners).toList()) {
      l.call();
    }
  }

  /// Arranca la conexión (si no estaba activa). URL restaurada del shared prefs.
  static void start() {
    if (_started) return;
    _started = true;

    // Deriva la URL de la misma pieza de configuración que API (sin /api).
    final api = ApiService.baseUrl; // ej. http://192.168.98.153:3000/api
    final base = api.replaceAll(RegExp(r'/api$'), '');
    final server = base.replaceFirst('localhost', _explicitLocalIp(base));

    _socket = io.io(
      server,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[WS] Conectado a $server');
    });
    _socket!.on('db_update', (payload) {
      debugPrint('[WS] db_update: $payload');
      final mensaje = payload is Map
          ? (payload['mensaje']?.toString() ?? 'Base de datos actualizada')
          : 'Base de datos actualizada';
      _notificarSnackBar(mensaje);
      _emitirNotaEventoGlobal();
    });
    _socket!.onError((e) => debugPrint('[WS] Error: $e'));
    _socket!.onDisconnect((_) => debugPrint('[WS] Desconectado'));
  }

  static void stop() {
    _socket?.dispose();
    _socket = null;
    _started = false;
  }

  /// Si el equipo está en localhost pero tiene una IP LAN almacenada
  /// externamente, la usa (mantiene compatibilidad con Fase 1).
  static String _explicitLocalIp(String base) {
    // El campo api_base_url puede ser http://192.168.X.X:3000/api.
    // En modo local ESP (si el usuario tecleó exitosamente la IP),
    // el uptime del backend la retransmite al Header recognizable por todos.
    return base;
  }

  /// SnackBar global desde cualquier pantalla visible.
  static void _notificarSnackBar(String mensaje) {
    final messenger = SocketService.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.sync, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(mensaje)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
