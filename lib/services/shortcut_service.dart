import 'package:flutter/material.dart';

import '../widgets/walkthrough_overlay.dart';

/// Intención concreta para la ayuda contextual global (F1).
/// `Intent` es abstracto en Flutter; usar una subclase evita instanciarlo.
class AyudaContextualIntent extends Intent {
  const AyudaContextualIntent();
}

/// Servicio global de atajos de teclado y ayuda contextual (F1).
///
/// Centraliza el estado del módulo activo (vía [setModule] desde cada pantalla y
/// un [ModuleNavigatorObserver] que rastrea la ruta) y construye la guía
/// interactiva específica por pantalla usando [WalkthroughOverlay].
class ShortcutService {
  ShortcutService._();

  /// Navegador raíz para insertar el overlay de ayuda por encima de todo.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Observer que registra la ruta activa (nombre de `RouteSettings`).
  static final ModuleNavigatorObserver observer = ModuleNavigatorObserver();

  /// Módulo activo establecido por cada pantalla (fuente de verdad para F1).
  static String? _module;
  static String? get module => _module;

  static void setModule(String? m) => _module = m;

  /// Nombre de la última ruta observada (diagnóstico / F1).
  static String? _routeName;
  static String? get routeName => _routeName;

  static void _setRouteName(String? n) => _routeName = n;

  /// Construye los pasos de ayuda contextual para el módulo indicado.
  static List<WalkthroughStep> _pasosPara(String? mod) {
    switch (mod) {
      case 'pos':
        return const [
          WalkthroughStep(
            titulo: 'POS — Atajos de teclado',
            descripcion:
                'F2: enfoca el buscador/escáner. F3: edita la cantidad del ítem '
                'activo en el carrito. F12: abre el cobro. Operación sin ratón.',
            icono: Icons.keyboard,
          ),
          WalkthroughStep(
            titulo: 'F2 · Buscador',
            descripcion:
                'Presiona F2 para enfocar el campo de búsqueda por Nombre o SKU '
                'y digitar el código para encontrar el producto al instante.',
            icono: Icons.search,
          ),
          WalkthroughStep(
            titulo: 'F3 · Cantidad del ítem',
            descripcion:
                'Con un ítem activo (toca la tarjeta del carrito), F3 enfoca su '
                'cantidad para ajustarla sin usar el mouse. Se respeta el stock.',
            icono: Icons.pin,
          ),
          WalkthroughStep(
            titulo: 'F12 · Cobro',
            descripcion:
                'F12 abre el diálogo de cobro bimoneda (IVA + IGTF, vuelto en USD '
                'y Bs a Tasa BCV). Confirma y factura al instante.',
            icono: Icons.point_of_sale,
          ),
        ];
      case 'finanzas':
      case 'caja':
        return const [
          WalkthroughStep(
            titulo: 'Finanzas & Caja',
            descripcion:
                'Gestiona turnos de caja (apertura/arqueo), patrimonio, cuentas por '
                'pagar y reportes fiscales SENIAT.',
            icono: Icons.account_balance,
          ),
          WalkthroughStep(
            titulo: 'Apertura y Arqueo de Caja',
            descripcion:
                'Abre el turno con fondo base > \$0 y confirma la Tasa BCV. Al '
                'cerrar, cuadra el efectivo entregado contra el esperado (±1 USD).',
            icono: Icons.lock_open,
          ),
          WalkthroughStep(
            titulo: 'Exportables SENIAT',
            descripcion:
                'Tab "IVA/SENIAT": descarga Libro de Ventas/Compras en Bs (punto y '
                'coma) y el Resumen de IVA para la declaración.',
            icono: Icons.savings,
          ),
        ];
      case 'inventario':
        return const [
          WalkthroughStep(
            titulo: 'Inventario',
            descripcion:
                'Maestro de productos con SKU autogenerado, stock mínimo y '
                'categorías. Usa el buscador para filtrar.',
            icono: Icons.inventory_2,
          ),
          WalkthroughStep(
            titulo: 'Registrar producto',
            descripcion:
                'Botón "Nuevo Producto": nombre, precio, stock, categoría. El SKU '
                'se autogenera si no se indica código de fábrica.',
            icono: Icons.add_business,
          ),
        ];
      case 'dashboard':
      default:
        return const [
          WalkthroughStep(
            titulo: 'Dashboard',
            descripcion:
                'Métricas del negocio, serie de ventas, rentabilidad real y '
                'alertas de stock. Los paneles de alerta son accionables.',
            icono: Icons.space_dashboard,
          ),
          WalkthroughStep(
            titulo: 'Banners accionables',
            descripcion:
                'Toca una alerta de "Bajo Stock" para ir a Entradas con el '
                'producto pre-cargado y reabastecer sin buscar.',
            icono: Icons.notification_important,
          ),
        ];
    }
  }

  /// Dispara la ayuda contextual (F1) del módulo activo sobre toda la app.
  static void mostrarAyudaContextual() {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    WalkthroughOverlay.mostrarEnOverlay(
      overlay,
      pasos: _pasosPara(_module),
      onCompletado: () {},
      onOmitido: () {},
    );
  }
}

/// Rastrea la ruta activa y alimenta a [ShortcutService] con el nombre de la
/// última ruta (según `RouteSettings.name`, si la ruta la define).
class ModuleNavigatorObserver extends NavigatorObserver {
  static const Map<String, String> _nombresRutaModulo = {
    '/pos': 'pos',
    '/finanzas': 'finanzas',
    '/caja': 'caja',
    '/inventario': 'inventario',
    '/entradas': 'entradas',
    '/dashboard': 'dashboard',
  };

  void _marca(Route r) {
    final nombre = r.settings.name;
    if (nombre != null) {
      ShortcutService._setRouteName(nombre);
      final mod = _nombresRutaModulo[nombre];
      if (mod != null) ShortcutService.setModule(mod);
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _marca(route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _marca(previousRoute);
  }
}