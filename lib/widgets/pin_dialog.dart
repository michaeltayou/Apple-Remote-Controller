import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Asks the user for the 4-digit pairing PIN currently displayed on the TV.
/// Returns the PIN, or null if the user cancelled.
Future<String?> showPinDialog(
  BuildContext context, {
  required String deviceName,
  required String protocol,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        PinDialog(deviceName: deviceName, protocol: protocol),
  );
}

class PinDialog extends StatefulWidget {
  final String deviceName;
  final String protocol;

  const PinDialog({
    super.key,
    required this.deviceName,
    required this.protocol,
  });

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.length != 4 || _submitting) return;
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    final pin = _controller.text;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Pair with ${widget.deviceName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A 4-digit PIN is displayed on your TV screen '
            '(${widget.protocol} pairing). Enter it below.',
            style: const TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 12),
            decoration: const InputDecoration(
              hintText: '••••',
              counterText: '',
              filled: true,
              fillColor: AppColors.button,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              if (value.length == 4) _submit();
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pair'),
        ),
      ],
    );
  }
}
