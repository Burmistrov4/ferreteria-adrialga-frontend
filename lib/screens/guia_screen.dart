import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/walkthrough_overlay.dart';

/// Guía interactiva del usuario (reemplaza el walkthrough documental).
///
/// A diferencia de un .md, esta pantalla ES accionable: cada tarjeta explica
/// un módulo en 2 líneas y permite (a) saltar directo a ese módulo y
/// (b) revivir su tutorial contextual paso a paso. Además incluye un recorrido
/// rápido "primer día" ordenado según el rol del usuario autenticado.
class GuiaScreen extends StatefulWidget {
  final void Function(int modulo)? onNavegarModulo;
  const GuiaScreen({super.key, this.onNavegarModulo});

  @override
  State<GuiaScreen> createState() => _GuiaScreenState();
}

class _GuiaScreenState extends State<GuiaScreen> {
  /// Definición de los módulos guiados. El orden refleja el flujo natural del
  /// negocio: abrir caja → vender → consultar → reponer.
  static const List<_ModuloGuia> _modulos = [
    _ModuloGuia(
      indice: 1,
      nombre: 'Vender (POS)',
      icono: Icons.point_of_sale,
      resumen:
          'Busque productos (F2), agréguelos al carrito, ajuste cantidades y '
          'cobre en USD y/o Bs (F12). El sistema aplica IVA 16% e IGTF 3% en '
          'divisas, emite la factura fiscal y descuenta el stock solo.',
    ),
    _ModuloGuia(
      indice: 7,
      nombre: 'Caja y Finanzas',
      icono: Icons.account_balance_wallet,
      resumen:
          'Antes de vender, abra el turno con fondo base. Al cierre, haga el '
          'arqueo comparando el efectivo real con el esperado. Aquí también '
          'viven Cuentas por pagar y los exportables IVA/SENIAT.',
    ),
    _ModuloGuia(
      indice: 4,
      nombre: 'Productos (Inventario)',
      icono: Icons.inventory_2,
      resumen:
          'Catálogo con filtro por categoría y proveedor, búsqueda por SKU/'
          'nombre y paginación en servidor. Desde aquí se crean productos, '
          'variantes y se ajusta el stock.',
    ),
    _ModuloGuia(
      indice: 5,
      nombre: 'Compras (Entradas)',
      icono: Icons.add_shopping_cart,
      resumen:
          'Registre la recepción de mercancía por proveedor: actualiza stock y '
          'costo promedio ponderado, y genera la CxP si la compra es a crédito.',
    ),
    _ModuloGuia(
      indice: 2,
      nombre: 'Facturas',
      icono: Icons.receipt_long,
      resumen:
          'Historial de ventas con detalle línea a línea, cobro pendiente y '
          'nota de crédito con PIN de supervisor para devoluciones.',
    ),
    _ModuloGuia(
      indice: 0,
      nombre: 'Inicio (Dashboard)',
      icono: Icons.home,
      resumen:
          'Resumen del negocio: ventas del día/mes en USD y Bs, ticket '
          'promedio, productos top y alertas de stock bajo o margen.',
    ),
    _ModuloGuia(
      indice: 6,
      nombre: 'Proveedores',
      icono: Icons.local_shipping,
      resumen:
          'Maestro de proveedores con RIF, contacto y consulta de precios en '
          'línea (scraping EPA). Las compras se amarran a este maestro.',
    ),
    _ModuloGuia(
      indice: 3,
      nombre: 'Clientes',
      icono: Icons.people,
      resumen:
          'Maestro de clientes con RIF/Cédula (validación SENIAT), historial de '
          'compras y cuentas por cobrar cuando aplica.',
    ),
    _ModuloGuia(
      indice: 8,
      nombre: 'Ajustes',
      icono: Icons.settings,
      resumen:
          'Tema claro/oscuro, datos fiscales de la tienda, tasa BCV del día y '
          'reinicio de tutoriales contextuales.',
    ),
  ];

  /// Recorrido del primer día, ordenado por lo que un operador necesita hacer
  /// primero. Los módulos de tesorería se ocultan a cajeros (regla de roles).
  List<_ModuloGuia> get _recorrido {
    final rol = (ApiService.usuarioRol ?? '').toUpperCase();
    final esCajero = rol == 'CAJERO';
    return _modulos
        .where((m) => !(esCajero && (m.indice == 7)))
        .toList(growable: false);
  }

  void _irAlModulo(int indice) {
    widget.onNavegarModulo?.call(indice);
  }

  void _repasarTutorial(_ModuloGuia m) {
    final List<WalkthroughStep> pasos = switch (m.nombre) {
      'Vender (POS)' => walkthroughPos(),
      'Productos (Inventario)' => walkthroughInventario(),
      'Caja y Finanzas' => walkthroughTesoreria(),
      _ => [
          WalkthroughStep(
            titulo: m.nombre,
            descripcion: m.resumen,
            icono: m.icono,
          ),
        ],
    };
    WalkthroughOverlay.mostrar(
      context,
      pasos: pasos,
      onCompletado: () {},
      onOmitido: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Guía interactiva')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // Encabezado de bienvenida
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.waving_hand_outlined,
                      size: 44, color: cs.onPrimaryContainer),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bienvenido a Adrialga',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Recorra cada módulo en el orden sugerido. En cada tarjeta '
                          'puede abrir el módulo real o ver de nuevo su tutorial. '
                          'Consejo: pulse F1 en cualquier pantalla para ayuda contextual.',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Recorrido sugerido', style: tt.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < _recorrido.length; i++) ...[
            _tarjetaModulo(_recorrido[i], i + 1, cs, tt),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.currency_exchange, color: cs.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'La tasa BCV se actualiza sola al entrar al POS; si el sitio '
                      'del BCV no responde, el sistema usa la última tasa registrada '
                      'y avisa que puede no ser la vigente.',
                      style: tt.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaModulo(
      _ModuloGuia m, int orden, ColorScheme cs, TextTheme tt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: cs.primaryContainer,
                  child: Text('$orden',
                      style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Icon(m.icono, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.nombre,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(m.resumen, style: tt.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _irAlModulo(m.indice),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir módulo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _repasarTutorial(m),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Ver tutorial'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuloGuia {
  final int indice;
  final String nombre;
  final IconData icono;
  final String resumen;
  const _ModuloGuia({
    required this.indice,
    required this.nombre,
    required this.icono,
    required this.resumen,
  });
}
