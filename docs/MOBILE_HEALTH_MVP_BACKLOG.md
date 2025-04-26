# Mobile Health MVP – Product Backlog

## 1. BLE Sensor Integration
- [ ] Support heart-rate monitors (GATT Heart Rate Profile)
- [ ] Support glucose meters (custom BLE profile)
- [ ] Support weight scales (GATT Weight Scale Profile)
- [ ] Auto-reconnect to known devices

## 2. Participant & Device Management
- [ ] Onboarding wizard for device/participant mapping
- [ ] CRUD for participants and device nicknames
- [ ] Persist device-participant mapping in Firestore

## 3. Data Collection & Upload
- [ ] Stream BLE data into PhysioSample model
- [ ] Batch and upload samples to Pub/Sub
- [ ] Retry logic for failed uploads
- [ ] Offline queueing and sync

## 4. Cloud Function (Ingestion)
- [ ] Trigger on Pub/Sub message
- [ ] Validate and map JSON to HL7v2 (ORU^R01)
- [ ] Error handling and dead-letter queue
- [ ] Write to GCP Healthcare HL7v2 store

## 5. Security & Compliance
- [ ] BLE link-level encryption (LE Secure Connections)
- [ ] OAuth 2.0 for mobile-to-cloud
- [ ] VPC-SC enforcement for Healthcare API

## 6. Extensibility & Config
- [ ] Abstract SensorAdapter for new BLE profiles
- [ ] Per-participant sampling interval config (Firestore)
- [ ] Dynamic batching cadence in Cloud Function

## 7. Testing & QA
- [ ] Unit tests for SensorAdapter and Cloud Function
- [ ] Integration test: BLE → Cloud → HL7v2 store
- [ ] Manual test scripts for onboarding and data flow

## 8. Documentation
- [ ] Update architecture diagram
- [ ] API docs for PhysioSample and Cloud Function
- [ ] User guide for onboarding and troubleshooting

## 9. Milestones
- [ ] Alpha: Heart-rate → HL7v2 store E2E
- [ ] Beta: Add glucose, weight, multi-device support
- [ ] GA: Security, error handling, docs, extensibility
