import 'package:flutter/material.dart';

import '../screens/dashboard_screen.dart';
import '../screens/pos_screen.dart';
import '../screens/facturas_screen.dart';
import '../screens/clientes_screen.dart';
import '../screens/inventario_screen.dart';
import '../screens/entrada_screen.dart';
import '../screens/proveedores_screen.dart';
import '../screens/finanzas_screen.dart';
import '../screens/configuracion_screen.dart';
import '../screens/login_screen.dart';
import '../services/api_service.dart';

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
///                                los 9 destinos completos y cierre de sesión.
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

  static const List<DestinoNav> _destinos = [
    DestinoNav(
        icono: Icons.home_outlined,
        iconoActivo: Icons.home,
        etiqueta: 'Inicio'),
    DestinoNav(
        icono: Icons.point_of_sale_outlined,
        iconoActivo: Icons.point_of_sale,
        etiqueta: 'Vender'),
    DestinoNav(
        icono: Icons.receipt_long_outlined,
        iconoActivo: Icons.receipt_long,
        etiqueta: 'Facturas'),
    DestinoNav(
        icono: Icons.people_outline,
        iconoActivo: Icons.people,
        etiqueta: 'Clientes'),
    DestinoNav(
        icono: Icons.inventory_2_outlined,
        iconoActivo: Icons.inventory_2,
        etiqueta: 'Productos'),
    DestinoNav(
        icono: Icons.add_shopping_cart_outlined,
        iconoActivo: Icons.add_shopping_cart,
        etiqueta: 'Compras'),
    DestinoNav(
        icono: Icons.local_shipping_outlined,
        iconoActivo: Icons.local_shipping,
        etiqueta: 'Proveedores'),
    DestinoNav(
        icono: Icons.account_balance_wallet_outlined,
        iconoActivo: Icons.account_balance_wallet,
        etiqueta: 'Caja y Finanzas'),
    DestinoNav(
        icono: Icons.settings_outlined,
        iconoActivo: Icons.settings,
        etiqueta: 'Ajustes'),
  ];

  /// Destinos visibles directos en la barra inferior móvil (resto → "Más").
  static const List<int> _movilDirectos = [0, 1, 4, 5, 7];

  void _seleccionar(int i) {
    if (!mounted) return;
    setState(() => _indice = i);
  }

  void _cerrarSesion() {
    showDialog<bool>(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                    leading: Icon(_destinos[i].icono, color: colorScheme.primary),
                    title: Text(_destinos[i].etiqueta),
                    selected: _indice == i,
                    selectedTileColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.35),
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final contenido = IndexedStack(
      index: _indice,
      children: [
        DashboardScreen(onNavegarModulo: _seleccionar),
        PosScreen(),
        FacturasScreen(),
        ClientesScreen(),
        InventarioScreen(),
        EntradasScreen(),
        ProveedoresScreen(),
        FinanzasScreen(),
        ConfiguracionScreen(),
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
                          : NavigationRailLabelType.all,
                      onDestinationSelected: _seleccionar,
                      leading: Column(
                        children: [
                          const SizedBox(height: 12),
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: colorScheme.primary,
                            child: Icon(Icons.storefront,
                                color: colorScheme.onPrimary, size: 24),
                          ),
                          if (extendido) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Adrialga',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],
                      ),
                      trailing: Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(Icons.logout,
                                  color: colorScheme.error),
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
          body: contenido,
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
                  selectedIcon: Icon(_destinos[i].iconoActivo ?? _destinos[i].icono),
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
