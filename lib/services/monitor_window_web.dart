import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web: el Monitor puede abrirse en una pestaña nueva (`_blank`) que el usuario
/// puede arrastrar fuera del navegador para dejarla como ventana propia al lado
/// de la aplicación. La URL lleva el fragmento `#monitor`, que `main.dart`
/// reconoce para arrancar directamente en el Monitor sin pasar por el login.
bool get monitorWindowDisponible => true;

/// Abre [url] en una pestaña nueva. Devuelve `true` si el navegador la aceptó.
bool abrirMonitorWindow(String url) {
  try {
    final w = web.window.open(url, '_blank', '');
    return w != null;
  } catch (_) {
    return false;
  }
}
