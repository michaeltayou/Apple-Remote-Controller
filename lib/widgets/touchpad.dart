import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Swipe gesture touchpad: swipe to move the focus on the Apple TV,
/// tap to select (like the Siri Remote touch surface).
class Touchpad extends StatefulWidget {
  final void Function(String command) onCommand;

  const Touchpad({super.key, required this.onCommand});

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad> {
  static const _threshold = 48.0;

  double _dx = 0;
  double _dy = 0;

  void _send(String command) {
    HapticFeedback.lightImpact();
    widget.onCommand(command);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _dx += details.delta.dx;
    _dy += details.delta.dy;
    if (_dx.abs() >= _threshold || _dy.abs() >= _threshold) {
      // Send one direction per swipe step, based on the dominant axis.
      if (_dx.abs() > _dy.abs()) {
        _send(_dx > 0 ? 'right' : 'left');
      } else {
        _send(_dy > 0 ? 'down' : 'up');
      }
      _dx = 0;
      _dy = 0;
    }
  }

  void _onPanEnd(DragEndDetails _) {
    _dx = 0;
    _dy = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        color: AppColors.button,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.buttonPressed, width: 2),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: () => _send('select'),
        child: const Center(
          child: Icon(
            Icons.touch_app_outlined,
            size: 40,
            color: AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
