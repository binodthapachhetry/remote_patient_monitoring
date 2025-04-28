## Mobile-Health MVP – Progress Report  ❰YYYY-MM-DD❱

### 1. Microtasks Completed
| ID  | Title                                               | Status |
|-----|-----------------------------------------------------|--------|
| M1.1| Scaffold Flutter project & core packages            | ✅ |
| M1.2| BLE permission flow (Android/iOS)                   | ✅ |
| M1.3| `DeviceDiscoveryService` (BLE scanning)             | ✅ |
| M1.4| `SensorAdapter` abstract class                      | ✅ |
| M1.7| `WeightAdapter` (GATT 0x181D)                       | ✅ |
| M1.8| Firestore participant↔device repository (+Firebase) | ✅ |

### 2. Manual Test – Android phone + BLE Weight-Scale
1. **Boot app**  
   ```bash
   cd mobile_app
   flutter run -d <android_device_id>
   ```  
2. **Grant permissions** when prompted by `BlePermissionGate`.  
3. **Start scanning** in a DevTools console:  
   ```dart
   final scanner = DeviceDiscoveryService();     // library already loaded
   await scanner.start();                        // OK: DevTools supports await
   scanner.results.listen(print);                // look for your scale’s MAC/name
   ```  
4. **Bind WeightAdapter** (replace `device` with the discovered instance):  
   ```dart
   import 'package:mobile_health_app/sensors/weight_adapter.dart';
   final adapter = WeightAdapter(
     participantId: 'demoUser',
     deviceId: device.remoteId.str,      // MAC / UUID
   );
   await adapter.bind(device);
   adapter.samples.listen(print);        // expect PhysioSample(weightKg)
   ```  
5. **Persist mapping** (one-time):  
   ```dart
   import 'package:mobile_health_app/repositories/participant_device_repo.dart';
   await ParticipantDeviceRepo().saveMapping(
     participantId: 'demoUser',
     deviceId: device.remoteId.str,
     bleProfile: 'weight',
     nickname: 'Bathroom scale',
   );
   ```  
6. **Cleanup**  
   ```dart
   await adapter.dispose();
   await scanner.stop();
   ```

### 3. Next Obvious Microtask
Proceed to **M1.5 – Implement Heart-Rate Adapter (GATT 0x180D)** to enable a second sensor type and validate `SensorAdapter` extensibility.
