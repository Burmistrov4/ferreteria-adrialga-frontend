// Selector de implementación para abrir el Monitor de BD en otra pestaña o
// ventana del navegador. En web usa `window.open`; en nativo no aplica (la
// pantalla se abre como ruta normal del Navigator).
export 'monitor_window_stub.dart'
    if (dart.library.html) 'monitor_window_web.dart';
