class AppleTvDevice {
  final String identifier;
  final String name;
  final String address;
  final String model;
  final String os;
  final String? version;
  final List<String> services;

  const AppleTvDevice({
    required this.identifier,
    required this.name,
    required this.address,
    required this.model,
    required this.os,
    this.version,
    this.services = const [],
  });

  factory AppleTvDevice.fromMap(Map<String, dynamic> map) => AppleTvDevice(
        identifier: map['identifier']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Apple TV',
        address: map['address']?.toString() ?? '',
        model: map['model']?.toString() ?? 'Unknown',
        os: map['os']?.toString() ?? 'Unknown',
        version: map['version']?.toString(),
        services:
            (map['services'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      );

  String get infoLine {
    final parts = <String>[address];
    if (model != 'Unknown') parts.add(model);
    if (os != 'Unknown') parts.add(os);
    if (version != null && version!.isNotEmpty) parts.add('tvOS $version');
    return parts.join(' · ');
  }
}
