import 'package:flutter/material.dart';

/// Canal de navegación del AppShell: permite a las pantallas embebidas en
/// pestañas (Facturas, Inventario, etc.) retroceder a "Inicio" cuando NO
/// hay historial que poppear (callejón de navegación dentro del shell).
/// AppShell registra el callback al montarse y lo limpia al desmontarse.
class NavigationService {
  NavigationService._();

  static void Function()? irAInicio;

  /// Botón/acción "Atrás" inteligente: si el stack tiene historial, pop;
  /// si la pantalla es una pestaña fija del shell, vuelve a la pestaña
  /// Inicio. Devuelve true si alguna acción se ejecutó siempre.
  static bool volverAtras(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      irAInicio?.call();
    }
    return true;
  }
}
