import 'package:flutter/material.dart';

/// Un paso del tutorial interactivo de primer uso.
///
/// En esta versión sin dependencias externas cada paso se representa con un
/// icono, título y descripción en una tarjeta Material 3, en lugar de
/// resaltar widgets concretos con GlobalKeys (que requiere conocer las
/// pantallas individuales). El flujo navega 5 pasos con botones y se cierra
/// con "Finalizar" u "Omitir".
class WalkthroughStep {
  final String titulo;
  final String descripcion;
  final IconData icono;

  const WalkthroughStep({
    required this.titulo,
    required this.descripcion,
    required this.icono,
  });
}

/// Flujo guiado del cajero (5 pasos modernos): Turno → POS/Atajos → Carrito →
/// Reversión → Arqueo y SENIAT.
List<WalkthroughStep> walkthroughCajero() => const [
      WalkthroughStep(
        titulo: '1 · Apertura de Turno y Tasa BCV',
        descripcion:
            'Antes de vender, abre la caja con fondo base > \$0 (Finanzas → Caja) '
            'y confirma la Tasa BCV del día. Sin turno abierto no se procesan ventas '
            'ni arqueos.',
        icono: Icons.lock_open,
      ),
      WalkthroughStep(
        titulo: '2 · Búsqueda, Escáner y Atajos',
        descripcion:
            'En el POS busca por nombre o SKU (F2 foca el buscador). Añade al '
            'carrito con un toque y ajusta cantidades con F3; F12 abre el cobro. '
            'Operación mouseless completa.',
        icono: Icons.keyboard_command_key,
      ),
      WalkthroughStep(
        titulo: '3 · Carrito y Cobro Bimoneda',
        descripcion:
            'Revisa el carrito (modifica cantidades respetando stock) y cobra en '
            'USD y/o Bs. El sistema aplica IVA 16% e IGTF 3% sobre divisas y '
            'calcula el vuelto a la Tasa BCV. Confirma para imprimir ticket.',
        icono: Icons.point_of_sale,
      ),
      WalkthroughStep(
        titulo: '4 · Reversión con Nota de Crédito',
        descripcion:
            'Para devolver una venta se exige PIN de Supervisor (override): el '
            'sistema emite una Nota de Crédito fiscal, restituye el stock con '
            'recálculo del CMP y asienta el egreso en caja.',
        icono: Icons.assignment_return,
      ),
      WalkthroughStep(
        titulo: '5 · Arqueo y Exportables SENIAT',
        descripcion:
            'Al cerrar el turno, cuadra el efectivo entregado contra el esperado '
            'y descarga los exportables SENIAT (Libro de Ventas/Compras en Bs y '
            'Resumen de IVA) desde Finanzas → IVA/SENIAT.',
        icono: Icons.savings,
      ),
    ];

/// Overlay de tutorial de primer uso que flota sobre toda la aplicación.
///
/// Se inserta en el `Overlay` raíz con `OverlayEntry`, por lo que es visible
/// sobre cualquier pantalla. Usa únicamente componentes nativos de Flutter y
/// tokens de `Theme.of(context).colorScheme` (sin dependencias pesadas).
class WalkthroughOverlay extends StatefulWidget {
  final List<WalkthroughStep> pasos;
  final VoidCallback onCompletado;
  final VoidCallback? onOmitido;

  const WalkthroughOverlay({
    super.key,
    required this.pasos,
    required this.onCompletado,
    this.onOmitido,
  });

  static void mostrarEnOverlay(
    OverlayState overlay, {
    required List<WalkthroughStep> pasos,
    required VoidCallback onCompletado,
    VoidCallback? onOmitido,
  }) {
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => WalkthroughOverlay(
        pasos: pasos,
        onCompletado: () {
          entry?.remove();
          onCompletado();
        },
        onOmitido: () {
          entry?.remove();
          onOmitido?.call();
        },
      ),
    );
    overlay.insert(entry);
  }

  /// Inserta el overlay en el Overlay raíz de [context] y lo retira al finalizar/omitir.
  ///
  /// [onCompletado] se invoca al presionar "Finalizar"; [onOmitido] al presionar
  /// "Omitir". El caller decide qué persistir (p. ej. marcar onboarding como hecho).
  static void mostrar(
    BuildContext context, {
    required List<WalkthroughStep> pasos,
    required VoidCallback onCompletado,
    VoidCallback? onOmitido,
  }) {
    mostrarEnOverlay(
      Overlay.of(context, rootOverlay: true),
      pasos: pasos,
      onCompletado: onCompletado,
      onOmitido: onOmitido,
    );
  }

  @override
  State<WalkthroughOverlay> createState() => _WalkthroughOverlayState();
}

class _WalkthroughOverlayState extends State<WalkthroughOverlay> {
  int _index = 0;

  bool get _esUltimo => _index == widget.pasos.length - 1;

  WalkthroughStep get _paso => widget.pasos[_index];

  void _siguiente() {
    if (_esUltimo) {
      widget.onCompletado();
      return;
    }
    setState(() => _index++);
  }

  void _atras() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        // Veladura que oscurece el resto de la pantalla.
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.55)),
        ),
        // Tarjeta centrada con el paso actual.
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 8,
                  color: cs.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icono del paso.
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _paso.icono,
                            size: 38,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Column(
                            key: ValueKey<int>(_index),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _paso.titulo,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _paso.descripcion,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Indicador de progreso (puntos).
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(widget.pasos.length, (i) {
                            final activo = i == _index;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: activo ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: activo
                                    ? cs.primary
                                    : cs.outlineVariant,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        // Acciones.
                        Row(
                          children: [
                            TextButton(
                              onPressed: widget.onOmitido,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(80, 48),
                              ),
                              child: Text(
                                'Omitir',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ),
                            const Spacer(),
                            if (_index > 0)
                              TextButton(
                                onPressed: _atras,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(80, 48),
                                ),
                                child: const Text('Atrás'),
                              ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _siguiente,
                              style: FilledButton.styleFrom(
                                minimumSize: Size(_esUltimo ? 140 : 120, 48),
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                              ),
                              child: Text(
                                _esUltimo ? 'Finalizar' : 'Siguiente',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}