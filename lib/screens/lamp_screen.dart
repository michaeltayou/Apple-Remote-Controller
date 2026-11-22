import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/lamp_controller.dart';
import '../theme.dart';
import '../widgets/remote_circle_button.dart';

/// Bedroom lamp controller (NodeMCU ESP8266, ESPHome native API).
///
/// Power toggle + brightness / color-temperature steps. The board only
/// knows physical button presses, so steps use hold-to-repeat — throttled
/// to >= 300 ms between presses as required by the device.
class LampScreen extends StatelessWidget {
  /// Repeat cadence for step buttons — within the device's ~3-4 calls/sec.
  static const _stepRepeat = Duration(milliseconds: 350);

  const LampScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lamp = context.watch<LampController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bedroom Lamp'),
        actions: [
          IconButton(
            tooltip: 'Refresh connection',
            icon: const Icon(Icons.refresh),
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            onPressed: lamp.ping,
          ),
          IconButton(
            tooltip: 'Lamp box settings',
            icon: const Icon(Icons.settings_outlined),
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            onPressed: () => _showSettings(context, lamp),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            _StatusHeader(lamp: lamp),
            const SizedBox(height: 24),
            Center(
              child: RemoteCircleButton(
                icon: Icons.lightbulb,
                size: 140,
                iconSize: 64,
                color: lamp.isOn ? AppColors.accent : AppColors.button,
                iconColor: lamp.isOn ? Colors.white : AppColors.text,
                onPressed: lamp.power,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                lamp.isOn ? 'On' : 'Off',
                style: const TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
            ),
            const SizedBox(height: 32),
            _StepRow(
              icon: Icons.brightness_6,
              label: 'Brightness',
              decreaseIcon: Icons.remove,
              increaseIcon: Icons.add,
              onDecrease: lamp.brightnessDown,
              onIncrease: lamp.brightnessUp,
            ),
            const SizedBox(height: 24),
            _StepRow(
              icon: Icons.thermostat,
              label: 'Warmth',
              decreaseIcon: Icons.wb_sunny_outlined,
              increaseIcon: Icons.wb_sunny,
              onDecrease: lamp.cooler,
              onIncrease: lamp.warmer,
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Brightness and warmth adjust in steps — hold a button to '
                'keep stepping. The board does not report levels back, so '
                'only on/off is shown.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettings(BuildContext context, LampController lamp) async {
    final controller = TextEditingController(text: lamp.host);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Lamp address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hostname or IP of the ESPHome lamp board on your Wi-Fi. '
              'mDNS (.local) names and plain IPs both work.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'lampe-chambre.local',
                filled: true,
                fillColor: AppColors.button,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await lamp.setHost(result);
    }
  }
}

class _StatusHeader extends StatelessWidget {
  final LampController lamp;

  const _StatusHeader({required this.lamp});

  @override
  Widget build(BuildContext context) {
    final (color, fallback) = switch (lamp.reachability) {
      LampReachability.online => (AppColors.online, 'Connected'),
      LampReachability.offline => (AppColors.offline, 'Unreachable'),
      LampReachability.unknown => (AppColors.textDim, 'Checking…'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lamp.statusMessage ?? fallback,
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData decreaseIcon;
  final IconData increaseIcon;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _StepRow({
    required this.icon,
    required this.label,
    required this.decreaseIcon,
    required this.increaseIcon,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RemoteCircleButton(
            icon: decreaseIcon,
            size: 56,
            repeat: true,
            repeatInterval: LampScreen._stepRepeat,
            onPressed: onDecrease,
          ),
          Column(
            children: [
              Icon(icon, color: AppColors.textDim, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style:
                      const TextStyle(color: AppColors.textDim, fontSize: 13)),
            ],
          ),
          RemoteCircleButton(
            icon: increaseIcon,
            size: 56,
            repeat: true,
            repeatInterval: LampScreen._stepRepeat,
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}
