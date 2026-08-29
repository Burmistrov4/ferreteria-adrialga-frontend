import 'package:flutter/material.dart';

import 'pos_screen.dart';
import 'inventario_screen.dart';
import 'categorias_screen.dart';
import 'clientes_screen.dart';
import 'proveedores_screen.dart';
import 'entrada_screen.dart';
import 'facturas_screen.dart';
import 'login_screen.dart';
import '../services/api_service.dart';

String _num(dynamic v) {
  if (v == null) return '0';
  return v.toString();
}

String _moneda(dynamic v) {
  final n = v == null ? 0 : double.tryParse(v.toString()) ?? 0;
  return n.toStringAsFixed(2);
}

class _ModuloItem {
  final String titulo;
  final IconData icon;
  final Color color;
  final Widget pantalla;

  const _ModuloItem(this.titulo, this.icon, this.color, this.pantalla);
}

class _MetricaCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final String valor;
  final String descripcion;
  final VoidCallback? onTap;

  const _MetricaCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.valor,
    this.descripcion = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _metricas;
  bool _isLoading = true;
  String? _error;
  double _tasaCambio = 36.50;
  bool _tasaEsBCV = false;

  @override
  void initState() {
    super.initState();
    _cargarMetricas();
    _cargarTasa();
  }

  Future<void> _cargarTasa() async {
    final tasa = await ApiService.getTasaCambio();
    if (mounted) {
      setState(() {
        _tasaCambio = tasa;
        _tasaEsBCV = ApiService.lastTasaEsBCV;
      });
    }
  }

  Future<void> _cargarMetricas() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getDashboard();
      if (mounted) {
        setState(() {
          _metricas = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _navegar(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    // Al regresar de un módulo se recargan las métricas para reflejar cambios.
    _cargarMetricas();
  }

  void _cerrarSesion() {
    ApiService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Principal - Adrialga'),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _tasaEsBCV ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _tasaEsBCV
                        ? 'Tasa BCV: ${_tasaCambio.toStringAsFixed(2)} Bs/usd'
                        : 'Tasa BCV: Sin conexión',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _tasaEsBCV
                          ? Colors.blue.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  if (!_tasaEsBCV)
                    const Text(
                      'Usando respaldo',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _cargarMetricas();
              _cargarTasa();
            },
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: RefreshIndicator(
        onRefresh: _cargarMetricas,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEncabezado(),
              const SizedBox(height: 20),
              _buildMetricas(),
              const SizedBox(height: 28),
              const Text(
                'Módulos del Sistema',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildSubmenu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.storefront, color: Colors.white, size: 34),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Ferretería Adrialga C.A.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Sistema de gestión de ventas e inventario',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricas() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No se pudieron cargar las métricas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _cargarMetricas,
                    child: const Text(
                      'Reintentar',
                      style: TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final resumen = (_metricas?['resumen'] as Map<String, dynamic>?) ?? {};
    final alertas = (_metricas?['alertas'] as Map<String, dynamic>?) ?? {};
    final conteoStockBajo = alertas['conteoStockBajo'] ?? 0;

    final metricas = <Widget>[
      _MetricaCard(
        icon: Icons.inventory_2,
        color: Colors.blue,
        titulo: 'Productos',
        valor: _num(resumen['totalProductos']),
        descripcion:
            'Artículos activos en el catálogo. Toque para ver inventario.',
        onTap: () => _navegar(const InventarioScreen()),
      ),
      _MetricaCard(
        icon: Icons.person,
        color: Colors.teal,
        titulo: 'Clientes',
        valor: _num(resumen['totalClientes']),
        descripcion: 'Clientes registrados para facturación.',
        onTap: () => _navegar(const ClientesScreen()),
      ),
      _MetricaCard(
        icon: Icons.local_shipping,
        color: Colors.indigo,
        titulo: 'Proveedores',
        valor: _num(resumen['totalProveedores']),
        descripcion: 'Proveedores activos para compras.',
        onTap: () => _navegar(const ProveedoresScreen()),
      ),
      _MetricaCard(
        icon: Icons.shopping_cart,
        color: Colors.green,
        titulo: 'Ventas (Bs)',
        valor: _moneda(resumen['montoTotalVentas']),
        descripcion: 'Total facturado a la fecha (incluye IVA).',
        onTap: () => _navegar(const FacturasScreen()),
      ),
      _MetricaCard(
        icon: Icons.assignment,
        color: Colors.orange,
        titulo: 'Facturas',
        valor: _num(resumen['totalFacturas']),
        descripcion: 'Nº de ventas (facturas) registradas.',
        onTap: () => _navegar(const FacturasScreen()),
      ),
      _MetricaCard(
        icon: Icons.warning_amber,
        color: Colors.red,
        titulo: 'Stock bajo',
        valor: _num(conteoStockBajo),
        descripcion: 'Productos con stock ≤ mínimo. Reponga en Entradas.',
        onTap: () => _navegar(const EntradasScreen()),
      ),
      _MetricaCard(
        icon: Icons.call_received,
        color: Colors.purple,
        titulo: 'Entradas (Bs)',
        valor: _moneda(resumen['montoTotalEntradas']),
        descripcion: 'Valor de mercancía recibida por compras.',
        onTap: () => _navegar(const EntradasScreen()),
      ),
    ];

    return GridView.count(
      crossAxisCount: _columnasMetricas(),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: metricas,
    );
  }

  int _columnasMetricas() {
    final ancho = MediaQuery.of(context).size.width;
    if (ancho >= 1200) return 4;
    if (ancho >= 800) return 3;
    if (ancho >= 600) return 2;
    return 2;
  }

  Widget _buildSubmenu() {
    final modulos = <_ModuloItem>[
      _ModuloItem(
        'Punto de Venta (POS)',
        Icons.point_of_sale,
        Colors.blueAccent,
        const PosScreen(),
      ),
      _ModuloItem(
        'Inventario / Productos',
        Icons.inventory_2,
        Colors.amber.shade700,
        const InventarioScreen(),
      ),
      _ModuloItem(
        'Clientes',
        Icons.people,
        Colors.teal,
        const ClientesScreen(),
      ),
      _ModuloItem(
        'Proveedores',
        Icons.local_shipping,
        Colors.indigo,
        const ProveedoresScreen(),
      ),
      _ModuloItem(
        'Categorías',
        Icons.category,
        Colors.green,
        const CategoriasScreen(),
      ),
      _ModuloItem(
        'Entradas de Mercancía',
        Icons.add_shopping_cart,
        Colors.purple,
        const EntradasScreen(),
      ),
    ];

    return GridView.count(
      crossAxisCount: _columnasSubmenu(),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: modulos
          .map(
            (m) => Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _navegar(m.pantalla),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(m.icon, size: 30, color: m.color),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        m.titulo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  int _columnasSubmenu() {
    final ancho = MediaQuery.of(context).size.width;
    if (ancho >= 1200) return 4;
    if (ancho >= 800) return 3;
    if (ancho >= 600) return 2;
    return 2;
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blueAccent),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.storefront, color: Colors.white, size: 48),
                SizedBox(height: 8),
                Text(
                  'Adrialga',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('Menú principal', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          _drawerItem(Icons.point_of_sale, 'Punto de Venta', const PosScreen()),
          _drawerItem(
            Icons.inventory_2,
            'Inventario',
            const InventarioScreen(),
          ),
          _drawerItem(Icons.people, 'Clientes', const ClientesScreen()),
          _drawerItem(
            Icons.local_shipping,
            'Proveedores',
            const ProveedoresScreen(),
          ),
          _drawerItem(Icons.category, 'Categorías', const CategoriasScreen()),
          _drawerItem(
            Icons.add_shopping_cart,
            'Entradas de Mercancía',
            const EntradasScreen(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Cerrar sesión',
              style: TextStyle(color: Colors.red),
            ),
            onTap: _cerrarSesion,
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String titulo, Widget pantalla) {
    return ListTile(
      leading: Icon(icon),
      title: Text(titulo),
      onTap: () {
        Navigator.pop(context);
        _navegar(pantalla);
      },
    );
  }
}
