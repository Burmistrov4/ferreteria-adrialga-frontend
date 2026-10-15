/// Implementación nativa (Android / Windows / iOS): no hay "pestañas".
///
/// La apertura en ventana aparte solo tiene sentido en web, donde el Monitor
/// puede vivir en su propia pestaña y colocarse al lado de la aplicación para
/// la demostración. En nativo la pantalla se abre con el Navigator normal.
bool get monitorWindowDisponible => false;

/// No-op: en nativo el llamador debe usar `Navigator.push`.
bool abrirMonitorWindow(String url) => false;
