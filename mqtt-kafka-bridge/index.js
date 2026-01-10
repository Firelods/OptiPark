const mqtt = require("mqtt");
const { Kafka, logLevel } = require("kafkajs");

const mqttUrl = process.env.MQTT_URL || "mqtt://mosquitto:1883";
const kafkaBrokers = (process.env.KAFKA_BROKERS || "kafka:9092").split(",");

// Allowed parking IDs (must match your Kafka topics)
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

/**
 * Safe JSON parse
 */
function safeJsonParse(str) {
  try {
    return JSON.parse(str);
  } catch {
    return null;
  }
}

/**
 * Extract parking_id either from JSON payload or topic parking/<parking_id>/status
 */
function deriveParkingId(mqttTopic, payloadStr) {
  const parsed = safeJsonParse(payloadStr);
  if (parsed && typeof parsed.parking_id === "string") return parsed.parking_id;

  const parts = mqttTopic.split("/");
  if (parts.length >= 3 && parts[0] === "parking" && parts[2] === "status") return parts[1];
  return null;
}

/**
 * Parse rain payload:
 * - Accept proper JSON: {"sensor_id":"rain-1","rain_pct":80,"raw":5100}
 * - Accept legacy (invalid JSON): {sensor_id:rain-1,rain_pct:80,raw:5100}
 * - Ignore empty retained payload
 */
function parseRainPayload(value) {
  const trimmed = (value || "").trim();
  if (!trimmed) return null;

  // 1) Proper JSON
  const json = safeJsonParse(trimmed);
  if (json) return json;

  // 2) Legacy format: {k:v,k2:v2}
  if (!(trimmed.startsWith("{") && trimmed.endsWith("}"))) return null;

  const inside = trimmed.slice(1, -1).trim();
  if (!inside) return null;

  const obj = {};
  for (const part of inside.split(",")) {
    const idx = part.indexOf(":");
    if (idx < 0) continue;

    const k = part.slice(0, idx).trim();
    let v = part.slice(idx + 1).trim();

    if (!k) continue;

    // number?
    if (/^-?\d+$/.test(v)) v = Number(v);

    obj[k] = v;
  }
  return obj;
}

async function connectProducerWithRetry() {
  let attempt = 0;
  while (true) {
    try {
      attempt += 1;
      console.log(
        `[bridge] Connecting Kafka producer (attempt ${attempt}) to ${kafkaBrokers.join(",")}...`
      );
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
  // Register MQTT handlers BEFORE connecting
  let subscribed = false;
  let producerReady = false;

  const client = mqtt.connect(mqttUrl, { reconnectPeriod: 5000 });

  function trySubscribe() {
    if (subscribed || !producerReady) return;
    subscribed = true;

    client.subscribe(["parking/+/status", "parking/rain"], { qos: 1 }, (err) => {
      if (err) {
        subscribed = false;
        console.error("[bridge] MQTT subscribe error:", err?.message || err);
      } else {
        console.log("[bridge] MQTT subscribed to parking/+/status and parking/rain");
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

    // --------------------------
    // RAIN TOPIC
    // --------------------------
    if (topic === "parking/rain") {
      const parsed = parseRainPayload(value);

      // Empty retained (-r -n) or invalid => ignore (no error spam)
      if (!parsed) {
        console.warn("[bridge] Rain payload empty/invalid. Dropping.");
        return;
      }

      // Validate fields
      const sensorIdOk = typeof parsed.sensor_id === "string" && parsed.sensor_id.length > 0;
      const rainPctOk = typeof parsed.rain_pct === "number" && Number.isFinite(parsed.rain_pct);

      if (!sensorIdOk || !rainPctOk) {
        console.warn("[bridge] Invalid rain fields. Dropping.", parsed);
        return;
      }

      // Normalize to strict JSON (always)
      const normalized = JSON.stringify({
        sensor_id: parsed.sensor_id,
        rain_pct: Math.max(0, Math.min(100, Math.trunc(parsed.rain_pct))),
        raw: typeof parsed.raw === "number" ? parsed.raw : undefined,
      });

      try {
        console.log("[bridge] Producing rain to Kafka topic=rain.global");
        await producer.send({
          topic: "rain.global",
          messages: [{ key: "rain", value: normalized }],
        });
      } catch (e) {
        console.error("[bridge] Kafka send error (rain):", e?.message || e);
      }
      return;
    }

    // --------------------------
    // SPOT STATUS TOPICS
    // --------------------------
    const parkingId = deriveParkingId(topic, value);
    if (!parkingId) {
      console.warn("[bridge] Cannot derive parking_id. Dropping message.");
      return;
    }

    if (!ALLOWED_PARKING_IDS.has(parkingId)) {
      console.warn(`[bridge] parking_id=${parkingId} not allowed. Dropping message.`);
      return;
    }

    // Optional: drop non-JSON spot payloads early to avoid downstream parse failures
    // (You can remove this if you intentionally accept legacy spot payloads)
    const spotParsed = safeJsonParse(value);
    if (!spotParsed) {
      console.warn("[bridge] Spot payload is not valid JSON. Dropping.");
      return;
    }

    const targetTopic = `parking.${parkingId}`;

    try {
      console.log(`[bridge] Producing to Kafka topic=${targetTopic}`);
      await producer.send({
        topic: targetTopic,
        messages: [{ key: topic, value: JSON.stringify(spotParsed) }],
      });
    } catch (e) {
      console.error("[bridge] Kafka send error:", e?.message || e);
    }
  });

  // Connect Kafka producer (after handlers are ready)
  await connectProducerWithRetry();
  producerReady = true;

  // If MQTT already connected before, subscribe now
  trySubscribe();
}

run().catch((err) => {
  console.error("[bridge] Fatal error:", err?.message || err);
  process.exit(1);
});
