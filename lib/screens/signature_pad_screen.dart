import 'package:flutter/material.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<Offset?> _points = [];

  void _undoLastStroke() {
    setState(() {
      if (_points.isEmpty) return;
      if (_points.last == null) {
        _points.removeLast();
      }
      while (_points.isNotEmpty && _points.last != null) {
        _points.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Add Signature'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _points.isEmpty ? null : _undoLastStroke,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _points.isEmpty
                ? null
                : () => setState(() => _points.clear()),
            tooltip: 'Clear All',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                final List<Offset> validPoints = _points
                    .where((p) => p != null)
                    .cast<Offset>()
                    .toList();
                if (validPoints.isNotEmpty) {
                  Navigator.pop(context, validPoints);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please draw your signature first'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 32, 16, 16),
              child: Text(
                'Please sign in the box below',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ).copyWith(bottom: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Signature line guidance
                      Positioned.fill(
                        child: CustomPaint(
                          painter: SignatureBackgroundPainter(),
                        ),
                      ),
                      // Gesture pad
                      Builder(
                        builder: (padContext) {
                          return GestureDetector(
                            onPanUpdate: (DragUpdateDetails details) {
                              setState(() {
                                RenderBox renderBox =
                                    padContext.findRenderObject() as RenderBox;
                                _points.add(
                                  renderBox.globalToLocal(
                                    details.globalPosition,
                                  ),
                                );
                              });
                            },
                            onPanEnd: (DragEndDetails details) {
                              setState(() {
                                _points.add(null);
                              });
                            },
                            child: CustomPaint(
                              painter: SignaturePainter(_points),
                              size: Size.infinite,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}

class SignatureBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw baseline
    final double y = size.height * 0.7;

    // Draw dashed line
    double dashWidth = 8, dashSpace = 8, startX = 20;
    while (startX < size.width - 20) {
      canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
      startX += dashWidth + dashSpace;
    }

    // Draw an 'X' to signify where to sign
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'X',
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(20, y - 28));
  }

  @override
  bool shouldRepaint(SignatureBackgroundPainter oldDelegate) => false;
}
