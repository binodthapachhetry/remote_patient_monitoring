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
   > **Note:** The DevTools console only accepts Dart _expressions_ (not `import` or `final` statements).  
   All project files are pre-imported; just call functions directly:  
   ```dart
   await debugInitScanner();                       // starts scan (singleton)
   debugGetScanner().results.listen(print);        // look for your scale’s MAC/name
   ```  
4. **Bind WeightAdapter** (replace `device` with the discovered instance):  
   ```dart
   await debugBindWeightAdapter(         // returns WeightAdapter
     participantId: 'demoUser',
     device: device,                     // replace with discovered BluetoothDevice
   ).then((a) => a.samples.listen(print));
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
   await debugStopScanner();             // stops scan & cleans up
   ```
   
> **Tip:**  
> If you need to keep a reference in the console, wrap the assignment in a map literal (an expression):  
> ```dart
> { 'scanner': debugInitScanner() }
> ```

### 3. Next Obvious Microtask
Proceed to **M1.5 – Implement Heart-Rate Adapter (GATT 0x180D)** to enable a second sensor type and validate `SensorAdapter` extensibility.
