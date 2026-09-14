import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../services/api_service.dart';

class _VarianteGenerada {
  String sku;
  Map<String, String> atributos;
  TextEditingController stock;
  TextEditingController costo;
  TextEditingController precio;

  _VarianteGenerada({
    required this.sku,
    required this.atributos,
    required this.stock,
    required this.costo,
    required this.precio,
  });
}

/// Pestaña "Variantes" del diálogo de producto (solo en modo edición).
/// Permite definir hasta 2 atributos con valores separados por comas,
/// generar el producto cartesiano y enviarlo en lote al backend
/// (POST /productos/:id/variantes/bulk — upsert por SKU para idempotencia).
class VariantesTab extends StatefulWidget {
  final ProductoModel producto;
  final VoidCallback onGuardado;

  const VariantesTab({
    super.key,
    required this.producto,
    required this.onGuardado,
  });

  @override
  State<VariantesTab> createState() => _VariantesTabState();
}

class _VariantesTabState extends State<VariantesTab> {
  final _attr1Nombre = TextEditingController();
  final _attr1Valores = TextEditingController();
  final _attr2Nombre = TextEditingController();
  final _attr2Valores = TextEditingController();
  List<_VarianteGenerada> _generadas = [];
  bool _guardando = false;
  bool _matrizCargada = false;

  @override
  void initState() {
    super.initState();
    // Carga previa: si el producto ya tiene ejes definidos, prellenarlos.
    ApiService.getVariantesProducto(widget.producto.productoId).then((data) {
      if (!mounted) return;
      final ejes = data['ejes'];
      if (ejes is Map && ejes.isNotEmpty) {
        final nombres = ejes.keys.toList();
        _attr1Nombre.text = nombres.first;
        _attr1Valores.text = (ejes[nombres.first] as List).join(', ');
        if (nombres.length > 1) {
          _attr2Nombre.text = nombres[1];
          _attr2Valores.text = (ejes[nombres[1]] as List).join(', ');
        }
      }
      setState(() => _matrizCargada = true);
    }).catchError((_) {
      if (mounted) setState(() => _matrizCargada = true);
    });
  }

  @override
  void dispose() {
    _attr1Nombre.dispose();
    _attr1Valores.dispose();
    _attr2Nombre.dispose();
    _attr2Valores.dispose();
    for (final v in _generadas) {
      v.stock.dispose();
      v.costo.dispose();
      v.precio.dispose();
    }
    super.dispose();
  }

  List<String> _dividirValores(String t) => t
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet() // sin duplicados
      .toList();

  void _generarCartesiano() {
    final a1 = _attr1Nombre.text.trim();
    final v1 = _dividirValores(_attr1Valores.text);
    final a2 = _attr2Nombre.text.trim();
    final v2 = _dividirValores(_attr2Valores.text);

    if (a1.isEmpty || v1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Define el nombre del Atributo 1 y sus valores (separados por coma)')),
      );
      return;
    }

    final nuevo = <_VarianteGenerada>[];
    for (final x in v1) {
      if (a2.isNotEmpty && v2.isNotEmpty) {
        for (final y in v2) {
          final slug = '$x-$y'.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-');
          nuevo.add(_VarianteGenerada(
            sku: '${widget.producto.skuCodigo}-$slug',
            atributos: {a1: x, a2: y},
            stock: TextEditingController(text: '${widget.producto.stockActual}'),
            costo: TextEditingController(text: widget.producto.costoUltimo.toStringAsFixed(2)),
            precio: TextEditingController(text: widget.producto.precioVenta.toStringAsFixed(2)),
          ));
        }
      } else {
        final slug = x.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-');
        nuevo.add(_VarianteGenerada(
          sku: '${widget.producto.skuCodigo}-$slug',
          atributos: {a1: x},
          stock: TextEditingController(text: '${widget.producto.stockActual}'),
          costo: TextEditingController(text: widget.producto.costoUltimo.toStringAsFixed(2)),
          precio: TextEditingController(text: widget.producto.precioVenta.toStringAsFixed(2)),
        ));
      }
    }
    setState(() => _generadas = nuevo);
  }

  Future<void> _enviarBulk() async {
    if (_generadas.isEmpty) return;
    setState(() => _guardando = true);
    final payload = _generadas
        .map((v) => {
              'sku': v.sku,
              'atributos': v.atributos,
              'stock': int.tryParse(v.stock.text.trim()) ?? 0,
              'costo': double.tryParse(v.costo.text.trim().replaceAll(',', '.')) ?? 0.0,
              'precio': double.tryParse(v.precio.text.trim().replaceAll(',', '.')) ?? 0.0,
            })
        .toList();
    final res =
        await ApiService.crearVariantesBulk(widget.producto.productoId, payload);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Variantes guardadas correctamente')),
      );
      widget.onGuardado();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error']?.toString() ?? 'Error al guardar'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crea la matriz de opciones del producto: define atributos y el '
            'sistema generará todas las combinaciones para que les asignes '
            'stock y precio.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // Filas de atributos: nombre + valores (siempre 2 columnas,
          // válido en cualquier ancho al usar Expanded dentro de Row).
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _attr1Nombre,
                  decoration: const InputDecoration(
                      labelText: 'Atributo 1', hintText: 'Color'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _attr1Valores,
                  decoration: const InputDecoration(
                      labelText: 'Valores', hintText: 'Rojo, Azul, Gris'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _attr2Nombre,
                  decoration: const InputDecoration(
                      labelText: 'Atributo 2 (opcional)', hintText: 'Talla'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _attr2Valores,
                  decoration: const InputDecoration(
                      labelText: 'Valores', hintText: 'S, M, L'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.grid_view),
              onPressed: _generarCartesiano,
              label: const Text('Generar combinaciones'),
            ),
          ),
          const SizedBox(height: 12),
          if (!_matrizCargada) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],
          if (_generadas.isNotEmpty) ...[
            Text(
              '${_generadas.length} combinaciones generadas. Toca una fila para eliminarla si no aplica.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ..._generadas.asMap().entries.map((e) {
              final v = e.value;
              final aTexto = v.atributos.entries
                  .map((kv) => '${kv.key}: ${kv.value}')
                  .join(' · ');
              return Dismissible(
                key: ValueKey(v.sku),
                background: Container(
                  color: cs.errorContainer,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  child: Icon(Icons.delete, color: cs.error),
                ),
                direction: DismissDirection.startToEnd,
                onDismissed: (_) {
                  setState(() {
                    _generadas.removeAt(e.key);
                  });
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                aTexto,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                v.sku,
                                style: TextStyle(
                                    fontSize: 10, color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: v.stock,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Stock', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v.costo,
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Costo', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v.precio,
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Precio', isDense: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_guardando
                    ? 'Guardando…'
                    : 'Guardar ${_generadas.length} variantes'),
                onPressed: _guardando ? null : _enviarBulk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
