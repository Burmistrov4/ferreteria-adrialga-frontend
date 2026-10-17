import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/login_url.dart';
import '../widgets/app_shell.dart';
import 'monitor_db_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;

  /// Segundos que lleva el intento en curso. Sirve para avisar de que el
  /// servidor está despertando en vez de dejar un spinner mudo: el arranque en
  /// frío de la capa gratuita puede tardar casi un minuto (medido 2026-10-16).
  int _segundosEsperando = 0;
  Timer? _relojEspera;

  // Selector de entorno: Producción (Railway) o Local (backend XAMPP en LAN).
  bool _usarLocal = false;
  final _ipController = TextEditingController(); // ej. 192.168.98.153

  /// Esquema con el que el navegador cargó la app (web). Fuera de web no existe
  /// el concepto de contenido mixto, así que devuelve '' y el aviso se apaga.
  String get _esquemaPagina => kIsWeb ? Uri.base.scheme : '';

  /// Aviso de contenido mixto: la app se sirve por HTTPS (p. ej. GitHub Pages)
  /// y "Local Wi-Fi" apunta a un backend http:// → el navegador bloquea la
  /// petición y el login falla con un mensaje que no explica el motivo.
  bool get _avisoContenidoMixto {
    if (!_usarLocal) return false;
    final ip = _ipController.text.trim();
    // Sin IP todavía se asume http (el servidor local no usa certificado).
    final url = ip.isEmpty ? 'http://' : normalizarUrlLocal(ip);
    return bloqueadaPorContenidoMixto(url, _esquemaPagina);
  }

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
      // Empezar a despertar el backend YA, en segundo plano, mientras el
      // usuario escribe: si la capa gratuita está dormida, para cuando pulse
      // INGRESAR ya llevará decenas de segundos arrancando. No se espera ni se
      // avisa si falla: es una optimización, el login tiene su propio mensaje.
      ApiService.despertarServidor();
    });
  }

  @override
  void dispose() {
    _relojEspera?.cancel();
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

    setState(() {
      _loading = true;
      _segundosEsperando = 0;
    });

    // Fija la URL base al momento del login y la persiste. Si NO se usa local,
    // se limpia cualquier runtime guardado → en web vuelve al mismo origen.
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
      // Normaliza siempre a http(s)://host[:puerto]/api. Antes, si el campo
      // empezaba con "http" se usaba tal cual sin completar ':3000' → el login
      // se posteba al puerto 80 ("servidor fuera de línea").
      final url = normalizarUrlLocal(ip);
      if (url.isEmpty) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('IP/host inválido (ej. 192.168.98.153)'),
          ),
        );
        return;
      }
      ApiService.setBaseUrlRuntime(url);
    } else {
      ApiService.setBaseUrlRuntime(null); // producción por defecto
    }

    // Reloj para el mensaje de espera: a partir de los 6 s avisa de que el
    // servidor está despertando, para que la espera no parezca un cuelgue.
    _relojEspera?.cancel();
    _relojEspera = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_loading) return;
      setState(() => _segundosEsperando++);
    });

    final resultado = await ApiService.login(user, pass);

    if (!mounted) return;
    _relojEspera?.cancel();
    setState(() => _loading = false);

    if (resultado == ResultadoLogin.ok) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AppShell()),
      );
      return;
    }

    // El mensaje ahora distingue las dos causas que antes se confundían en uno
    // solo ("Credenciales incorrectas o servidor fuera de línea"): una clave
    // mal escrita no es lo mismo que un backend dormido que no contestó.
    // Si el fallo es del servidor, el segundo intento suele funcionar, así que
    // el aviso dura más y lo dice explícitamente.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: Duration(seconds: reintentable(resultado) ? 9 : 4),
        content: Text(mensajeLogin(resultado)),
      ),
    );
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
                    // ── Selector de entorno (nativo y web) ──
                    // En el despliegue unificado (el backend sirve la web) la API
                    // es del mismo origen, así que "Producción" = este mismo
                    // servidor. "Local Wi-Fi" permite apuntar a otra IP:3000
                    // (frontend en la nube + backend en la LAN del Hotspot).
                    ...[
                      const SizedBox(height: 16),
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
                          // Reconstruye para recalcular el aviso de contenido
                          // mixto mientras se escribe la IP.
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'IP de esta laptop/servidor',
                            hintText: '192.168.98.153',
                            prefixIcon: Icon(Icons.wifi_tethering),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        // La causa NO es la IP ni el backend: el navegador no
                        // permite que una página https:// llame a http://.
                        // Se explica en pantalla en vez de dejar el error
                        // genérico de credenciales.
                        if (_avisoContenidoMixto) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Estás abriendo la app desde https:// y el '
                                    'navegador bloquea las llamadas a http:// '
                                    '(contenido mixto). Para usar Local Wi-Fi, '
                                    'abre la app desde el propio servidor: '
                                    'http://<IP>:3000',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
                    // Aviso de espera larga. El arranque en frío de la capa
                    // gratuita puede tardar casi un minuto; sin esto el usuario
                    // ve un spinner mudo y cree que la app se colgó (o peor:
                    // que la contraseña está mal). Medido el 2026-10-16.
                    if (_loading && _segundosEsperando >= 6)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          mensajeEsperaLogin(_segundosEsperando),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    // ── Acceso discreto al Monitor de Base de Datos ──
                    // Abre el diagrama en vivo del esquema. En modo
                    // presentación se muestran las 12 tablas del modelo.
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Opacity(
                        opacity: 0.55,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MonitorDbScreen(
                                modoInicial: 'presentacion',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.storage, size: 15),
                          label: const Text(
                            'Monitor de BD',
                            style: TextStyle(fontSize: 12),
                          ),
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
