import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

class ScannerPage extends StatefulWidget {
  final Function(String) onDetect;

  const ScannerPage({super.key, required this.onDetect});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool detectado = false;

  final double scanWidth = 320;
  final double scanHeight = 180;

  void tratarCodigo(Code result) {
    if (detectado) return;

    final codigo = result.text?.trim() ?? '';

    if (!result.isValid || codigo.isEmpty) {
      return;
    }

    setState(() {
      detectado = true;
    });

    Navigator.pop(context);
    widget.onDetect(codigo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ReaderWidget(
            onScan: tratarCodigo,
            codeFormat: Format.any,
            tryHarder: true,
            tryInverted: true,
            tryRotate: true,
            showScannerOverlay: false,
            showGallery: false,
            showToggleCamera: false,
            showFlashlight: true,
            allowPinchZoom: true,
            cropPercent: 0.62,
            scanDelay: const Duration(milliseconds: 350),
            scanDelaySuccess: const Duration(milliseconds: 1200),
            actionButtonsAlignment: Alignment.topRight,
            actionButtonsPadding: const EdgeInsets.only(top: 42, right: 14),
            actionButtonsBackgroundColor: Colors.black.withValues(alpha: 0.55),
            loading: const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),

          Container(
            decoration: ShapeDecoration(
              shape: ScannerOverlay(
                scanWidth: scanWidth,
                scanHeight: scanHeight,
              ),
            ),
          ),

          Center(
            child: Container(
              width: scanWidth,
              height: scanHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      height: 3,
                      width: scanWidth - 30,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).size.height / 2 + 110,
            left: 20,
            right: 20,
            child: const Text(
              'Aponte o código de barras dentro do retângulo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlay extends ShapeBorder {
  final double scanWidth;
  final double scanHeight;

  const ScannerOverlay({required this.scanWidth, required this.scanHeight});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final center = rect.center;

    final scanRect = Rect.fromCenter(
      center: center,
      width: scanWidth,
      height: scanHeight,
    );

    return Path()
      ..addRect(rect)
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(14)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final center = rect.center;

    final scanRect = Rect.fromCenter(
      center: center,
      width: scanWidth,
      height: scanHeight,
    );

    final outerPath = Path()..addRect(rect);

    final innerPath = Path()
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(14)));

    canvas.drawPath(
      Path.combine(PathOperation.difference, outerPath, innerPath),
      paint,
    );
  }

  @override
  ShapeBorder scale(double t) => this;
}
