const mqtt = require("mqtt");
const { Kafka, logLevel } = require("kafkajs");

const mqttUrl = process.env.MQTT_URL || "mqtt://mosquitto:1883";
const kafkaBrokers = (process.env.KAFKA_BROKERS || "kafka:9092").split(",");

// Allowed parking IDs in your system (must match created Kafka topics)
const ALLOWED_PARKING_IDS = new Set(["nice_sophia.A", "nice_sophia.B", "nice_sophia.C"]);

const kafka = new Kafka({
  clientId: "mqtt-kafka-bridge",
  brokers: kafkaBrokers,
  logLevel: logLevel.INFO,
  retry: { retries: 10, initialRetryTime: 300, maxRetryTime: 30000 },
  connectionTimeout: 10000,
  requestTimeout: 30000,
});

const producer = kafka.producer();

function deriveParkingId(mqttTopic, payloadStr) {
  // 1) Try JSON payload
  try {
    const parsed = JSON.parse(payloadStr);
    if (parsed && typeof parsed.parking_id === "string") return parsed.parking_id;
  } catch (_) {}

  // 2) Try from topic: parking/<parking_id>/status
  const parts = mqttTopic.split("/");
  if (parts.length >= 3 && parts[0] === "parking" && parts[2] === "status") {
    return parts[1];
  }
  return null;
}

async function connectProducerWithRetry() {
  let attempt = 0;
  while (true) {
    try {
      attempt += 1;
      console.log(`[bridge] Connecting Kafka producer (attempt ${attempt}) to ${kafkaBrokers.join(",")}...`);
      await producer.connect();
      console.log("[bridge] Kafka producer connected.");
      return;
    } catch (err) {
      const waitMs = Math.min(1000 * Math.pow(2, attempt), 30000);
      console.error("[bridge] Kafka producer connect failed:", err?.message || err);
      console.log(`[bridge] retry in ${waitMs}ms`);
      await new Promise((r) => setTimeout(r, waitMs));
    }
  }
}

async function run() {
  // IMPORTANT: register MQTT handlers BEFORE connecting, so we never miss "connect"
  let subscribed = false;
  let producerReady = false;

  const client = mqtt.connect(mqttUrl, { reconnectPeriod: 5000 });

  function trySubscribe() {
    if (subscribed || !producerReady) return;
    subscribed = true;

    client.subscribe("parking/+/status", { qos: 1 }, (err) => {
      if (err) {
        subscribed = false;
        console.error("[bridge] MQTT subscribe error:", err?.message || err);
      } else {
        console.log("[bridge] MQTT subscribed to parking/+/status");
      }
    });
  }

  client.on("connect", () => {
    console.log("[bridge] MQTT connected to", mqttUrl);
    trySubscribe();
  });

  client.on("reconnect", () => console.log("[bridge] MQTT reconnecting..."));
  client.on("error", (e) => console.error("[bridge] MQTT error:", e?.message || e));

  client.on("message", async (topic, payload) => {
    const value = payload.toString();
    console.log("[bridge] MQTT", topic, value);

    if (!producerReady) {
      console.warn("[bridge] Kafka producer not ready yet. Dropping message.");
      return;
    }

    const parkingId = deriveParkingId(topic, value);
    if (!parkingId) {
      console.warn("[bridge] Cannot derive parking_id. Dropping message.");
      return;
    }

    if (!ALLOWED_PARKING_IDS.has(parkingId)) {
      console.warn(`[bridge] parking_id=${parkingId} not allowed. Dropping message.`);
      return;
    }

    const targetTopic = `parking.${parkingId}`;

    try {
      console.log(`[bridge] Producing to Kafka topic=${targetTopic}`);
      await producer.send({
        topic: targetTopic,
        messages: [{ key: topic, value }],
      });
    } catch (e) {
      console.error("[bridge] Kafka send error:", e?.message || e);
    }
  });

  // Now connect Kafka producer (after handlers are ready)
  await connectProducerWithRetry();
  producerReady = true;

  // If MQTT already connected before, subscribe now
  trySubscribe();
}

run().catch((err) => {
  console.error("[bridge] Fatal error:", err?.message || err);
  process.exit(1);
});
