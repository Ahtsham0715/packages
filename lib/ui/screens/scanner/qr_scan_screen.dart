import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';

/// Scans an `otpauth://` QR code and returns its text.
///
/// The camera feed is never stored, never written to a file, and never leaves
/// this screen — the app has no network permission to send it anywhere even if
/// something tried.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Autofocus only; no torch by default, which would be startling when the
    // screen opens.
    facing: CameraFacing.back,
  );

  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Scan setup code'),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
            tooltip: 'Torch',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xxl),
                child: EmptyState(
                  icon: Icons.no_photography_rounded,
                  title: 'The camera is unavailable',
                  message: _messageFor(error),
                  action: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Enter the key by hand instead'),
                  ),
                ),
              ),
            ),
          ),
          const _ScanReticle(),
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.huge,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.md,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Text(
                  'Point the camera at the QR code',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _messageFor(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Sablekey needs camera access to read a QR code. You can grant it in '
            'system settings, or type the setup key in by hand.',
      MobileScannerErrorCode.unsupported =>
        'This device cannot scan QR codes.',
      _ => 'The camera could not be started.',
    };
  }
}

/// A framing square with ember corners.
class _ScanReticle extends StatelessWidget {
  const _ScanReticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: CustomPaint(painter: _ReticlePainter()),
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SableColors.emberBright
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const arm = 28.0;
    final w = size.width;
    final h = size.height;

    // Four corner brackets rather than a full box: the code has to sit inside
    // them, and a solid frame hides part of what the camera sees.
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, arm)
          ..lineTo(0, 0)
          ..lineTo(arm, 0),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w - arm, 0)
          ..lineTo(w, 0)
          ..lineTo(w, arm),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w, h - arm)
          ..lineTo(w, h)
          ..lineTo(w - arm, h),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(arm, h)
          ..lineTo(0, h)
          ..lineTo(0, h - arm),
        paint,
      );
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => false;
}
