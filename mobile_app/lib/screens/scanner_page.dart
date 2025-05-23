import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/device_discovery_service.dart';
import '../services/background_service_manager.dart';
import '../services/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sensors/weight_adapter.dart';
import '../sensors/blood_pressure_adapter.dart';
import '../utils/device_detector.dart';    // For device type detection                                                                                  
import '../models/physio_sample.dart';     // For PhysioMetric type  
import '../sensors/sensor_adapter.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.participantId});
  final String participantId;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _scanner = DeviceDiscoveryService();
  final _serviceManager = BackgroundServiceManager();
  StreamSubscription? _sub;
  final List<ScanResult> _results = [];
  SensorAdapter? _adapter; 
  bool _backgroundServiceEnabled = false;
  bool _autoReconnectEnabled = false;
  String? _autoConnectDeviceId;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _startScan();
  }
  
  // Show logout confirmation dialog
  Future<void> _confirmLogout() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out? Any active connections will be closed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      // Close any active connections
      await _adapter?.dispose();
      _adapter = null;
      
      // Log out the user
      await UserManager().logout();
    }
  }
  
  // Load saved preferences for background service and auto-reconnect
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundServiceEnabled = prefs.getBool('backgroundServiceEnabled') ?? false;
      _autoReconnectEnabled = prefs.getBool('autoReconnectEnabled') ?? false;
      _autoConnectDeviceId = prefs.getString('autoConnectDeviceId');
    });
  }

  // Start BLE scan and listen for results
  Future<void> _startScan() async {
    await _scanner.start();
    _sub = _scanner.results.listen((r) {
      if (mounted && !_results.any((e) => e.device.remoteId == r.device.remoteId)) {
        setState(() => _results.add(r));
      }
    });
  }
  
  // Clear current results and start a new scan
  Future<void> _restartScan() async {
    // Cancel any existing subscription
    await _sub?.cancel();
    
    // If scanner is already running, stop it first
    await _scanner.stop();
    
    // Clear current results
    setState(() {
      _results.clear();
    });
    
    // Start a new scan
    await _startScan();
    
    // Show feedback to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning for devices...')),
      );
    }
  }

  // On tap, bind to the selected device and listen for weight samples
  Future<void> _onTap(ScanResult r) async {
    await _scanner.stop();

    const maxRetries = 2; // Try initial connection + 2 retries
    int attempt = 0;
    bool connected = false;

    while (attempt <= maxRetries && !connected) {
      attempt++;
      debugPrint('>>> Connection attempt $attempt for ${r.device.remoteId.str}');
      try {
        // _adapter = WeightAdapter(
        //   participantId: widget.participantId,
        //   deviceId: r.device.remoteId.str,
        // );
        // await _adapter!.bind(r.device); // Attempt to connect and bind

        // Use device detector to determine the right adapter type                                                                                         
        final adapter = await DeviceDetector.createAdapterForDevice(
          device: r.device,                                                                                                                                
          participantId: widget.participantId,                                                                                                             
          );                                                                                                                                                 
                                                                                                                                                  
        // Check if we found a suitable adapter                                                                                                            
        if (adapter == null) {                                                                                                                             
          throw Exception('No suitable adapter found for this device type');                                                                               
        }                                                                                                                                                  
                                                                                                                                                         
        // Store the adapter for later use                                                                                                                 
        _adapter = adapter; 
        connected = true; // Mark as successful if bind completes

        // Listen for samples only after successful binding
        // _adapter!.samples.listen((s) => debugPrint('Weight: ${s.value} kg'));
        // Listen for different types of measurements depending on the device                                                                              
         _adapter!.samples.listen((s) {                                                                                                                     
           if (s.metric == PhysioMetric.weightKg) {                                                                                                         
             debugPrint('Weight: ${s.value} kg');                                                                                                           
             
             // Show success notification to user
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Weight measurement received: ${s.value.toStringAsFixed(1)} kg')),
               );
             }
           } else if (s.metric == PhysioMetric.bloodPressureSystolicMmHg) {                                                                                 
             final diastolic = s.metadata?['diastolic'] ?? 0;                                                                                               
             debugPrint('Blood pressure: ${s.value}/${diastolic} mmHg');                                                                                    
             
             // Show success notification to user for blood pressure
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(
                   content: Text('Blood pressure: ${s.value.toStringAsFixed(0)}/${diastolic.toString()} mmHg'),
                   action: SnackBarAction(
                     label: 'Measure Again',
                     onPressed: () {
                       // Try to request another measurement if adapter is blood pressure type
                       if (_adapter.runtimeType.toString().contains('BloodPressure')) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Sending commands to blood pressure monitor...')),
                         );
                         (_adapter as dynamic).requestMeasurement();
                        
                         // Set a short timer to show a followup message
                         Future.delayed(const Duration(seconds: 2), () {
                           if (mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(
                                 content: Text('IMPORTANT: You MUST press the START button on the physical device after commands are sent. Make sure cuff is properly applied at heart level.'),
                                 duration: Duration(seconds: 10),
                               ),
                             );
                           }
                         });
                       }
                     },
                   ),
                 ),
               );
             }
           } else if (s.metric == PhysioMetric.heartRate) {                                                                                                 
             debugPrint('Heart rate: ${s.value} bpm');                                                                                                      
             
             // Show heart rate notification
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Heart rate: ${s.value.toStringAsFixed(0)} bpm')),
               );
             }
           } else {                                                                                                                                         
             debugPrint('Measurement: ${s.metric.name}: ${s.value}');                                                                                       
           }                                                                                                                                                
         }); 
        // --- Save Device ID for Auto-Connect and enable ---
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('autoConnectDeviceId', r.device.remoteId.str);
        setState(() {
          _autoConnectDeviceId = r.device.remoteId.str;
          // Auto-enable auto-reconnect when a device is connected
          if (!_autoReconnectEnabled) {
            _autoReconnectEnabled = true;
            prefs.setBool('autoReconnectEnabled', true);
            _scanner.enableAutoReconnect(r.device.remoteId.str, _onAutoConnectSuccess);
          }
        });
        debugPrint('>>> Saved ${r.device.remoteId.str} for auto-connect');
        // --- End Save ---
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to ${r.device.platformName.isNotEmpty ? r.device.platformName : r.device.remoteId.str}'),
              action: SnackBarAction(
                label: 'Enable Background',
                onPressed: () {
                  _toggleBackgroundService(true);
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
          
          // If device appears to be a blood pressure monitor, show additional instructions
          if (_adapter.runtimeType.toString().contains('BloodPressure')) {
            // Delay slightly so messages don't stack too quickly
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                // Show a dialog with instructions for blood pressure measurement
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Blood Pressure Monitor Connected'),
                    content: const Text(
                      '1. Apply the cuff to your arm properly (cuff must be placed at heart level)\n'
                      '2. Press "Send Commands" below to initialize the device\n'
                      '3. IMPORTANT: You MUST press START on the physical blood pressure monitor\n'
                      '4. Hold your arm still and wait for the measurement to complete\n\n'
                      'The reading will appear automatically when the measurement is complete.\n\n'
                      'Note: The commands only prepare the device but do not start the actual measurement.'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          // Try to send initialization command first
                          (_adapter as dynamic).requestMeasurement();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sending commands to blood pressure monitor. After commands are sent, you MUST press START on the device.'),
                              duration: Duration(seconds: 5),
                            ),
                          );
                          // Delay dialog dismissal to show the snackbar
                          Future.delayed(const Duration(milliseconds: 500), () {
                            Navigator.pop(context);
                          });
                        },
                        child: const Text('SEND COMMANDS'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('SKIP'),
                      ),
                    ],
                  ),
                );
              }
            });
          }
        }
      } catch (e) {
        debugPrint('!!! Attempt $attempt failed: Error connecting/binding to device: $e');
        // Clean up adapter if bind failed partway through
        // Use a temporary variable to avoid race conditions if dispose is async
        final adapterToDispose = _adapter;
        _adapter = null; // Nullify immediately
        await adapterToDispose?.dispose();


        if (attempt > maxRetries) {
          // Final attempt failed, show error to user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connection failed after $attempt attempts: ${e.toString()}')),
            );
          }
        } else {
          // Wait a bit before retrying
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    // Restart scanning if all connection attempts fail
    if (!connected) {
      await _restartScan();
    }
  }

  @override
  void dispose() {
    debugPrint('ScannerPage dispose called'); // Add logging here
    _sub?.cancel();
    _scanner.stop();
    _adapter?.dispose();
    super.dispose();
  }

  // Toggle background service
  Future<void> _toggleBackgroundService(bool value) async {
    await _serviceManager.setServicePreference(value);
    setState(() {
      _backgroundServiceEnabled = value;
    });
  }
  
  // Toggle auto-reconnect
  Future<void> _toggleAutoReconnect(bool value) async {
    if (value && _autoConnectDeviceId != null) {
      await _scanner.enableAutoReconnect(_autoConnectDeviceId!, (device) {
        debugPrint('>>> Auto-reconnect callback from UI toggle');
        _onAutoConnectSuccess(device);
      });
      
      // When enabling auto-reconnect, also try a direct connection immediately
      _scanner.attemptDirectConnection();
    } else {
      await _scanner.disableAutoReconnect();
    }
    
    setState(() {
      _autoReconnectEnabled = value;
    });
  }
  
  // Handle successful auto-connection
  void _onAutoConnectSuccess(BluetoothDevice device) {
    // Use DeviceDetector instead of hardcoding WeightAdapter
    DeviceDetector.createAdapterForDevice(
      device: device,
      participantId: widget.participantId,
    ).then((adapter) {
      if (adapter != null) {
        _adapter = adapter;
        debugPrint('>>> Device adapter created for auto-reconnect: ${adapter.runtimeType}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Auto-reconnected to ${device.platformName}')),
          );
        }
      } else {
        debugPrint('!!! No suitable adapter found for auto-reconnected device');
      }
    }).catchError((e) {
      debugPrint('!!! Error binding to auto-reconnected device: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan for Weight-Scale'),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan for devices',
            onPressed: _restartScan,
          ),
          // User menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'logout') {
                _confirmLogout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(UserManager().userEmail ?? 'No email'),
                    const SizedBox(height: 4),
                    Text('ID: ${widget.participantId}', 
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Log Out'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Settings panel
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Background Service'),
                    subtitle: const Text('Keep connections active when app is closed'),
                    value: _backgroundServiceEnabled,
                    onChanged: _toggleBackgroundService,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Auto-Reconnect'),
                    subtitle: Text(_autoConnectDeviceId != null
                        ? 'Will reconnect to saved device: ${_autoConnectDeviceId!.substring(0, 8)}...'
                        : 'No device saved for auto-reconnect'),
                    value: _autoReconnectEnabled,
                    onChanged: _autoConnectDeviceId != null ? _toggleAutoReconnect : null,
                  ),
                  // Add control buttons for connected device
                  if (_adapter != null) 
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Device Controls',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Blood pressure specific controls
                              if (_adapter is BloodPressureAdapter)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        (_adapter as BloodPressureAdapter).requestDataDownload();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Requesting stored readings from device...'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.download),
                                      label: const Text('Get Readings'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        (_adapter as BloodPressureAdapter).probeDeviceCharacteristics();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Reading device characteristics...'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.info_outline),
                                      label: const Text('Probe Device'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_autoReconnectEnabled && _autoConnectDeviceId != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Note: For best results, avoid locking your screen when immediate reconnection is needed.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Device list
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) {
                final r = _results[i];
                final isAutoConnectDevice = r.device.remoteId.str == _autoConnectDeviceId;
                
                return ListTile(
                  title: Text(r.device.platformName.isEmpty
                      ? r.advertisementData.advName
                      : r.device.platformName),
                  subtitle: Text(r.device.remoteId.str),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAutoConnectDevice)
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Icon(Icons.autorenew, color: Colors.green),
                        ),
                      Text('${r.rssi} dBm'),
                    ],
                  ),
                  onTap: () => _onTap(r),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
