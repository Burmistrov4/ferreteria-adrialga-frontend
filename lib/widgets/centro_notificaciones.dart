import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Centro de Notificaciones (MISIÓN 1 — FASE C).
///
/// Campana para el AppBar que consulta el Asistente de Negocio del backend
/// (`GET /api/dashboard/notificaciones`) y clasifica los *insights* por
/// severidad con color semántico:
///   • `critico`  → rojo   (caja olvidada abierta, agotados reales, arqueo en déficit)
///   • `atencion` → ámbar  (stock crítico bajo, arqueo con sobrante)
///   • `positivo` → verde  (señales de ventas al alza)
///
/// El endpoint es de **solo lectura** y reutiliza las mismas reglas de negocio
/// que el arqueo contable, por lo que no agrega carga ni toca la lógica
/// contable. Cero efecto sobre el resto del dashboard.
class CentroNotificaciones extends StatefulWidget {
  const CentroNotificaciones({super.key});

  @override
  State<CentroNotificaciones> createState() => _CentroNotificacionesState();
}

class _CentroNotificacionesState extends State<CentroNotificaciones> {
  List<Map<String, dynamic>> _insights = [];
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final data = await ApiService.getNotificaciones();
      if (mounted) {
        setState(() {
          _insights = data;
          _cargando = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  int get _criticos =>
      _insights.where((i) => i['severidad'] == 'critico').length;
  int get _atenciones =>
      _insights.where((i) => i['severidad'] == 'atencion').length;

  /// Color de la campana: rojo si hay críticos, ámbar si hay atención,
  /// neutro en caso contrario (incluye los positivos).
  Color _colorCampana(BuildContext context) {
    if (_criticos > 0) return Theme.of(context).colorScheme.error;
    if (_atenciones > 0) return Colors.amber.shade800;
    return Theme.of(context).colorScheme.onSurface;
  }

  /// Abre la hoja de notificaciones.
  ///
  /// IMPORTANTE: la hoja NO recibe una copia de los datos. Antes se le pasaban
  /// `insights`/`cargando` como parámetros y, como `showModalBottomSheet`
  /// construye el `builder` una sola vez, la hoja quedaba congelada con
  /// `cargando: true` para siempre (spinner infinito) aunque la petición
  /// hubiera terminado. Ahora la hoja es un widget con estado propio que
  /// consulta y refresca sus propios datos.
  void _abrir(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _HojaNotificaciones(),
    ).then((_) {
      // Al cerrar, refrescar el contador de la campana.
      if (mounted) _cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _insights.length;
    final campana = _colorCampana(context);
    final bell = IconButton(
      icon: Icon(Icons.notifications_outlined, color: campana),
      tooltip: 'Centro de notificaciones',
      onPressed: () => _abrir(context),
    );
    if (total == 0) return bell;
    return Badge(
      label: Text('$total'),
      backgroundColor: campana,
      textColor: Colors.white,
      child: bell,
    );
  }
}

class _HojaNotificaciones extends StatefulWidget {
  const _HojaNotificaciones();

  @override
  State<_HojaNotificaciones> createState() => _HojaNotificacionesState();
}

class _HojaNotificacionesState extends State<_HojaNotificaciones> {
  List<Map<String, dynamic>> _insights = [];
  bool _cargando = true;
  String? _error;

  static const Map<String, IconData> _iconoSeveridad = {
    'critico': Icons.error_outline,
    'atencion': Icons.warning_amber_outlined,
    'positivo': Icons.trending_up,
  };

  static const Map<String, Color> _colorSeveridad = {
    'critico': Colors.red,
    'atencion': Colors.amber,
    'positivo': Colors.green,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await ApiService.getNotificaciones();
      if (!mounted) return;
      setState(() {
        _insights = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  int get _criticos =>
      _insights.where((i) => i['severidad'] == 'critico').length;
  int get _atenciones =>
      _insights.where((i) => i['severidad'] == 'atencion').length;
  int get _positivos =>
      _insights.where((i) => i['severidad'] == 'positivo').length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.notifications_active, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Centro de Notificaciones',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualizar',
                    onPressed: _cargando ? null : _cargar,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    conteo: _criticos,
                    etiqueta: 'Críticos',
                    color: Colors.red,
                  ),
                  _Chip(
                    conteo: _atenciones,
                    etiqueta: 'Atención',
                    color: Colors.amber.shade800,
                  ),
                  _Chip(
                    conteo: _positivos,
                    etiqueta: 'Positivos',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: _cuerpo(cs, scroll)),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo(ColorScheme cs, ScrollController scroll) {
    if (_cargando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text(
                'Consultando el estado del negocio…',
                style: TextStyle(fontSize: 13, color: Color(0x99CBD5E1)),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: cs.error),
              const SizedBox(height: 12),
              Text(
                'No se pudieron cargar las notificaciones:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_insights.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: Colors.green,
              ),
              const SizedBox(height: 12),
              const Text(
                'Sin novedades',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'El negocio opera dentro de parámetros normales.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _insights.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = _insights[i];
        final sev = (it['severidad'] ?? 'atencion').toString();
        final color = _colorSeveridad[sev] ?? Colors.amber;
        final icono = _iconoSeveridad[sev] ?? Icons.info_outline;
        final titulo = (it['titulo'] ?? '').toString();
        final mensaje = (it['mensaje'] ?? '').toString();
        final modulo = (it['modulo'] ?? '').toString();
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icono, color: color),
            ),
            title: Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(mensaje),
                if (modulo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        modulo,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final int conteo;
  final String etiqueta;
  final Color color;
  const _Chip({
    required this.conteo,
    required this.etiqueta,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text('$etiqueta: $conteo'),
      backgroundColor: color.withValues(alpha: 0.12),
      visualDensity: VisualDensity.compact,
    );
  }
}
