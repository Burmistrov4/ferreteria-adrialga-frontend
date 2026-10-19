import 'package:flutter/material.dart';

import '../screens/dashboard_screen.dart';
import '../widgets/centro_notificaciones.dart';
import '../screens/pos_screen.dart';
import '../screens/facturas_screen.dart';
import '../screens/clientes_screen.dart';
import '../screens/inventario_screen.dart';
import '../screens/entrada_screen.dart';
import '../screens/proveedores_screen.dart';
import '../screens/finanzas_screen.dart';
import '../screens/configuracion_screen.dart';
import '../screens/guia_screen.dart';
import '../screens/login_screen.dart';
import '../screens/monitor_db_screen.dart';
import '../services/api_service.dart';
import '../services/monitor_window.dart';
import '../services/navigation_service.dart';
import '../services/socket_service.dart';

/// Destino de navegación adaptativa del shell principal.
class DestinoNav {
  final IconData icono;
  final IconData? iconoActivo;
  final String etiqueta;
  const DestinoNav({
    required this.icono,
    this.iconoActivo,
    required this.etiqueta,
  });
}

/// Shell de navegación adaptativo (reemplaza el Drawer heredado):
///   - Móvil (<600 dp)          → NavigationBar inferior con accesos clave
///                                y hoja "Más" para el resto de módulos.
///   - Tablet/Desktop (≥600 dp) → NavigationRail lateral (extensible) con
///                                los 10 destinos completos y cierre de sesión.
///
/// El contenido vive en un IndexedStack: al cambiar de pestaña el estado
/// de cada módulo se conserva (transiciones de estado fluidas).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _indice = 0;

  /// Instancias perezosas de los 10 módulos. Antes se construían las 9
  /// pantallas en el primer frame del IndexedStack, lo que disparaba ~9
  /// ráfagas de API al iniciar sesión (arranque lento). Ahora cada módulo se
  /// crea la primera vez que se visita; a partir de ahí se conserva en la
  /// caché para no perder su estado al navegar.
  final List<Widget?> _modulos = List<Widget?>.filled(10, null);

  Widget _modulo(int i) {
    return _modulos[i] ??= switch (i) {
      0 => DashboardScreen(onNavegarModulo: _seleccionar),
      1 => const PosScreen(),
      2 => const FacturasScreen(),
      3 => const ClientesScreen(),
      4 => const InventarioScreen(),
      5 => const EntradasScreen(),
      6 => const ProveedoresScreen(),
      7 => const FinanzasScreen(),
      8 => const ConfiguracionScreen(),
      _ => GuiaScreen(onNavegarModulo: _seleccionar),
    };
  }

  static const List<DestinoNav> _destinos = [
    DestinoNav(
      icono: Icons.home_outlined,
      iconoActivo: Icons.home,
      etiqueta: 'Inicio',
    ),
    DestinoNav(
      icono: Icons.point_of_sale_outlined,
      iconoActivo: Icons.point_of_sale,
      etiqueta: 'Vender',
    ),
    DestinoNav(
      icono: Icons.receipt_long_outlined,
      iconoActivo: Icons.receipt_long,
      etiqueta: 'Facturas',
    ),
    DestinoNav(
      icono: Icons.people_outline,
      iconoActivo: Icons.people,
      etiqueta: 'Clientes',
    ),
    DestinoNav(
      icono: Icons.inventory_2_outlined,
      iconoActivo: Icons.inventory_2,
      etiqueta: 'Productos',
    ),
    DestinoNav(
      icono: Icons.add_shopping_cart_outlined,
      iconoActivo: Icons.add_shopping_cart,
      etiqueta: 'Compras',
    ),
    DestinoNav(
      icono: Icons.local_shipping_outlined,
      iconoActivo: Icons.local_shipping,
      etiqueta: 'Proveedores',
    ),
    DestinoNav(
      icono: Icons.account_balance_wallet_outlined,
      iconoActivo: Icons.account_balance_wallet,
      // Etiqueta corta: en la barra inferior de 360 px "Caja y Finanzas" se
      // partía en dos líneas y desalineaba el resto de destinos.
      etiqueta: 'Caja',
    ),
    DestinoNav(
      icono: Icons.settings_outlined,
      iconoActivo: Icons.settings,
      etiqueta: 'Ajustes',
    ),
    DestinoNav(
      icono: Icons.menu_book_outlined,
      iconoActivo: Icons.menu_book,
      etiqueta: 'Guía',
    ),
  ];

  /// Destinos visibles directos en la barra inferior móvil (resto → "Más").
  static const List<int> _movilDirectos = [0, 1, 4, 5, 7];

  @override
  void initState() {
    super.initState();
    // Sincronización LAN: después de iniciar sesión, se activa el canal WebSocket y
    // cada pantalla interesada se suscribe a `db_update` para refrescarse.
    SocketService.start();
    // Las pestañas sin historial (p.ej. Facturas abierta como pestaña base)
    // usan este canal para retroceder a Inicio desde su botón Atrás.
    NavigationService.irAInicio = () => _seleccionar(0);
    // Solo el Dashboard se construye de entrada; el resto nace al visitarse.
    _modulo(0);
  }

  @override
  void dispose() {
    NavigationService.irAInicio = null;
    super.dispose();
  }

  void _seleccionar(int i) {
    if (!mounted) return;
    _modulo(i); // instancia perezosa: solo se crea al visitarse por 1ª vez
    setState(() => _indice = i);
  }

  /// Abre el Monitor de Base de Datos. Ofrece dos formas para que el usuario
  /// elija según lo que necesite en la demostración:
  ///   · dentro de la app (ruta normal);
  ///   · en otra pestaña/ventana del navegador (web), para poder poner el
  ///     Monitor al lado de la aplicación y mostrar la actividad en vivo.
  void _abrirMonitorDb() {
    if (!monitorWindowDisponible) {
      _abrirMonitorDbEnApp();
      return;
    }
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.storage, color: cs.primary),
                  const SizedBox(width: 10),
                  const Text(
                    'Monitor de Base de Datos',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.open_in_full, color: cs.primary),
              title: const Text('Ver dentro de la app'),
              subtitle: const Text('Se abre como pantalla normal'),
              onTap: () {
                Navigator.pop(ctx);
                _abrirMonitorDbEnApp();
              },
            ),
            ListTile(
              leading: Icon(Icons.open_in_new, color: cs.primary),
              title: const Text('Abrir en otra pestaña / ventana'),
              subtitle: const Text(
                'Ábrala aparte y colóquela al lado del sistema para mostrar la '
                'actividad en vivo',
              ),
              onTap: () {
                Navigator.pop(ctx);
                final url = Uri.base
                    .replace(fragment: 'monitor', queryParameters: const {})
                    .toString();
                final ok = abrirMonitorWindow(url);
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'El navegador bloqueó la ventana emergente. Permita las '
                        'ventanas emergentes para este sitio e inténtelo de nuevo.',
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _abrirMonitorDbEnApp() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MonitorDbScreen(modoInicial: 'presentacion'),
      ),
    );
  }

  void _cerrarSesion() {    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que deseas salir del sistema?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    ).then((confirmado) {
      if (confirmado != true || !mounted) return;
      SocketService.stop();
      ApiService.logout();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  /// Hoja "Más módulos" para móvil: lista los módulos no fijados en la barra.
  void _mostrarMas(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Text(
                    'Todos los módulos',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                for (int i = 0; i < _destinos.length; i++)
                  ListTile(
                    leading: Icon(
                      _destinos[i].icono,
                      color: colorScheme.primary,
                    ),
                    title: Text(_destinos[i].etiqueta),
                    selected: _indice == i,
                    selectedTileColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.35,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _seleccionar(i);
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.logout, color: colorScheme.error),
                  title: Text(
                    'Cerrar sesión',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _cerrarSesion();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Barra global superior para móvil: muestra la marca y la campana de
  /// notificaciones de forma persistente (una sola instancia para los 10 módulos).
  /// Se implementa como Container (no Material AppBar) para no apilarse con el
  /// AppBar propio de cada módulo.
  Widget _barraGlobal(ColorScheme colorScheme) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary,
              child: Icon(
                Icons.storefront,
                color: colorScheme.onPrimary,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Adrialga',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Opacity(
              opacity: 0.6,
              child: IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.storage),
                tooltip: 'Monitor de BD',
                onPressed: _abrirMonitorDb,
              ),
            ),
            const CentroNotificaciones(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final contenido = IndexedStack(
      index: _indice,
      // Solo se instancia el módulo visitado; el resto son marcadores de
      // posición sin estado ni trabajo de build (arranque perezoso).
      children: [
        for (var i = 0; i < _modulos.length; i++)
          _modulos[i] ?? const SizedBox.shrink(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 600;

        if (!esMovil) {
          // ── Tablet / Desktop: NavigationRail lateral ──────────────────
          final extendido = constraints.maxWidth >= 1200;
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _indice,
                    extended: extendido,
                    minExtendedWidth: 170,
                    labelType: extendido
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.selected,
                    onDestinationSelected: _seleccionar,
                    leading: Column(
                      children: [
                        const SizedBox(height: 12),
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.primary,
                          child: Icon(
                            Icons.storefront,
                            color: colorScheme.onPrimary,
                            size: 24,
                          ),
                        ),
                        if (extendido) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Adrialga',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                    trailing: Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Acceso discreto al Monitor de Base de Datos (ventana
                          // independiente con el esquema en vivo).
                          Opacity(
                            opacity: 0.6,
                            child: IconButton(
                              icon: const Icon(Icons.storage),
                              tooltip: 'Monitor de BD',
                              onPressed: _abrirMonitorDb,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Centro de Notificaciones persistente: se monta una
                          // sola vez en el shell y acompaña a los 10 módulos sin
                          // duplicarse ni recrearse al cambiar de pestaña.
                          const CentroNotificaciones(),
                          const SizedBox(height: 4),
                          IconButton(
                            icon: Icon(Icons.logout, color: colorScheme.error),
                            onPressed: _cerrarSesion,
                            tooltip: 'Cerrar sesión',
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    destinations: _destinos
                        .map(
                          (d) => NavigationRailDestination(
                            icon: Icon(d.icono),
                            selectedIcon: Icon(d.iconoActivo ?? d.icono),
                            label: Text(d.etiqueta),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: contenido),
              ],
            ),
          );
        }

        // ── Móvil: NavigationBar inferior ─────────────────────────────────
        final posicionDirecta = _movilDirectos.indexOf(_indice);
        return Scaffold(
          body: Column(
            children: [
              // Barra global persistente (es un Container, NO un Material AppBar,
              // así no se apila con el AppBar de cada módulo → evita doble-AppBar).
              // Alberga la campana para los 10 módulos en móvil.
              _barraGlobal(colorScheme),
              Expanded(child: contenido),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: posicionDirecta >= 0 ? posicionDirecta : 0,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) {
              if (i < _movilDirectos.length) {
                _seleccionar(_movilDirectos[i]);
              } else {
                _mostrarMas(context);
              }
            },
            destinations: [
              for (final i in _movilDirectos)
                NavigationDestination(
                  icon: Icon(_destinos[i].icono),
                  selectedIcon: Icon(
                    _destinos[i].iconoActivo ?? _destinos[i].icono,
                  ),
                  label: _destinos[i].etiqueta,
                ),
              const NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'Más',
              ),
            ],
          ),
        );
      },
    );
  }
}
