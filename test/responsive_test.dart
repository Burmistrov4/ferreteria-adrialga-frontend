import 'package:flutter_test/flutter_test.dart';
import 'package:adrialga_frontend/utils/responsive.dart';

void main() {
  group('AdrialgaResponsive.columns', () {
    test('usa una columna en móvil estrecho', () {
      expect(AdrialgaResponsive.columns(375), 1);
    });

    test('usa dos columnas en tablet compacto', () {
      expect(AdrialgaResponsive.columns(768), 2);
    });

    test('mantiene dos columnas antes del breakpoint de escritorio', () {
      expect(AdrialgaResponsive.columns(1024), 2);
    });

    test('usa cuatro columnas en escritorio amplio', () {
      expect(AdrialgaResponsive.columns(1440), 4);
    });

    test('permite personalizar el número de columnas sin alterar breakpoints', () {
      expect(
        AdrialgaResponsive.columns(
          375,
          mobileColumns: 2,
          tabletColumns: 3,
          desktopColumns: 5,
        ),
        2,
      );
      expect(
        AdrialgaResponsive.columns(
          1440,
          mobileColumns: 2,
          tabletColumns: 3,
          desktopColumns: 5,
        ),
        5,
      );
    });
  });
}
