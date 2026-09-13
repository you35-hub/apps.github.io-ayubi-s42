import 'dart:math' as math;
import 'package:flutter/material.dart';

enum OrbState { idle, listening, thinking, speaking }

class Orb3D extends StatefulWidget {
  final OrbState state;
  final double size;
  const Orb3D({super.key, this.state = OrbState.idle, this.size = 50});

  @override
  State<Orb3D> createState() => _Orb3DState();
}

class _Orb3DState extends State<Orb3D>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _primary {
    switch (widget.state) {
      case OrbState.listening:
        return const Color(0xFF7C4DFF);
      case OrbState.thinking:
        return const Color(0xFFFF4081);
      case OrbState.speaking:
        return const Color(0xFF00E676);
      case OrbState.idle:
        return const Color(0xFF00E5FF);
    }
  }

  Color get _secondary {
    switch (widget.state) {
      case OrbState.listening:
        return const Color(0xFFB388FF);
      case OrbState.thinking:
        return const Color(0xFFFF80AB);
      case OrbState.speaking:
        return const Color(0xFF69F0AE);
      case OrbState.idle:
        return const Color(0xFF7C4DFF);
    }
  }

  double get _speed {
    switch (widget.state) {
      case OrbState.listening:
        return 2.5;
      case OrbState.thinking:
        return 4.0;
      case OrbState.speaking:
        return 2.0;
      case OrbState.idle:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _OrbPainter(
            progress: (_controller.value * _speed) % 1.0,
            primary: _primary,
            secondary: _secondary,
            state: widget.state,
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final OrbState state;

  _OrbPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withOpacity(0.4),
          primary.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glowPaint);

    // Wireframe sphere
    final lines = 12;
    final wirePaint = Paint()
      ..color = primary.withOpacity(0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Horizontal circles (like latitude lines)
    for (int i = 1; i < lines; i++) {
      final angle = (i / lines) * math.pi;
      final r = radius * 0.7 * math.sin(angle);
      final y = center.dy + radius * 0.7 * math.cos(angle);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx, y),
          width: r * 2,
          height: r * 0.4,
        ),
        wirePaint,
      );
    }

    // Vertical circles (like longitude lines) - rotating
    for (int i = 0; i < lines; i++) {
      final angle = (i / lines) * math.pi + progress * math.pi * 2;
      final r = radius * 0.7 * math.sin(angle).abs();
      final x = center.dx + radius * 0.7 * math.cos(angle);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, center.dy),
          width: r * 0.5,
          height: r * 2,
        ),
        wirePaint,
      );
    }

    // Core circle
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [primary, secondary],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.4));
    canvas.drawCircle(center, radius * 0.35, corePaint);

    // Orbital ring
    final ringPaint = Paint()
      ..color = secondary.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 1.8,
        height: radius * 0.6,
      ),
      ringPaint,
    );
    canvas.restore();

    // Second ring
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-progress * math.pi * 2 + math.pi / 3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 0.6,
        height: radius * 1.8,
      ),
      ringPaint,
    );
    canvas.restore();

    // Particles
    final particlePaint = Paint()..color = primary.withOpacity(0.8);
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2 + progress * math.pi * 2;
      final distance = radius * (0.9 + 0.15 * math.sin(i + progress * 10));
      final x = center.dx + math.cos(angle) * distance;
      final y = center.dy + math.sin(angle) * distance;
      canvas.drawCircle(Offset(x, y), 1.5, particlePaint);
    }

    // Wave rings when speaking/listening
    if (state == OrbState.speaking || state == OrbState.listening) {
      final wavePaint = Paint()
        ..color = primary.withOpacity(0.3)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < 3; i++) {
        final waveProgress = (progress * 3 + i * 0.33) % 1.0;
        final waveRadius = radius * (0.5 + waveProgress);
        canvas.drawCircle(
          center,
          waveRadius,
          wavePaint..color = primary.withOpacity((1 - waveProgress) * 0.4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.progress != progress || old.state != state;
}