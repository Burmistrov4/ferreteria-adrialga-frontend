import 'package:flutter/material.dart';

import '../models/variante_model.dart';
import '../services/api_service.dart';

/// Grilla matricial de variantes (inventario multidimensional).
///
/// - Desktop (`compacto: false`): 1 atributo → Wrap de tarjetas; 2 atributos
///   → Table bidimensional (filas = eje 1, columnas = eje 2). Combinaciones
///   inexistentes se marcan bloqueadas, nunca se "inventan" celdas.
/// - Móvil (`compacto: true`): acordeón de ExpansionTile por valor del primer
///   atributo con chips del segundo.
/// Tap en celda habilitada → edición inline de stock/costo/precio (multipanel,
/// 48dp, apto para táctil). Tras guardar se sincroniza contra el backend.
class MatrixStockGrid extends StatefulWidget {
  final int productoId;
  final String skuBase;
  final String nombreProducto;
  final bool compacto;

  /// Invocado tras cada guardado exitoso para re-sincronizar el padre.
  final VoidCallback? onCambio;

  const MatrixStockGrid({
    super.key,
    required this.productoId,
    required this.skuBase,
    required this.nombreProducto,
    this.compacto = false,
    this.onCambio,
  });

  @override
  State<MatrixStockGrid> createState() => MatrixStockGridState();
}

class MatrixStockGridState extends State<MatrixStockGrid> {
  MatrizVariantes? _matriz;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getVariantesProducto(widget.productoId);
      if (mounted) {
        setState(() {
          _matriz = MatrizVariantes.fromJson(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Edición inline rápida: stock, costo y precio de una combinación.
  Future<void> _editarVariante(ProductoVariante v) async {
    final stockCtrl = TextEditingController(text: '${v.stock}');
    final costoCtrl =
        TextEditingController(text: v.costo.toStringAsFixed(2));
    final precioCtrl =
        TextEditingController(text: v.precio.toStringAsFixed(2));
    // Margen: vacío = heredar (backend mantiene null → cascada producto/cat).
    final margenCtrl = TextEditingController(
        text: v.margenPropio != null ? v.margenPropio!.toStringAsFixed(2) : '');
    final attrsTexto = v.atributos.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(v.sku, style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attrsTexto.isEmpty ? 'Variante por defecto' : attrsTexto,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stock'),
              ),
              TextField(
                controller: costoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Costo (\$)'),
              ),
              TextField(
                controller: precioCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Precio (\$)'),
              ),
              TextField(
                controller: margenCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Margen %',
                  helperText: 'Vacío = heredar del producto/categoría',
                  hintText: v.margenPropio == null
                      ? 'Heredado: ${v.margenEfectivo.toStringAsFixed(2)}%'
                      : null,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final s = int.tryParse(stockCtrl.text.trim());
              final c =
                  double.tryParse(costoCtrl.text.trim().replaceAll(',', '.'));
              final p =
                  double.tryParse(precioCtrl.text.trim().replaceAll(',', '.'));
              final mTxt = margenCtrl.text.trim();
              final m = mTxt.isEmpty
                  ? null
                  : double.tryParse(mTxt.replaceAll(',', '.'));
              if (s == null || s < 0 || c == null || c < 0 || p == null || p < 0 ||
                  (mTxt.isNotEmpty && (m == null || m < 0))) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Revisa los valores: deben ser numéricos y no negativos.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // Capturar valores ANTES de disponer los controladores.
    final stockText = stockCtrl.text.trim();
    final costoText = costoCtrl.text.trim().replaceAll(',', '.');
    final precioText = precioCtrl.text.trim().replaceAll(',', '.');
    final margenText = margenCtrl.text.trim().replaceAll(',', '.');
    stockCtrl.dispose();
    costoCtrl.dispose();
    precioCtrl.dispose();
    margenCtrl.dispose();
    if (ok != true) return;

    final res = await ApiService.actualizarVariante(v.varianteId, {
      'stock': int.tryParse(stockText) ?? v.stock,
      'costo': double.tryParse(costoText) ?? v.costo,
      'precio': double.tryParse(precioText) ?? v.precio,
      // Margen: campo vacío → null explícito = la variante vuelve a heredar.
      'margen': margenText.isEmpty ? null : double.tryParse(margenText),
    });
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Variante actualizada')),
      );
      await _cargar();
      widget.onCambio?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error']?.toString() ?? 'No se pudo guardar'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error: $_error',
            style: TextStyle(color: cs.error, fontSize: 12)),
      );
    }
    final m = _matriz!;
    // Producto sin personalización adicional (legacy lineal): vista compacta
    if (m.ejes.isEmpty) {
      return _tarjetaSimple(m.matriz.isNotEmpty ? m.matriz.first : null, cs);
    }
    return widget.compacto ? _acordeonMovil(m, cs) : _grilla(m, cs);
  }

  /// Variante única por defecto (producto atributo-less): tarjeta directa.
  Widget _tarjetaSimple(ProductoVariante? v, ColorScheme cs) {
    if (v == null) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.inventory_2, color: cs.onPrimaryContainer, size: 20),
        ),
        title: Text(v.sku, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          'Stock: ${v.stock} · Costo: \$${v.costo.toStringAsFixed(2)} · Precio: \$${v.precio.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Icon(Icons.edit_outlined, color: cs.primary),
        onTap: () => _editarVariante(v),
      ),
    );
  }

  /// Búsqueda en la matriz por combinación exacta de atributos.
  ProductoVariante? _porCombinacion(
      MatrizVariantes m, Map<String, String> combinacion) {
    for (final v in m.matriz) {
      var match = true;
      for (final kv in combinacion.entries) {
        if (v.atributos[kv.key] != kv.value) {
          match = false;
          break;
        }
      }
      if (match) return v;
    }
    return null;
  }

  /// Desktop: 1 eje → Wrap de tarjetas · 2 ejes → Table bidimensional.
  Widget _grilla(MatrizVariantes m, ColorScheme cs) {
    final ejes = m.ejes.entries.toList();
    if (ejes.length == 1) {
      final eje = ejes.first;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: eje.value.map((valor) {
          final v = _porCombinacion(m, {eje.key: valor});
          return _tarjetaStock(
            etiqueta: '${eje.key} $valor',
            variante: v,
            cs: cs,
          );
        }).toList(),
      );
    }
    if (ejes.length == 2) {
      final ejeFilas = ejes.first;
      final ejeCols = ejes.last;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
              color: cs.outlineVariant.withValues(alpha: 0.4), width: 0.6),
          children: [
            TableRow(
              decoration: BoxDecoration(color: cs.surfaceContainerHighest),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(ejeCol0Header(ejeFilas.key, ejeCols.key),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                ...ejeCols.value.map((col) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(col,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    )),
              ],
            ),
            ...ejeFilas.value.map((filaValor) => TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(filaValor,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ...ejeCols.value.map((colValor) {
                    final v = _porCombinacion(
                        m, {ejeFilas.key: filaValor, ejeCols.key: colValor});
                    if (v == null) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.lock_outline,
                            size: 14, color: cs.outline),
                      );
                    }
                    return InkWell(
                      onTap: () => _editarVariante(v),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          children: [
                            Text(
                              '${v.stock}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: v.stock == 0 ? cs.error : cs.primary,
                              ),
                            ),
                            Text(
                              '\$${v.precio.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ])),
          ],
        ),
      );
    }
    // 3+ ejes: listado agrupado (raro en ferretería, pero no se oculta).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: m.matriz.map((v) => _tarjetaSimple(v, cs)).toList(),
    );
  }

  /// Móvil: acordeón del primer eje con chips del segundo (o lista plana).
  Widget _acordeonMovil(MatrizVariantes m, ColorScheme cs) {
    final ejes = m.ejes.entries.toList();
    if (ejes.isEmpty) {
      return _tarjetaSimple(
          m.matriz.isNotEmpty ? m.matriz.first : null, cs);
    }
    if (ejes.length == 1) {
      final eje = ejes.first;
      return Column(
        children: eje.value.map((valor) {
          final v = _porCombinacion(m, {eje.key: valor});
          return _tarjetaStock(
              etiqueta: valor, variante: v, cs: cs, estirar: true);
        }).toList(),
      );
    }
    final ejePrincipal = ejes.first;
    final ejeSecundario = ejes[1];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: ejePrincipal.value.map((valorPrincipal) {
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${ejePrincipal.key}: $valorPrincipal',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ejeSecundario.value.map((valorSec) {
                    final v = _porCombinacion(m, {
                      ejePrincipal.key: valorPrincipal,
                      ejeSecundario.key: valorSec,
                    });
                    if (v == null) {
                      return Chip(
                        label: Text(valorSec),
                        avatar: const Icon(Icons.lock, size: 12),
                        backgroundColor: cs.surfaceContainerHighest,
                        labelStyle: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      );
                    }
                    return ActionChip(
                      onPressed: () => _editarVariante(v),
                      avatar: Icon(Icons.circle,
                          size: 10,
                          color: v.stock == 0 ? cs.error : cs.primary),
                      label: Text(
                        '$valorSec · ${v.stock}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Tarjeta de stock con edición inline para el eje único (desktop) y el
  /// listado plano móvil (estirar=true ocupa todo el ancho disponible).
  Widget _tarjetaStock({
    required String etiqueta,
    required ProductoVariante? variante,
    required ColorScheme cs,
    bool estirar = false,
  }) {
    Widget contenido = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          if (variante == null)
            Text('No disponible',
                style: TextStyle(fontSize: 11, color: cs.outline))
          else ...[
            Text('${variante.stock} uds',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: variante.stock == 0 ? cs.error : cs.primary)),
            Text('\$${variante.precio.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
    if (estirar) {
      contenido = SizedBox(
        width: double.infinity,
        child: contenido,
      );
    }
    return Card(
      margin: EdgeInsets.only(bottom: estirar ? 6 : 0),
      child: InkWell(
        onTap: variante == null ? null : () => _editarVariante(variante),
        borderRadius: BorderRadius.circular(12),
        child: contenido,
      ),
    );
  }

  static String ejeCol0Header(String fila, String col) => '$fila \\ $col';
}
