import 'package:flutter/material.dart';

import '../theme.dart';
import 'remote_circle_button.dart';

/// Tactile directional pad: Up / Down / Left / Right + center Select.
///
/// The four arrow buttons support hold-to-repeat (see [RemoteCircleButton]):
/// pressing moves one step, keeping the finger down repeats ~7/sec until
/// released — like holding a button on the real Siri Remote.
class DPad extends StatelessWidget {
  final void Function(String command) onCommand;

  const DPad({super.key, required this.onCommand});

  static const _arrowRepeat = Duration(milliseconds: 140);

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
          RemoteCircleButton(
            icon: Icons.keyboard_arrow_up,
            size: 80,
            iconSize: 34,
            repeat: true,
            repeatInterval: _arrowRepeat,
            onPressed: () => onCommand('up'),
          ),
          const SizedBox.shrink(),
          RemoteCircleButton(
            icon: Icons.keyboard_arrow_left,
            size: 80,
            iconSize: 34,
            repeat: true,
            repeatInterval: _arrowRepeat,
            onPressed: () => onCommand('left'),
          ),
          RemoteCircleButton(
            icon: Icons.circle,
            size: 80,
            iconSize: 22,
            color: AppColors.accent,
            iconColor: Colors.white,
            onPressed: () => onCommand('select'),
          ),
          RemoteCircleButton(
            icon: Icons.keyboard_arrow_right,
            size: 80,
            iconSize: 34,
            repeat: true,
            repeatInterval: _arrowRepeat,
            onPressed: () => onCommand('right'),
          ),
          const SizedBox.shrink(),
          RemoteCircleButton(
            icon: Icons.keyboard_arrow_down,
            size: 80,
            iconSize: 34,
            repeat: true,
            repeatInterval: _arrowRepeat,
            onPressed: () => onCommand('down'),
          ),
          const SizedBox.shrink(),
        ],
      ),
    );
  }
}
