import 'dart:math' as math;
import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
// `intl` exporta su propia clase `TextDirection` (sin `ltr`), que colisiona con
// la de dart:ui que usa el TextPainter. Se oculta aquí y se importa
// explícitamente la de dart:ui para dejar el nombre sin ambigüedad.
import 'package:intl/intl.dart' hide TextDirection;

/// Un punto de la serie temporal del dashboard (una hora, un día o un mes).
class PuntoSerie {
  final String etiqueta;
  final double montoUsd;
  final double montoBs;
  final int facturas;

  const PuntoSerie({
    required this.etiqueta,
    required this.montoUsd,
    required this.montoBs,
    required this.facturas,
  });

  /// Parseo defensivo: la API entrega los montos como num o String (Decimal).
  factory PuntoSerie.fromJson(Map<String, dynamic> m) => PuntoSerie(
    etiqueta: (m['etiqueta'] ?? '').toString(),
    montoUsd: double.tryParse(m['monto']?.toString() ?? '') ?? 0,
    montoBs: double.tryParse(m['montoBs']?.toString() ?? '') ?? 0,
    facturas: int.tryParse(m['facturas']?.toString() ?? '') ?? 0,
  );
}

enum BiModo { histograma, linea }

/// Gráfico BI de la serie de ventas (Fase 2 — Data Storytelling) con DOS vistas:
///   • Histograma — barras con el VALOR IMPRESO encima de cada barra (sin hover)
///     y **tooltip nativo** al pasar el cursor/tocar.
///   • Línea temporal — curva suavizada (Bezier), relleno degradado, puntos,
///     etiquetas de valor y **tooltip por toque** (guía vertical + tarjeta).
///
/// Ejes dinámicos: las etiquetas del eje X se **adelgazan** automáticamente
/// cuando hay muchos puntos, evitando el solapamiento. Tipografía ampliada
/// (11.5–17) para lectura en PC. Sin dependencias nuevas.
class BiSerieChart extends StatefulWidget {
  final List<PuntoSerie> serie;
  final String titulo;
  final bool enBs;

  const BiSerieChart({
    super.key,
    required this.serie,
    required this.titulo,
    this.enBs = true,
  });

  @override
  State<BiSerieChart> createState() => _BiSerieChartState();
}

class _BiSerieChartState extends State<BiSerieChart> {
  BiModo _modo = BiModo.histograma;
  int? _seleccionado; // índice resaltado en la vista de línea (tooltip)
  final _fmt = NumberFormat.decimalPattern('es');

  double _valor(PuntoSerie p) => widget.enBs ? p.montoBs : p.montoUsd;

  /// Formato compacto para el eje (1.2k, 3.4M) — evita etiquetas kilométricas.
  String _eje(double v) {
    final pref = widget.enBs ? 'Bs ' : '\$';
    final a = v.abs();
    if (a >= 1000000) return '$pref${(v / 1000000).toStringAsFixed(1)}M';
    if (a >= 10000) return '$pref${(v / 1000).toStringAsFixed(1)}k';
    return '$pref${_fmt.format(v)}';
  }

  /// Valor exacto, con separador de miles, para las etiquetas directas.
  String _exacto(double v) => '${widget.enBs ? 'Bs. ' : '\$'}${_fmt.format(v)}';

  /// Etiqueta impresa SOBRE cada barra.
  ///
  /// Un importe como `Bs. 2.670.698,382` mide 19 caracteres: al comprimirlo en
  /// el ancho de una columna quedaba ilegible en pantallas de escritorio
  /// (reportado el 2026-10-14). Se usa notación compacta (2.67M / 20.7k) que sí
  /// se lee, y el valor EXACTO sigue disponible en el tooltip al pasar el
  /// cursor o tocar la barra.
  String _etiquetaBarra(double v) {
    final pref = widget.enBs ? 'Bs ' : '\$';
    final a = v.abs();
    if (a >= 1000000) return '$pref${(v / 1000000).toStringAsFixed(2)}M';
    if (a >= 10000) return '$pref${(v / 1000).toStringAsFixed(1)}k';
    return _exacto(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 520;
                final controles = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toggle(
                      cs,
                      BiModo.histograma,
                      Icons.bar_chart,
                      'Histograma',
                    ),
                    _toggle(cs, BiModo.linea, Icons.show_chart, 'Línea'),
                  ],
                );
                if (compacto) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      controles,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.titulo,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    controles,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (widget.serie.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    'Sin ventas registradas en el período seleccionado.',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else if (_modo == BiModo.histograma)
              _histograma(cs)
            else
              LayoutBuilder(
                builder: (context, constraints) => _linea(
                  cs,
                  alto: constraints.maxWidth < 520 ? 260 : _altoLinea,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(ColorScheme cs, BiModo modo, IconData icon, String label) {
    final sel = _modo == modo;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: sel ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _modo = modo;
            _seleccionado = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HISTOGRAMA ─────────────────────────────────────────────────────────────
  static const double _altoHist = 240;
  static const double _anchoCol = 78;

  /// Franja superior reservada a la etiqueta de valor, para que quepa SIEMPRE
  /// justo encima de su barra sin recortarse ni invadir el área del gráfico.
  static const double _altoEtiquetaBarra = 24;

  Widget _histograma(ColorScheme cs) {
    final valores = widget.serie.map(_valor).toList();
    final maxV = valores.fold<double>(0, (m, v) => v > m ? v : m);
    final maxEscala = maxV <= 0 ? 1.0 : maxV;
    final idxMax = valores.indexOf(maxV);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ejeY(cs, maxEscala),
          for (var i = 0; i < widget.serie.length; i++)
            _barra(cs, widget.serie[i], valores[i], maxEscala, i == idxMax),
        ],
      ),
    );
  }

  Widget _ejeY(ColorScheme cs, double maxEscala) {
    const ticks = [1.0, 0.75, 0.5, 0.25, 0.0];
    return Padding(
      // El `top` coincide con la franja de la etiqueta de barra: así la marca
      // superior del eje queda alineada con la base de las barras más altas.
      padding: const EdgeInsets.only(right: 8, top: _altoEtiquetaBarra),
      child: SizedBox(
        width: 66,
        height: _altoHist,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final t in ticks)
              Text(
                _eje(maxEscala * t),
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barra(
    ColorScheme cs,
    PuntoSerie p,
    double v,
    double maxEscala,
    bool destacada,
  ) {
    final h = maxEscala <= 0 ? 0.0 : (v / maxEscala) * _altoHist;
    final color = destacada ? cs.primary : cs.primary.withValues(alpha: 0.6);
    return Tooltip(
      message: '${p.etiqueta}\n${_exacto(v)}\n${p.facturas} factura(s)',
      waitDuration: const Duration(milliseconds: 250),
      child: SizedBox(
        width: _anchoCol,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zona del gráfico: la columna se ancla ABAJO, así cada barra nace
            // de la misma línea base y su etiqueta flota justo encima de ella.
            // (Antes la etiqueta quedaba arriba del todo, separada de la barra
            // y encimada con las de las barras vecinas.)
            SizedBox(
              height: _altoHist + _altoEtiquetaBarra,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: _altoEtiquetaBarra - 4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _etiquetaBarra(v),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: destacada ? cs.primary : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: h.clamp(2.0, _altoHist),
                    width: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [color, Color.lerp(color, Colors.white, 0.3)!],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  p.etiqueta,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── LÍNEA TEMPORAL ─────────────────────────────────────────────────────────
  static const double _altoLinea = 300;
  static const double _padIzq = 66;
  static const double _padDer = 18;

  Widget _linea(ColorScheme cs, {double alto = _altoLinea}) {
    final valores = widget.serie.map(_valor).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 600.0;
        final size = Size(ancho, alto);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setState(
            () => _seleccionado = _indiceCercano(
              d.localPosition.dx,
              size,
              valores.length,
            ),
          ),
          onHorizontalDragUpdate: (d) => setState(
            () => _seleccionado = _indiceCercano(
              d.localPosition.dx,
              size,
              valores.length,
            ),
          ),
          child: Stack(
            children: [
              CustomPaint(
                size: size,
                painter: _LineaPainter(
                  valores: valores,
                  etiquetas: widget.serie.map((p) => p.etiqueta).toList(),
                  seleccionado: _seleccionado,
                  color: cs.primary,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.55),
                  labelColor: cs.onSurfaceVariant,
                  valueColor: cs.onSurface,
                  formatoEje: _eje,
                  formatoValor: _exacto,
                ),
              ),
              if (_seleccionado != null &&
                  _seleccionado! >= 0 &&
                  _seleccionado! < widget.serie.length)
                Positioned(
                  left: 6,
                  top: 2,
                  child: _tooltipLinea(
                    cs,
                    widget.serie[_seleccionado!],
                    valores[_seleccionado!],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Índice del punto más cercano a la posición X tocada (mapea el ancho útil).
  int _indiceCercano(double dx, Size size, int n) {
    final w = size.width - _padIzq - _padDer;
    if (n <= 1 || w <= 0) return 0;
    final t = ((dx - _padIzq) / w).clamp(0.0, 1.0);
    return (t * (n - 1)).round();
  }

  Widget _tooltipLinea(ColorScheme cs, PuntoSerie p, double v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${p.etiqueta} · ${_exacto(v)} · ${p.facturas} fact.',
        style: TextStyle(
          fontSize: 12,
          color: cs.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Pinta la línea temporal: rejilla, relleno degradado, curva suavizada (Bezier),
/// puntos, etiquetas de valor y guía vertical del punto seleccionado.
class _LineaPainter extends CustomPainter {
  final List<double> valores;
  final List<String> etiquetas;
  final int? seleccionado;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color valueColor;
  final String Function(double) formatoEje;
  final String Function(double) formatoValor;

  _LineaPainter({
    required this.valores,
    required this.etiquetas,
    required this.seleccionado,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.valueColor,
    required this.formatoEje,
    required this.formatoValor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;
    const left = 66.0;
    const right = 18.0;
    const top = 34.0;
    const bottom = 44.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;

    final maxV = valores.fold<double>(0, (m, v) => v > m ? v : m);
    final maxEscala = maxV <= 0 ? 1.0 : maxV * 1.1;

    double xFor(int i) => valores.length == 1
        ? left + w / 2
        : left + (w * i / (valores.length - 1));
    double yFor(double v) => top + h - (v / maxEscala) * h;

    // Rejilla + marcas del eje Y.
    const ticks = [1.0, 0.75, 0.5, 0.25, 0.0];
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = top + h - t * h;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), gridPaint);
      _text(
        canvas,
        formatoEje(maxEscala * t),
        Offset(left - 10, y),
        color: labelColor,
        size: 11.5,
        anchorX: 1,
        anchorY: 0.5,
      );
    }

    final puntos = <Offset>[
      for (var i = 0; i < valores.length; i++)
        Offset(xFor(i), yFor(valores[i])),
    ];

    // ── Caso especial: UN solo dato ────────────────────────────────────────
    // Con un único punto no hay línea que trazar: el relleno de área producía
    // un triángulo extraño. Se dibuja una guía punteada hasta la base y un
    // punto destacado con su valor, que es lo que realmente se quiere mostrar.
    if (puntos.length == 1) {
      final p = puntos.first;
      final guia = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      for (var y = p.dy; y < top + h; y += 8) {
        canvas.drawLine(
          Offset(p.dx, y),
          Offset(p.dx, y + 4 > top + h ? top + h : y + 4),
          guia,
        );
      }
      canvas.drawCircle(p, 7, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, 4.5, Paint()..color = color);
      _text(
        canvas,
        formatoValor(valores.first),
        Offset(p.dx, p.dy - 16),
        color: valueColor,
        size: 13,
        anchorX: 0.5,
        anchorY: 1,
      );
      if (etiquetas.isNotEmpty) {
        _text(
          canvas,
          etiquetas.first,
          Offset(p.dx, top + h + 14),
          color: labelColor,
          size: 11.5,
          anchorX: 0.5,
          anchorY: 0,
        );
      }
      return;
    }

    // Curva suavizada (Catmull-Rom → Bézier cúbica).
    final linea = _suavizar(puntos);

    // Área rellena bajo la curva.
    final relleno = Path.from(linea)
      ..lineTo(puntos.last.dx, top + h)
      ..lineTo(puntos.first.dx, top + h)
      ..close();
    canvas.drawPath(
      relleno,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(left, top, w, h)),
    );

    // Trazo de la línea.
    canvas.drawPath(
      linea,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Guía vertical del punto seleccionado (tooltip por toque).
    if (seleccionado != null &&
        seleccionado! >= 0 &&
        seleccionado! < valores.length) {
      final px = xFor(seleccionado!);
      canvas.drawLine(
        Offset(px, top),
        Offset(px, top + h),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeWidth = 1.5,
      );
    }

    // Ejes deliberadamente escasos: la línea debe leerse primero por su forma;
    // el detalle exacto queda disponible mediante toque/tooltip.
    final paso = math.max(1, (valores.length / 6).ceil());

    final idxMax = valores.indexOf(maxV);
    final idxLast = valores.length - 1;
    final mostrarValor = <int>{idxMax, idxLast};
    if (valores.length <= 6) {
      mostrarValor.add(0);
    }

    for (var i = 0; i < valores.length; i++) {
      final px = xFor(i);
      final py = yFor(valores[i]);
      final esSel = i == seleccionado;
      canvas.drawCircle(Offset(px, py), esSel ? 7 : 5, Paint()..color = color);
      canvas.drawCircle(
        Offset(px, py),
        esSel ? 3.4 : 2.4,
        Paint()..color = Colors.white,
      );

      // Etiqueta del eje X (debajo), adelgazada para no solaparse.
      if (i % paso == 0 || i == idxLast || esSel) {
        _text(
          canvas,
          etiquetas[i],
          Offset(px, top + h + 10),
          color: labelColor,
          size: 11.5,
          anchorX: 0.5,
          anchorY: 0,
        );
      }

      // Solo se imprimen pocos valores de referencia. El resto se consulta
      // mediante toque para evitar ruido visual y colisiones en móvil.
      if (mostrarValor.contains(i) && !esSel) {
        final etiqueta = formatoValor(valores[i]);
        final anchoEtiqueta = etiqueta.length > 13 ? 76.0 : 68.0;
        final x = px.clamp(
          left + anchoEtiqueta / 2,
          left + w - anchoEtiqueta / 2,
        );
        _text(
          canvas,
          etiqueta,
          Offset(x, py - 10),
          color: valueColor,
          size: 11.5,
          bold: true,
          anchorX: 0.5,
          anchorY: 1,
        );
      }
    }
  }

  /// Curva suavizada Catmull-Rom convertida a segmentos Bézier cúbicos.
  Path _suavizar(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length < 2) return path;
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = (i + 2 < pts.length) ? pts[i + 2] : p2;
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  /// Dibuja texto con anclaje relativo: anchorX 0=izq,0.5=centro,1=der;
  /// anchorY 0=arriba,0.5=medio,1=abajo.
  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    required Color color,
    double size = 12,
    bool bold = false,
    double anchorX = 0,
    double anchorY = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(
      canvas,
      Offset(at.dx - tp.width * anchorX, at.dy - tp.height * anchorY),
    );
  }

  @override
  bool shouldRepaint(covariant _LineaPainter old) =>
      old.valores != valores ||
      old.color != color ||
      old.etiquetas != etiquetas ||
      old.seleccionado != seleccionado;
}
