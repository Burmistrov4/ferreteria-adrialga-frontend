import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Helper uniforme para manejo de errores de red/API en toda la app.
/// Muestra un SnackBar con mensaje accionable y opción de reintento.
class ManejoErrores {
  /// Ejecuta una petición asíncrona y maneja errores de red, timeout y servidor.
  /// Retorna el resultado o null si falló (el error ya se mostró en SnackBar).
  static Future<T?> ejecutar<T>({
    required BuildContext context,
    required Future<T> Function() operacion,
    String? mensajeExito,
    bool mostrarExito = false,
  }) async {
    try {
      final resultado = await operacion();
      if (mostrarExito && mensajeExito != null && context.mounted) {
        _mostrarSnackBar(context, mensajeExito, _tono(context, _Tono.exito));
      }
      return resultado;
    } on http.ClientException {
      if (context.mounted) {
        _mostrarSnackBar(
          context,
          'Sin conexión al servidor. Verifica tu red.',
          _tono(context, _Tono.alerta),
        );
      }
      return null;
    } on TimeoutException {
      if (context.mounted) {
        _mostrarSnackBar(
          context,
          'La operación tardó mucho. Reintentando...',
          _tono(context, _Tono.alerta),
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        final mensaje = _extraerMensaje(e);
        _mostrarSnackBar(context, mensaje, _tono(context, _Tono.error));
      }
      return null;
    }
  }

  /// Tonos semánticos derivados del tema activo (contraste garantizado en
  /// modo claro y oscuro, sin colores fijos que desaparecen en dark mode).
  static Color _tono(BuildContext context, _Tono tono) {
    final cs = Theme.of(context).colorScheme;
    switch (tono) {
      case _Tono.exito:
        return cs.tertiary;
      case _Tono.alerta:
        return cs.secondary;
      case _Tono.error:
        return cs.error;
    }
  }

  /// Muestra un SnackBar con estilo uniforme.
  static void _mostrarSnackBar(
    BuildContext context,
    String mensaje,
    Color color,
  ) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje, style: const TextStyle(fontSize: 14)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        showCloseIcon: true,
      ),
    );
  }

  /// Extrae un mensaje legible de excepciones del backend.
  static String _extraerMensaje(Object e) {
    final raw = e.toString();
    // Buscar patrones comunes de error del backend
    if (raw.contains('ARQUEO_PENDIENTE')) {
      return 'Arqueo pendiente: hay un turno de un día anterior sin '
          'cerrar. Realice el arqueo Z de esa jornada en el módulo de Caja '
          'antes de vender.';
    }
    if (raw.contains('CAJA_CERRADA')) {
      return 'Caja cerrada. Abre caja para continuar.';
    }
    if (raw.contains('SALDO_INSUFICIENTE')) {
      return 'Saldo insuficiente en caja para la devolución. Solicite un '
          'Ingreso de Caja al supervisor.';
    }
    if (raw.contains('409') || raw.contains('Conflict')) {
      return 'Conflicto: el registro ya existe o hay duplicidad.';
    }
    if (raw.contains('401') || raw.contains('Unauthorized')) {
      return 'Sesión expirada. Inicia sesión nuevamente.';
    }
    if (raw.contains('404') || raw.contains('Not Found')) {
      return 'Recurso no encontrado.';
    }
    if (raw.contains('500') || raw.contains('Internal')) {
      return 'Error interno del servidor. Intenta más tarde.';
    }
    // Limpiar prefijos de excepción
    return raw.replaceFirst('Exception: ', '').replaceFirst('Error: ', '');
  }
}

/// Tonos semánticos soportados por [_tono].
enum _Tono { exito, alerta, error }
