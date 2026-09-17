import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_notifier.dart';
import '../services/api_service.dart';
import '../services/configuracion_service.dart';
import '../services/preferences_service.dart';
import '../widgets/walkthrough_overlay.dart';
import 'categorias_screen.dart';

/// Módulo 8: Configuración (Tasa BCV, Sistema y catálogo maestro).
class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  double? _tasa;
  bool _tasaEsBCV = false;
  bool _cargando = true;

  // ── Datos de la Empresa (edición de cabecera de tickets/PDF) ───────────
  final _nombreCtrl = TextEditingController();
  final _rifCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _pieCtrl = TextEditingController();
  bool _guardandoEmpresa = false;
  bool _empresaCargada = false;

  @override
  void initState() {
    super.initState();
    _cargarTasa();
    _cargarEmpresa();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rifCtrl.dispose();
    _direccionCtrl.dispose();
    _telefonoCtrl.dispose();
    _pieCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarEmpresa() async {
    try {
      final cfg = await ConfiguracionService.obtener();
      if (!mounted) return;
      setState(() {
        _nombreCtrl.text = cfg.nombre;
        _rifCtrl.text = cfg.rif;
        _direccionCtrl.text = cfg.direccion;
        _telefonoCtrl.text = cfg.telefono;
        _pieCtrl.text = cfg.mensajePie;
        _empresaCargada = true;
      });
    } catch (_) {
      if (mounted) setState(() => _empresaCargada = true);
    }
  }

  Future<void> _guardarEmpresa() async {
    final nombre = _nombreCtrl.text.trim();
    final rif = _rifCtrl.text.trim().toUpperCase();
    final direccion = _direccionCtrl.text.trim();
    if (nombre.isEmpty || rif.isEmpty || direccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nombre, RIF y Dirección son obligatorios'),
      ));
      return;
    }
    setState(() => _guardandoEmpresa = true);
    final res = await ApiService.updateConfiguracionTienda({
      'nombre': nombre,
      'rif': rif,
      'direccion': direccion,
      'telefono': _telefonoCtrl.text.trim(),
      'mensajePie': _pieCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _guardandoEmpresa = false);
    if (res['success'] == true) {
      ConfiguracionService.invalidar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Datos de la empresa actualizados'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(res['error']?.toString() ?? 'Error al guardar la empresa'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _cargarTasa() async {
    setState(() => _cargando = true);
    final tasa = await ApiService.getTasaCambio();
    if (!mounted) return;
    setState(() {
      _tasa = tasa;
      _tasaEsBCV = ApiService.lastTasaEsBCV;
      _cargando = false;
    });
  }

  Future<void> _reiniciarTutorial() async {
    // Se fuerza has_completed_onboarding = false y se abre el tutorial de inmediato.
    await PreferencesService.setOnboardingDone(false);
    if (!mounted) return;
    WalkthroughOverlay.mostrar(
      context,
      pasos: walkthroughCajero(),
      onCompletado: () => PreferencesService.setOnboardingDone(true),
      onOmitido: () => PreferencesService.setOnboardingDone(true),
    );
  }

  Widget _filaInfo(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              etiqueta,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración del Sistema')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Tasa de cambio ──────────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.currency_exchange,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tasa de Cambio BCV',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: _cargando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        onPressed: _cargando ? null : _cargarTasa,
                        tooltip: 'Recargar tasa',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cargando
                        ? 'Consultando...'
                        : '${_tasa?.toStringAsFixed(4) ?? '--'} Bs/USD',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _tasaEsBCV
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Text(
                    _tasaEsBCV
                        ? 'Origen: Banco Central de Venezuela (en vivo)'
                        : 'Origen: valor de respaldo (BCV sin conexión)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _tasaEsBCV
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Datos de la empresa (cabecera de ticket/PDF) ─────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storefront_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Datos de la Empresa',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_empresaCargada)
                    const LinearProgressIndicator()
                  else ...[
                    TextField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Razón Social / Nombre *'),
                    ),
                    TextField(
                      controller: _rifCtrl,
                      decoration:
                          const InputDecoration(labelText: 'RIF (J-…) *'),
                    ),
                    TextField(
                      controller: _direccionCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Dirección fiscal *'),
                      maxLines: 2,
                    ),
                    TextField(
                      controller: _telefonoCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Teléfono de contacto'),
                    ),
                    TextField(
                      controller: _pieCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje al pie del ticket',
                        hintText: 'Ej.: ¡Gracias por su compra!',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        icon: _guardandoEmpresa
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                            _guardandoEmpresa ? 'Guardando…' : 'Guardar datos'),
                        onPressed:
                            _guardandoEmpresa ? null : _guardarEmpresa,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Consumer<ThemeNotifier>(
                builder: (context, themeNotifier, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          themeNotifier.isDark
                              ? Icons.dark_mode
                              : Icons.light_mode,
                          color: themeNotifier.isDark
                              ? Colors.indigo
                              : Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Tema de la aplicación',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Scroll horizontal: en móviles de 320dp los 3 segmentos
                    // (icono + texto) no caben siempre; evita RenderFlex overflow.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<ThemeModePreference>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeModePreference.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('Sistema'),
                        ),
                        ButtonSegment(
                          value: ThemeModePreference.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Claro'),
                        ),
                        ButtonSegment(
                          value: ThemeModePreference.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Oscuro'),
                        ),
                      ],
                      selected: {themeNotifier.preference},
                      onSelectionChanged: (sel) =>
                          themeNotifier.setPreference(sel.first),
                    ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      themeNotifier.isDark
                          ? 'Modo oscuro activado (se conserva en cada inicio)'
                          : 'Modo claro activado (se conserva en cada inicio)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Catálogo maestro ────────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(Icons.category,
                  color: Theme.of(context).colorScheme.tertiary),
              title: const Text('Categorías (Catálogo Maestro)'),
              subtitle: const Text(
                'Agrupaciones de productos usadas en inventario y POS.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriasScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Tutorial de primer uso (onboarding) ────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(Icons.help_outline,
                  color: Theme.of(context).colorScheme.secondary),
              title: const Text('Tutorial de Cajero'),
              subtitle: const Text(
                'Repite el recorrido guiado de primer uso (Caja → POS → Cobro → Arqueo).',
              ),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: _reiniciarTutorial,
            ),
          ),
          const SizedBox(height: 12),

          // ── Información del sistema ─────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Información del Sistema',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _filaInfo('Sistema', 'Ferretería Adrialga C.A. v1.0'),
                  _filaInfo('API en uso', ApiService.baseUrl),
                  _filaInfo('Backend', 'Node.js + Express + Prisma'),
                  _filaInfo('Base de datos', 'MySQL'),
                  _filaInfo(
                    'Servicios externos',
                    'BCV (scraper) · SENIAT (caído — registro manual)',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
