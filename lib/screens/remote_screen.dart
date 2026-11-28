import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/remote_controller.dart';
import '../theme.dart';
import '../widgets/apps_sheet.dart';
import '../widgets/dpad.dart';
import '../widgets/keyboard_sheet.dart';
import '../widgets/remote_circle_button.dart';
import '../widgets/touchpad.dart';

/// Dark-mode remote control UI, modeled after the Siri Remote.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen>
    with WidgetsBindingObserver {
  bool _useTouchpad = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android may freeze the process (and silently kill the socket) while
    // backgrounded — probe/revive the link when the user comes back.
    if (state == AppLifecycleState.resumed) {
      context.read<RemoteController>().notifyForeground();
    }
  }

  void _press(RemoteController controller, String command) {
    controller.sendCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final device = controller.connectedDevice;

    final reconnecting = controller.status != AtvStatus.connected;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // The navigation area (touchpad/D-Pad) is FIXED, not scrollable:
            // swiping on the touchpad must never scroll the page — only the
            // button area below scrolls if it doesn't fit.
            Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: _Header(
                    deviceName: device?.name ?? 'Apple TV',
                    connected: controller.status == AtvStatus.connected,
                    statusMessage: controller.statusMessage,
                    // Toggle: pyatv can't poll power state on newer tvOS, so we
                    // track it locally — off -> wake (incl. Wake-on-LAN), else sleep.
                    onPower: () => _press(
                      controller,
                      controller.powerState == 'off' ? 'power_on' : 'power_off',
                    ),
                    onKeyboard: () => showKeyboardSheet(
                      context,
                      onSend: controller.sendText,
                    ),
                    onApps: () => showAppsSheet(context, controller),
                    onSwitchDevice: controller.switchDevice,
                    onUnpair: controller.unpairCurrent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _NavigationToggle(
                    useTouchpad: _useTouchpad,
                    onChanged: (v) => setState(() => _useTouchpad = v),
                  ),
                ),
                const SizedBox(height: 8),
                _useTouchpad
                    ? Touchpad(onCommand: controller.sendCommand)
                    : DPad(onCommand: controller.sendCommand),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _PrimaryControls(
                          onMenu: () => _press(controller, 'menu'),
                          onPlayPause: () => _press(controller, 'play_pause'),
                          onHome: () => _press(controller, 'home'),
                          onHomeLongPress: () => _press(controller, 'top_menu'),
                        ),
                        const SizedBox(height: 16),
                        // Media transport: works system-wide inside whatever
                        // app is playing (YouTube, Music, ...).
                        _MediaTransport(
                          onPrevious: () => _press(controller, 'previous'),
                          onSkipBackward: () =>
                              _press(controller, 'skip_backward'),
                          onSkipForward: () =>
                              _press(controller, 'skip_forward'),
                          onNext: () => _press(controller, 'next'),
                        ),
                        const SizedBox(height: 16),
                        _VolumeRow(
                          onVolumeUp: () => _press(controller, 'volume_up'),
                          onVolumeDown: () => _press(controller, 'volume_down'),
                          onMute: () => _press(controller, 'mute'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // NOTE: intentionally not absorbing pointers — the power button
            // must stay usable while reconnecting (that's how you wake the TV).
            if (reconnecting)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: AppColors.accent,
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            controller.statusMessage ??
                                'Reconnecting to ${device?.name ?? 'Apple TV'}…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 14,
                            ),
                          ),
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

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final String deviceName;
  final bool connected;
  final String? statusMessage;
  final VoidCallback onPower;
  final VoidCallback onKeyboard;
  final VoidCallback onApps;
  final VoidCallback onSwitchDevice;
  final VoidCallback onUnpair;

  const _Header({
    required this.deviceName,
    required this.connected,
    required this.statusMessage,
    required this.onPower,
    required this.onKeyboard,
    required this.onApps,
    required this.onSwitchDevice,
    required this.onUnpair,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? AppColors.online : AppColors.offline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deviceName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                statusMessage ??
                    (connected ? 'Connected' : 'Disconnected'),
                style: TextStyle(
                  fontSize: 12,
                  // Errors show in warning amber; healthy states green/dim.
                  color: statusMessage != null
                      ? const Color(0xFFFFD60A)
                      : connected
                          ? AppColors.online
                          : AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Apple TV apps',
          icon: const Icon(Icons.apps),
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          onPressed: onApps,
        ),
        IconButton(
          tooltip: 'Keyboard input',
          icon: const Icon(Icons.keyboard),
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          onPressed: onKeyboard,
        ),
        IconButton(
          tooltip: 'Sleep / wake',
          icon: const Icon(Icons.power_settings_new),
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          onPressed: onPower,
        ),
        PopupMenuButton<String>(
          tooltip: 'Device options',
          iconColor: AppColors.text,
          onSelected: (value) {
            if (value == 'switch') onSwitchDevice();
            if (value == 'unpair') onUnpair();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'switch', child: Text('Switch Device')),
            PopupMenuItem(value: 'unpair', child: Text('Unpair this Apple TV')),
          ],
        ),
      ],
    );
  }
}

class _NavigationToggle extends StatelessWidget {
  final bool useTouchpad;
  final ValueChanged<bool> onChanged;

  const _NavigationToggle({
    required this.useTouchpad,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: true,
          icon: Icon(Icons.swipe),
          label: Text('Touchpad'),
        ),
        ButtonSegment(
          value: false,
          icon: Icon(Icons.gamepad),
          label: Text('D-Pad'),
        ),
      ],
      selected: {useTouchpad},
      onSelectionChanged: (selection) => onChanged(selection.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
      ),
    );
  }
}

class _PrimaryControls extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onPlayPause;
  final VoidCallback onHome;
  final VoidCallback onHomeLongPress;

  const _PrimaryControls({
    required this.onMenu,
    required this.onPlayPause,
    required this.onHome,
    required this.onHomeLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: Icons.arrow_back,
          label: 'Back',
          onPressed: onMenu,
        ),
        _ControlButton(
          icon: Icons.play_arrow,
          label: 'Play/Pause',
          size: 74,
          iconSize: 34,
          onPressed: onPlayPause,
        ),
        _ControlButton(
          icon: Icons.tv,
          label: 'Home',
          onPressed: onHome,
          onLongPress: onHomeLongPress,
        ),
      ],
    );
  }
}

/// Media transport: previous track, seek -10s / +10s (hold to keep
/// seeking), next track. These are system-level media keys on the Apple TV,
/// so they act on whatever app is currently playing.
class _MediaTransport extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onSkipBackward;
  final VoidCallback onSkipForward;
  final VoidCallback onNext;

  const _MediaTransport({
    required this.onPrevious,
    required this.onSkipBackward,
    required this.onSkipForward,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: Icons.skip_previous,
          label: 'Previous',
          small: true,
          onPressed: onPrevious,
        ),
        _ControlButton(
          icon: Icons.replay_10,
          label: '-10 s',
          repeat: true,
          onPressed: onSkipBackward,
        ),
        _ControlButton(
          icon: Icons.forward_10,
          label: '+10 s',
          repeat: true,
          onPressed: onSkipForward,
        ),
        _ControlButton(
          icon: Icons.skip_next,
          label: 'Next',
          small: true,
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onMute;

  const _VolumeRow({
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: Icons.volume_down,
          label: 'Vol -',
          repeat: true,
          small: true,
          onPressed: onVolumeDown,
        ),
        _ControlButton(
          icon: Icons.volume_off,
          label: 'Mute',
          small: true,
          onPressed: onMute,
        ),
        _ControlButton(
          icon: Icons.volume_up,
          label: 'Vol +',
          repeat: true,
          small: true,
          onPressed: onVolumeUp,
        ),
      ],
    );
  }
}

/// Circle button with visible press feedback; [repeat] enables hold-to-repeat
/// (volume +/-), [onLongPress] gives Home its long-press = top menu action.
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final double size;
  final double iconSize;
  final bool small;
  final bool repeat;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.label,
    this.onLongPress,
    this.size = 64,
    this.iconSize = 26,
    this.small = false,
    this.repeat = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = RemoteCircleButton(
      icon: icon,
      size: small ? size * 0.75 : size,
      iconSize: iconSize,
      repeat: repeat,
      repeatInterval: const Duration(milliseconds: 160),
      onPressed: onPressed,
      onLongPress: onLongPress,
    );

    if (label == null) return button;
    return Column(
      children: [
        button,
        const SizedBox(height: 6),
        Text(label!, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
      ],
    );
  }
}
