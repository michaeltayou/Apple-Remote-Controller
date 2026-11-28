/// An app installed on the Apple TV (from pyatv's Apps interface).
class AppleTvApp {
  final String name;
  final String bundleId;

  const AppleTvApp({required this.name, required this.bundleId});

  factory AppleTvApp.fromMap(Map<String, dynamic> map) => AppleTvApp(
        name: map['name']?.toString() ?? 'App',
        bundleId: map['bundleId']?.toString() ?? '',
      );
}
