import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/variante_model.dart';
import '../services/api_service.dart';

/// Eje de atributo del generador matricial (nombre + valores separados por coma).
class _AtributoCtrl {
  final TextEditingController nombreCtrl = TextEditingController();
  final TextEditingController valoresCtrl = TextEditingController();

  /// Valores normalizados: limpiados, sin vacíos, sin duplicados
  /// (insensible a mayúsculas para el dedupe: "Rojo" y "rojo" colapsan).
  List<String> get valores => valoresCtrl.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .fold<List<String>>([], (acc, v) {
        final clave = v.toLowerCase();
        if (!acc.any((a) => a.toLowerCase() == clave)) acc.add(v);
        return acc;
      });

  void dispose() {
    nombreCtrl.dispose();
    valoresCtrl.dispose();
  }
}

/// Fila editable de la matriz: una combinación atributos con su precio, costo,
/// stock y margen. `yaPersistida` indica que vino hidratada del backend.
class _VarianteFila {
  String sku;
  Map<String, String> atributos;
  final TextEditingController stockCtrl;
  final TextEditingController costoCtrl;
  final TextEditingController precioCtrl;
  final TextEditingController margenCtrl;

  /// null → hereda el margen del producto (cascada).
  double? get margenOverride {
    final t = margenCtrl.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  bool yaPersistida;
  int? varianteId;

  _VarianteFila({
    required this.sku,
    required this.atributos,
    required String stockInicial,
    required String costoInicial,
    required String precioInicial,
    String margenInicial = '',
    this.yaPersistida = false,
    this.varianteId,
  })  : stockCtrl = TextEditingController(text: stockInicial),
        costoCtrl = TextEditingController(text: costoInicial),
        precioCtrl = TextEditingController(text: precioInicial),
        margenCtrl = TextEditingController(text: margenInicial);

  void dispose() {
    stockCtrl.dispose();
    costoCtrl.dispose();
    precioCtrl.dispose();
    margenCtrl.dispose();
  }
}

/// Pestaña "Variantes" del diálogo de producto: generador N atributos,
/// hidratación del GET y guardado idempotente (upsert por SKU).
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
  static const int _maxAtributos = 3;

  List<_AtributoCtrl> _atributos = [_AtributoCtrl()];
  List<_VarianteFila> _filas = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarMatriz();
  }

  @override
  void dispose() {
    for (final a in _atributos) {
      a.dispose();
    }
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  /// Hidratación completa: ejes prellenados y filas con los valores reales
  /// guardados (lo que resuelve la pérdida al reabrir el formulario).
  Future<void> _cargarMatriz() async {
    try {
      final data = await ApiService.getVariantesProducto(widget.producto.productoId);
      if (!mounted) return;
      final m = MatrizVariantes.fromJson(data);
      final ejes = m.ejes.entries.toList();

      // Descartar atributos/filas anteriores de forma ordenada.
      for (final a in _atributos) {
        a.dispose();
      }
      for (final f in _filas) {
        f.dispose();
      }

      final nuevosAtributos = <_AtributoCtrl>[];
      for (final e in ejes.take(_maxAtributos)) {
        final c = _AtributoCtrl();
        c.nombreCtrl.text = e.key;
        c.valoresCtrl.text = e.value.join(', ');
        nuevosAtributos.add(c);
      }
      if (nuevosAtributos.isEmpty) nuevosAtributos.add(_AtributoCtrl());

      final filas = m.matriz
          // La variante por defecto del backfill (sin atributos) es la
          // rama lineal del producto; no forma parte de la matriz visual.
          .where((v) => v.atributos.isNotEmpty)
          .map((v) => _VarianteFila(
                sku: v.sku,
                atributos: v.atributos,
                stockInicial: '${v.stock}',
                costoInicial: v.costo.toStringAsFixed(2),
                precioInicial: v.precio.toStringAsFixed(2),
                margenInicial:
                    v.margenPropio != null ? v.margenPropio!.toStringAsFixed(2) : '',
                yaPersistida: true,
                varianteId: v.varianteId,
              ))
          .toList();

      setState(() {
        _atributos = nuevosAtributos;
        _filas = filas;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _slug(String valor) =>
      valor.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-');

  /// Cartesiano recursivo sobre una lista de ejes (nombre → valores).
  List<Map<String, String>> _combinar(
      List<MapEntry<String, List<String>>> ejes) {
    if (ejes.isEmpty) return [const <String, String>{}];
    final cabeza = ejes.first;
    final resto = ejes.skip(1).toList();
    final cola = _combinar(resto);
    final out = <Map<String, String>>[];
    for (final v in cabeza.value) {
      for (final restoMapa in cola) {
        out.add({cabeza.key: v, ...restoMapa});
      }
    }
    return out;
  }

  /// Genera el producto cartesiano sobre el estado visible (fusionado con
  /// filas persistidas: no duplica, marca lo ya existente).
  void _generarCartesiano() {
    final ejes = _atributos
        .where((a) => a.nombreCtrl.text.trim().isNotEmpty && a.valores.isNotEmpty)
        .map((a) => MapEntry(a.nombreCtrl.text.trim(), a.valores))
        .toList();
    if (ejes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Define al menos un atributo con valores separados por coma.'),
        ),
      );
      return;
    }

    final combinaciones = _combinar(ejes);
    final padre = widget.producto;
    final filasNuevas = <_VarianteFila>[];

    for (final combo in combinaciones) {
      final slug = combo.values.map(_slug).join('-');
      final sku = '${padre.skuCodigo}-$slug';
      // ¿Ya existe en el estado? Se conserva su configuración; si no, se
      // precarga desde el padre con herencia visual (margen vacío = heredar).
      final existente = _filas.where((f) => f.sku == sku).firstOrNull;
      filasNuevas.add(
        existente ??
            _VarianteFila(
              sku: sku,
              atributos: combo,
              stockInicial: '${padre.stockActual}',
              costoInicial: padre.costoUltimo.toStringAsFixed(2),
              precioInicial: padre.precioVenta.toStringAsFixed(2),
              margenInicial: '',
            ),
      );
    }
    setState(() => _filas = filasNuevas);
  }

  /// Elimina una fila: si era nueva, simplemente sale del búfer; si estaba
  /// persistida, se archiva en el backend (soft-delete / `Activo=false`).
  Future<void> _eliminarFila(_VarianteFila f) async {
    if (f.yaPersistida) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Archivar variante guardada'),
          content: Text(
            '"${f.atributos.values.join(' · ')}" puede tener historial de '
            'ventas. Se archivará (saldrá de la matriz del POS) pero se '
            'conservará en los registros fiscales.',
          ),
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
              child: const Text('Archivar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      if (f.varianteId != null) {
        final res = await ApiService.eliminarVariante(f.varianteId!);
        if (!mounted) return;
        if (res['success'] != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['error']?.toString() ?? 'No se pudo archivar'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
      }
    }
    setState(() {
      final idx = _filas.indexWhere((x) => x.sku == f.sku);
      if (idx >= 0) {
        _filas[idx].dispose();
        _filas.removeAt(idx);
      }
    });
  }

  Future<void> _enviarBulk() async {
    if (_filas.isEmpty) return;
    setState(() => _guardando = true);
    final payload = _filas
        .map((f) => {
              'sku': f.sku,
              'atributos': f.atributos,
              'stock': int.tryParse(f.stockCtrl.text.trim()) ?? 0,
              'costo': double.tryParse(
                      f.costoCtrl.text.trim().replaceAll(',', '.')) ??
                  0.0,
              'precio': double.tryParse(
                      f.precioCtrl.text.trim().replaceAll(',', '.')) ??
                  0.0,
              if (f.margenOverride != null) 'margen': f.margenOverride,
            })
        .toList();
    final res = await ApiService.crearVariantesBulk(
        widget.producto.productoId, payload);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Matriz guardada correctamente')),
      );
      await _cargarMatriz(); // rehidrata para marcar como persistidas
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
            'Define hasta $_maxAtributos atributos y sus valores. El sistema '
            'arma la matriz sin duplicados y cada fila hereda el costo y el '
            'margen del producto padre salvo que indiques lo contrario.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ..._atributos.asMap().entries.map((e) {
            final i = e.key;
            final a = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: a.nombreCtrl,
                      decoration: InputDecoration(
                        labelText: 'Atributo ${i + 1}',
                        hintText: i == 0 ? 'Color' : (i == 1 ? 'Talla' : 'Material'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: a.valoresCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Valores (coma)',
                        hintText: 'Rojo, Azul, Gris',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Quitar atributo',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _atributos.length <= 1
                        ? null
                        : () {
                            setState(() {
                              final q = _atributos.removeAt(i);
                              q.dispose();
                            });
                          },
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: _atributos.length <= 1 ? cs.outline : cs.error,
                    ),
                  ),
                ],
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir atributo'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _atributos.length >= _maxAtributos
                      ? null
                      : () {
                          setState(() => _atributos.add(_AtributoCtrl()));
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.grid_view),
                  label: const Text('Generar matriz'),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _generarCartesiano,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cargando) const LinearProgressIndicator(),
          if (!_cargando && _filas.isNotEmpty) ...[
            Text(
              '${_filas.length} combinación(es). El icono de la derecha '
              'quita una fila nueva del lote o archiva una ya guardada.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ..._filas.map((f) {
              final texto = f.atributos.entries
                  .map((kv) => '${kv.key}: ${kv.value}')
                  .join(' · ');
              return Card(
                key: ValueKey(f.sku),
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              texto,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              f.sku,
                              style: TextStyle(
                                  fontSize: 10, color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: f.yaPersistida
                                ? 'Archivar variante'
                                : 'Quitar del lote',
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: Icon(
                              f.yaPersistida
                                  ? Icons.archive_outlined
                                  : Icons.close,
                              color: f.yaPersistida ? cs.tertiary : cs.error,
                            ),
                            onPressed: () => _eliminarFila(f),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: f.stockCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Stock', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: f.costoCtrl,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Costo (\$)', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: f.margenCtrl,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Margen %',
                                hintText: 'Heredar',
                                isDense: true,
                                filled: true,
                                fillColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: f.precioCtrl,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Precio (\$)',
                                isDense: true,
                                filled: true,
                                fillColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    : 'Guardar ${_filas.length} variante(s)'),
                onPressed: _guardando || _filas.isEmpty ? null : _enviarBulk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
