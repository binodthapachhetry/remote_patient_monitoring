import 'package:flutter/foundation.dart';
import 'package:mobile_health_app/services/device_discovery_service.dart';
import 'package:mobile_health_app/sensors/weight_adapter.dart';

/// Helper methods that can be invoked directly from the DevTools / IDE
/// debug console.  They are guarded by `kDebugMode`, so they are tree-shaken
/// from release builds and incur **zero** production overhead.
///
/// Usage examples in DevTools console:
/// ```dart
/// final scanner = await debugStartScanner();
/// scanner.results.listen(print);
///
/// final adapter = await debugBindWeightAdapter(
///   participantId: 'demoUser',
///   device: device,            // a BluetoothDevice you picked from scan list
/// );
/// adapter.samples.listen(print);
/// ```
@pragma('vm:entry-point')
Future<DeviceDiscoveryService> debugStartScanner() async {
  assert(kDebugMode, 'debugStartScanner is for debugging only');
  final scanner = DeviceDiscoveryService();
  await scanner.start();
  return scanner;
}

@pragma('vm:entry-point')
Future<WeightAdapter> debugBindWeightAdapter({
  required String participantId,
  required dynamic device, // BluetoothDevice from flutter_blue_plus
}) async {
  assert(kDebugMode, 'debugBindWeightAdapter is for debugging only');
  final adapter =
      WeightAdapter(participantId: participantId, deviceId: device.remoteId.str);
  await adapter.bind(device);
  return adapter;
}
