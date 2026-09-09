import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/parseo.dart';

/// Parseo seguro: Prisma serializa Decimal como String, nunca castear directo.
double _numD(dynamic v) => numD(v);

/// Tab de Caja con control de turno: apertura (arqueo inicial) y cierre
/// (arqueo con validacion de saldo). Consume `/api/caja/*`.
class CajaTurnoTab extends StatefulWidget {
  const CajaTurnoTab({super.key});
  @override
  State<CajaTurnoTab> createState() => _CajaTurnoTabState();
}

class _CajaTurnoTabState extends State<CajaTurnoTab> {
  static const double _tolerancia = 1.0;

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _arqueos = [];
  bool _cargando = true;
  bool _trabajando = false;
  final _montoInicialCtrl = TextEditingController();
  final _montoContadoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _montoInicialCtrl.dispose();
    _montoContadoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await ApiService.getEstadoCaja();
      if (mounted) setState(() { _data = data; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() { _cargando = false; });
    }
    // Historial de arqueos: un fallo aquí no debe tumbar el estado del turno.
    try {
      final arqueos = await ApiService.getHistoricoArqueos();
      if (mounted) setState(() => _arqueos = arqueos);
    } catch (_) {}
  }

  double get _saldo {
    final caja = (_data?['caja'] as Map<String, dynamic>?) ?? {};
    return _numD(caja['Saldo_Actual']);
  }

  void _mensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _abrir() async {
    final monto = double.tryParse(_montoInicialCtrl.text.trim()) ?? 0;
    if (monto <= 0) {
      _mensaje('El fondo base de caja debe ser mayor a \$0.00', error: true);
      return;
    }
    setState(() => _trabajando = true);
    final r = await ApiService.abrirCaja(
      montoInicial: monto,
      observacion: _obsCtrl.text.trim(),
    );
    setState(() => _trabajando = false);
    if (r['success'] == true) {
      _mensaje('Caja abierta correctamente');
      _montoInicialCtrl.clear();
      _obsCtrl.clear();
      await _cargar();
    } else {
      _mensaje(r['error']?.toString() ?? 'No se pudo abrir la caja', error: true);
    }
  }

  Future<void> _cerrar() async {
    final montoContado = double.tryParse(_montoContadoCtrl.text.trim());
    if (montoContado != null && montoContado < 0) {
      _mensaje('El monto contado no puede ser negativo', error: true);
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar caja (arqueo)'),
        content: Text(
            'Se cerrara el turno actual. Saldo en caja: USD \$${_saldo.toStringAsFixed(2)}.\nDesea continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _trabajando = true);
    final r = await ApiService.cerrarCaja(
      montoContado: montoContado,
      observacion: _obsCtrl.text.trim(),
    );
    setState(() => _trabajando = false);
    if (r['success'] == true) {
      _mensaje('Caja cerrada. Saldo entregado: USD \$${_numD(r['saldoEntregado'] ?? 0).toStringAsFixed(2)}');
      _montoContadoCtrl.clear();
      _obsCtrl.clear();
      await _cargar();
    } else {
      _mensaje(r['error']?.toString() ?? 'No se pudo cerrar la caja', error: true);
    }
  }

  void _mostrarDialogoAbrir() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DialogoAbrirCaja(
        montoCtrl: _montoInicialCtrl,
        obsCtrl: _obsCtrl,
        onAbrir: () {
          Navigator.pop(ctx);
          _abrir();
        },
      ),
    );
  }

  /// Dialogo de apertura autocontenido: exige fondo base > $0 y la confirmacion
  /// explicita de la Tasa BCV del dia antes de habilitar el boton "Abrir".
  /// El `StatefulBuilder`/estado local evita redibujar la vista de caja completa.

  void _mostrarDialogoCerrar() {
    _montoContadoCtrl.text = _saldo.toStringAsFixed(2);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar caja (arqueo)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _montoContadoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Monto contado en caja (USD)',
                prefixText: '\$ ',
                helperText: 'Debe coincidir con el saldo (+-${_tolerancia.toStringAsFixed(2)})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              decoration: const InputDecoration(labelText: 'Observacion (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cerrar();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return const Center(child: Text('Error al cargar caja'));
    }

    final cajaActiva = (_data?['cajaActiva'] as bool?) ?? false;
    final movimientos = (_data?['movimientos'] as List?) ?? [];
    final resumen = (_data?['resumenTurno'] as Map<String, dynamic>?) ?? {};

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: isDark ? cs.surfaceContainerHighest : cs.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(cajaActiva ? Icons.lock_open : Icons.lock_outline, color: cajaActiva ? Colors.green : Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cajaActiva ? 'Caja ABIERTA' : 'Caja CERRADA',
                          style: TextStyle(color: cajaActiva ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.refresh), onPressed: _trabajando ? null : _cargar, tooltip: 'Recargar'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Saldo Disponible', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('\$${_saldo.toStringAsFixed(2)}', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 28, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Ingresos', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          Text('+\$${_numD(resumen['ingresosUSDTurno']).toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Egresos', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          Text('-\$${_numD(resumen['egresosUSDTurno']).toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (cajaActiva)
                    OutlinedButton.icon(
                      onPressed: _trabajando ? null : () => _mostrarDialogoCerrar(),
                      icon: _trabajando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock),
                      label: const Text('Cerrar caja (arqueo)'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _trabajando ? null : () => _mostrarDialogoAbrir(),
                      icon: _trabajando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_open),
                      label: const Text('Abrir caja'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Movimientos Recientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 8),
          if (movimientos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Sin movimientos', style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600))),
            )
          else
            ...movimientos.map<Widget>((m) {
              final esIngreso = m['Tipo'] == 'INGRESO';
              return Card(
                color: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: esIngreso ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                    child: Icon(esIngreso ? Icons.arrow_downward : Icons.arrow_upward, color: esIngreso ? Colors.green : Colors.red),
                  ),
                  title: Text(m['Concepto'] ?? '', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text('${m['Metodo_Pago'] ?? ''} - ${m['Fecha'] ?? ''}', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                  trailing: Text('${esIngreso ? '+' : '-'}\$${_numD(m['Monto_USD']).toStringAsFixed(2)}', style: TextStyle(color: esIngreso ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('Arqueos del Mes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 8),
          if (_arqueos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('Sin turnos registrados este mes', style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey))),
            )
          else
            ..._arqueos.map<Widget>((a) {
              final diferencia = _numD(a['diferencia']);
              final cuadrado = diferencia.abs() < 0.01;
              final esAbierto = a['estado'] == 'ABIERTA';
              // Verde = cuadra; rojo = faltante (entregó de menos); ámbar = sobrante.
              final Color indicador = cuadrado
                  ? Colors.green
                  : (diferencia > 0 ? cs.error : cs.tertiary);
              return Card(
                color: cs.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: indicador.withValues(alpha: 0.15),
                    child: Icon(
                      esAbierto
                          ? Icons.timelapse
                          : (cuadrado ? Icons.check : Icons.warning_amber),
                      color: esAbierto ? cs.primary : indicador,
                    ),
                  ),
                  title: Text(
                    'Turno #${a['turnoId']} — ${a['apertura'].toString().substring(0, 10)}${esAbierto ? ' (abierto)' : ''}',
                    style: TextStyle(color: cs.onSurface),
                  ),
                  subtitle: Text(
                    'Inicial: \$${_numD(a['saldoInicial']).toStringAsFixed(2)} · Entregado: \$${_numD(a['saldoEntregado']).toStringAsFixed(2)} · Esperado: \$${_numD(a['saldoEsperado']).toStringAsFixed(2)}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  trailing: Text(
                    cuadrado
                        ? 'OK'
                        : (diferencia > 0
                            ? 'Falta \$${diferencia.toStringAsFixed(2)}'
                            : 'Sobra \$${(-diferencia).toStringAsFixed(2)}'),
                    style: TextStyle(
                      color: indicador,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Diálogo de apertura de caja autocontenido.
/// Gestión local de estado: carga la Tasa BCV del día y exige que el cajero
/// registre un fondo base > $0 y confirme explícitamente la tasa antes de
/// habilitar el botón "Abrir".
class _DialogoAbrirCaja extends StatefulWidget {
  final TextEditingController montoCtrl;
  final TextEditingController obsCtrl;
  final VoidCallback onAbrir;

  const _DialogoAbrirCaja({
    required this.montoCtrl,
    required this.obsCtrl,
    required this.onAbrir,
  });

  @override
  State<_DialogoAbrirCaja> createState() => _DialogoAbrirCajaState();
}

class _DialogoAbrirCajaState extends State<_DialogoAbrirCaja> {
  double? _tasa;
  bool _tasaEsBCV = false;
  bool _cargandoTasa = true;
  bool _tasaConfirmada = false;

  @override
  void initState() {
    super.initState();
    _cargarTasa();
  }

  Future<void> _cargarTasa() async {
    final tasa = await ApiService.getTasaCambio();
    if (!mounted) return;
    setState(() {
      _tasa = tasa;
      _tasaEsBCV = ApiService.lastTasaEsBCV;
      _cargandoTasa = false;
    });
  }

  double get _montoBase => double.tryParse(widget.montoCtrl.text.trim()) ?? 0;

  bool get _habilitar =>
      !_cargandoTasa && _montoBase > 0 && _tasaConfirmada;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Abrir caja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Fondo base (USD) — debe ser > 0',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            // Confirmación obligatoria de la Tasa BCV del día.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.currency_exchange,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _cargandoTasa
                              ? 'Consultando tasa BCV...'
                              : 'Tasa BCV del día: ${_tasa?.toStringAsFixed(4) ?? '--'} Bs/\$'
                                  '${_tasaEsBCV ? '' : ' (respaldo)'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _tasaConfirmada,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Confirmo la Tasa BCV del día',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                    onChanged: _cargandoTasa
                        ? null
                        : (v) => setState(() => _tasaConfirmada = v ?? false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.obsCtrl,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _habilitar ? widget.onAbrir : null,
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}