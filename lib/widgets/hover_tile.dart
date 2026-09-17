import 'package:flutter/material.dart';

/// Wrapper de interacción de escritorio/web: cursor de mano y fondo sutil al
/// pasar el ratón. Se emplea para envolver ListTile/Card en las tablas
/// principales de la app (Clientes, Facturas, Inventario).
///
/// Panel lateral de control: `onTap` es obligatorio para habilitar el
/// cursor (sin él, el envoltorio se considera puramente pasivo).
class HoverTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const HoverTile({super.key, required this.child, required this.onTap});

  @override
  State<HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<HoverTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: _hovering
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}
