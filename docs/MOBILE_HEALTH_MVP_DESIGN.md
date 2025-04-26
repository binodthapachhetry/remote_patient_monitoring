# Mobile Health MVP – System Design

## 1. Overview
Collect BLE sensor data (heart-rate, glucose, weight) on Android/iOS Flutter
app, map to HL7v2 ORU^R01 messages, and persist in Google Cloud Healthcare
API HL7v2 store.

## 2. Component Diagram
```
(ASCII diagram showing: BLE Sensors → Flutter App → Cloud Pub/Sub → Cloud
Function (NodeJS/TS) → Healthcare HL7v2 Store)  
```  

## 2.a Framework Selection – Flutter vs React Native

| Criterion                | Flutter                                  | React Native                             | Verdict |
|--------------------------|------------------------------------------|------------------------------------------|---------|
| BLE Ecosystem            | `flutter_blue_plus`, `flutter_reactive_ble` mature; consistent APIs on iOS/Android | Community plug-ins vary in quality; some iOS lags | Flutter |
| Performance (GATT data)  | Compiled ARM code; low-latency stream handling | JS bridge adds ~3-5 ms per call          | Flutter |
| HL7v2 Parsing/Mapping    | Pure-Dart libraries available; can reuse TS in cloud | Same—neutral                              | Tie |
| Team Skillset            | *<fill in>*                               | *<fill in>*                               | — |
| Long-Term Maintenance    | Single language (Dart) front-end; stable | Depends on React & RN release cadence     | Flutter |

**Decision:** Proceed with **Flutter** to maximise BLE stability and minimise latency for real-time physiological data capture.

> Note: Should project constraints change (e.g., strong React expertise), this section must be revisited before Task 02 kicks off.

## 3. Data Flow
1. BLE peripheral advertises **GATT** services.  
2. Flutter plugin `flutter_blue_plus` streams raw measurements into `StreamController<PhysioSample>`.  
3. Samples are batched every *N* seconds, JSON-encoded and pushed to **Pub/Sub** via `googleapis` REST.  
4. Cloud Function triggers on Pub/Sub, maps JSON → HL7v2 via open-source `hl7v2-js` mapper, validates, and POSTs to `projects.locations.datasets.hl7V2Stores.messages`.  

## 3.a Device & Participant Management

### Goals
• Let users add any BLE sensor at run-time.  
• Guarantee each measurement is tagged with the correct `participantId` and `deviceId`.  

### Mobile Workflow
1. **Onboarding Wizard**  
   - Scan → select device → assign or create participant.  
   - Persist mapping to **Firestore**  
     `/participants/{pid}/devices/{did}` → `{bleProfile, nickname, pairedAt}`.  
2. `flutter_blue_plus` feeds data into `SensorAdapter`, which enriches every
   `PhysioSample`:
   ```dart
   PhysioSample(
     participantId: pid,
     deviceId: did,
     metric: ...,
     timestamp: DateTime.now(),
   )
   ```  

### Cloud-Side Mapping
- Cloud Function reads IDs and populates HL7v2 fields  
  - `PID-3`  ← `participantId`  
  - `OBX-18` ← `deviceId`  

### Data Model Snapshot
| Collection / Document | Fields                          |
|-----------------------|---------------------------------|
| participants/{pid}    | name, dob, …                    |
| └─ devices/{did}      | bleProfile, nickname, pairedAt  |

### Future Frequency Control
`/participants/{pid}/config` → `{samplingIntervalSecs}` consumed by Cloud Function for batching cadence.

## 4. Minimal Tech Stack
| Layer              | Tech                                |
|--------------------|-------------------------------------|
| Mobile             | Flutter 3, flutter_blue_plus        |
| Messaging          | Cloud Pub/Sub                       |
| Transformation     | Cloud Functions (TypeScript)        |
| Persistence        | GCP Healthcare HL7v2 store          |

## 5. Security
- BLE link-level security (LE Secure Connections).  
- OAuth 2.0 service account for mobile → Pub/Sub.  
- VPC-SC around Healthcare API.  

## 6. Extensibility Hooks
- `abstract class SensorAdapter` for new BLE profiles.  
- Cloud Function reads a `frequency` config from Firestore for per-user batching.  

## 7. MVP Deliverables & Milestones
… (timeline & KPIs)

## 8. Open Issues
… (latency, battery, regulatory)

```  
