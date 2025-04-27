## Mobile Health MVP – Microtask Roadmap

### 0. Meta
- M0.1 Create & maintain this microtask roadmap (this commit).

### 1. Mobile App: Data Acquisition
- M1.1 Scaffold Flutter project & core package setup.
- M1.2 Implement BLE permission flow (iOS/Android).
- M1.3 Implement `DeviceDiscoveryService` using `flutter_blue_plus`.
- M1.4 Establish `SensorAdapter` abstract class.
- M1.5 Implement Heart-Rate adapter (GATT 0x180D).
- M1.6 Implement Glucose adapter (GATT 0x1808).
- M1.7 Implement Weight adapter (GATT 0x181D).
- M1.8 Persist participant↔device mapping to Firestore.

### 2. Mobile App: Messaging Layer
- M2.1 Serialize `PhysioSample` → JSON.
- M2.2 Implement sample batching (configurable interval).
- M2.3 Publish batches to Cloud Pub/Sub with OAuth token.

### 3. Cloud Infrastructure
- M3.1 Terraform/CLI script to create Pub/Sub topic & IAM.
- M3.2 Provision HL7v2 store in Cloud Healthcare API.

### 4. Cloud Function
- M4.1 Scaffold TypeScript Cloud Function trigger.
- M4.2 Implement JSON→HL7v2 mapping via `hl7v2-js`.
- M4.3 Validate HL7v2 with schema & unit tests.
- M4.4 POST message to HL7v2 store.
- M4.5 Implement per-participant frequency control (Firestore lookup).

### 5. Security Hardening
- M5.1 Enforce BLE LE Secure Connections on mobile.
- M5.2 OAuth2 Service Account keys rotation procedure.
- M5.3 Configure VPC-SC around Healthcare API.

### 6. Quality Assurance
- M6.1 Unit tests for SensorAdapters.
- M6.2 Integration tests for Pub/Sub→HL7v2 pipeline.
- M6.3 E2E test script with simulated BLE device.

### 7. CI/CD & Ops
- M7.1 GitHub Actions: lint, test, build Flutter app.
- M7.2 GitHub Actions: deploy Cloud Function on tag.
- M7.3 Monitoring dashboards (Cloud Logging, Error Reporting).

### 8. Documentation & Handover
- M8.1 Update README and architecture diagrams.
- M8.2 Runbook for on-call engineers.
