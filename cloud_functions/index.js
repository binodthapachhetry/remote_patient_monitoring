/**
 * Cloud Run Function (2nd gen) to receive health measurements from mobile app and forward them to the
 * Healthcare API as HL7v2 messages.
 * 
 * DEPLOYMENT NOTE: Deploy using 'gcloud functions deploy' with --gen2 flag
 * List deployed functions with: 'gcloud functions list --gen2'
 * 
 * @param {!express:Request} req HTTP request context.
 * @param {!express:Response} res HTTP response context.
 */
const {google} = require('googleapis');

// For compatibility with PubSub trigger
exports.helloPubSub = async (pubSubEvent, context) => {
  try {
    console.log('Received PubSub message', context.eventId);
    
    // Extract the message data
    const messageData = JSON.parse(
      Buffer.from(pubSubEvent.data, 'base64').toString()
    );
    
    console.log(`Processing ${messageData.measurements?.length || 0} measurements from PubSub`);
    
    // Process measurements similar to the HTTP endpoint
    // Get environment variables
    const projectId = process.env.PROJECT_ID;
    const location = process.env.LOCATION || 'us-central1';
    const datasetId = process.env.DATASET_ID || 'health-dataset';
    const hl7v2StoreId = process.env.HL7V2_STORE_ID || 'test-hl7v2-store';

    if (!projectId) {
      console.error('Missing PROJECT_ID environment variable');
      return;
    }

    const parent = `projects/${projectId}/locations/${location}/datasets/${datasetId}/hl7V2Stores/${hl7v2StoreId}`;
    
    // Set up the Healthcare API client
    const healthcare = google.healthcare({
      version: 'v1',
      auth: await google.auth.getClient({
        scopes: ['https://www.googleapis.com/auth/cloud-platform']
      })
    });
    
    // Process each measurement
    if (messageData.measurements && Array.isArray(messageData.measurements)) {
      await Promise.all(messageData.measurements.map(async (measurement) => {
        try {
          // Validate required fields
          if (!measurement.participantId || !measurement.type || 
              measurement.value === undefined || !measurement.unit || 
              !measurement.timestamp) {
            console.error('Missing required fields in measurement', measurement.id || 'unknown');
            return;
          }

          // Create HL7v2 message
          const hl7v2Message = createHL7v2Message(measurement);
          
          // Send to Healthcare API
          const response = await healthcare.projects.locations.datasets.hl7V2Stores.messages.create({
            parent,
            requestBody: {
              message: {
                data: Buffer.from(hl7v2Message).toString('base64')
              }
            }
          });

          console.log(`Successfully sent message for participant ${measurement.participantId}, message ID: ${response.data.name}`);
        } catch (err) {
          console.error('Error processing measurement:', err);
        }
      }));
    }
  } catch (error) {
    console.error('Error processing PubSub message:', error);
  }
}

// Main entry point for Cloud Run - handles the root path
exports.receiveHealthData = async (req, res) => {
  // Set CORS headers for all requests
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');

  if (req.method === 'OPTIONS') {
    // Handle preflight requests
    res.status(204).send('');
    return;
  }

  // Only allow POST
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }
  
  try {
    // Extract request body
    const data = req.body;
    if (!data) {
      res.status(400).send('Invalid request: request body is required');
      return;
    }

    console.log(`Processing health data request: ${JSON.stringify(data)}`);
    
    // Process the data directly in this function
    return await processHealthData(req, res);
  } catch (err) {
    console.error('Error in receiveHealthData:', err);
    res.status(500).send(`Internal server error: ${err.message}`);
  }
};

// Helper function used by receiveHealthData - not exposed as an endpoint
async function processHealthData(req, res) {

  try {
    // Extract request body
    const data = req.body;
    if (!data || !data.measurements || !Array.isArray(data.measurements)) {
      res.status(400).send('Invalid request: measurements array is required');
      return;
    }

    console.log(`Processing ${data.measurements.length} measurements`);

    // Get environment variables
    const projectId = process.env.PROJECT_ID;
    const location = process.env.LOCATION || 'us-central1';
    const datasetId = process.env.DATASET_ID || 'health-dataset';
    const hl7v2StoreId = process.env.HL7V2_STORE_ID || 'test-hl7v2-store';

    if (!projectId) {
      console.error('Missing PROJECT_ID environment variable');
      res.status(500).send('Server configuration error: Missing PROJECT_ID');
      return;
    }

    console.log(`Using project: ${projectId}, dataset: ${datasetId}, store: ${hl7v2StoreId}`);

    // Set up the parent resource path
    const parent = `projects/${projectId}/locations/${location}/datasets/${datasetId}/hl7V2Stores/${hl7v2StoreId}`;
    
    // Set up the Healthcare API client
    const healthcare = google.healthcare({
      version: 'v1',
      auth: await google.auth.getClient({
        scopes: ['https://www.googleapis.com/auth/cloud-platform']
      })
    });
    
    // Process each measurement
    const results = await Promise.all(data.measurements.map(async (measurement) => {
      try {
        // Validate required fields
        if (!measurement.participantId || !measurement.type || 
            measurement.value === undefined || !measurement.unit || 
            !measurement.timestamp) {
          return {
            id: measurement.id || 'unknown',
            success: false,
            error: 'Missing required fields'
          };
        }

        // Create HL7v2 message
        const hl7v2Message = createHL7v2Message(measurement);
        
        // Send to Healthcare API
        const response = await healthcare.projects.locations.datasets.hl7V2Stores.messages.create({
          parent,
          requestBody: {
            message: {
              data: Buffer.from(hl7v2Message).toString('base64')
            }
          }
        });

        console.log(`Successfully sent message for participant ${measurement.participantId}`);
        return {
          id: measurement.id || 'unknown',
          success: true,
          messageId: response.data.name
        };
      } catch (err) {
        console.error('Error processing measurement:', err);
        return {
          id: measurement.id || 'unknown',
          success: false,
          error: err.message
        };
      }
    }));

    // Return response with status of each measurement
    res.status(200).json({
      success: true,
      results
    });
  } catch (err) {
    console.error('Error in Cloud Function:', err);
    res.status(500).send(`Internal server error: ${err.message}`);
  }
};

/**
 * Creates an HL7v2 message from a health measurement.
 * 
 * @param {Object} measurement The health measurement data
 * @return {string} HL7v2 formatted message
 */
function createHL7v2Message(measurement) {
  // Get current datetime for message timestamp
  const now = new Date();
  const messageTimestamp = formatHL7Date(now);
  
  // Format measurement timestamp
  const observationTime = formatHL7Date(new Date(measurement.timestamp));
  
  // Generate a unique message ID
  const messageId = `RPM${now.getTime()}`;
  
  // Format device information
  const deviceId = measurement.deviceId || 'UNKNOWN_DEVICE';
  
  // Build the HL7v2 message segments
  let message = [
    // Message Header (MSH)
    `MSH|^~\\&|REMOTE_PATIENT_MONITORING|MOBILE_APP|HEALTHCARE_API|GCP|${messageTimestamp}||ORU^R01|${messageId}|P|2.5.1`,
    
    // Patient Identification (PID)
    `PID|1||${measurement.participantId}||PARTICIPANT^${measurement.participantId}`,
    
    // Observation Request (OBR)
    `OBR|1|${messageId}|${deviceId}|${measurement.type}^Remote Monitoring Measurement^LOCAL||${observationTime}`,
    
    // Observation/Result (OBX)
    `OBX|1|NM|${measurement.type}^${getDescriptiveTypeName(measurement.type)}^LOCAL||${measurement.value}|${measurement.unit}|||||F|||${observationTime}|||${deviceId}^${measurement.deviceId || 'Unknown Device'}`
  ];
  
  // Add any additional metadata as Notes (NTE)
  if (measurement.metadata) {
    const metadataKeys = Object.keys(measurement.metadata);
    for (let i = 0; i < metadataKeys.length; i++) {
      const key = metadataKeys[i];
      // Skip sensitive or large metadata fields
      if (key !== 'rawData' && key !== 'originalLength' && key !== 'isTestData') {
        message.push(`NTE|${i+1}|L|${key}: ${measurement.metadata[key]}`);
      }
    }
  }
  
  // Join all segments with carriage return
  return message.join('\r');
}

/**
 * Formats a JavaScript Date into HL7 format.
 * 
 * @param {Date} date The date to format
 * @return {string} Date in HL7 format (YYYYMMDDHHMMSS)
 */
function formatHL7Date(date) {
  return date.getFullYear() +
    (date.getMonth() + 1).toString().padStart(2, '0') +
    date.getDate().toString().padStart(2, '0') +
    date.getHours().toString().padStart(2, '0') +
    date.getMinutes().toString().padStart(2, '0') +
    date.getSeconds().toString().padStart(2, '0');
}

/**
 * Returns a descriptive name for the measurement type.
 * 
 * @param {string} type The measurement type
 * @return {string} Human-readable description
 */
function getDescriptiveTypeName(type) {
  const typeMap = {
    'heart_rate': 'Heart Rate',
    'blood_pressure_systolic': 'Blood Pressure - Systolic',
    'blood_pressure_diastolic': 'Blood Pressure - Diastolic',
    'weight': 'Body Weight',
    'glucose': 'Blood Glucose'
  };
  
  return typeMap[type] || type;
}
