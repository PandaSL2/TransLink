import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class BusMarkerGenerator {

  static Future<BitmapDescriptor> generateMarker({
    required String busNumber,
    required String routeName,
    required Color color,
    bool isLive = true,
    double scale = 1.0,
    double vibeOffset = 0.0,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = ui.Canvas(pictureRecorder);

    const size = ui.Size(240, 180);
    final center = Offset(size.width / 2, size.height / 2 + vibeOffset);

    if (isLive) {
      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(
          center.translate(0, 15),
          60 * scale,
          [color.withValues(alpha: 0.4), color.withValues(alpha: 0.0)],
        );
      canvas.drawCircle(center.translate(0, 15), 60 * scale, glowPaint);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.6 * scale);
      canvas.drawCircle(center.translate(0, 15), 45 * scale, ringPaint);
    }

    final shadowPath = Path()
      ..addOval(Rect.fromCenter(center: center.translate(5, 20), width: 120 * scale, height: 40 * scale));
    canvas.drawShadow(shadowPath, Colors.black, 10.0, true);

    final paint = Paint()..isAntiAlias = true;
    final busWidth = 50.0 * scale;
    final busHeight = 90.0 * scale;
    final busRect = Rect.fromCenter(center: center, width: busWidth, height: busHeight);
    final rRect = RRect.fromRectAndRadius(busRect, Radius.circular(8 * scale));

    paint.shader = ui.Gradient.linear(
      busRect.topCenter,
      busRect.bottomCenter,
      [color, color.withAlpha(200)],
    );
    canvas.drawRRect(rRect, paint);

    paint.shader = null;

    paint.color = Colors.white.withValues(alpha: 0.4);
    final windshieldRect = Rect.fromLTWH(
      busRect.left + 4 * scale,
      busRect.top + 6 * scale,
      busWidth - 8 * scale,
      12 * scale,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(windshieldRect, Radius.circular(2 * scale)), paint);

    paint.color = Colors.black.withValues(alpha: 0.1);
    canvas.drawRect(Rect.fromLTWH(busRect.left + 15 * scale, busRect.top + 30 * scale, busWidth - 30 * scale, 40 * scale), paint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: busNumber,
      style: GoogleFonts.outfit(
        fontSize: 22 * scale,
        fontWeight: FontWeight.w900,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
    textPainter.layout();

    textPainter.paint(canvas, center.translate(-textPainter.width / 2, -textPainter.height / 2 + 10 * scale));

    final arrowPath = Path()
      ..moveTo(center.dx, busRect.top - 5 * scale)
      ..lineTo(center.dx - 8 * scale, busRect.top + 5 * scale)
      ..lineTo(center.dx + 8 * scale, busRect.top + 5 * scale)
      ..close();
    paint.color = Colors.white;
    canvas.drawPath(arrowPath, paint);

    if (isLive) {
      final beaconPos = center.translate(0, -65 * scale);
      final beaconPaint = Paint()..color = Colors.white;
      canvas.drawCircle(beaconPos, 6 * scale, beaconPaint);
      beaconPaint.color = const Color(0xFF10B981);
      canvas.drawCircle(beaconPos, 4 * scale, beaconPaint);

      final beaconGlow = Paint()
        ..shader = ui.Gradient.radial(beaconPos, 12 * scale, [const Color(0xFF10B981).withValues(alpha: 0.5), Colors.transparent]);
      canvas.drawCircle(beaconPos, 12 * scale, beaconGlow);
    }

    final image = await pictureRecorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt()
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    if (data == null) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.bytes(data.buffer.asUint8List());
  }
}