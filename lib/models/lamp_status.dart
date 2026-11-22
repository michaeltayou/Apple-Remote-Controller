class LampStatus {
  final String ip;
  final int rssi;
  final int uptimeSeconds;

  const LampStatus({
    required this.ip,
    required this.rssi,
    required this.uptimeSeconds,
  });

  factory LampStatus.fromMap(Map<String, dynamic> map) => LampStatus(
        ip: map['ip']?.toString() ?? '',
        rssi: int.tryParse(map['rssi']?.toString() ?? '') ?? 0,
        uptimeSeconds:
            int.tryParse(map['uptime_s']?.toString() ?? '') ?? 0,
      );
}
