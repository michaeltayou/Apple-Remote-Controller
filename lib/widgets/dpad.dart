import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Tactile directional pad: Up / Down / Left / Right + center Select.
///
/// The four arrow buttons support hold-to-repeat: pressing sends one command,
/// keeping the finger down repeats it (~7/sec) until released — like holding
/// a button on the real Siri Remote. The center Select button is tap-only.
class DPad extends StatelessWidget {
  final void Function(String command) onCommand;

  const DPad({super.key, required this.onCommand});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          const SizedBox.shrink(),
          _ArrowButton(icon: Icons.keyboard_arrow_up, command: 'up', onCommand: onCommand),
          const SizedBox.shrink(),
          _ArrowButton(icon: Icons.keyboard_arrow_left, command: 'left', onCommand: onCommand),
          _selectButton(),
          _ArrowButton(icon: Icons.keyboard_arrow_right, command: 'right', onCommand: onCommand),
          const SizedBox.shrink(),
          _ArrowButton(icon: Icons.keyboard_arrow_down, command: 'down', onCommand: onCommand),
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _selectButton() => Material(
        color: AppColors.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.lightImpact();
            onCommand('select');
          },
          child: const Center(
            child: Icon(Icons.circle, size: 22, color: Colors.white),
          ),
        ),
      );
}

class _ArrowButton extends StatefulWidget {
  final IconData icon;
  final String command;
  final void Function(String command) onCommand;

  /// Delay before repeating starts (ms).
  static const repeatDelay = Duration(milliseconds: 450);

  /// Interval between repeated commands.
  static const repeatInterval = Duration(milliseconds: 140);

  const _ArrowButton({
    required this.icon,
    required this.command,
    required this.onCommand,
  });

  @override
  State<_ArrowButton> createState() => _ArrowButtonState();
}

class _ArrowButtonState extends State<_ArrowButton> {
  Timer? _delayTimer;
  Timer? _repeatTimer;

  void _startRepeat() {
    _repeatTimer = Timer.periodic(_ArrowButton.repeatInterval, (_) {
      widget.onCommand(widget.command);
    });
  }

  void _onTapDown(TapDownDetails _) {
    HapticFeedback.lightImpact();
    widget.onCommand(widget.command);
    _delayTimer = Timer(_ArrowButton.repeatDelay, _startRepeat);
  }

  void _onTapUp([Object? _]) {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _delayTimer = null;
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _onTapUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: () => _onTapUp(),
      child: Material(
        color: AppColors.button,
        shape: const CircleBorder(),
        child: Center(child: Icon(widget.icon, size: 34, color: AppColors.text)),
      ),
    );
  }
}
