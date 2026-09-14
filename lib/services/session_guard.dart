import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/login_screen.dart';
import 'shortcut_service.dart';

/// Guarda de sesión: intercepción global de expiración del JWT (401
/// TOKEN_EXPIRADO del backend). Al dispararse:
///   1. Persiste el carrito del POS en SharedPreferences (`pos_cart_backup`).
///   2. Redirige al login por el navigatorKey global (sin BuildContext).
///   3. Muestra un mensaje claro en lugar de expulsar sin explicación.
/// Al reingresar al POS se ofrece restaurar el carrito respaldado.
class SessionGuard {
  SessionGuard._();

  static const String _claveCarrito = 'pos_cart_backup';

  /// Snapshot reactivo del carrito del POS (el lo actualiza en cada
  /// mutación; puede estar vacío). Formato: {producto: json, cantidad}.
  static List<Map<String, dynamic>> carritoActual = [];

  /// Invocado por ApiService cuando el backend responde 401 TOKEN_EXPIRADO /
  /// TOKEN_INVALIDO. Idempotente (se regula en ApiService con ventana de 10s).
  static Future<void> manejarSesionExpirada() async {
    // 1) Respaldar el carrito de la sesión saliente (si había ítems).
    if (carritoActual.isNotEmpty) {
      await _respaldar(carritoActual);
    } else {
      await limpiarRespaldoCarrito();
    }
    carritoActual = [];

    // 2) Redirigir al login con mensaje claro, reemplazando todo el stack.
    final nav = ShortcutService.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    final messenger =
        ScaffoldMessenger.maybeOf(ShortcutService.navigatorKey.currentContext!);
    messenger?.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 5),
        content: Text(
          'Tu sesión expiró. El carrito quedó guardado para que no pierdas la venta.',
        ),
      ),
    );
  }

  static Future<void> _respaldar(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveCarrito, jsonEncode(items));
  }

  /// Lee (y deja intacto) el respaldo en disco. Null si no existe o está
  /// corrupto (en ese caso se limpia para no volver a disparar el diálogo).
  static Future<List<Map<String, dynamic>>?> leerRespaldoCarrito() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_claveCarrito);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } catch (_) {
      // Backups corruptos se auto-eliminan.
    }
    await limpiarRespaldoCarrito();
    return null;
  }

  static Future<void> limpiarRespaldoCarrito() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveCarrito);
  }
}
