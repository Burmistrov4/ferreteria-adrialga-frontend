import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_service.dart';
import 'socket_url.dart';

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
  static final List<void Function(String modulo)> _listenersModulo = [];
  static final List<void Function(Map<String, dynamic> evento)>
      _listenersEvento = [];
  static bool _started = false;

  /// Suscribe un listener al evento global `db_update` (sin distinguir módulo).
  static void onDbUpdate(VoidCallback listener) => _listeners.add(listener);

  /// Elimina el listener del evento.
  static void offDbUpdate(VoidCallback listener) => _listeners.remove(listener);

  /// Suscribe un listener que recibe el evento COMPLETO (modulo, mensaje,
  /// timestamp y extras). Usado por el Monitor de Base de Datos para su
  /// registro en vivo.
  static void onDbUpdateEvento(
          void Function(Map<String, dynamic> evento) listener) =>
      _listenersEvento.add(listener);

  /// Elimina el listener de evento completo.
  static void offDbUpdateEvento(
          void Function(Map<String, dynamic> evento) listener) =>
      _listenersEvento.remove(listener);

  /// Suscribe un listener que recibe el MÓDULO afectado ('caja', 'proveedores',
  /// 'facturas', ...). Permite refrescar SOLO lo relevante en vez de reaccionar
  /// a cualquier cambio de la base de datos (p. ej. recargar la lista de
  /// proveedores únicamente cuando alguien los crea/edita/borra).
  static void onDbUpdateModulo(void Function(String modulo) listener) =>
      _listenersModulo.add(listener);

  /// Elimina el listener por módulo.
  static void offDbUpdateModulo(void Function(String modulo) listener) =>
      _listenersModulo.remove(listener);

  static void _emitirNotaEventoGlobal([String modulo = '']) {
    for (final l in List.of(_listeners)) {
      l.call();
    }
    for (final l in List.of(_listenersModulo)) {
      l.call(modulo);
    }
  }

  /// Arranca la conexión (si no estaba activa). URL restaurada del shared prefs.
  static void start() {
    if (_started) return;
    _started = true;

    // Deriva la URL de la misma pieza de configuración que API (sin /api).
    // OJO (regresión): antes se hacía replaceFirst('localhost', _explicitLocalIp(...))
    // con la URL completa → URL malformada (http://http://localhost:3000:3000).
    // `normalizarUrlSocket` solo quita el sufijo /api; el host ya lo resuelve
    // ApiService.baseUrl.
    final server = normalizarUrlSocket(ApiService.baseUrl);

    final token = ApiService.socketToken;
    if (token == null || token.isEmpty) {
      _started = false;
      debugPrint('[WS] No se inicia Socket.IO sin una sesión autenticada');
      return;
    }

    _socket = io.io(
      server,
      io.OptionBuilder()
          .setAuth({'token': token})
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[WS] Conectado a $server');
    });
    _socket!.on('db_update', (payload) {
      debugPrint('[WS] db_update: $payload');
      final map = payload is Map
          ? Map<String, dynamic>.from(payload.cast<String, dynamic>())
          : <String, dynamic>{};
      final modulo = map['modulo']?.toString() ?? '';
      final mensaje =
          map['mensaje']?.toString() ?? 'Base de datos actualizada';
      _notificarSnackBar(mensaje);
      _emitirNotaEventoGlobal(modulo);
      for (final l in List.of(_listenersEvento)) {
        l.call(map);
      }
    });
    _socket!.onReconnect((_) {
      debugPrint('[WS] Conexión LAN restablecida');
      _notificarSnackBar('Conexión LAN restablecida. Sincronizando datos...');
      _emitirNotaEventoGlobal('__reconexion__');
    });
    _socket!.onError((e) => debugPrint('[WS] Error: $e'));
    _socket!.onDisconnect((_) => debugPrint('[WS] Desconectado'));
  }

  static void stop() {
    _socket?.dispose();
    _socket = null;
    _started = false;
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
        // 5 s: el aviso de sincronización LAN debe alcanzar a leerse antes de
        // desaparecer (antes 2 s). El refresh de datos ya ocurre en background.
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
