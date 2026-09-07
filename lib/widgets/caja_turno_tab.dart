import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Parseo seguro: Prisma serializa Decimal como String, nunca castear directo.
double _numD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

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
    if (monto < 0) {
      _mensaje('El monto inicial no puede ser negativo', error: true);
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
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _montoInicialCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Monto inicial (USD)', prefixText: '\$ '),
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
              _abrir();
            },
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

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
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                          Text('Ingresos', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                          Text('+\$${_numD(resumen['ingresosUSDTurno']).toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Egresos', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                          Text('-\$${_numD(resumen['egresosUSDTurno']).toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
              child: Center(child: Text('Sin movimientos', style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey))),
            )
          else
            ...movimientos.map<Widget>((m) {
              final esIngreso = m['Tipo'] == 'INGRESO';
              return Card(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
              final cs = Theme.of(context).colorScheme;
              return Card(
                color: cs.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cuadrado
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.25),
                    child: Icon(
                      esAbierto ? Icons.timelapse : (cuadrado ? Icons.check : Icons.warning_amber),
                      color: cuadrado ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(
                    'Turno #${a['turnoId']} — ${a['apertura'].toString().substring(0, 10)}${esAbierto ? ' (abierto)' : ''}',
                    style: TextStyle(color: cs.onSurface),
                  ),
                  subtitle: Text(
                    'Entregado: \$${_numD(a['saldoEntregado']).toStringAsFixed(2)} · Esperado: \$${_numD(a['saldoEsperado']).toStringAsFixed(2)}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  trailing: Text(
                    cuadrado
                        ? 'OK'
                        : (diferencia > 0 ? 'Falta \$${diferencia.toStringAsFixed(2)}' : 'Sobra \$${(-diferencia).toStringAsFixed(2)}'),
                    style: TextStyle(
                      color: cuadrado ? Colors.green : Colors.orange,
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