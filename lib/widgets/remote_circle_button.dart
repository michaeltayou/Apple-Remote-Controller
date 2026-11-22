import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Circular remote-control button with tactile press feedback:
/// a visible white splash plus a scale-down animation while pressed
/// (the button stays visually "pressed" while hold-to-repeat is firing).
///
/// Modes:
/// - plain tap (default): [onPressed] fires on pointer down.
/// - [repeat]: [onPressed] fires on pointer down, then repeats at
///   [repeatInterval] after [repeatDelay] until released.
/// - [onLongPress]: [onPressed] fires on release if the press was short;
///   holding >= 500 ms fires [onLongPress] instead (e.g. Home vs top menu).
class RemoteCircleButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool repeat;
  final Duration repeatDelay;
  final Duration repeatInterval;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;

  const RemoteCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.repeat = false,
    this.repeatDelay = const Duration(milliseconds: 450),
    this.repeatInterval = const Duration(milliseconds: 150),
    this.size = 64,
    this.iconSize = 26,
    this.color = AppColors.button,
    this.iconColor = AppColors.text,
  });

  @override
  State<RemoteCircleButton> createState() => _RemoteCircleButtonState();
}

class _RemoteCircleButtonState extends State<RemoteCircleButton> {
  static const _longPressDelay = Duration(milliseconds: 500);

  Timer? _delayTimer;
  Timer? _repeatTimer;
  Timer? _longPressTimer;
  bool _longFired = false;
  bool _pressed = false;

  void _onPointerDown(PointerDownEvent _) {
    setState(() => _pressed = true);
    if (widget.onLongPress != null) {
      // Defer the tap action: short press = onPressed on release,
      // long press = onLongPress.
      _longPressTimer = Timer(_longPressDelay, () {
        _longFired = true;
        HapticFeedback.mediumImpact();
        widget.onLongPress!();
      });
    } else {
      HapticFeedback.lightImpact();
      widget.onPressed();
      if (widget.repeat) {
        _delayTimer = Timer(widget.repeatDelay, () {
          _repeatTimer =
              Timer.periodic(widget.repeatInterval, (_) => widget.onPressed());
        });
      }
    }
  }

  void _onRelease([Object? _]) {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _longPressTimer?.cancel();
    _delayTimer = null;
    _repeatTimer = null;
    _longPressTimer = null;
    if (widget.onLongPress != null && !_longFired) {
      HapticFeedback.lightImpact();
      widget.onPressed();
    }
    _longFired = false;
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onRelease,
      onPointerCancel: (_) => _onRelease(),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Material(
          color: widget.color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            // Empty tap enables the splash visuals; press/repeat logic is
            // handled by the Listener above (pointer events don't compete
            // in the gesture arena, so release detection is reliable).
            onTap: () {},
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Icon(widget.icon,
                  size: widget.iconSize, color: widget.iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
