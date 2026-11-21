import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/apple_tv_device.dart';
import '../state/remote_controller.dart';
import '../theme.dart';
import '../widgets/pin_dialog.dart';

/// Wi-Fi auto-discovery screen: lists Apple TVs found by pyatv.scan()
/// and drives the pairing flow (PIN shown on TV, entered here).
class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  Future<void> _onDeviceTap(
    BuildContext context,
    RemoteController controller,
    AppleTvDevice device,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    bool ok;
    if (await controller.hasCredentials(device.identifier)) {
      // Already paired — connect straight away.
      ok = await controller.connectTo(device.identifier);
    } else {
      // Not paired — the Apple TV will show a PIN on the TV screen.
      ok = await controller.pairAndConnect(
        device,
        (protocol) => showPinDialog(
          context,
          deviceName: device.name,
          protocol: protocol,
        ),
      );
    }
    // On success the root screen swaps to the remote automatically
    // (status becomes connected). Otherwise surface the failure.
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.statusMessage ?? 'Failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final scanning = controller.status == AtvStatus.scanning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apple TV Remote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: scanning ? null : controller.scan,
          ),
        ],
      ),
      body: _buildBody(context, controller, scanning),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RemoteController controller,
    bool scanning,
  ) {
    if (scanning && controller.devices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'Scanning for Apple TVs…',
              style: TextStyle(color: AppColors.textDim),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.scan,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                controller.statusMessage!,
                style: const TextStyle(color: AppColors.textDim),
              ),
            ),
            const SizedBox(height: 16),
          ],
          for (final device in controller.devices)
            _DeviceTile(
              device: device,
              onTap: () => _onDeviceTap(context, controller, device),
            ),
          if (controller.devices.isEmpty && !scanning)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  'No Apple TVs found.\n'
                  'Make sure your phone and Apple TV are on the same Wi-Fi, '
                  'then pull to refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim),
                ),
              ),
            ),
          if (scanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final AppleTvDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: AppColors.button,
          child: Icon(Icons.tv, color: AppColors.text),
        ),
        title: Text(device.name, style: const TextStyle(fontSize: 17)),
        subtitle: Text(
          device.infoLine,
          style: const TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
        onTap: onTap,
      ),
    );
  }
}
