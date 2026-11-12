import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Cream Glass palette and type.
class Cream {
  static const bg = Color(0xFFF6F1E4);
  static const ink = Color(0xFF1C1A14);
  static const muted = Color(0xFF6B6450);
  static const line = Color(0x1A1C1A14);
  static const glow = Color(0xFF6B5A12);

  /// Milky cream glass for captions over photos, so dark text stays readable.
  static const frost = LiquidGlassSettings(
    glassColor: Color(0xB3F6F1E4),
    blur: 14,
    frost: 0.4,
  );

  /// Bars and buttons that sit on the cream ground: whiter and frosted so
  /// they read as raised glass instead of disappearing into the page.
  static const bar = LiquidGlassSettings(
    glassColor: Color(0x99FFFFFF),
    blur: 18,
    frost: 0.5,
    thickness: 24,
  );

  /// Modal sheets: mostly opaque cream glass so text always reads.
  static const sheet = LiquidGlassSettings(
    glassColor: Color(0xD9F6F1E4),
    blur: 24,
    frost: 0.5,
    thickness: 30,
  );

  /// Large panels (collections, sections).
  static const panel = LiquidGlassSettings(
    glassColor: Color(0x4DFFFCF0),
    blur: 22,
    frost: 0.3,
    thickness: 30,
  );

  static TextStyle label(
    BuildContext context, {
    double size = 12,
    FontWeight w = FontWeight.w500,
    Color c = muted,
  }) {
    final s = context.s(size);
    return GoogleFonts.manrope(
      fontSize: s,
      fontWeight: w,
      letterSpacing: s * 0.22,
      color: c,
    );
  }

  static TextStyle body(
    BuildContext context, {
    double size = 15,
    FontWeight w = FontWeight.w400,
    Color c = ink,
  }) => GoogleFonts.manrope(
    fontSize: context.s(size),
    fontWeight: w,
    color: c,
    height: 1.45,
  );

  static TextStyle display(BuildContext context, {double size = 64}) {
    final s = context.s(size);
    return GoogleFonts.manrope(
      fontSize: s,
      fontWeight: FontWeight.w300,
      letterSpacing: -s * 0.03,
      color: ink,
      height: 1,
    );
  }
}

/// Responsive sizing: everything is designed at 390pt wide and scales with
/// the screen, clamped so tiny and tablet screens stay sensible.
extension Responsive on BuildContext {
  double get scale {
    final w = MediaQuery.sizeOf(this).width;
    return (w / 390).clamp(0.85, 1.4);
  }

  double s(double v) => v * scale;

  /// Side gutter: 20 on phones, more on wide screens.
  double get gutter => (MediaQuery.sizeOf(this).width * 0.05).clamp(16, 48);

  /// Grid columns for post tiles.
  int get columns {
    final w = MediaQuery.sizeOf(this).width;
    return w >= 900 ? 4 : (w >= 600 ? 3 : 2);
  }
}

/// Cream ground with the blurred dark-gold glow the glass refracts.
class CreamBackground extends StatelessWidget {
  const CreamBackground({
    super.key,
    this.alignment = const Alignment(0.15, -0.35),
  });
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final d = (size.shortestSide * 1.35).clamp(420.0, 900.0);
    // Plain radial gradient (soft enough without a live blur filter),
    // cached in its own layer so glass and scrolling never repaint it.
    return RepaintBoundary(
      child: Container(
        color: Cream.bg,
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          alignment: alignment,
          child: Container(
            width: d,
            height: d,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFF14110A),
                  Color(0xFF2E270B),
                  Color(0xFF5A4B10),
                  Color(0xB38C7A2A),
                  Color(0x55D4BE5A),
                  Color(0x00F6F1E4),
                ],
                stops: [0.0, 0.2, 0.38, 0.55, 0.7, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Large cream glass bottom sheet used for every modal in the app.
Future<T?> showCreamSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: const Color(0x401C1A14),
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (c, _, _) {
      final mq = MediaQuery.of(c);
      // Lift the sheet above the keyboard so text fields stay visible.
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.85,
              ),
              child: Padding(
                padding: EdgeInsets.all(c.s(10)),
                child: GlassContainer(
                  settings: Cream.sheet,
                  shape: LiquidRoundedSuperellipse(borderRadius: c.s(36)),
                  padding: EdgeInsets.fromLTRB(
                    c.gutter,
                    c.s(22),
                    c.gutter,
                    c.s(24),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: Cream.label(c, size: 14, c: Cream.ink),
                        ),
                        SizedBox(height: c.s(18)),
                        builder(c),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Primary dark pill button.
class InkPill extends StatelessWidget {
  const InkPill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: context.s(58),
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Cream.ink,
        foregroundColor: Cream.bg,
        shape: const StadiumBorder(),
      ),
      onPressed: onTap,
      child: Text(
        label.toUpperCase(),
        style: Cream.label(context, size: 13, c: Cream.bg),
      ),
    ),
  );
}

/// Round glass icon button sized for touch on every screen.
class GlassIcon extends StatelessWidget {
  const GlassIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.label,
    this.live = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final String? label;

  /// Live liquid glass only for buttons pinned in place. Buttons that scroll
  /// with content use a static frosted look: same style, no per-frame cost.
  final bool live;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: !live
        ? Material(
            color: const Color(0xCCFFFFFF),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0x14000000)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: context.s(size),
                height: context.s(size),
                child: Icon(
                  icon,
                  color: Cream.ink,
                  size: context.s(size * 0.44),
                ),
              ),
            ),
          )
        : GlassButton(
            settings: Cream.bar,
            icon: Icon(icon, color: Cream.ink, size: context.s(size * 0.44)),
            width: context.s(size),
            height: context.s(size),
            onTap: onTap,
          ),
  );
}

/// Static frosted panel for anything that scrolls. Looks like the glass
/// panels but costs nothing extra per frame.
class Frost extends StatelessWidget {
  const Frost({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
    this.color = const Color(0xB3FFFCF2),
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(context.s(radius)),
      border: Border.all(color: const Color(0xB3FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14403200),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

/// Glass sheet with one text box. Returns the text, or null if dismissed.
Future<String?> showCreamInput(
  BuildContext context, {
  required String title,
  required String action,
  String hint = '',
  String initial = '',
  int maxLines = 1,
}) {
  final ctrl = TextEditingController(text: initial);
  return showCreamSheet<String>(
    context,
    title: title,
    builder: (c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: maxLines,
          textCapitalization: TextCapitalization.sentences,
          style: Cream.body(c, size: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: Cream.body(c, size: 16, c: Cream.muted),
            filled: true,
            fillColor: const Color(0x80FFFFFF),
            contentPadding: EdgeInsets.symmetric(
              horizontal: c.s(18),
              vertical: c.s(18),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(c.s(20)),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SizedBox(height: c.s(16)),
        InkPill(label: action, onTap: () => Navigator.pop(c, ctrl.text)),
      ],
    ),
  );
}
