import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Drag-to-seek strip: drag right to move forward, left to move backward.
/// Every [_pxPerStep] of drag fires one ±[_stepSeconds]s seek (with a haptic
/// tick) and the accumulated offset is shown while dragging — like scrubbing
/// through the video. Works in any app (system-level seek commands).
class ScrubBar extends StatefulWidget {
  final void Function(String command) onCommand;

  const ScrubBar({super.key, required this.onCommand});

  @override
  State<ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<ScrubBar> {
  static const _pxPerStep = 48.0;
  static const _stepSeconds = 10;
  static const _minStepInterval = Duration(milliseconds: 200);

  double _accumulated = 0;
  int _offsetSeconds = 0;
  bool _dragging = false;
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);

  void _onDragStart(DragStartDetails _) {
    setState(() {
      _dragging = true;
      _offsetSeconds = 0;
      _accumulated = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _accumulated += details.delta.dx;
    while (_accumulated.abs() >= _pxPerStep) {
      final now = DateTime.now();
      if (now.difference(_lastStep) < _minStepInterval) break; // throttle
      final forward = _accumulated > 0;
      widget.onCommand(forward ? 'skip_forward' : 'skip_backward');
      HapticFeedback.selectionClick();
      _lastStep = now;
      _accumulated -= forward ? _pxPerStep : -_pxPerStep;
      setState(() {
        _offsetSeconds += forward ? _stepSeconds : -_stepSeconds;
      });
    }
  }

  void _onDragEnd(DragEndDetails _) => _reset();
  void _onDragCancel() => _reset();

  void _reset() {
    setState(() {
      _dragging = false;
      _accumulated = 0;
    });
    // Keep the final offset visible briefly, then clear it.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && !_dragging) setState(() => _offsetSeconds = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sign = _offsetSeconds >= 0 ? '+' : '−';
    final magnitude = _offsetSeconds.abs();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.button,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _dragging ? AppColors.accent : AppColors.buttonPressed,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Icon(Icons.fast_rewind,
                  color: AppColors.textDim, size: 22),
            ),
            Text(
              _dragging || _offsetSeconds != 0
                  ? '$sign$magnitude s'
                  : 'Drag to seek',
              style: TextStyle(
                fontSize: _dragging ? 20 : 14,
                fontWeight: _dragging ? FontWeight.w700 : FontWeight.w400,
                color: _dragging ? AppColors.accent : AppColors.textDim,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child:
                  Icon(Icons.fast_forward, color: AppColors.textDim, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
