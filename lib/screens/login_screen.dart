import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;

  // Selector de entorno: Producción (Railway) o Local (backend XAMPP en LAN).
  bool _usarLocal = false;
  final _ipController = TextEditingController(); // ej. 192.168.98.153

  @override
  void initState() {
    super.initState();
    // Restaurar la selección si la app ya tenía un runtime guardado.
    ApiService.loadBaseUrlRuntime().then((_) {
      if (!mounted) return;
      final c = ApiService.ultimoBaseUrlRuntime;
      if (c != null && c.startsWith('http://192.')) {
        setState(() {
          _usarLocal = true;
          _ipController.text =
              c.replaceAll('http://', '').replaceAll(':3000/api', '');
        });
      }
    });
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, ingresa usuario y contraseña'),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    // Si está en modo local, fija la URL base al momento del login y persiste
    // en disco (para no requerir reingresar la IP cada vez que se abra la app).
    if (_usarLocal) {
      final ip = _ipController.text.trim();
      if (ip.isEmpty) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingresa la IP de la computadora (ej. 192.168.98.153)'),
          ),
        );
        return;
      }
      final url = ip.startsWith('http')
          ? ip.trim()
          : 'http://$ip:3000/api';
      ApiService.setBaseUrlRuntime(url);
    } else {
      ApiService.setBaseUrlRuntime(null); // producción por defecto
    }

    final success = await ApiService.login(user, pass);

    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AppShell()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text(
              'Credenciales incorrectas o servidor fuera de línea'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            // Tarjeta elástica: en pantallas anchas se limita a 380dp para
            // no estirarse; en teléfonos estrechos ocupa el ancho disponible
            // (equivalente a un max-width en flexbox).
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sistema Adrialga',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _userController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Usuario / RIF / Email',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Selector de entorno (para pruebas locales por LAN) ──
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Producción'),
                          icon: Icon(Icons.cloud_done),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Local Wi-Fi'),
                          icon: Icon(Icons.wifi),
                        ),
                      ],
                      selected: {_usarLocal},
                      onSelectionChanged: (s) =>
                          setState(() => _usarLocal = s.first),
                    ),
                    if (_usarLocal) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ipController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'IP de esta laptop/servidor',
                          hintText: '192.168.98.153',
                          prefixIcon: Icon(Icons.wifi_tethering),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'INGRESAR',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
