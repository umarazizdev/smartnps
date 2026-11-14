import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class NewUi {
  static const bgDark = Color(0xFF070912);
  static const bgDark2 = Color(0xFF0C1020);
  static const bgDark3 = Color(0xFF11162A);
  static const bgLight = Color(0xFFF5F7FB);
  static const pageLight = Color(0xFFE9ECF3);
  static const accent = Color(0xFF4F8DFF);
  static const accent2 = Color(0xFF7CC4FF);
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const purple = Color(0xFFA78BFA);
  static const teal = Color(0xFF14B8A6);
  static const textDark = Color(0xFFEAF0FB);
  static const textMutedDark = Color(0xFF9AA6BD);
  static const textLight = Color(0xFF0F172A);
  static const textMutedLight = Color(0xFF64748B);

  static LinearGradient appBackground(bool dark) {
    return dark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgDark, bgDark2, bgDark3],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgLight, Colors.white, pageLight],
          );
  }

  static LinearGradient accentGradient(Color color) {
    if (color == success || color == cGreen) {
      return const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF34D399)]);
    }
    if (color == warning || color == cOrange) {
      return const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]);
    }
    if (color == danger || color == cRed) {
      return const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFF87171)]);
    }
    if (color == purple) {
      return const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)]);
    }
    if (color == teal) {
      return const LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF14B8A6)]);
    }
    return const LinearGradient(colors: [accent, accent2]);
  }
}

class NewAnimatedShell extends StatelessWidget {
  const NewAnimatedShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: NewUi.appBackground(isDark)))),
        Positioned(
          top: -120,
          left: -70,
          child: _GlowBlob(color: NewUi.accent.withAlpha(isDark ? 45 : 22), size: 260),
        ),
        Positioned(
          right: -90,
          bottom: 80,
          child: _GlowBlob(color: NewUi.accent2.withAlpha(isDark ? 30 : 18), size: 240),
        ),
        child,
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
        child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ),
    );
  }
}

class NewGlassCard extends StatefulWidget {
  const NewGlassCard({super.key, required this.child, this.padding, this.margin, this.onTap, this.highlightColor});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? highlightColor;

  @override
  State<NewGlassCard> createState() => _NewGlassCardState();
}

class _NewGlassCardState extends State<NewGlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.highlightColor ?? NewUi.accent;
    final card = GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: double.infinity,
              margin: widget.margin,
              padding: widget.padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.white.withAlpha(238),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: widget.highlightColor != null ? color.withAlpha(80) : isDark ? Colors.white.withAlpha(18) : const Color(0xFFE5EAF1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(isDark ? 70 : 20), blurRadius: 26, offset: const Offset(0, 12)),
                  if (widget.highlightColor != null) BoxShadow(color: color.withAlpha(isDark ? 24 : 14), blurRadius: 24),
                ],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    return card;
  }
}

class NewSectionTitle extends StatelessWidget {
  const NewSectionTitle({super.key, required this.title, required this.icon, this.action});

  final String title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NewUi.accent2),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4))),
          ?action,
        ],
      ),
    );
  }
}

class NewPulseDot extends StatefulWidget {
  const NewPulseDot({super.key, this.color = NewUi.success, this.size = 6});

  final Color color;
  final double size;

  @override
  State<NewPulseDot> createState() => _NewPulseDotState();
}

class _NewPulseDotState extends State<NewPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          width: widget.size + (t * 7),
          height: widget.size + (t * 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withAlpha(((1 - t) * 70).round())),
          child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
        );
      },
    );
  }
}

class NewPill extends StatelessWidget {
  const NewPill({super.key, required this.text, this.icon, this.color, this.pulse = false});

  final String text;
  final IconData? icon;
  final Color? color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final c = color ?? NewUi.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(99), border: Border.all(color: c.withAlpha(65))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse) ...[
            NewPulseDot(color: c, size: 5),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 5),
          ],
          Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.1)),
        ],
      ),
    );
  }
}

class NewActionButton extends StatelessWidget {
  const NewActionButton({super.key, required this.text, required this.onTap, this.icon, this.primary = true, this.enabled = true, this.color});

  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? NewUi.accent;
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: primary ? NewUi.accentGradient(c) : null,
            color: primary ? null : Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(12) : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: primary ? Colors.transparent : c.withAlpha(55)),
            boxShadow: primary ? [BoxShadow(color: c.withAlpha(70), blurRadius: 16, offset: const Offset(0, 7))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: primary ? Colors.white : c),
                const SizedBox(width: 8),
              ],
              Text(text, style: TextStyle(color: primary ? Colors.white : c, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -0.1)),
            ],
          ),
        ),
      ),
    );
  }
}

class NewRingPainter extends CustomPainter {
  NewRingPainter({required this.progress, required this.breakProgress, required this.statusColor, required this.dark, required this.pulse});

  final double progress;
  final double breakProgress;
  final Color statusColor;
  final bool dark;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 12;
    const start = math.pi * 1.28;
    const sweep = math.pi * 1.44;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = dark ? Colors.white.withAlpha(18) : const Color(0xFFE7ECF4);
    final work = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF34D399)]).createShader(Rect.fromCircle(center: center, radius: radius));
    final breakPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]).createShader(Rect.fromCircle(center: center, radius: radius));
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 + pulse * 4
      ..strokeCap = StrokeCap.round
      ..color = statusColor.withAlpha((40 + pulse * 70).round());
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, start, sweep, false, track);
    canvas.drawArc(rect, start, sweep * progress.clamp(0, 1), false, pulsePaint);
    canvas.drawArc(rect, start, sweep * progress.clamp(0, 1), false, work);
    if (breakProgress > 0) canvas.drawArc(rect, start + (sweep * 0.46), sweep * breakProgress.clamp(0, 0.26), false, breakPaint);

    final dotPaint = Paint()..color = dark ? Colors.white.withAlpha(22) : const Color(0xFFCBD5E1);
    final activePaint = Paint()..color = NewUi.accent2;
    for (int i = 0; i < 60; i++) {
      final a = start + (sweep / 59) * i;
      final p = Offset(center.dx + math.cos(a) * (radius - 24), center.dy + math.sin(a) * (radius - 24));
      canvas.drawCircle(p, 2, i / 59 <= progress ? activePaint : dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant NewRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.breakProgress != breakProgress || oldDelegate.statusColor != statusColor || oldDelegate.pulse != pulse || oldDelegate.dark != dark;
  }
}

class NewEmptyState extends StatelessWidget {
  const NewEmptyState({super.key, required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return NewGlassCard(
      child: Column(
        children: [
          Icon(icon, size: 34, color: NewUi.accent2),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NewUi.textMutedLight)),
        ],
      ),
    );
  }
}

IconData newIcon(String key) {
  switch (key) {
    case 'clock':
      return Icons.access_time_rounded;
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'coffee':
      return Icons.coffee_rounded;
    case 'patrol':
      return Icons.location_on_rounded;
    case 'dar':
      return Icons.description_rounded;
    case 'incident':
      return Icons.report_rounded;
    case 'parking':
      return Icons.local_parking_rounded;
    case 'people':
      return Icons.groups_rounded;
    case 'home':
      return Icons.home_work_rounded;
    case 'tasks':
      return Icons.task_alt_rounded;
    case 'manual':
      return Icons.menu_book_rounded;
    case 'fire':
      return Icons.local_fire_department_rounded;
    case 'bell':
      return Icons.notifications_rounded;
    case 'message':
      return Icons.chat_bubble_rounded;
    case 'calendar':
      return Icons.calendar_month_rounded;
    case 'check':
      return Icons.verified_rounded;
    default:
      return Icons.apps_rounded;
  }
}

Color newColor(String key) {
  switch (key) {
    case 'blue':
      return NewUi.accent;
    case 'amber':
      return NewUi.warning;
    case 'purple':
      return NewUi.purple;
    case 'teal':
      return NewUi.teal;
    case 'red':
      return NewUi.danger;
    case 'pink':
      return const Color(0xFFEC4899);
    case 'green':
      return NewUi.success;
    default:
      return const Color(0xFF64748B);
  }
}
