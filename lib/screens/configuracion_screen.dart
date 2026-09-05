import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_notifier.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _cargarTasa();
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
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
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
      appBar: AppBar(title: const Text('8. Configuración del Sistema')),
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
                      const Icon(
                        Icons.currency_exchange,
                        color: Colors.blueAccent,
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
                      color: _tasaEsBCV ? Colors.green.shade700 : Colors.orange,
                    ),
                  ),
                  Text(
                    _tasaEsBCV
                        ? 'Origen: Banco Central de Venezuela (en vivo)'
                        : 'Origen: valor de respaldo (BCV sin conexión)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _tasaEsBCV ? Colors.grey : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Tema claro / oscuro ──────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Consumer<ThemeNotifier>(
              builder: (context, themeNotifier, _) => SwitchListTile(
                secondary: Icon(
                  themeNotifier.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: themeNotifier.isDark ? Colors.indigo : Colors.amber,
                ),
                title: const Text(
                  'Modo Oscuro',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  themeNotifier.isDark ? 'Tema oscuro activado' : 'Tema claro activado',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: themeNotifier.isDark,
                onChanged: (_) => themeNotifier.toggle(),
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
              leading: const Icon(Icons.category, color: Colors.green),
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
