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

## 3. Data Flow
1. BLE peripheral advertises **GATT** services.  
2. Flutter plugin `flutter_blue_plus` streams raw measurements into `StreamController<PhysioSample>`.  
3. Samples are batched every *N* seconds, JSON-encoded and pushed to **Pub/Sub** via `googleapis` REST.  
4. Cloud Function triggers on Pub/Sub, maps JSON → HL7v2 via open-source `hl7v2-js` mapper, validates, and POSTs to `projects.locations.datasets.hl7V2Stores.messages`.  

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
