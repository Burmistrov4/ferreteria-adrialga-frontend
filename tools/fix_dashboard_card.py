from pathlib import Path

WIDGET_BUILD = """@override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    descripcion,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}"""

path = Path(r"C:\Users\Loro\Desktop\Cuarto Semestre\3. Analisis de Sistemas II\Adrialga_Sistema_Renovado\adrialga_frontend\lib\screens\dashboard_screen.dart")
txt = path.read_text(encoding="utf-8")
ini = txt.index("  @override\n  Widget build(BuildContext context) {\n    final colorScheme")
fin = txt.index("class DashboardScreen extends StatefulWidget")
nuevo = txt[:ini] + WIDGET_BUILD + "\n\n" + txt[fin:]
path.write_text(nuevo, encoding="utf-8")
print("Escrito OK")
