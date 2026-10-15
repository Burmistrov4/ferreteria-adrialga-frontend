import 'package:flutter/material.dart';

/// Breakpoints y medidas compartidas del sistema Adrialga.
/// Evita que cada pantalla invente sus propios umbrales y paddings.
class AdrialgaResponsive {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1440;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;

  static int columns(
    double width, {
    int mobileColumns = 1,
    int tabletColumns = 2,
    int desktopColumns = 4,
  }) {
    // Los nombres de parámetros distinguen explícitamente el número de
    // columnas de los breakpoints estáticos (600/1200 px).
    if (width < AdrialgaResponsive.mobile) return mobileColumns;
    if (width < AdrialgaResponsive.desktop) return tabletColumns;
    return desktopColumns;
  }

  static double pagePadding(double width) {
    if (width < 600) return 12;
    if (width < 900) return 16;
    if (width < 1200) return 20;
    return 24;
  }

  static double sectionGap(double width) => width < 600 ? 14 : 20;

  /// Limita el ancho de contenido en monitores grandes para conservar una
  /// lectura cómoda en vez de estirar tarjetas hasta los extremos del monitor.
  static double contentMaxWidth(double width) {
    if (width < wide) return double.infinity;
    return 1440;
  }

  static EdgeInsets pageInsets(double width) =>
      EdgeInsets.all(pagePadding(width));
}

class AdrialgaSection extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const AdrialgaSection({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AdrialgaResponsive.contentMaxWidth(width),
        ),
        child: Padding(
          padding: padding ?? AdrialgaResponsive.pageInsets(width),
          child: child,
        ),
      ),
    );
  }
}
