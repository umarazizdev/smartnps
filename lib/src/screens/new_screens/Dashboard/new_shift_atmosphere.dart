import 'dart:math' as math;
import 'package:flutter/material.dart';

enum NewShiftScene { morning, afternoon, evening, graveyard }

NewShiftScene newShiftSceneForHour(int hour) {
  if (hour >= 5 && hour < 11) return NewShiftScene.morning;
  if (hour >= 11 && hour < 17) return NewShiftScene.afternoon;
  if (hour >= 17 && hour < 21) return NewShiftScene.evening;
  return NewShiftScene.graveyard;
}

class NewShiftAtmospherePainter extends CustomPainter {
  NewShiftAtmospherePainter({
    required Animation<double> motion,
    required this.scene,
    required this.isDark,
  })  : _motion = motion,
        super(repaint: motion);

  final Animation<double> _motion;
  final NewShiftScene scene;
  final bool isDark;

  static const _slate = Color(0xFF7FA5CA);
  static const _nightBlue = Color(0xFFAACCF1);
  static const _gold = Color(0xFFE7B16A);
  static const _coral = Color(0xFFDB9E8B);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final t = _motion.value * 2 * math.pi;
    final width = size.width;
    final height = size.height;
    final shortSide = math.min(width, height);
    final center = Offset(width / 2, height / 2);

    canvas.save();
    final bounds = Path()..addRect(Offset.zero & size);
    final protectedDial = Path()
      ..addOval(Rect.fromCircle(center: center, radius: shortSide * .476));
    canvas.clipPath(
      Path.combine(PathOperation.difference, bounds, protectedDial),
    );

    switch (scene) {
      case NewShiftScene.morning:
        _morning(canvas, size, t);
        break;
      case NewShiftScene.afternoon:
        _afternoon(canvas, size, t);
        break;
      case NewShiftScene.evening:
        _evening(canvas, size, t);
        break;
      case NewShiftScene.graveyard:
        _night(canvas, size, t);
        break;
    }
    canvas.restore();
  }

  void _morning(Canvas canvas, Size s, double t) {
    final sun = _position(s, .15, .19) + Offset(0, math.sin(t) * 2.5);
    _halo(canvas, sun, 71, _gold, isDark ? .085 : .075);
    _sun(canvas, sun, 15, t, _gold, isDark ? .51 : .60);
    _cloud(
      canvas,
      _position(s, .89, .23) + Offset(math.sin(t + .7) * 9, 0),
      .76,
      _slate,
      isDark ? .28 : .23,
    );
    _cloud(
      canvas,
      _position(s, .11, .80) + Offset(math.sin(t + 2.2) * 8, 2),
      .55,
      _slate,
      isDark ? .18 : .16,
    );
    _motes(canvas, s, t, _gold, isDark ? .36 : .30);
  }

  void _afternoon(Canvas canvas, Size s, double t) {
    final sun = _position(s, .86, .19) + Offset(math.cos(t) * 2, math.sin(t) * 2);
    _halo(canvas, sun, 78, _gold, isDark ? .065 : .075);
    _sun(canvas, sun, 17, t * .7, _gold, isDark ? .48 : .55);
    _cloud(
      canvas,
      _position(s, .11, .23) + Offset(math.sin(t) * 10, math.cos(t) * 1.5),
      .83,
      _slate,
      isDark ? .29 : .24,
    );
    _cloud(
      canvas,
      _position(s, .88, .83) + Offset(math.cos(t + 1.2) * 10, 0),
      .63,
      _slate,
      isDark ? .21 : .17,
    );
    _motes(canvas, s, t + 1.8, _slate, isDark ? .30 : .24);
  }

  void _evening(Canvas canvas, Size s, double t) {
    final sunset = _position(s, .84, .80) + Offset(math.sin(t) * 3, 0);
    _halo(canvas, sunset, 80, _coral, isDark ? .095 : .075);
    _sun(canvas, sunset, 18, t * .18, _coral, isDark ? .48 : .53, rays: false);
    _horizon(canvas, sunset, _coral, isDark ? .30 : .25, t);
    _cloud(
      canvas,
      _position(s, .12, .18) + Offset(math.sin(t + .7) * 8, 0),
      .78,
      _slate,
      isDark ? .28 : .22,
    );
    _cloud(
      canvas,
      _position(s, .11, .81) + Offset(math.sin(t + 1.6) * 7, 0),
      .55,
      _coral,
      isDark ? .23 : .18,
    );
    _motes(canvas, s, t, _coral, isDark ? .22 : .17);
  }

  void _night(Canvas canvas, Size s, double t) {
    final moon = _position(s, .85, .19) + Offset(0, math.sin(t) * 2.6);
    _halo(canvas, moon, 69, _nightBlue, isDark ? .09 : .06);
    _moon(canvas, moon, 17, _nightBlue, isDark ? .62 : .52);

    const locations = <Offset>[
      Offset(.13, .15), Offset(.28, .06), Offset(.92, .33),
      Offset(.10, .66), Offset(.17, .87), Offset(.86, .82),
      Offset(.96, .68), Offset(.73, .94), Offset(.07, .43),
    ];
    for (var i = 0; i < locations.length; i++) {
      final p = _position(s, locations[i].dx, locations[i].dy);
      final twinkle = .55 + .45 * math.sin(t * (2.2 + (i % 3) * .45) + i * 1.34);
      final alpha = (isDark ? .58 : .45) * twinkle;
      _star(canvas, p, i.isEven ? 3.4 : 1.9, _nightBlue, alpha);
    }

    final phase = _motion.value;
    if (phase > .73 && phase < .78) {
      final progress = (phase - .73) / .05;
      final opacity = math.sin(progress * math.pi) * (isDark ? .24 : .15);
      final start = _position(s, .11 + progress * .14, .24 + progress * .05);
      final end = start + const Offset(15, -8);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = _nightBlue.withAlpha(_alpha(opacity))
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
    _cloud(
      canvas,
      _position(s, .11, .83) + Offset(math.sin(t) * 6, 0),
      .44,
      _slate,
      isDark ? .12 : .10,
    );
  }

  Offset _position(Size s, double x, double y) =>
      Offset(s.width * x, s.height * y);

  int _alpha(double opacity) => (opacity.clamp(0.0, 1.0) * 255).round();

  void _halo(Canvas canvas, Offset at, double radius, Color color, double opacity) {
    final area = Rect.fromCircle(center: at, radius: radius);
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withAlpha(_alpha(opacity)),
            color.withAlpha(0),
          ],
        ).createShader(area),
    );
  }

  void _sun(
    Canvas canvas,
    Offset at,
    double radius,
    double phase,
    Color color,
    double opacity, {
    bool rays = true,
  }) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (rays) {
      canvas.rotate(phase * .12);
      final ray = Paint()
        ..color = color.withAlpha(_alpha(opacity * .58))
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(
          Offset(math.cos(a) * (radius + 7), math.sin(a) * (radius + 7)),
          Offset(math.cos(a) * (radius + 13), math.sin(a) * (radius + 13)),
          ray,
        );
      }
    }
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = color.withAlpha(_alpha(opacity * .18)),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .74,
      Paint()..color = color.withAlpha(_alpha(opacity)),
    );
    canvas.restore();
  }

  void _moon(Canvas canvas, Offset at, double radius, Color color, double opacity) {
    final outside = Path()..addOval(Rect.fromCircle(center: at, radius: radius));
    final cutout = Path()
      ..addOval(Rect.fromCircle(
        center: at + Offset(radius * .46, -radius * .38),
        radius: radius * .90,
      ));
    final crescent = Path.combine(PathOperation.difference, outside, cutout);
    canvas.drawPath(
      crescent,
      Paint()..color = color.withAlpha(_alpha(opacity)),
    );
  }

  void _cloud(Canvas canvas, Offset at, double scale, Color color, double opacity) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(scale);
    final cloud = Path()
      ..moveTo(-35, 11)
      ..cubicTo(-46, 10, -46, -5, -31, -8)
      ..cubicTo(-26, -25, -9, -28, 0, -16)
      ..cubicTo(10, -28, 27, -19, 27, -8)
      ..cubicTo(45, -8, 48, 13, 31, 13)
      ..lineTo(-35, 13)
      ..close();
    canvas.drawPath(
      cloud,
      Paint()..color = color.withAlpha(_alpha(opacity)),
    );
    canvas.drawPath(
      cloud,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withAlpha(_alpha(opacity * .48)),
    );
    canvas.restore();
  }

  void _horizon(Canvas canvas, Offset at, Color color, double opacity, double t) {
    final line = Paint()
      ..color = color.withAlpha(_alpha(opacity))
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = at.dy + 23 + i * 7;
      final spread = 15.0 + (2 - i) * 5 + math.sin(t + i) * 2;
      canvas.drawLine(
        Offset(at.dx - spread, y),
        Offset(at.dx + spread, y),
        line,
      );
    }
  }

  void _star(Canvas canvas, Offset center, double radius, Color color, double opacity) {
    final p = Paint()
      ..color = color.withAlpha(_alpha(opacity))
      ..strokeCap = StrokeCap.round;
    if (radius < 2.5) {
      canvas.drawCircle(center, radius * .76, p);
      return;
    }
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx + radius * .22, center.dy - radius * .22,
          center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx + radius * .22, center.dy + radius * .22,
          center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx - radius * .22, center.dy + radius * .22,
          center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx - radius * .22, center.dy - radius * .22,
          center.dx, center.dy - radius)
      ..close();
    canvas.drawPath(path, p);
  }

  void _motes(Canvas canvas, Size s, double t, Color color, double opacity) {
    const points = <Offset>[
      Offset(.07, .35), Offset(.92, .47), Offset(.92, .70), Offset(.13, .94),
      Offset(.77, .07), Offset(.06, .58),
    ];
    for (var i = 0; i < points.length; i++) {
      final phase = t + i * 1.42;
      final position = _position(s, points[i].dx, points[i].dy) +
          Offset(math.cos(phase) * 3, math.sin(phase) * 4);
      final alpha = opacity * (.5 + math.sin(phase * 1.4) * .24);
      canvas.drawCircle(
        position,
        i.isEven ? 1.7 : 1.2,
        Paint()..color = color.withAlpha(_alpha(alpha)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant NewShiftAtmospherePainter oldDelegate) =>
      scene != oldDelegate.scene ||
      isDark != oldDelegate.isDark ||
      _motion != oldDelegate._motion;
}
